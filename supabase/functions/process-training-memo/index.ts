import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { detectInjury, upsertInjury } from "../_shared/injuries.ts";
import { rebuildAthleteState } from "../_shared/athlete-state.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
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
  splitsFromExtractedIntervals,
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
    user_id?: string;
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

// ── Voice-extracted → workout-field mapping ───────────────────────────────
// The voice analyzer drops structured detail (reps, splits, paces, effort)
// into the `extracted_data` JSON blob. These helpers lift that detail onto
// the row's actual workout columns so a spoken session is DISPLAYABLE (rep
// chart + insight splits + notes) instead of buried in JSON.

/** Format seconds/mile as "M:SS". */
function formatPaceMMSS(sec: number): string {
  const m = Math.floor(sec / 60);
  const s = Math.round(sec % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

/** Parse a "M:SS" pace/time string to seconds, or null. */
function parsePaceMMSS(s: string | undefined): number | null {
  if (!s) return null;
  const m = s.trim().match(/^(\d{1,2}):([0-5]\d)$/);
  if (!m) return null;
  return parseInt(m[1]) * 60 + parseInt(m[2]);
}

/**
 * Build `pace_segments` rows from the voice-extracted structured data so a
 * spoken interval/rep session renders on the row (rep chart + the insight's
 * splits block) instead of living only inside the `extracted_data` blob.
 *
 * Source priority:
 *   1. extracted_data.intervals — "6×800m @ 2:50" style reps. Expanded by
 *      count via the shared parser the insight already trusts; needs a
 *      parseable distance AND time so a pace can be derived. Effort-only reps
 *      (no time → no pace) fall through and are captured in workout_notes.
 *   2. extracted_data.splits — mile-by-mile "{mile, time}" splits (tempo /
 *      progression runs). Each is one mile at the stated pace.
 *
 * Returns rows in the Garmin/HealthKit `pace_segments` shape
 * ({effort, distance_miles, pace_per_mile}); empty array when nothing is
 * derivable.
 */
function paceSegmentsFromExtracted(
  extracted: Record<string, unknown>,
): Array<{ effort: string; distance_miles: number; pace_per_mile: string }> {
  // 1. Intervals → reps.
  const intervals = Array.isArray(extracted.intervals)
    ? (extracted.intervals as Array<{ distance?: string; time?: string; rest?: string; count?: number }>)
    : null;
  const reps = splitsFromExtractedIntervals(intervals);
  if (reps.length > 0) {
    return reps.map((r) => ({
      effort: r.label,
      distance_miles: Number(r.distanceMiles.toFixed(3)),
      pace_per_mile: formatPaceMMSS(r.paceSecPerMile),
    }));
  }

  // 2. Mile splits → one segment per mile (split time IS the per-mile pace).
  const splits = Array.isArray(extracted.splits)
    ? (extracted.splits as Array<{ mile?: number; time?: string }>)
    : null;
  if (splits) {
    const out: Array<{ effort: string; distance_miles: number; pace_per_mile: string }> = [];
    for (const sp of splits) {
      const paceSec = parsePaceMMSS(sp.time);
      if (paceSec == null) continue;
      out.push({
        effort: `Mile ${sp.mile ?? out.length + 1}`,
        distance_miles: 1,
        pace_per_mile: formatPaceMMSS(paceSec),
      });
    }
    return out;
  }

  return [];
}

/**
 * Last-resort `workout_notes` builder. The LLM almost always returns a
 * formatted workout_notes string, but when it doesn't (and there IS
 * structured data), synthesize a minimal human-readable summary so the
 * spoken session is never lost to the `extracted_data` blob alone. This is
 * the "at minimum, capture it in notes" floor for effort-only reps that
 * carry no pace (and so produce no pace_segments).
 */
function synthesizeWorkoutNotes(extracted: Record<string, unknown>): string | null {
  const lines: string[] = [];

  const intervals = Array.isArray(extracted.intervals)
    ? (extracted.intervals as Array<{ distance?: string; time?: string; rest?: string; count?: number }>)
    : null;
  if (intervals && intervals.length > 0) {
    const parts = intervals
      .map((iv) => {
        const dist = (iv.distance ?? "").trim();
        if (!dist) return "";
        const count = iv.count && iv.count > 1 ? `${iv.count}×` : "";
        const time = iv.time ? ` @ ${iv.time}` : "";
        const rest = iv.rest ? ` w/ ${iv.rest} rest` : "";
        return `${count}${dist}${time}${rest}`.trim();
      })
      .filter((s) => s.length > 0);
    if (parts.length > 0) lines.push(`Intervals: ${parts.join(", ")}`);
  }

  const dist = Number(extracted.distance_miles);
  if (Number.isFinite(dist) && dist > 0) lines.push(`Distance: ${dist} miles`);

  if (typeof extracted.pace_per_mile === "string" && extracted.pace_per_mile.trim()) {
    lines.push(`Pace: ${extracted.pace_per_mile.trim()}/mi`);
  }

  const warmup = typeof extracted.warmup === "string" ? extracted.warmup.trim() : "";
  if (warmup) lines.push(`Warmup: ${warmup}`);
  const cooldown = typeof extracted.cooldown === "string" ? extracted.cooldown.trim() : "";
  if (cooldown) lines.push(`Cooldown: ${cooldown}`);

  const effort = typeof extracted.effort_level === "string" ? extracted.effort_level.trim() : "";
  const rpe = Number(extracted.rpe);
  if (effort && Number.isFinite(rpe)) lines.push(`Effort: ${effort} (RPE ${rpe})`);
  else if (effort) lines.push(`Effort: ${effort}`);
  else if (Number.isFinite(rpe)) lines.push(`Effort: RPE ${rpe}`);

  return lines.length > 0 ? lines.join("\n") : null;
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

    // ── Ownership guard (IDOR protection) ─────────────────────────────
    // The auth gate above only proves the JWT matches the body user_id;
    // it does NOT prove the training_logs row identified by record.id
    // belongs to that user. Fetch the row once and require ownership
    // before any read/write keyed on record.id. Returns 404 (not 403) so
    // an attacker can't distinguish "not yours" from "doesn't exist".
    const { data: ownerRow, error: ownerErr } = await supabase
      .from("training_logs")
      .select("user_id")
      .eq("id", recordId)
      .maybeSingle();
    if (ownerErr || !ownerRow || ownerRow.user_id !== authUserId) {
      return new Response(
        JSON.stringify({ error: "Not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    // From here on, authUserId is the verified owner of record.id.

    const rlBlocked = await enforceFeatureRateLimit(authUserId, "voice_memo", corsHeaders, { isServiceRole });
    if (rlBlocked) return rlBlocked;

    // Hard monthly ceiling: ≤200 voice-memo uploads processed per user/month.
    const capped = await enforceMonthlyCap(authUserId, "voice_memo", 200, corsHeaders, { isServiceRole });
    if (capped) return capped;

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
    const coachContextPromise = loadCoachContext(supabase, authUserId);

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

    const userIdForMatcher = authUserId;
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
      .eq("user_id", authUserId)
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
      // A (2026-06-17 rev3): the AI Insight is NOT written or triggered here.
      // This function owns only the Voice Summary (cleaned_notes / mood /
      // workout_notes / pace_segments / extracted_data). The athlete-state-aware
      // v5 insight is generated ON DEMAND when the athlete taps "Generate AI
      // insight" (WorkoutRepChart.swift), which calls generate-workout-insight
      // directly. We leave coach_insight null and status "pending" so the row
      // rests in the un-generated state until that tap — no auto/synchronous
      // generation, no empty-window race.
      coach_insight_status: "pending",
      transcript_url: transcriptUrl,
      extracted_data: analysis.extracted_data,
      processing_status: "completed",
      processing_error: null,
    };

    // workout_notes: the voice memo is the PRIMARY source — but only write it
    // when the memo actually described the session. A null/empty value here
    // would clobber the AI-from-laps note that compute-workout-features
    // derives when the athlete didn't describe the workout out loud. So we
    // leave the field untouched on a no-description memo and let the laps
    // fallback stand. Voice description always wins when present.
    if (typeof analysis.workout_notes === "string" && analysis.workout_notes.trim().length > 0) {
      updatePayload.workout_notes = analysis.workout_notes;
    } else if (analysis.extracted_data) {
      // The LLM returned no workout_notes but DID extract structured data —
      // synthesize a minimal summary so a spoken interval/effort session is
      // captured on the row rather than lost to the extracted_data blob. This
      // is the "at minimum, in notes" floor for effort-only reps (e.g. "2K and
      // 1K at effort 7-8") that carry no pace and so produce no pace_segments.
      const synthNotes = synthesizeWorkoutNotes(analysis.extracted_data);
      if (synthNotes) updatePayload.workout_notes = synthNotes;
    }

    // Populate workout_type and pace from extracted_data — but VALIDATE
    // first. The LLM can hallucinate out-of-range or malformed values, and
    // these feed ACWR fallback weights + dedup downstream. Reject anything
    // implausible rather than poisoning the training history.
    if (analysis.extracted_data) {
      const ed = analysis.extracted_data;

      // workout_type: non-empty string, capped length. (No CHECK constraint
      // exists on the column yet, so guard here.)
      if (typeof ed.workout_type === "string") {
        const wt = ed.workout_type.trim();
        if (wt.length > 0 && wt.length <= 40) {
          updatePayload.workout_type = wt;
        }
      }

      // pace_per_mile: must look like M:SS or MM:SS.
      if (typeof ed.pace_per_mile === "string" && /^\d{1,2}:[0-5]\d$/.test(ed.pace_per_mile.trim())) {
        updatePayload.workout_pace_per_mile = ed.pace_per_mile.trim();
      }

      // distance_miles: positive, sane upper bound (ultra-distance ceiling).
      const dist = Number(ed.distance_miles);
      if (Number.isFinite(dist) && dist > 0 && dist <= 200 && !existingRecord?.workout_distance_miles) {
        updatePayload.workout_distance_miles = dist;
      }

      // duration_minutes: positive, under ~33h ceiling.
      const dur = Number(ed.duration_minutes);
      if (Number.isFinite(dur) && dur > 0 && dur <= 2000 && !existingRecord?.workout_duration_minutes) {
        updatePayload.workout_duration_minutes = dur;
      }

      // pace_segments: surface the spoken rep/split structure as displayable
      // segments (rep chart + the insight's splits block). NEVER clobber the
      // richer Garmin/HealthKit segments already on the row — those carry HR
      // and true GPS distances the voice path can't. We only fill the gap for
      // voice-only logs that have no watch segments yet.
      const hasWatchSegments =
        Array.isArray(existingRecord?.pace_segments) && existingRecord.pace_segments.length > 0;
      if (!hasWatchSegments) {
        const segs = paceSegmentsFromExtracted(ed);
        if (segs.length > 0) updatePayload.pace_segments = segs;
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

    // ── A (2026-06-17 rev3): AI Insight is ON DEMAND, not generated here. ──
    // Earlier revs generated the v5 insight from this function (first async via
    // a coach_insight_jobs row, then synchronously inline). We've moved it to a
    // pure button-tap flow: the athlete reviews the parsed workout (notes /
    // pace_segments / fields written above), then taps "Generate AI insight"
    // (WorkoutRepChart.swift), which calls generate-workout-insight directly
    // with the user's JWT. So this function neither calls nor enqueues the
    // insight — coach_insight stays null and coach_insight_status "pending"
    // until that tap. The INSERT trigger (fn_enqueue_workout_insight) already
    // skips voice rows, so no auto-generation path remains.

    // Create injury record if injury detected in voice memo
    try {
      // Verified owner from the ownership guard — never a "dev-user" stand-in.
      const injuryUserId = authUserId;
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
    try {
      await rebuildAthleteState(supabase, authUserId);
    } catch (stateError) {
      console.error("Athlete state rebuild failed (non-fatal):", stateError);
    }

    return new Response(
      JSON.stringify({
        success: true,
        id: record.id,
        mood: analysis.mood,
        cleaned_notes: analysis.cleaned_notes,
        // A (2026-06-17 rev3): AI Insight is generated on demand via the
        // "Generate AI insight" button (generate-workout-insight), not here —
        // return null so callers don't persist a stale/empty read.
        coach_insight: null,
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
      await updateProcessingStatus(recordId, "failed", error instanceof Error ? error.message : String(error));
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
