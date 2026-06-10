import { createClient } from "jsr:@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { detectInjury, upsertInjury } from "../_shared/injuries.ts";
import { rebuildAthleteState } from "../_shared/athlete-state.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit } from "../_shared/rateLimit.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import {
  loadCoachContext,
  formatPacesBlock,
  classifyPace,
  comparePrescribedToExecuted,
  findSimilarPriorWorkout,
  formatProgressionBlock,
  formatSplitsBlock,
  splitsFromPaceSegments,
  type ScheduledLite as CoachScheduledLite,
} from "../_shared/coach-context.ts";

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
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let recordId: string | null = null;

  try {
    const payload: TrainingLogPayload = await req.json();
    const { record } = payload;
    recordId = record.id;

    // Auth gate — record.user_id is part of the payload. Service-role
    // callers (DB trigger / chained edge function) bypass the JWT check
    // but must still name the subject user. iOS callers must present a
    // JWT matching record.user_id.
    const bodyUserId = (record as { user_id?: string }).user_id;
    const auth = await requireAuthOrServiceRole(req, bodyUserId, corsHeaders);
    if ("response" in auth) return auth.response;
    const { userId: authUserId, isServiceRole } = auth;

    const rlBlocked = await enforceFeatureRateLimit(authUserId, "voice_memo", corsHeaders, { isServiceRole });
    if (rlBlocked) return rlBlocked;

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
      .select("workout_distance_miles, workout_duration_minutes, pace_segments, vital_workout_id, workout_date, scheduled_workout_id, workout_type")
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

    // Coach context fetched in parallel with transcription — adds zone
    // anchors and (if linked) prescribed-vs-executed framing to the prompt.
    const coachContextPromise = (record as { user_id?: string }).user_id
      ? loadCoachContext(supabase, (record as { user_id: string }).user_id)
      : Promise.resolve({ zones: null, goal: null });

    // Scheduled-workout fetch (when linked) for prescribed-vs-executed.
    const scheduledPromise = (existingRecord as { scheduled_workout_id?: string | null })?.scheduled_workout_id
      ? supabase
          .from("scheduled_workouts")
          .select("workout_type, workout_data")
          .eq("id", (existingRecord as { scheduled_workout_id: string }).scheduled_workout_id)
          .maybeSingle()
      : Promise.resolve({ data: null });

    // Similar prior workout — gated on having workout_type + distance +
    // duration on the row at function entry (typically true when
    // HealthKit pre-populated the row). For pure voice-only logs where
    // workout_type is determined by the LLM analysis later, we skip
    // progression in this round; the next session will see this one as
    // the prior.
    const existingType = (existingRecord as { workout_type?: string | null })?.workout_type ?? null;
    const existingDist = existingRecord?.workout_distance_miles as number | null;
    const existingDur = existingRecord?.workout_duration_minutes as number | null;
    const existingDate = existingRecord?.workout_date as string | null;
    const existingPaceSec = (existingDist && existingDur && existingDist > 0 && existingDur > 0)
      ? Math.round((Number(existingDur) * 60) / Number(existingDist))
      : null;

    const userIdForMatcher = (record as { user_id?: string }).user_id;
    const priorPromise = (existingType && existingDist && existingPaceSec && existingDate && userIdForMatcher)
      ? findSimilarPriorWorkout(
          supabase,
          userIdForMatcher,
          {
            workoutType: existingType,
            distanceMiles: existingDist,
            paceSecPerMile: existingPaceSec,
          },
          new Date(existingDate),
        )
      : Promise.resolve(null);

    // Start fetching recent logs in parallel with transcription (don't await yet)
    const recentLogsPromise = supabase
      .from("training_logs")
      .select("workout_date, cleaned_notes, mood, workout_notes, workout_distance_miles, workout_type")
      .eq("user_id", record.user_id)
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

    // Await the recent logs + coach context + scheduled workout + similar
    // prior workout — all fetched in parallel with transcription.
    const [recentRes, coachCtx, scheduledRes, prior] = await Promise.all([
      recentLogsPromise,
      coachContextPromise,
      scheduledPromise,
      priorPromise,
    ]);
    const recentLogs = recentRes.data;
    const scheduledLite = (scheduledRes.data ?? null) as CoachScheduledLite | null;

    // ── Pace anchoring + classification + prescription comparison ──
    // These blocks are independent: paces always render when zones are
    // available, classification renders when we have an executed avg pace,
    // prescription block only renders when a scheduled_workout is linked.
    const pacesBlock = formatPacesBlock(coachCtx);

    const executedPaceSec = (() => {
      const dist = existingRecord?.workout_distance_miles;
      const dur = existingRecord?.workout_duration_minutes;
      if (dist && dur && dist > 0 && dur > 0) {
        return Math.round((Number(dur) * 60) / Number(dist));
      }
      return null;
    })();

    const classificationLine =
      executedPaceSec != null && coachCtx.zones
        ? classifyPace(executedPaceSec, coachCtx.zones).summary
        : "";

    const prescribedComparison =
      scheduledLite
        ? comparePrescribedToExecuted(
            scheduledLite,
            {
              averagePaceSec: executedPaceSec,
              paceSegments: existingRecord?.pace_segments as Array<{
                effort?: string;
                pace_per_mile?: string;
                distance_miles?: number;
              }> | undefined,
            },
            coachCtx.zones,
          )
        : null;

    // Workout progression block — only when matcher found a comparable
    // prior AND the deltas are meaningful (formatProgressionBlock filters
    // out runs that are essentially the same).
    const progressionComparison = (prior && existingType && existingDist && existingPaceSec)
      ? formatProgressionBlock(
          {
            workoutType: existingType,
            distanceMiles: existingDist,
            paceSecPerMile: existingPaceSec,
          },
          prior,
        )
      : null;

    // Splits block — Garmin/HealthKit segments if available. Voice path
    // can't use voice-extracted intervals here because the LLM hasn't
    // run yet; those become available on the row after this function
    // writes extracted_data. For voice-only workouts with no watch data,
    // splits are surfaced in workout_notes via the LLM's own extraction.
    const watchSplits = splitsFromPaceSegments(
      existingRecord?.pace_segments as Array<{
        effort?: string;
        distance_miles?: number | string;
        pace_per_mile?: string;
        avg_heart_rate?: number;
      }> | null,
    );
    const splitsBlock = formatSplitsBlock(watchSplits, coachCtx.zones);

    let coachAnchorContext = "";
    if (pacesBlock) {
      coachAnchorContext = `\n\n${pacesBlock}`;
    }
    if (classificationLine) {
      coachAnchorContext += `\n\n## Zone classification (deterministic — trust this over your own pace math)\n${classificationLine}`;
    }
    if (splitsBlock) {
      coachAnchorContext += `\n\n${splitsBlock}`;
    }
    if (prescribedComparison?.block) {
      coachAnchorContext += `\n\n${prescribedComparison.block}`;
    }
    if (progressionComparison?.block) {
      coachAnchorContext += `\n\n${progressionComparison.block}`;
    }

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
    const prompt = loadPrompt("process-training-memo.v1", { coachAnchorContext, recentContext });

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
