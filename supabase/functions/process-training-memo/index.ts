import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { detectInjury, upsertInjury } from "../_shared/injuries.ts";

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

    // Fetch existing record to check for HealthKit-linked data
    const { data: existingRecord } = await supabase
      .from("training_logs")
      .select("workout_distance_miles, workout_duration_minutes")
      .eq("id", record.id)
      .single();

    // Extract filename from URL
    const audioUrl = new URL(record.audio_url);
    const fileName = audioUrl.pathname.split("/").pop();

    if (!fileName) {
      throw new Error("Could not extract filename from audio URL");
    }

    // Download audio file from storage
    const { data: audioData, error: downloadError } = await supabase.storage
      .from("training-memos")
      .download(fileName);

    if (downloadError) {
      throw new Error(`Failed to download audio: ${downloadError.message}`);
    }

    // Convert to base64 for Gemini (chunked to avoid stack overflow)
    const arrayBuffer = await audioData.arrayBuffer();
    const uint8Array = new Uint8Array(arrayBuffer);
    let binary = "";
    const chunkSize = 8192;
    for (let i = 0; i < uint8Array.length; i += chunkSize) {
      const chunk = uint8Array.subarray(i, i + chunkSize);
      binary += String.fromCharCode(...chunk);
    }
    const base64Audio = btoa(binary);

    // Get MIME type
    const mimeType = fileName.endsWith(".m4a") ? "audio/mp4" : "audio/mpeg";

    // Initialize Gemini model
    const model = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

    // Structured prompt with distinct fields and few-shot examples
    const prompt = `You are an elite running coach analyzing a runner's voice memo about their training.

Transcribe the audio accurately, then analyze it to produce 6 distinct fields.

## Field Definitions

1. **transcription**: The complete, verbatim transcription of what the runner said.

2. **cleaned_notes**: A 2-4 sentence summary of the runner's subjective training experience. Focus on how they felt, what went well or poorly, and any observations. Do NOT include specific numbers (distance, pace) here — those go in workout_notes. Do NOT include coaching advice here.

3. **mood**: Assess the runner's mood from their voice tone and words. Return exactly ONE of these values:
   - "energized" = excited, fired up, feeling great
   - "positive" = good, happy, satisfied with training
   - "neutral" = matter-of-fact, neither good nor bad
   - "tired" = fatigued, low energy, drained
   - "struggling" = frustrated, overwhelmed, having a hard time
   - "injured" = reporting pain, injury, or physical issue

4. **coach_insight**: 1-2 sentences of specific, actionable coaching advice based on what they shared. Be supportive and forward-looking. Reference specific details from their memo. Example: "Since you felt strong through the last 3 miles of your long run, consider adding a mile next week" rather than generic advice like "great job, keep it up."

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
     "effort_level": "easy" | "moderate" | "hard" | "max" or null
   }
   Return null if no quantitative data was mentioned.

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

## Important
- Respond ONLY with the JSON object, no markdown code blocks, no extra text.
- All 6 top-level fields must be present in the response.
- workout_notes and extracted_data should be null (not empty string or empty object) when no quantitative data is mentioned.`;

    const result = await model.generateContent([
      { text: prompt },
      {
        inlineData: {
          mimeType,
          data: base64Audio,
        },
      },
    ]);

    const responseText = result.response.text();
    console.log("Gemini raw response length:", responseText.length);

    // Parse and validate
    const rawAnalysis = parseJsonResponse(responseText);
    const analysis = validateAnalysis(rawAnalysis);

    // Save full transcript to storage
    let transcriptUrl: string | null = null;
    if (analysis.transcription) {
      const transcriptFileName = fileName.replace(/\.(m4a|mp3|wav)$/, "_transcript.txt");
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
      }
    } catch (injuryError) {
      console.error("Error creating injury record:", injuryError);
      // Don't fail the request if injury tracking fails
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
