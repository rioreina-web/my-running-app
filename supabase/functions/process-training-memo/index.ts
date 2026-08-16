import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { corsHeaders } from "../_shared/cors.ts";
import { captureException, flushSentry } from "../_shared/sentry.ts";
import { requireAuthOrServiceRole } from "../_shared/auth.ts";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { llmBudgetAllows, llmBudgetBlockedResponse } from "../_shared/llm-budget.ts";
import {
  isProviderExhausted,
  PROVIDER_EXHAUSTED_MARKER,
  PROVIDER_EXHAUSTED_STATUS,
} from "../_shared/provider-errors.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { writeNiggleMentions, writeNiggleResolutions } from "../_shared/niggleWriter.ts";
import { writeMemoryCandidates } from "../_shared/memoryWriter.ts";
import {
  loadCoachContext,
  formatPacesBlock,
  classifyPace,
  comparePrescribedToExecuted,
  findSimilarPriorWorkout,
  formatProgressionBlock,
  formatSplitsBlock,
  isQualityWorkoutType,
  splitsFromPaceSegments,
  splitsFromExtractedIntervals,
  splitsFromLaps,
  splitsFromParsedBlocks,
  type ScheduledLite as CoachScheduledLite,
} from "../_shared/coach-context.ts";
import { getOrBuildAthleteState, stateToPromptContext } from "../_shared/athlete-state.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

const supabase = createClient(supabaseUrl, supabaseServiceKey);
const genAI = new GoogleGenerativeAI(geminiApiKey);

// Background-task hook (Supabase keeps the worker alive until the promise
// settles). Falls back to a detached promise off-platform.
declare const EdgeRuntime: { waitUntil(p: Promise<unknown>): void } | undefined;

/**
 * Run a promise off the critical path. Supabase's EdgeRuntime.waitUntil keeps
 * the worker alive until it settles; off-platform we just detach. Callers must
 * pass promises that never throw (or .catch first) — this is fire-and-forget.
 */
function runInBackground(p: Promise<unknown>): void {
  try {
    if (typeof EdgeRuntime !== "undefined" && EdgeRuntime?.waitUntil) {
      EdgeRuntime.waitUntil(p);
      return;
    }
  } catch { /* fall through */ }
  void p;
}

/**
 * Fire parse-workout-structure for this row AFTER the response returns. The
 * pg_net trigger that was supposed to do this is dead on Supabase (ALTER
 * DATABASE SET app.settings.* is permission-denied), so we invoke the parser
 * directly with the service role. Re-parsing here lets a voice-linked run fold
 * any spoken detail in alongside the GPS streams. Fire-and-forget. See Option A.
 */
function fireParseStructure(trainingLogId: string, userId: string): void {
  const p = fetch(`${supabaseUrl}/functions/v1/parse-workout-structure`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${supabaseServiceKey}`,
      apikey: supabaseServiceKey,
    },
    body: JSON.stringify({ training_log_id: trainingLogId, user_id: userId }),
  })
    .then((r) => {
      if (!r.ok) console.warn(`[process-training-memo] parse-structure ${r.status} for ${trainingLogId}`);
    })
    .catch((e) => console.warn(`[process-training-memo] parse-structure fetch failed: ${e}`));
  runInBackground(p);
}

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
  // v3: long-term memory candidates. Kept as an opaque array here — the
  // closed-vocab validation + dedup live in _shared/memoryWriter.ts. [] when
  // the memo holds nothing worth remembering (the common case).
  memory_candidates: unknown[];
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

  // v3: memory_candidates — always an array. Missing/null/non-array coerces to
  // [] so a prompt slip never crashes the memo path (memory is best-effort).
  const memory_candidates = Array.isArray(raw.memory_candidates) ? raw.memory_candidates : [];

  return { transcription, cleaned_notes, mood, coach_insight, workout_notes, extracted_data, memory_candidates };
}

// ── Voice-extracted → workout-field mapping ───────────────────────────────
// The voice analyzer drops structured detail (reps, splits, paces, effort)
// into the `extracted_data` JSON blob. These helpers lift that detail onto
// the row's actual workout columns so a spoken session is DISPLAYABLE (rep
// chart + insight splits + notes) instead of buried in JSON.

/** Format seconds/mile as "M:SS". */
function formatPaceMMSS(sec: number): string {
  // Round total first — rounding sec%60 alone renders "7:60" at 479.6s.
  const t = Math.round(sec);
  return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
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
/**
 * Shape of a `pace_segments` entry. `duration_seconds` is REQUIRED — the iOS
 * `PaceSegment` model and the fitness/signal math both read it. Emitting a
 * segment without it previously broke the journal decode outright.
 */
type PaceSegmentOut = {
  effort: string;
  distance_miles: number;
  duration_seconds: number;
  pace_per_mile: string;
};

function paceSegmentsFromExtracted(
  extracted: Record<string, unknown>,
): PaceSegmentOut[] {
  // 1. Intervals → reps.
  const intervals = Array.isArray(extracted.intervals)
    ? (extracted.intervals as Array<{ distance?: string; time?: string; rest?: string; count?: number }>)
    : null;
  const reps = splitsFromExtractedIntervals(intervals);
  if (reps.length > 0) {
    return reps.map((r) => ({
      effort: r.label,
      distance_miles: Number(r.distanceMiles.toFixed(3)),
      duration_seconds: Number((r.paceSecPerMile * r.distanceMiles).toFixed(1)),
      pace_per_mile: formatPaceMMSS(r.paceSecPerMile),
    }));
  }

  // 2. Mile splits → one segment per mile (split time IS the per-mile pace).
  const splits = Array.isArray(extracted.splits)
    ? (extracted.splits as Array<{ mile?: number; time?: string }>)
    : null;
  if (splits) {
    const out: PaceSegmentOut[] = [];
    for (const sp of splits) {
      const paceSec = parsePaceMMSS(sp.time);
      if (paceSec == null) continue;
      out.push({
        effort: `Mile ${sp.mile ?? out.length + 1}`,
        distance_miles: 1,
        duration_seconds: Number(paceSec.toFixed(1)),
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
 * spoken session is never lost to the `extracted_data` blob alone.
 *
 * IMPORTANT (2026-06-18): `workout_notes` describes the WORKOUT STRUCTURE
 * (reps/splits/distance/pace), and it is the gate compute-workout-features
 * uses to decide whether to derive structure FROM the Strava/Garmin laps —
 * it only backfills the laps-derived structure when `workout_notes` is empty.
 * So an effort-only memo ("felt like a 7/10") must NOT produce a workout_notes
 * here: a thin "Effort: hard (RPE 7)" line would make the field non-empty and
 * block the lap parse, leaving a linked Strava run with no parsed structure.
 * Effort/RPE has its own home (`felt_rpe` via extract-rpe) and shows in the
 * voice summary, so we deliberately omit it from this fallback. Only return a
 * note when the memo actually conveyed STRUCTURE.
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

  // Effort/RPE is intentionally NOT added here — see the docstring. If the memo
  // carried only effort and no structure, return null so the Strava/Garmin laps
  // become the structure source in compute-workout-features.
  return lines.length > 0 ? lines.join("\n") : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  let recordId: string | null = null;
  const tStart = Date.now();

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
      .select("user_id, notes, cleaned_notes, audio_url, processing_status")
      .eq("id", recordId)
      .maybeSingle();
    if (ownerErr || !ownerRow || ownerRow.user_id !== authUserId) {
      return new Response(
        JSON.stringify({ error: "Not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }
    // From here on, authUserId is the verified owner of record.id.
    //
    // NOTE (2026-08-06): the rate-limit + monthly-cap gates used to sit HERE,
    // before the no-op short-circuits below. That charged the user's daily
    // voice_memo quota for calls that did no work — polling retries, the
    // journal's stale-record sweep, duplicate invokes racing the drain — and
    // one stuck memo could burn the whole day's budget on failed retries
    // (429 loop, memo pinned at 'pending' forever). The gates now run AFTER
    // the already-processed / nothing-to-process / already-in-flight guards,
    // immediately before real work starts, so only calls that actually begin
    // a transcription+analysis run are metered. (enforceMonthlyCap's own
    // docstring already prescribed this: "call it AFTER any cached-return
    // short-circuit.")

    // A row is processable when it has audio to transcribe OR typed notes to
    // analyze directly (manual notes take the text path). Read both from the
    // row — the outbox payload only carries id/user_id/audio_url.
    const typedNotes = ((ownerRow.notes as string | null) ?? "").trim();
    const audioUrlStr = (ownerRow.audio_url as string | null) ?? record.audio_url ?? null;
    const hasAudio = !!audioUrlStr;
    // "Already processed" short-circuit. Gated on processing_status =
    // 'completed', NOT on cleaned_notes alone: the two-stage reveal writes the
    // raw transcript to cleaned_notes at status 'transcribed' BEFORE the
    // analysis runs, so a cleaned_notes-only guard would make any retry of a
    // half-done row skip the analysis forever. cleaned_notes stays in the
    // condition so a completed row with no notes (edge case) still reprocesses.
    if (ownerRow.cleaned_notes && ownerRow.processing_status === "completed") {
      return new Response(JSON.stringify({ message: "Skipped: already processed" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }
    if (!hasAudio && !typedNotes) {
      return new Response(JSON.stringify({ message: "Skipped: no audio or notes" }), {
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

    // 'transcribed' counts as in-flight too: the two-stage reveal flips the
    // row to 'transcribed' mid-run (transcript written, analysis still
    // going), and without it here a racing drain retry inside that 5-12s
    // window would start a duplicate transcription + analysis.
    if (
      currentStatus?.processing_status === "processing" ||
      currentStatus?.processing_status === "transcribed"
    ) {
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

    // ── Quota gates — only charged when real work is about to start ──────
    // Daily per-user ceiling (free: 20/day). Service-role callers (the
    // drain worker) bypass, so a queued retry can always complete even
    // after the athlete's own budget is spent.
    const rlBlocked = await enforceFeatureRateLimit(authUserId, "voice_memo", corsHeaders, { isServiceRole });
    if (rlBlocked) return rlBlocked;

    // Hard monthly ceiling: ≤200 voice-memo uploads processed per user/month.
    const capped = await enforceMonthlyCap(authUserId, "voice_memo", corsHeaders, { isServiceRole });
    if (capped) return capped;

    // App-wide budget guard (2026-08-13). Keyed on the training_log row so a
    // single memo stuck in a retry/dispatch cycle trips the per-subject 24h
    // ceiling within minutes instead of burning all day (the Aug-11 runaway
    // shape). Does NOT bypass for service-role — the drain worker is exactly
    // the path a runaway rides in on. Sits after all the no-op/in-flight
    // short-circuits above, so only a call that starts real transcription +
    // analysis work consumes budget (see migration 20260813180100).
    if (!(await llmBudgetAllows("voice_memo", { subjectId: recordId, userId: authUserId }))) {
      return llmBudgetBlockedResponse("voice_memo", corsHeaders);
    }

    // Mark as processing
    await updateProcessingStatus(record.id, "processing");

    // Fetch existing record to check for HealthKit-linked data and pace segments.
    // NOTE: `scheduled_workout_id` is intentionally NOT selected — that column
    // does not exist on training_logs in this schema, and including it made
    // PostgREST reject the entire query (400), which nulled `existingRecord` and
    // silently disabled the sibling-GPS merge below. The scheduled-workout
    // enrichment is guarded on the field being truthy, so it no-ops until a real
    // linkage column exists.
    const { data: existingRecord, error: existingErr } = await supabase
      .from("training_logs")
      .select("workout_distance_miles, workout_duration_minutes, pace_segments, vital_workout_id, workout_date, workout_type, external_streams, parsed_structure")
      .eq("id", record.id)
      .single();

    if (existingErr) {
      console.error(`[process-training-memo] failed to load existing record ${record.id}:`, existingErr.message);
    }

    // ── Merge a sibling GPS row (Strava/HealthKit) into this voice row ──
    // A voice memo recorded against an already-imported run lands as its OWN
    // voice_log row with only distance+duration copied over — NOT the GPS
    // streams or splits, which stay on the separate Strava row. That leaves the
    // structure parser and the AI insight with no real workout to read. So when
    // this row has distance but no streams, find the sibling run on the same day
    // with a matching distance and pull its external_streams + pace_segments
    // over, so parse-workout-structure + the insight see the actual GPS.
    let mergedStreams: unknown = null;
    let mergedPaceSegments: unknown = null;
    let siblingRunId: string | null = null;
    let siblingParsedStructure: unknown = null;
    {
      const er = existingRecord as {
        workout_distance_miles?: number | null;
        workout_date?: string | null;
        external_streams?: unknown;
        pace_segments?: unknown;
      } | null;
      const erDist = er?.workout_distance_miles ?? null;
      const erDate = er?.workout_date ?? null;
      const erHasStreams = er?.external_streams != null;
      if (!erHasStreams && erDist && erDate) {
        const day = String(erDate).slice(0, 10);
        const { data: siblings } = await supabase
          .from("training_logs")
          .select("id, workout_distance_miles, external_streams, pace_segments, parsed_structure")
          .eq("user_id", authUserId)
          .neq("id", record.id)
          .not("external_streams", "is", null)
          .gte("workout_date", `${day}T00:00:00Z`)
          .lte("workout_date", `${day}T23:59:59Z`)
          .limit(10);
        const match = (siblings ?? []).find((s: { workout_distance_miles?: number | null }) =>
          typeof s.workout_distance_miles === "number" &&
          Math.abs((s.workout_distance_miles as number) - (erDist as number)) <= 0.3
        ) as { id?: string; external_streams?: unknown; pace_segments?: unknown; parsed_structure?: unknown } | undefined;
        if (match) {
          mergedStreams = match.external_streams ?? null;
          // The laps table is keyed on the SIBLING row's id (the lap-writer
          // trigger fired when Strava sync wrote its external_streams). Keep
          // the id so the splits block below can read the true rep structure.
          siblingRunId = match.id ?? null;
          siblingParsedStructure = match.parsed_structure ?? null;
          const erHasSegs = Array.isArray(er?.pace_segments) && (er!.pace_segments as unknown[]).length > 0;
          if (!erHasSegs) mergedPaceSegments = match.pace_segments ?? null;
          console.log(`[process-training-memo] merged GPS from sibling run into voice row ${record.id}`);
        }
      }
    }

    // ── Watch laps — the true rep structure ─────────────────────────────
    // running_workout_laps holds the actual lap presses (work reps + flagged
    // recoveries). Far richer than pace_segments, which are PER-MILE averages
    // that smear work + recovery together — feeding those to the model as
    // "reps" is how a 5×4:00 threshold session got read back as "4×1 mile".
    // The voice row rarely has laps of its own (no streams yet at this point),
    // so fall back to the sibling GPS run found above.
    const watchLaps: Array<{
      lap_index?: number | null;
      distance_meters?: number | null;
      moving_time_seconds?: number | null;
      avg_pace_sec_per_mile?: number | null;
      avg_heart_rate?: number | null;
      is_rest?: boolean | null;
    }> = [];
    for (const lapWorkoutId of [record.id, siblingRunId]) {
      if (!lapWorkoutId) continue;
      const { data: lapRows } = await supabase
        .from("running_workout_laps")
        .select("lap_index, distance_meters, moving_time_seconds, avg_pace_sec_per_mile, avg_heart_rate, is_rest")
        .eq("workout_id", lapWorkoutId)
        .eq("user_id", authUserId)
        .order("lap_index", { ascending: true });
      if (lapRows && lapRows.length > 0) {
        watchLaps.push(...(lapRows as typeof watchLaps));
        break;
      }
    }

    // Audio path only: resolve the storage path + download. Typed notes have
    // no audio and take the text branch in Step 1 below.
    let storagePath: string | undefined;
    let audioData: Blob | null = null;
    if (hasAudio) {
      const audioUrl = new URL(audioUrlStr!);
      const bucketPrefix = "/storage/v1/object/public/training-memos/";
      const pathIndex = audioUrl.pathname.indexOf(bucketPrefix);
      storagePath = pathIndex !== -1
        ? decodeURIComponent(audioUrl.pathname.slice(pathIndex + bucketPrefix.length))
        : audioUrl.pathname.split("/").pop();

      if (!storagePath) {
        throw new Error("Could not extract storage path from audio URL");
      }

      // Download audio file from storage
      const { data: dlData, error: downloadError } = await supabase.storage
        .from("training-memos")
        .download(storagePath);

      if (downloadError) {
        throw new Error(`Failed to download audio: ${downloadError.message}`);
      }
      audioData = dlData;
    }

    // Coach context fetched in parallel with transcription — adds zone
    // anchors and (if linked) prescribed-vs-executed framing to the prompt.
    const coachContextPromise = loadCoachContext(supabase, authUserId);

    // Scheduled-workout fetch (when linked) for prescribed-vs-executed.
    // Inert until a real linkage column exists: `training_logs` has no
    // `scheduled_workout_id` in this schema, so there is nothing to join on.
    // (Selecting it is what made PostgREST 400 the whole existing-record read.)
    const scheduledPromise: Promise<{ data: null }> = Promise.resolve({ data: null });

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

    // Athlete state — launched HERE, in parallel with transcription, because
    // it takes no transcript input. It was previously awaited serially after
    // transcription, which put a full 2-6s rebuild on the critical path (the
    // blanket invalidation trigger meant the 60-min cache never hit). Wrapped
    // so a state failure never blocks memo ingest — saving the memo matters
    // more than the insight.
    const tStatePromiseStart = Date.now();
    const athleteStatePromise = (async () => {
      try {
        const st = await getOrBuildAthleteState(supabase, authUserId);
        console.log(`[memo-timing] athlete-state=${Date.now() - tStatePromiseStart}ms`);
        return st;
      } catch (err) {
        console.warn("process-training-memo: athlete-state load failed:", err);
        return null;
      }
    })();

    // ── Step 1: get the transcript ──
    // Voice memos: transcribe the audio (Groq → OpenAI → Gemini fallback).
    // Typed notes: the athlete's text IS the transcript — skip transcription.
    let transcription: string | null = null;
    let transcriptionProvider = "unknown";

    if (hasAudio && audioData) {
      const audioArrayBuffer = await audioData.arrayBuffer();
      const mimeType = storagePath!.endsWith(".m4a") ? "audio/mp4" : "audio/mpeg";
      const fileName = storagePath!.split("/").pop() || "memo.m4a";

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
          // 12s, not 30s: a typical 60s memo transcribes on Groq in 2-3s, so a
          // long timeout only ever delays the OpenAI fallback when Groq is
          // degraded-but-up. Same model, same output — we just fail over faster.
          signal: AbortSignal.timeout(12000),
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
    } else {
      // Typed note: the athlete's text is the transcript — zero transcription cost.
      transcription = typedNotes;
      transcriptionProvider = "typed-note";
      if (transcription.length < 5) {
        throw new Error("Typed note too short to analyze");
      }
      console.log(`[process-training-memo] typed note (${transcription.length} chars) — skipping transcription`);
    }

    const tTranscribed = Date.now();
    console.log(`Transcription complete via ${transcriptionProvider}: "${transcription.slice(0, 100)}..."`);
    console.log(`[memo-timing] transcription=${tTranscribed - tStart}ms provider=${transcriptionProvider}`);

    // ── Two-stage reveal: put the athlete's own words on the row NOW ──
    // The transcript is ready ~6-10s in; the analysis takes another 5-12s.
    // Write the raw transcript as cleaned_notes and flip the status to
    // 'transcribed' so the Log entry renders the athlete's words immediately;
    // mood / niggles / extracted structure fill in when the final UPDATE flips
    // it to 'completed'. Safe against retries because the "already processed"
    // short-circuit above is gated on processing_status = 'completed'.
    const earlyRevealPromise = supabase
      .from("training_logs")
      .update({ cleaned_notes: transcription, processing_status: "transcribed" })
      .eq("id", record.id)
      .then(({ error }: { error: { message: string } | null }) => {
        if (error) console.warn(`[process-training-memo] early reveal failed: ${error.message}`);
      });

    // ── Step 2: Analyze transcript with Gemini ──
    const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

    // Await the recent logs + coach context + scheduled workout + similar
    // prior workout + athlete state — all fetched in parallel with
    // transcription. (The early-reveal write rides along so it's settled well
    // before the final results UPDATE — no write-ordering race.)
    const [recentRes, coachCtx, scheduledRes, prior, athleteState] = await Promise.all([
      recentLogsPromise,
      coachContextPromise,
      scheduledPromise,
      priorPromise,
      athleteStatePromise,
      earlyRevealPromise,
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

    // Splits block — fidelity ladder, mirroring generate-workout-insight:
    //   1. parsed_structure blocks — recovery-segmented by the structure
    //      parser from the GPS stream (own row, else the sibling GPS run's).
    //      The only source that reliably separates JOGGED recoveries for
    //      athletes at any pace — the lap `is_rest` heuristic is absolute
    //      (<200m / <2.0 m/s) and misses recoveries run at a normal jog.
    //   2. running_workout_laps — actual lap presses (true rep structure,
    //      rest flagged + relative recovery filter). Fetched above,
    //      sibling-aware.
    //   3. pace_segments — PER-MILE averages. Work + recovery smeared
    //      together; usable pacing context but NOT rep structure.
    // Voice-extracted intervals can't participate here because the LLM hasn't
    // run yet; those become available on the row after this function writes
    // extracted_data. For voice-only workouts with no watch data at all,
    // splits are surfaced in workout_notes via the LLM's own extraction.
    const parsedBlocks =
      ((existingRecord as { parsed_structure?: { blocks?: unknown } } | null)
        ?.parsed_structure?.blocks ??
        (siblingParsedStructure as { blocks?: unknown } | null)?.blocks) as
        | Array<{
            role?: string;
            rep_num?: number | null;
            distance_miles?: number | string;
            duration_s?: number | string;
            avg_pace_per_mile?: string;
            avg_hr?: number | null;
          }>
        | null
        | undefined;
    const parsedSplits = splitsFromParsedBlocks(parsedBlocks);
    const lapSplits = splitsFromLaps(watchLaps);
    const segSplits = splitsFromPaceSegments(
      (existingRecord?.pace_segments ?? mergedPaceSegments) as Array<{
        effort?: string;
        distance_miles?: number | string;
        pace_per_mile?: string;
        avg_heart_rate?: number;
      }> | null,
    );
    const workReps = (s: Array<{ effortKind: string }>) =>
      s.filter((x) => x.effortKind === "work").length;
    const splitSource: "parsed" | "laps" | "segments" = workReps(parsedSplits) >= 2
      ? "parsed"
      : workReps(lapSplits) >= 2
      ? "laps"
      : "segments";
    const watchSplits = splitSource === "parsed"
      ? parsedSplits
      : splitSource === "laps"
      ? lapSplits
      : segSplits;
    // Quality sessions get the full split read; easy / steady / long runs use
    // the large-dropoff-only register — silent on normal drift, but a real big
    // late fade still surfaces (matches generate-workout-insight).
    const splitsBlock = isQualityWorkoutType(existingType)
      ? formatSplitsBlock(watchSplits, coachCtx.zones, { detectPattern: true })
      : formatSplitsBlock(watchSplits, coachCtx.zones, {
          detectPattern: true,
          largeDropoffOnly: true,
        });

    // Athlete-state block — the SAME canonical context the Daily Read / Coach
    // surfaces read (goals, phase, mileage, load, niggles, patterns). Without
    // this the voice-log insight was goal-blind and thinner than the HealthKit
    // insight; now both reason from the same direction. Fetched in parallel
    // with transcription (athleteStatePromise above) — same context, no longer
    // paid for serially on the critical path.
    let athleteStateContext = "";
    if (athleteState) {
      try {
        const block = stateToPromptContext(athleteState);
        if (block) athleteStateContext = `\n\n## Athlete state\n${block}`;
      } catch (err) {
        console.warn("process-training-memo: athlete-state format failed:", err);
      }
    }

    let coachAnchorContext = "";
    if (athleteStateContext) {
      coachAnchorContext = athleteStateContext;
    }
    if (pacesBlock) {
      coachAnchorContext += `\n\n${pacesBlock}`;
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

    // Build Garmin/watch data context for sharper coaching. Built from the
    // SAME fidelity-laddered splits as the splits block above — never from raw
    // pace_segments, which are per-mile averages: labeling those "reps" is how
    // a 5×4:00 threshold session got narrated back as "actual 4×1 mile reps"
    // a minute-per-mile slower than the athlete actually ran.
    let garminContext = "";
    if (watchSplits.length > 0) {
      garminContext = splitSource === "parsed"
        ? "\n\n## GPS Watch Data (parsed workout structure)\nThe workout structure below was segmented from the GPS stream — recoveries are separated out, and each work line is a true rep as executed:\n"
        : splitSource === "laps"
        ? "\n\n## GPS Watch Data (recorded laps)\nThe runner's watch recorded these laps. Rest/recovery laps are excluded — each line below is a WORK rep as the watch captured it:\n"
        : "\n\n## GPS Watch Data (per-distance splits)\nOnly distance-based splits (per mile/km) are available for this workout. Each line AVERAGES work and any recovery jogs within that distance — these are NOT reps. Do not describe them as reps, and do not contradict the runner's own account of the rep structure based on them:\n";
      for (const s of watchSplits) {
        const hr = s.avgHeartRate ? ` (${s.avgHeartRate} bpm)` : "";
        garminContext += `- ${s.label}: ${s.distanceMiles.toFixed(2)} mi @ ${formatPaceMMSS(s.paceSecPerMile)}/mi${hr}\n`;
      }
      const totalDist = existingRecord?.workout_distance_miles ?? 0;
      if (totalDist > 0) {
        const totalMin = existingRecord?.workout_duration_minutes || 0;
        const avgPaceSec = totalMin > 0 ? Math.round((totalMin * 60) / totalDist) : 0;
        const paceM = Math.floor(avgPaceSec / 60);
        const paceS = avgPaceSec % 60;
        garminContext += `Total: ${Number(totalDist).toFixed(1)} mi in ${Math.round(totalMin)} min (${paceM}:${String(paceS).padStart(2, "0")}/mi avg)\n`;
      }
      garminContext += "\nUSE THIS DATA in your coach_insight. Compare what the runner SAID about their workout to what the WATCH DATA shows. Note discrepancies. Analyze effort distribution. Were easy segments actually easy? Only call out a fade or negative split on a quality session (tempo / intervals / race-pace reps) AND when it's a real, sizable pace change — normal drift on an easy, steady, or long run is expected and must not be labeled a fade. Be specific about paces.\n";
    }

    // Structured prompt with distinct fields and few-shot examples
    const prompt = loadPrompt("process-training-memo.v3", { coachAnchorContext, recentContext });

    // Feed the TEXT transcript + Garmin data to Gemini for analysis
    const result = await model.generateContent([
      { text: prompt + garminContext + `\n\n## Audio Transcript (from ${transcriptionProvider})\n"${transcription}"` },
    ]);

    const responseText = result.response.text();
    console.log("Gemini raw response length:", responseText.length);

    // Parse and validate
    const rawAnalysis = parseJsonResponse(responseText);
    const analysis = validateAnalysis(rawAnalysis);
    console.log(`[memo-timing] gemini-analysis=${Date.now() - tTranscribed}ms`);

    // Save full transcript to storage (audio path only — a typed note has no
    // audio storage path to derive the transcript filename from, and the note
    // text already lives on the row as `notes`/`cleaned_notes`).
    //
    // The upload itself runs in the BACKGROUND (runInBackground): the athlete
    // is waiting on processing_status, and the .txt artifact is never read on
    // the hot path. transcript_url is safe to write before the upload lands —
    // getPublicUrl is pure string construction (see the 2026-07-15 note below),
    // so the identifier is deterministic; a failed upload logs and leaves a
    // dangling identifier, exactly as a failed awaited upload left a null one.
    let transcriptUrl: string | null = null;
    if (analysis.transcription && hasAudio && storagePath) {
      const transcriptFileName = storagePath.replace(/\.(m4a|mp3|wav)$/, "_transcript.txt");
      const transcriptContent = new TextEncoder().encode(analysis.transcription);

      // NOTE (2026-07-15): training-memos is a PRIVATE bucket now.
      // getPublicUrl is pure string construction — we keep it because the
      // URL-shaped string is the canonical identifier format stored in
      // training_logs (readers parse the storage path back out of it and
      // download with the service role). It is not a fetchable link.
      const { data: urlData } = supabase.storage
        .from("training-memos")
        .getPublicUrl(transcriptFileName);
      transcriptUrl = urlData.publicUrl;

      runInBackground(
        supabase.storage
          .from("training-memos")
          .upload(transcriptFileName, transcriptContent, {
            contentType: "text/plain",
            upsert: true,
          })
          .then(({ error: uploadError }) => {
            if (uploadError) {
              console.error(`Failed to save transcript: ${uploadError.message}`);
            } else {
              console.log(`Saved transcript to: ${transcriptUrl}`);
            }
          })
          .catch((e) => console.error(`Transcript upload threw: ${e}`)),
      );
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

    // Carry the sibling run's GPS onto this voice row so the parser + insight
    // have the real workout. Voice-extracted pace_segments (if any) win; the
    // merged GPS only fills the gap.
    if (mergedStreams != null) {
      updatePayload.external_streams = mergedStreams;
    }
    if (mergedPaceSegments != null && updatePayload.pace_segments == null) {
      updatePayload.pace_segments = mergedPaceSegments;
    }

    // Update training_logs with all results
    const { error: updateError } = await supabase
      .from("training_logs")
      .update(updatePayload)
      .eq("id", record.id);

    if (updateError) {
      throw new Error(`Failed to update training log: ${updateError.message}`);
    }

    // Parse the workout structure (GPS streams + any spoken detail) now that the
    // row is written. Direct call — the pg_net trigger is dead on Supabase.
    fireParseStructure(record.id, authUserId);

    // ── Niggle classification (audit fix #2) ──────────────────────────
    // The memo pipeline is the PRIMARY body-mentions writer: persist the
    // LLM's structured `soreness` entries as durable niggles (closed
    // vocabulary + laterality + verbatim words), so patterns survive
    // across rebuilds and carry the side. Runs under service role (RLS is
    // not the silent no-op it is on the athlete-state rebuild path). Awaited
    // so failures log, but writeNiggleMentions never throws.
    const mentionDate = (existingRecord?.workout_date as string | null) ?? new Date().toISOString();
    // Kept AWAITED deliberately (unlike the resolution/memory writes below):
    // the niggle chips render alongside the journal entry, and backgrounding
    // this write made them pop in a beat late. It's also the cheapest write.
    await writeNiggleMentions(supabase, authUserId, record.id, mentionDate, analysis.extracted_data);
    // The all-clear signal: when the athlete says a niggle is better now,
    // record a resolution watermark so it drops out of active analysis until
    // (and unless) a new mention comes in after this date. Background: nothing
    // athlete-visible reads it in the seconds after the entry appears, and the
    // writer never throws — runInBackground still runs it to completion.
    runInBackground(writeNiggleResolutions(supabase, authUserId, record.id, mentionDate, analysis.extracted_data));

    // ── Long-term memory extraction (roadmap 4.1, "it knows you") ─────────
    // Dedup-or-reinforce the LLM's memory_candidates into user_memories:
    // durable facts, preferences, constraints, life context, gear, and
    // quotable episodes — the athlete's own framing only. Zero extra LLM cost
    // (the candidates rode in the memo analysis response above). Service-role,
    // backgrounded (runInBackground) so the athlete isn't waiting on it —
    // failures still log, writeMemoryCandidates never throws, and the write
    // always runs to completion. Long-term memory is read by later coaching
    // surfaces, never by the entry that's about to render.
    const memoExcerpt = (analysis.cleaned_notes || analysis.transcription || "").slice(0, 200);
    runInBackground(writeMemoryCandidates(
      supabase,
      authUserId,
      record.id,
      mentionDate,
      memoExcerpt,
      analysis.memory_candidates,
    ));

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

    // ── Scope: this function summarizes + parses the workout (above) and
    //    now also CLASSIFIES niggles (writeNiggleMentions, just above). It
    //    does NOT run injury-early-warning or rebuild athlete state. Those
    //    remain separate concerns:
    //      • Athlete-state freshness: the `trg_invalidate_athlete_state` trigger
    //        (20260420200000) fires on the row UPDATE above and invalidates the
    //        cache, so the next coaching read rebuilds — no inline rebuild here.
    //      • Body-part / niggle mentions: this function is the PRIMARY writer
    //        (memo_llm source, closed vocabulary + laterality + verbatim words).
    //        The rebuild-time regex scan remains only as backfill for TYPED
    //        notes and imported descriptions, and skips voice rows (which this
    //        path owns). Detection-not-diagnosis; never auto-converted to
    //        formal injuries.
    //    Keeping the voice path lean is what keeps it fast.
    console.log(`[memo-timing] total=${Date.now() - tStart}ms (summarize + parse only)`);

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
    const rawMessage = error instanceof Error ? error.message : String(error);

    // ── Provider out of credit ≠ this memo is broken (2026-08-13). ──
    // Collapsing an upstream billing 429 into the generic 500 below is what
    // permanently stranded memos during the credit outage: the drain could
    // not tell "our code failed" from "Gemini is unfunded", so it spent all
    // three retries in three minutes and gave up for good. Answer 503 with
    // Retry-After instead, and tag processing_error so both the drain and
    // the iOS failure classifier can say something true to the athlete
    // rather than "we couldn't transcribe it. Tap to try again" — which is
    // both wrong and unactionable while the provider is down.
    //
    // Still Sentry-captured: a billing lapse has no other alarm on it (there
    // is no billing alert anywhere yet), so this path is the only signal.
    // Tagged `provider_exhausted` so it groups separately from real faults.
    if (isProviderExhausted(error)) {
      console.error(`[process-training-memo] provider exhausted: ${rawMessage}`);
      captureException(error, {
        fn: "process-training-memo",
        recordId,
        reason: "provider_exhausted",
      });
      await flushSentry();

      if (recordId) {
        await updateProcessingStatus(
          recordId,
          "failed",
          `${PROVIDER_EXHAUSTED_MARKER}: ${rawMessage}`,
        );
      }

      return new Response(
        JSON.stringify({
          error: "Analysis provider unavailable.",
          reason: PROVIDER_EXHAUSTED_MARKER,
        }),
        {
          status: PROVIDER_EXHAUSTED_STATUS,
          headers: { "Content-Type": "application/json", "Retry-After": "900" },
        }
      );
    }

    console.error("Error processing training memo:", error);
    captureException(error, { fn: "process-training-memo", recordId });
    await flushSentry();

    // Mark as failed with error message
    if (recordId) {
      await updateProcessingStatus(recordId, "failed", rawMessage);
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
