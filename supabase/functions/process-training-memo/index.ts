import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { detectInjury, upsertInjury } from "../_shared/injuries.ts";
import { rebuildAthleteState } from "../_shared/athlete-state.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceKey);
const genAI = new GoogleGenerativeAI(geminiApiKey);

const VALID_MOODS = ["energized", "positive", "neutral", "tired", "struggling", "injured"] as const;

interface TrainingLogPayload {
  type: "INSERT" | "UPDATE";
  table: string;
  schema: string;
  record: {
    id: string;
    audio_url?: string;
    notes?: string;
    cleaned_notes?: string;
    mood?: string;
  };
  old_record: null | Record<string, unknown>;
}

interface AnalysisResult {
  transcription: string;
  cleaned_notes: string;
  mood: string;
  coach_insight: string | null;
  workout_notes: string | null;
  extracted_data: Record<string, unknown> | null;
}

// Helper to update processing status
async function updateProcessingStatus(
  recordId: string,
  status: "pending" | "processing" | "completed" | "failed",
  error?: string
) {
  const update: Record<string, unknown> = {
    processing_status: status,
    last_processing_attempt: new Date().toISOString(),
  };

  if (status === "processing") {
    const { data } = await supabase
      .from("training_logs")
      .select("processing_attempts")
      .eq("id", recordId)
      .single();
    update.processing_attempts = (data?.processing_attempts || 0) + 1;
  }

  if (error) {
    update.processing_error = error;
  } else if (status === "completed") {
    update.processing_error = null;
  }

  await supabase.from("training_logs").update(update).eq("id", recordId);
}

// Robust JSON parsing with multiple fallback strategies
function parseJsonResponse(responseText: string): Record<string, unknown> {
  // Strategy 1: Direct parse
  try {
    return JSON.parse(responseText);
  } catch { /* continue */ }

  // Strategy 2: Extract from markdown code block
  const codeBlockMatch = responseText.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (codeBlockMatch) {
    try {
      return JSON.parse(codeBlockMatch[1].trim());
    } catch { /* continue */ }
  }

  // Strategy 3: Find first { to last } and parse
  const firstBrace = responseText.indexOf("{");
  const lastBrace = responseText.lastIndexOf("}");
  if (firstBrace !== -1 && lastBrace > firstBrace) {
    try {
      return JSON.parse(responseText.substring(firstBrace, lastBrace + 1));
    } catch { /* continue */ }
  }

  throw new Error("Failed to parse AI response as JSON");
}

// Validate and normalize the analysis result
function validateAnalysis(raw: Record<string, unknown>): AnalysisResult {
  const transcription = typeof raw.transcription === "string" && raw.transcription.length > 0
    ? raw.transcription
    : null;

  if (!transcription) {
    throw new Error("AI response missing transcription field");
  }

  const mood = typeof raw.mood === "string" && VALID_MOODS.includes(raw.mood as typeof VALID_MOODS[number])
    ? raw.mood
    : "neutral";

  const cleaned_notes = typeof raw.cleaned_notes === "string" && raw.cleaned_notes.length > 0
    ? raw.cleaned_notes
    : transcription;

  const coach_insight = typeof raw.coach_insight === "string" && raw.coach_insight.length > 0
    ? raw.coach_insight
    : null;

  const workout_notes = typeof raw.workout_notes === "string" && raw.workout_notes.length > 0
    ? raw.workout_notes
    : null;

  const extracted_data = raw.extracted_data && typeof raw.extracted_data === "object"
    ? raw.extracted_data as Record<string, unknown>
    : null;

  return { transcription, cleaned_notes, mood, coach_insight, workout_notes, extracted_data };
}

Deno.serve(async (req) => {
  let recordId: string | null = null;

  try {
    const payload: TrainingLogPayload = await req.json();
    const { record } = payload;
    recordId = record.id;

    // Skip if already processed or no audio
    if (record.cleaned_notes || !record.audio_url) {
      return new Response(JSON.stringify({ message: "Skipped: already processed or no audio" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Concurrency guard: prevent duplicate processing
    const { data: currentStatus } = await supabase
      .from("training_logs")
      .select("processing_status, last_processing_attempt")
      .eq("id", record.id)
      .single();

    if (currentStatus?.processing_status === "processing") {
      const lastAttempt = currentStatus.last_processing_attempt
        ? new Date(currentStatus.last_processing_attempt)
        : null;
      const twoMinutesAgo = new Date(Date.now() - 2 * 60 * 1000);
      if (lastAttempt && lastAttempt > twoMinutesAgo) {
        return new Response(
          JSON.stringify({ message: "Already processing", status: "processing" }),
          { status: 409, headers: { "Content-Type": "application/json" } }
        );
      }
    }

    // Mark as processing
    await updateProcessingStatus(record.id, "processing");

    // Fetch existing record to check for HealthKit-linked data and pace segments
    const { data: existingRecord } = await supabase
      .from("training_logs")
      .select("workout_distance_miles, workout_duration_minutes, pace_segments, vital_workout_id, workout_date")
      .eq("id", record.id)
      .single();

    // Extract storage path from URL (everything after the bucket name)
    const audioUrl = new URL(record.audio_url);
    const bucketPrefix = "/storage/v1/object/public/training-memos/";
    const pathIndex = audioUrl.pathname.indexOf(bucketPrefix);
    const storagePath = pathIndex !== -1
      ? decodeURIComponent(audioUrl.pathname.slice(pathIndex + bucketPrefix.length))
      : audioUrl.pathname.split("/").pop();

    if (!storagePath) {
      throw new Error("Could not extract storage path from audio URL");
    }

    // Download audio file from storage
    const { data: audioData, error: downloadError } = await supabase.storage
      .from("training-memos")
      .download(storagePath);

    if (downloadError) {
      throw new Error(`Failed to download audio: ${downloadError.message}`);
    }

    // Start fetching recent logs in parallel with transcription (don't await yet)
    const recentLogsPromise = supabase
      .from("training_logs")
      .select("workout_date, cleaned_notes, mood, workout_notes, workout_distance_miles, workout_type")
      .not("cleaned_notes", "is", null)
      .order("workout_date", { ascending: false })
      .limit(5);

    // ── Step 1: Transcribe with Whisper (Groq → OpenAI → Gemini fallback) ──
    const audioArrayBuffer = await audioData.arrayBuffer();
    const mimeType = storagePath.endsWith(".m4a") ? "audio/mp4" : "audio/mpeg";
    const fileName = storagePath.split("/").pop() || "memo.m4a";

    let transcription: string | null = null;
    let transcriptionProvider = "unknown";

    // Try Groq Whisper first (cheapest, fastest)
    const groqKey = Deno.env.get("GROQ_API_KEY");
    if (groqKey && !transcription) {
      try {
        const formData = new FormData();
        formData.append("file", new File([audioArrayBuffer], fileName, { type: mimeType }));
        formData.append("model", "whisper-large-v3");
        formData.append("response_format", "verbose_json");

        const groqRes = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
          method: "POST",
          headers: { Authorization: `Bearer ${groqKey}` },
          body: formData,
          signal: AbortSignal.timeout(30000),
        });

        if (groqRes.ok) {
          const result = await groqRes.json();
          transcription = result.text;
          transcriptionProvider = "groq-whisper";
          console.log(`Groq Whisper transcription: ${transcription?.length} chars`);
        } else {
          console.error(`Groq failed: ${groqRes.status}`);
        }
      } catch (e) {
        console.error("Groq Whisper error:", e);
      }
    }

    // Fallback: OpenAI Whisper
    const openaiKey = Deno.env.get("OPENAI_API_KEY");
    if (openaiKey && !transcription) {
      try {
        const formData = new FormData();
        formData.append("file", new File([audioArrayBuffer], fileName, { type: mimeType }));
        formData.append("model", "whisper-1");
        formData.append("response_format", "verbose_json");

        const openaiRes = await fetch("https://api.openai.com/v1/audio/transcriptions", {
          method: "POST",
          headers: { Authorization: `Bearer ${openaiKey}` },
          body: formData,
          signal: AbortSignal.timeout(30000),
        });

        if (openaiRes.ok) {
          const result = await openaiRes.json();
          transcription = result.text;
          transcriptionProvider = "openai-whisper";
          console.log(`OpenAI Whisper transcription: ${transcription?.length} chars`);
        }
      } catch (e) {
        console.error("OpenAI Whisper error:", e);
      }
    }

    // Last resort: Gemini audio (original approach)
    if (!transcription) {
      const uint8Array = new Uint8Array(audioArrayBuffer);
      let binary = "";
      const chunkSize = 8192;
      for (let i = 0; i < uint8Array.length; i += chunkSize) {
        const chunk = uint8Array.subarray(i, i + chunkSize);
        binary += String.fromCharCode(...chunk);
      }
      const base64Audio = btoa(binary);

      const geminiModel = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });
      const geminiResult = await geminiModel.generateContent([
        { text: "Transcribe this audio recording verbatim. Return ONLY the transcription text, no formatting." },
        { inlineData: { mimeType, data: base64Audio } },
      ]);
      transcription = geminiResult.response.text().trim();
      transcriptionProvider = "gemini";
      console.log(`Gemini transcription fallback: ${transcription?.length} chars`);
    }

    if (!transcription || transcription.length < 5) {
      throw new Error("Transcription failed — no text extracted from audio");
    }

    console.log(`Transcription complete via ${transcriptionProvider}: "${transcription.slice(0, 100)}..."`);

    // ── Step 2: Analyze transcript with Gemini ──
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    // Await the recent logs that were fetched in parallel with transcription
    const { data: recentLogs } = await recentLogsPromise;

    let recentContext = "";
    if (recentLogs && recentLogs.length > 0) {
      recentContext = "\n\n## Recent Training Context\nHere are the runner's last few sessions so you understand their current training state:\n";
      for (const log of recentLogs) {
        const date = log.workout_date ? String(log.workout_date).split("T")[0] : "?";
        const dist = log.workout_distance_miles ? Number(log.workout_distance_miles).toFixed(1) + " mi" : "";
        recentContext += "- " + date + ": " + dist + " " + (log.workout_type || "") + " — " + (log.cleaned_notes || "no notes") + " (mood: " + (log.mood || "?") + ")\n";
      }
      recentContext += "\nUse this context to give advice that connects to their training patterns. Do NOT repeat information from previous sessions — focus on TODAY's memo.\n";
    }

    // Build Garmin/watch data context for sharper coaching
    let garminContext = "";
    if (existingRecord?.pace_segments && Array.isArray(existingRecord.pace_segments) && existingRecord.pace_segments.length > 0) {
      garminContext = "\n\n## GPS Watch Data (Garmin)\nThe runner's watch recorded these pace segments for this workout:\n";
      for (const seg of existingRecord.pace_segments) {
        const hr = seg.avg_heart_rate ? ` (${seg.avg_heart_rate} bpm)` : "";
        garminContext += `- ${seg.effort}: ${Number(seg.distance_miles).toFixed(2)} mi @ ${seg.pace_per_mile}/mi${hr}\n`;
      }
      if (existingRecord.workout_distance_miles) {
        const totalMin = existingRecord.workout_duration_minutes || 0;
        const avgPaceSec = totalMin > 0 && existingRecord.workout_distance_miles > 0
          ? Math.round((totalMin * 60) / existingRecord.workout_distance_miles)
          : 0;
        const paceM = Math.floor(avgPaceSec / 60);
        const paceS = avgPaceSec % 60;
        garminContext += `Total: ${Number(existingRecord.workout_distance_miles).toFixed(1)} mi in ${Math.round(totalMin)} min (${paceM}:${String(paceS).padStart(2, "0")}/mi avg)\n`;
      }
      garminContext += "\nUSE THIS DATA in your coach_insight. Compare what the runner SAID about their workout to what the WATCH DATA shows. Note discrepancies. Analyze effort distribution. Were easy segments actually easy? Did they fade or negative split? Be specific about paces.\n";
    }

    // Structured prompt with distinct fields and few-shot examples
    const prompt = `You are an elite running coach reading a transcript of your athlete's voice memo about their training.

Your job: analyze the transcript to produce 6 distinct fields. The transcription field should contain the transcript exactly as provided.

## CRITICAL RULES FOR coach_insight
- ONLY comment on what the runner ACTUALLY SAID. Do not invent topics they didn't mention.
- If they say they're sore from lifting/gym/strength training, acknowledge it as normal cross-training soreness. Do NOT interpret it as a running injury or form problem.
- NEVER comment on: body weight, body composition, BMI, appearance, or foot strike patterns (unless they specifically asked).
- You CAN encourage proper fueling and nutrition for performance (e.g., "make sure you're fueling well before your long run" or "recovery nutrition after hard sessions matters"). But NEVER suggest eating less, losing weight, or restricting calories.
- NEVER give medical diagnoses or suggest seeing a doctor unless they describe a specific acute injury.
- NEVER give generic filler advice like "keep it up", "listen to your body", or "stay hydrated".
- Your advice must be SPECIFIC to what they said and ACTIONABLE for their next run. Reference exact details from the memo.
- If the runner mentions soreness, fatigue, or tiredness, consider context: Did they mention lifting? A hard workout the day before? Poor sleep? Being sick? Address the ACTUAL cause, not a guess.
- When you don't have enough information to give specific advice, say something observational about their training pattern rather than making something up.

## Field Definitions

1. **transcription**: The complete, verbatim transcription of what the runner said.

2. **cleaned_notes**: A 2-4 sentence first-person summary of the training experience (write as if you ARE the runner — "I felt...", "Legs were...", "Started easy and..."). Focus on how they felt, what went well or poorly, and any observations. Do NOT include specific numbers (distance, pace) here — those go in workout_notes. Do NOT include coaching advice here. Never write "the runner" — this IS the runner's own summary.

3. **mood**: Assess the runner's mood from their voice tone and words. Return exactly ONE of these values:
   - "energized" = excited, fired up, feeling great
   - "positive" = good, happy, satisfied with training
   - "neutral" = matter-of-fact, neither good nor bad
   - "tired" = fatigued, low energy, drained
   - "struggling" = frustrated, overwhelmed, having a hard time
   - "injured" = reporting pain, injury, or physical issue (ONLY for running-related injuries, NOT soreness from lifting)

4. **coach_insight**: 1-2 sentences of specific, actionable TRAINING advice. See CRITICAL RULES above.

5. **workout_notes**: A structured text summary of quantitative training details mentioned. Use this format with one item per line:
   - Distance: X miles (or km)
   - Duration: X:XX
   - Pace: X:XX/mi
   - Intervals: 4x800m @ 2:45 w/ 90s rest
   - Warmup: 1 mile easy
   - Cooldown: 1 mile easy
   Only include lines for data the runner actually mentioned. Return null if no quantitative data was mentioned.

6. **extracted_data**: A JSON object with structured numeric/typed data extracted from the memo. Only include fields that were mentioned:
   {
     "distance_miles": number or null,
     "pace_per_mile": "M:SS" string or null,
     "duration_minutes": number or null,
     "workout_type": "easy" | "tempo" | "interval" | "long_run" | "recovery" | "race" | "other",
     "intervals": [{"distance": "800m", "time": "2:45", "rest": "90s", "count": 4}] or null,
     "splits": [{"mile": 1, "time": "7:30"}, {"mile": 2, "time": "7:15"}] or null,
     "warmup": "1 mile easy" or null,
     "cooldown": "1 mile easy" or null,
     "rpe": number 1-10 or null (rate of perceived exertion — infer from how they described the effort),
     "weather": "hot and humid" | "cold" | "windy" | "rainy" | "perfect" | string or null,
     "terrain": "track" | "road" | "trail" | "treadmill" | "mixed" or null,
     "running_partners": ["name1", "name2"] or null (people they mentioned running with),
     "shoe": string or null (if they mentioned specific shoes),
     "sleep_quality": "good" | "poor" | "ok" or null (if they mentioned sleep),
     "fueling": string or null (if they mentioned what they ate/drank before or during),
     "effort_level": "easy" | "moderate" | "hard" | "max" or null
   }
   Always return at least a partial object with whatever fields you can extract — RPE, weather, terrain, running partners, etc. Only return null if the runner said absolutely nothing about their training.

## Examples

### Example 1: Quantitative memo
Audio: "Just got back from my long run. Did 13 miles in about 1 hour 45. Started around 8:30 pace, worked down to 7:45 for the last three miles. Legs felt really good, nice and loose the whole way."

Response:
{
  "transcription": "Just got back from my long run. Did 13 miles in about 1 hour 45. Started around 8:30 pace, worked down to 7:45 for the last three miles. Legs felt really good, nice and loose the whole way.",
  "cleaned_notes": "Great long run today. Legs felt loose and good throughout. Ran a natural negative split, finishing faster than starting pace.",
  "mood": "positive",
  "coach_insight": "Your ability to negative split a long run is a strong sign of aerobic fitness. Consider pushing the last 3 miles to 7:30 pace next week to continue building that finishing kick.",
  "workout_notes": "Distance: 13 miles\\nDuration: 1:45\\nPace: ~8:05/mi average\\nSplits: Started at 8:30/mi, finished at 7:45/mi for last 3 miles",
  "extracted_data": {
    "distance_miles": 13,
    "pace_per_mile": "8:05",
    "duration_minutes": 105,
    "workout_type": "long_run",
    "effort_level": "moderate"
  }
}

### Example 2: Interval workout
Audio: "Did my track workout today. Warmed up with a mile, then did 6 times 800 at 2:50 with 90 seconds jog recovery. Felt strong on the first four, the last two were tough. Cooled down with a mile."

Response:
{
  "transcription": "Did my track workout today. Warmed up with a mile, then did 6 times 800 at 2:50 with 90 seconds jog recovery. Felt strong on the first four, the last two were tough. Cooled down with a mile.",
  "cleaned_notes": "Solid track session. Felt strong through the first four reps but the last two were a grind. Good effort overall.",
  "mood": "positive",
  "coach_insight": "Fading on the last 2 reps suggests you're at the right intensity. Next session, try holding 2:50 for all 6 — if you can, it's time to move to 2:45.",
  "workout_notes": "Warmup: 1 mile\\nIntervals: 6x800m @ 2:50 w/ 90s jog recovery\\nCooldown: 1 mile",
  "extracted_data": {
    "workout_type": "interval",
    "intervals": [{"distance": "800m", "time": "2:50", "rest": "90s jog", "count": 6}],
    "warmup": "1 mile",
    "cooldown": "1 mile",
    "effort_level": "hard"
  }
}

### Example 3: Purely subjective memo
Audio: "Honestly just feeling really beat up today. My hamstring has been bugging me since Tuesday and I don't know if I should run tomorrow. Just took today off."

Response:
{
  "transcription": "Honestly just feeling really beat up today. My hamstring has been bugging me since Tuesday and I don't know if I should run tomorrow. Just took today off.",
  "cleaned_notes": "Feeling beat up with a nagging hamstring issue since Tuesday. Took today as a rest day and unsure about running tomorrow.",
  "mood": "injured",
  "coach_insight": "Smart decision to rest. If the hamstring pain hasn't improved by tomorrow, consider a gentle bike or pool session instead of running, and if it persists beyond 5 days, see a physio.",
  "workout_notes": null,
  "extracted_data": null
}

### Example 4: Cross-training soreness (NOT a running injury)
Audio: "Went for an easy 5 miler today. Legs were really sore from leg day yesterday at the gym. The run felt fine though, just slow."

Response:
{
  "transcription": "Went for an easy 5 miler today. Legs were really sore from leg day yesterday at the gym. The run felt fine though, just slow.",
  "cleaned_notes": "Easy 5-miler on sore legs from yesterday's gym session. The run itself felt fine, just slower than usual.",
  "mood": "neutral",
  "coach_insight": "Running easy on gym-sore legs is a solid way to flush them out. If you have a quality session planned this week, leave at least 48 hours between heavy leg day and that workout.",
  "workout_notes": "Distance: 5 miles",
  "extracted_data": {
    "distance_miles": 5,
    "workout_type": "easy",
    "effort_level": "easy"
  }
}
${recentContext}
## Important
- Respond ONLY with the JSON object, no markdown code blocks, no extra text.
- All 6 top-level fields must be present in the response.
- workout_notes and extracted_data should be null (not empty string or empty object) when no quantitative data is mentioned.`;

    // Feed the TEXT transcript + Garmin data to Gemini for analysis
    const result = await model.generateContent([
      { text: prompt + garminContext + `\n\n## Audio Transcript (from ${transcriptionProvider})\n"${transcription}"` },
    ]);

    const responseText = result.response.text();
    console.log("Gemini raw response length:", responseText.length);

    // Parse and validate
    const rawAnalysis = parseJsonResponse(responseText);
    const analysis = validateAnalysis(rawAnalysis);

    // Save full transcript to storage
    let transcriptUrl: string | null = null;
    if (analysis.transcription) {
      const transcriptFileName = storagePath.replace(/\.(m4a|mp3|wav)$/, "_transcript.txt");
      const transcriptContent = new TextEncoder().encode(analysis.transcription);

      const { error: uploadError } = await supabase.storage
        .from("training-memos")
        .upload(transcriptFileName, transcriptContent, {
          contentType: "text/plain",
          upsert: true,
        });

      if (!uploadError) {
        const { data: urlData } = supabase.storage
          .from("training-memos")
          .getPublicUrl(transcriptFileName);
        transcriptUrl = urlData.publicUrl;
        console.log(`Saved transcript to: ${transcriptUrl}`);
      } else {
        console.error(`Failed to save transcript: ${uploadError.message}`);
      }
    }

    // Build update payload — only overwrite distance/duration if no HealthKit values exist
    const updatePayload: Record<string, unknown> = {
      cleaned_notes: analysis.cleaned_notes,
      mood: analysis.mood,
      coach_insight: analysis.coach_insight,
      workout_notes: analysis.workout_notes,
      transcript_url: transcriptUrl,
      extracted_data: analysis.extracted_data,
      processing_status: "completed",
      processing_error: null,
    };

    // Populate workout_type and pace from extracted_data
    if (analysis.extracted_data) {
      if (analysis.extracted_data.workout_type) {
        updatePayload.workout_type = analysis.extracted_data.workout_type;
      }
      if (analysis.extracted_data.pace_per_mile) {
        updatePayload.workout_pace_per_mile = analysis.extracted_data.pace_per_mile;
      }
      // Only fill distance/duration if not already set from HealthKit
      if (analysis.extracted_data.distance_miles && !existingRecord?.workout_distance_miles) {
        updatePayload.workout_distance_miles = analysis.extracted_data.distance_miles;
      }
      if (analysis.extracted_data.duration_minutes && !existingRecord?.workout_duration_minutes) {
        updatePayload.workout_duration_minutes = analysis.extracted_data.duration_minutes;
      }
    }

    // Update training_logs with all results
    const { error: updateError } = await supabase
      .from("training_logs")
      .update(updatePayload)
      .eq("id", record.id);

    if (updateError) {
      throw new Error(`Failed to update training log: ${updateError.message}`);
    }

    // Create injury record if injury detected in voice memo
    try {
      const { data: logData } = await supabase
        .from("training_logs")
        .select("user_id")
        .eq("id", record.id)
        .single();

      // Use user_id from log, fall back to "dev-user" when auth is disabled
      const injuryUserId = logData?.user_id || "dev-user";
      const textToScan = `${analysis.cleaned_notes || ""} ${analysis.transcription || ""}`;
      const detected = detectInjury(textToScan);

      if (detected || analysis.mood === "injured") {
        const injury = detected || {
          bodyArea: "unspecified",
          side: "unknown",
          isResolved: false,
          severity: 5,
        };

        await upsertInjury(supabase, injuryUserId, {
          ...injury,
          source: "voice_memo",
          sourceReferenceId: record.id,
          description: analysis.cleaned_notes?.slice(0, 200),
        });

        // ── Voice-to-Action: auto-trigger injury-early-warning ──
        // When an injury is detected in a voice memo, immediately run the
        // injury risk assessment so the athlete state gets updated with the
        // new risk score and the coaching agent knows about it.
        console.log(`[Voice-to-Action] Injury detected (${injury.bodyArea}) — triggering injury-early-warning`);
        try {
          const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
          const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
          await fetch(`${supabaseUrl}/functions/v1/injury-early-warning`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${serviceKey}`,
              apikey: serviceKey,
            },
            body: JSON.stringify({ user_id: injuryUserId }),
            signal: AbortSignal.timeout(15000),
          });
          console.log(`[Voice-to-Action] Injury-early-warning completed for ${injuryUserId}`);
        } catch (warningError) {
          console.warn(`[Voice-to-Action] Injury-early-warning failed (non-fatal):`, warningError);
        }
      }
    } catch (injuryError) {
      console.error("Error creating injury record:", injuryError);
      // Don't fail the request if injury tracking fails
    }

    // ── Update Athlete State (Dynamic Context Object) ──
    // Full rebuild after a voice log because the training load metrics change.
    const { data: stateLogRow } = await supabase
      .from("training_logs")
      .select("user_id")
      .eq("id", record.id)
      .single();
    const stateUserId = stateLogRow?.user_id;
    if (stateUserId) {
      try {
        await rebuildAthleteState(supabase, stateUserId);
      } catch (stateError) {
        console.error("Athlete state rebuild failed (non-fatal):", stateError);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        id: record.id,
        mood: analysis.mood,
        cleaned_notes: analysis.cleaned_notes,
        coach_insight: analysis.coach_insight,
        workout_notes: analysis.workout_notes,
        workout_type: analysis.extracted_data?.workout_type || null,
        transcript_url: transcriptUrl,
      }),
      {
        status: 200,
        headers: { "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Error processing training memo:", error);

    // Mark as failed with error message
    if (recordId) {
      await updateProcessingStatus(recordId, "failed", error.message);
    }

    return new Response(
      JSON.stringify({ error: "Processing failed. Please try again." }),
      {
        status: 500,
        headers: { "Content-Type": "application/json" },
      }
    );
  }
});
