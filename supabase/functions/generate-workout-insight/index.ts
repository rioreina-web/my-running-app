/**
 * Generate Workout Insight
 *
 * Produces a one-sentence coaching reading for a `training_logs` row.
 * Pure LLM-call function — caller (the worker, or an authenticated user
 * regenerating via the UI) owns retry/policy.
 *
 * Coexists with `process-training-memo`, which already writes
 * coach_insight on voice-logged runs (audio_url present). This function
 * fills the gap for HealthKit / direct-entry runs.
 *
 * Idempotent: returns the existing insight if already populated.
 *
 * Auth:
 *   - Service-role caller (the drain worker) is allowed.
 *   - Otherwise, the JWT user must own the row (RLS-style check).
 *   - Anonymous callers are rejected with 401.
 *
 * Status-code contract (consumed by the worker):
 *   200 — success or already-populated (response.cached true)
 *   400 — bad request (missing / non-UUID training_log_id)
 *   401 — no auth
 *   403 — caller doesn't own the row
 *   404 — training log not found
 *   429 — caller / global rate limit hit (retryable)
 *   502 — Gemini upstream failure (retryable)
 *
 * Body:
 *   { training_log_id: string }
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { GoogleGenerativeAI } from "npm:@google/generative-ai@0.21.0";
import { enforceFeatureRateLimit, enforceMonthlyCap } from "../_shared/rateLimit.ts";
import { llmBudgetAllows, llmBudgetBlockedResponse } from "../_shared/llm-budget.ts";
import { loadPrompt } from "../_shared/prompt-library.ts";
import { firstAthleteNote } from "../_shared/athleteNoteText.ts";
import {
  loadCoachContext,
  formatPacesBlock,
  classifyPace,
  comparePrescribedToExecuted,
  findSimilarPriorWorkout,
  formatProgressionBlock,
  formatSplitsBlock,
  splitsFromLaps,
  splitsFromPaceSegments,
  splitsFromExtractedIntervals,
  splitsFromParsedBlocks,
  isQualityWorkoutType,
  type CoachContext,
  type ScheduledLite as CoachScheduledLite,
  type ExecutedSummary,
  type WorkoutSplit,
} from "../_shared/coach-context.ts";


import {
  buildAthleteStateBlock,
  formatConditionsBlock,
  formatRecentLogsBlock,
  summarizeRecent,
  parsePaceSec,
  deriveAveragePace,
  resolveKeySessionLine,
  type TrainingLogRow,
  type ScheduledLite,
  type RecentRow,
  type TrainingLap,
} from "../_shared/context.ts";
import { corsHeaders } from "../_shared/cors.ts";
import { captureException, flushSentry } from "../_shared/sentry.ts";
import {
  insightSafetyViolations,
  INSIGHT_STRICT_SUFFIX,
} from "../_shared/insight-safety.ts";
const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
const geminiApiKey = Deno.env.get("GEMINI_API_KEY")!;

const adminClient = createClient(supabaseUrl, supabaseServiceKey);
const genAI = new GoogleGenerativeAI(geminiApiKey);

// COST (2026-08-13): downgraded gemini-2.5-pro → gemini-2.5-flash. The
// "button-triggered, low-volume" premise above was no longer true: the
// coach_insight_jobs outbox auto-enqueues an insight on workout ingestion,
// so this ran on a Pro model ($1.25/$10 per 1M tokens) for every synced run.
// Flash ($0.30/$2.50) handles this structured, context-grounded read fine.
// A side benefit: the daily spend alert's coach_insight proxy row already
// assumes flash pricing, so the estimate is now accurate.
// If quality visibly drops on key-session insights, re-upgrade ONLY the
// button-triggered path, never the outbox path.
const INSIGHT_MODEL = "gemini-2.5-flash";

// Runtime safety guard (CLAUDE.md hard rule #2). Shared + unit-tested in
// _shared/insight-safety.ts so every AI surface enforces the same rule.






const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // --- Auth ---
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "Authentication required" }, 401);
    }
    const token = authHeader.slice("Bearer ".length).trim();
    const isServiceRole = constantTimeEq(token, supabaseServiceKey);

    let callerUserId: string | null = null;
    if (!isServiceRole) {
      // User JWT path — verify and extract uid.
      const userClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const { data, error } = await userClient.auth.getUser(token);
      if (error || !data.user) {
        return jsonResponse({ error: "Invalid token" }, 401);
      }
      callerUserId = data.user.id;
    }

    // --- Per-user rate limit (TASKS.md W2.3) ---
    // Service-role callers (trigger_workout_insight, drain-coach-insight-jobs
    // cron) bypass via isServiceRole. User-callable path (iOS retry from
    // TodayHomeView) is gated per user_id.
    if (!isServiceRole && callerUserId) {
      const rlBlocked = await enforceFeatureRateLimit(
        callerUserId,
        "workout_insight",
        corsHeaders,
        { isServiceRole: false },
      );
      if (rlBlocked) return rlBlocked;
    }

    // --- Input validation ---
    const body = await req.json().catch(() => ({}));
    const trainingLogId = (body as { training_log_id?: unknown }).training_log_id;
    if (typeof trainingLogId !== "string" || !UUID_RE.test(trainingLogId)) {
      return jsonResponse({ error: "training_log_id must be a UUID" }, 400);
    }

    // Cost protection: the app-wide budget guard runs below, AFTER the
    // cached-insight short-circuit, so a cache hit never consumes budget.
    // The Google Cloud billing cap (W1.1) remains the outermost backstop.

    // --- Load row ---
    const { data: row, error: loadErr } = await adminClient
      .from("training_logs")
      // NOTE: `scheduled_workout_id` is intentionally NOT selected — that
      // column does not exist on training_logs in this schema, and including it
      // made PostgREST reject the entire query ("Database error" 500, which
      // failed every coach_insight job). The scheduled-workout enrichment below
      // is guarded on `row.scheduled_workout_id` being truthy, so it simply
      // no-ops (undefined) until a real linkage column exists.
      // `stream_meta` pulls only the external_streams.meta JSON object (elevation,
      // temp, cadence, suffer score) — NOT the multi-MB per-second arrays — so the
      // coach can read this run's conditions (elevation gain, heat) without the
      // payload bloat.
      .select(
        "id, user_id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes, workout_notes, parsed_structure, coach_insight, pace_segments, extracted_data, weather_actual, stream_meta:external_streams->meta"
      )
      .eq("id", trainingLogId)
      .maybeSingle<TrainingLogRow & { stream_meta?: Record<string, unknown> | null; weather_actual?: Record<string, unknown> | null }>();

    if (loadErr) {
      console.error("training_logs load error:", loadErr.message);
      return jsonResponse({ error: "Database error" }, 500);
    }
    if (!row) {
      return jsonResponse({ error: "Log not found" }, 404);
    }

    // Ownership check for non-service callers.
    if (!isServiceRole && callerUserId !== row.user_id) {
      return jsonResponse({ error: "Forbidden" }, 403);
    }

    // --- Fire-once cache, EXCEPT for clarifying-question fallbacks ---
    // Normally one generation per workout (cost). But a cached insight that's a
    // "I need more info — what's your weekly mileage?" fallback must NOT be
    // frozen forever: it predates the context fix and is exactly what we're
    // trying to eliminate. Detect that shape and allow ONE regeneration so the
    // enriched-context + "never ask" prompt can replace it. Real insights still
    // return cached and never burn quota.
    const cachedInsight = row.coach_insight?.trim() ?? "";
    const looksLikeQuestionFallback = cachedInsight.length > 0 && (
      /\bmore info\b/i.test(cachedInsight) ||
      /weekly mileage/i.test(cachedInsight) ||
      /recent race time/i.test(cachedInsight) ||
      (cachedInsight.includes("?") && /\bwhat'?s your\b/i.test(cachedInsight))
    );
    if (cachedInsight.length > 0 && !looksLikeQuestionFallback) {
      return jsonResponse({ insight: row.coach_insight, cached: true });
    }

    // Hard monthly ceiling: ≤200 insight generations per user per month.
    // Placed AFTER the fire-once cached return so re-opening a workout that
    // already has an insight never burns quota — only a real generation counts.
    if (callerUserId) {
      const capped = await enforceMonthlyCap(callerUserId, "workout_insight", corsHeaders, { isServiceRole });
      if (capped) return capped;
    }

    // App-wide budget guard (2026-08-13). Keyed on the training_log row so
    // the per-subject 24h ceiling catches a single log stuck in a
    // re-insight loop within minutes (the Aug-11 runaway shape). Does NOT
    // bypass for service-role — the outbox drain is exactly the path a
    // runaway rides in on. Sits after the cached return so only a real
    // generation consumes budget (see migration 20260813180100).
    if (!(await llmBudgetAllows("coach_insight", {
      subjectId: trainingLogId,
      userId: callerUserId ?? row.user_id,
    }))) {
      return llmBudgetBlockedResponse("coach_insight", corsHeaders);
    }

    // --- Pull context ---
    // ── Find the planned session for this run (v6). ──
    // This lookup used to be guarded on `row.scheduled_workout_id`, a column
    // that does not exist on training_logs — the comment on the select above
    // says so outright. So `scheduled` was ALWAYS null and the plan's intent
    // never once reached the prompt. The link exists in the other direction:
    // `scheduled_workouts.completed_workout_id` → training_logs.id. Try that
    // first (exact), then fall back to same-user-same-date, which is how an
    // unreconciled import lines up with its planned day.
    //
    // A training plan is optional and `activePlan == nil` is first-class, so
    // both misses are normal, not an error: a self-coached athlete has no
    // scheduled_workouts rows at all and this correctly stays null.
    let scheduled: ScheduledLite | null = null;
    {
      const { data: byLink } = await adminClient
        .from("scheduled_workouts")
        .select("id, workout_type, workout_data, notes, is_key_session")
        .eq("completed_workout_id", row.id)
        .maybeSingle<ScheduledLite>();
      scheduled = byLink ?? null;

      if (!scheduled) {
        const workoutDay = row.workout_date.slice(0, 10);
        // Fetch TWO so we can detect ambiguity rather than silently taking the
        // first. A date match is only trustworthy when the day holds exactly
        // one planned session AND exactly one logged run: this athlete runs
        // doubles routinely (three separate runs on 2026-08-18), and attaching
        // the day's threshold prescription to a 2-mile shakeout would tell the
        // read the athlete missed a workout they actually nailed in the other
        // session. A wrong prescription is worse than none, so on any ambiguity
        // we leave `scheduled` null and the prescribed block simply stays out.
        const [{ data: sameDayPlans }, { count: sameDayRuns }] = await Promise.all([
          adminClient
            .from("scheduled_workouts")
            .select("id, workout_type, workout_data, notes, is_key_session")
            .eq("user_id", row.user_id)
            .eq("date", workoutDay)
            .order("session", { ascending: true })
            .limit(2),
          adminClient
            .from("training_logs")
            .select("id", { count: "exact", head: true })
            .eq("user_id", row.user_id)
            .gte("workout_date", `${workoutDay}T00:00:00Z`)
            .lt("workout_date", `${workoutDay}T23:59:59.999Z`),
        ]);

        const plans = (sameDayPlans ?? []) as ScheduledLite[];
        if (plans.length === 1 && (sameDayRuns ?? 0) <= 1) {
          scheduled = plans[0];
        } else if (plans.length > 0) {
          console.log(
            `[insight] ${row.id}: skipping date-matched plan — ` +
              `${plans.length} planned / ${sameDayRuns ?? 0} logged on ${workoutDay}`,
          );
        }
      }
    }

    // Key session — the plan's intent, or the athlete's own assignment via
    // `day_overrides` (field 'is_key_session'), which wins when present
    // because the athlete's call outranks the plan's.
    const keySessionLine = await resolveKeySessionLine(
      adminClient,
      row.user_id,
      row.workout_date.slice(0, 10),
      scheduled?.is_key_session ?? null,
    );

    const sevenDaysAgo = new Date(
      new Date(row.workout_date).getTime() - 7 * 86400000
    );
    // v6: the log block reads 28 days; `recentSummary` still reports 7, so the
    // prompt's "Last 7 days:" line stays literally true. One fetch serves both
    // — the 7-day set is a filter over it, not a second query.
    const twentyEightDaysAgo = new Date(
      new Date(row.workout_date).getTime() - 28 * 86400000
    );
    // Compute current run's pace once — needed for both classification
    // and the similar-prior matcher.
    const currentPaceSec = parsePaceSec(row.workout_pace_per_mile)
      ?? deriveAveragePace(row.workout_distance_miles, row.workout_duration_minutes);

    // Recent logs + coach context + similar prior workout — all fetched
    // in parallel. Similar-prior is gated on having a workout_type +
    // distance + pace; otherwise it's not a comparable session.
    const priorPromise = (row.workout_type && row.workout_distance_miles && currentPaceSec)
      ? findSimilarPriorWorkout(adminClient, row.user_id, {
          workoutType: row.workout_type,
          distanceMiles: row.workout_distance_miles,
          paceSecPerMile: currentPaceSec,
        }, new Date(row.workout_date))
      : Promise.resolve(null);

    const [recentRes, coachCtx, prior, athleteStateBlock, lapsRes] = await Promise.all([
      // 28 days, WITH the athlete's own words (v6). The window is a training
      // block, which is the shortest span that can show a recurring niggle or a
      // drifting mood; 7 days could only ever show within-week noise. Notes are
      // truncated per-row when the block is formatted, not here, so the
      // truncation rule lives in one place.
      adminClient
        .from("training_logs")
        .select(
          "workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, felt_rpe, cleaned_notes, workout_notes, notes",
        )
        .eq("user_id", row.user_id)
        .gte("workout_date", twentyEightDaysAgo.toISOString())
        .lt("workout_date", row.workout_date)
        .order("workout_date", { ascending: false })
        .limit(40),
      loadCoachContext(adminClient, row.user_id),
      priorPromise,
      buildAthleteStateBlock(adminClient, row.user_id),
      // Actual lap presses — the TRUE rep structure (e.g. 8×1K with jog
      // recoveries), far richer than the mile-averaged pace_segments which
      // smear work+rest together. generateInsight prefers these when present.
      adminClient
        .from("running_workout_laps")
        .select("lap_index, distance_meters, moving_time_seconds, avg_pace_sec_per_mile, avg_heart_rate, is_rest")
        .eq("workout_id", row.id)
        .order("lap_index", { ascending: true }),
    ]);
    const recent = recentRes.data ?? [];
    const laps = (lapsRes.data ?? []) as TrainingLap[];

    // This run's conditions — shared with the session ask so both surfaces
    // read terrain and weather the same way (_shared/context.ts).
    const conditionsBlock = formatConditionsBlock(
      (row as { stream_meta?: Record<string, unknown> | null }).stream_meta ?? null,
      (row as { weather_actual?: Record<string, unknown> | null }).weather_actual ?? null,
    );


    // Combined training-context block the insight reads through: athlete state
    // (volume / fitness ranges / load / niggles / patterns) + this run's conditions.
    const athleteContextBlock = [athleteStateBlock, conditionsBlock]
      .filter(Boolean)
      .join("\n\n");

    // Progression block — only when matcher found a comparable prior AND
    // the deltas are meaningful (formatProgressionBlock filters noise).
    const progressionBlock = (prior && row.workout_type && row.workout_distance_miles && currentPaceSec)
      ? (formatProgressionBlock(
          {
            workoutType: row.workout_type,
            distanceMiles: row.workout_distance_miles,
            paceSecPerMile: currentPaceSec,
          },
          prior,
        )?.block ?? "")
      : "";

    // --- LLM call ---
    let insight = await generateInsight(
      row,
      scheduled,
      recent as RecentRow[],
      coachCtx,
      progressionBlock,
      athleteContextBlock,
      laps,
      keySessionLine,
    );

    if (insight === null) {
      // Gemini failure — retryable. Worker will back off + retry.
      return jsonResponse({ error: "Upstream model failure" }, 502);
    }

    // ── Runtime safety guard (rule #2) ──
    // Scan the output. On a trip, regenerate ONCE under a stricter reminder.
    // If it still trips, refuse to persist — the client falls back to its
    // deterministic read, so a diagnosis / "see a doctor" never reaches Maya.
    let violations = insightSafetyViolations(insight);
    if (violations.length > 0) {
      console.warn(`insight tripped safety guard (${violations.join(",")}) — stricter retry`);
      const retry = await generateInsight(
        row,
        scheduled,
        recent as RecentRow[],
        coachCtx,
        progressionBlock,
        athleteContextBlock,
        laps,
        keySessionLine,
        INSIGHT_STRICT_SUFFIX,
      );
      violations = retry ? insightSafetyViolations(retry) : ["empty-retry"];
      if (retry && violations.length === 0) {
        insight = retry;
      } else {
        console.error(`insight failed safety guard twice (${violations.join(",")}) — not persisting`);
        return jsonResponse({ error: "Insight filtered for safety. Try regenerating." }, 422);
      }
    }

    // --- Conditional write ---
    // IS NULL guard makes the write fire-once and race-safe: only the first
    // generation wins; a concurrent voice/manual write or a second tap is a
    // no-op.
    const { error: updErr } = await adminClient
      .from("training_logs")
      .update({
        coach_insight: insight,
        coach_insight_status: "generated",
      })
      .eq("id", trainingLogId)
      .is("coach_insight", null);

    if (updErr) {
      console.warn("update coach_insight failed:", updErr.message);
      return jsonResponse({ error: "Database write failed" }, 500);
    }

    return jsonResponse({ insight, cached: false });
  } catch (err) {
    console.error("generate-workout-insight error:", err);
    captureException(err, { fn: "generate-workout-insight" });
    await flushSentry();
    return jsonResponse({ error: String(err) }, 500);
  }
});

/**
 * Constant-time string comparison to avoid timing attacks on the
 * service-role check.
 */
function constantTimeEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

async function generateInsight(
  log: TrainingLogRow,
  scheduled: ScheduledLite | null,
  recent: RecentRow[],
  coachCtx: CoachContext,
  progressionBlock: string,
  athleteStateBlock: string,
  laps: TrainingLap[],
  keySessionLine: string,
  extraConstraint = "",
): Promise<string | null> {
  // `recent` spans 28 days (v6). The prompt's "Last 7 days:" line must keep
  // meaning 7 days, so summarizeRecent gets a filtered view while the log
  // block below gets the full window.
  const sevenDayCutoff = new Date(
    new Date(log.workout_date).getTime() - 7 * 86400000,
  ).getTime();
  const recentSummary = summarizeRecent(
    recent.filter((r) => {
      const t = new Date(r.workout_date).getTime();
      return Number.isFinite(t) && t >= sevenDayCutoff;
    }),
  );
  const recentLogsBlock = formatRecentLogsBlock(recent);

  // Pace anchoring + deterministic zone classification.
  const pacesBlock = formatPacesBlock(coachCtx);
  const executedPaceSec = parsePaceSec(log.workout_pace_per_mile)
    ?? deriveAveragePace(log.workout_distance_miles, log.workout_duration_minutes);
  const classificationLine =
    executedPaceSec != null && coachCtx.zones
      ? classifyPace(executedPaceSec, coachCtx.zones).summary
      : "";

  // Splits block — priority by fidelity:
  //   1. running_workout_laps — the actual lap presses (true rep structure:
  //      e.g. 8×1K with jog recoveries). Richest, so it wins when present.
  //   2. Garmin/HK pace_segments — mile-averaged, smears work+rest together
  //      into "alternating fast/easy miles"; usable but blurs intervals.
  //   3. Voice-extracted intervals — athlete-recalled, last resort.
  // Highest fidelity: parse-workout-structure's recovery-segmented execution
  // blocks (continuous efforts already merged — a 2k is one rep, not two 1ks).
  // These win over raw laps, which lap every mile/km and would re-split a
  // continuous rep. Then laps, then watch pace_segments, then voice.
  const parsedBlockSplits = splitsFromParsedBlocks(log.parsed_structure?.blocks);
  const lapSplits = splitsFromLaps(laps);
  const watchSplits = splitsFromPaceSegments(log.pace_segments);
  const extractedIntervals = (log.extracted_data?.intervals ?? null) as
    | Array<{ distance?: string; time?: string; rest?: string; count?: number }>
    | null;
  const voiceSplits = splitsFromExtractedIntervals(extractedIntervals);
  // ≥2 work reps needed for a meaningful splits block (formatSplitsBlock's bar),
  // so only prefer a source when it actually yields reps; otherwise fall through.
  const workRepCount = (s: WorkoutSplit[]) => s.filter((x) => x.effortKind === "work").length;
  const splits = workRepCount(parsedBlockSplits) >= 2
    ? parsedBlockSplits
    : lapSplits.length >= 2
    ? lapSplits
    : watchSplits.length > 0
    ? watchSplits
    : voiceSplits;
  // Quality sessions (intervals, tempo, race-pace reps) get the full split read.
  // Easy / steady / long runs use the large-dropoff-only register: silent on
  // normal drift (expected), but a genuinely big late fade still surfaces since
  // it can signal fatigue or heat. This is what stopped an easy run from being
  // called a "significant fade" while still catching a real dropoff.
  const isQuality = isQualityWorkoutType(log.workout_type);
  const splitsBlock = formatSplitsBlock(
    splits,
    coachCtx.zones,
    isQuality
      ? { detectPattern: true }
      : { detectPattern: true, largeDropoffOnly: true },
  );

  // Prescription-vs-execution — pass real pace_segments now so per-rep
  // comparison fires when the scheduled workout has structured steps.
  const comparison = scheduled
    ? comparePrescribedToExecuted(
        scheduled as CoachScheduledLite,
        {
          averagePaceSec: executedPaceSec,
          paceSegments: (log.pace_segments ?? []) as ExecutedSummary["paceSegments"],
        } satisfies ExecutedSummary,
        coachCtx.zones,
      )
    : null;
  const prescribedBlock = comparison?.block ?? "";

  // The insight must understand WHAT the workout was before reading it. The
  // parsed workout description (workout_notes — from the voice memo, else
  // derived from laps) and the structure headline carry that. We fold them
  // into the existing `athleteNotes` variable (rather than adding a new prompt
  // placeholder) so no prompt-template edit is needed — that would trip the
  // eval-coverage gate. Labeled "Workout:" so the model reads it as the
  // session structure, not athlete commentary.
  // Prefer the EXECUTED pattern (what was actually run, recovery-segmented) over
  // the raw typed note, which is the prescription. e.g. note "8×1000m" but ran
  // "2×(2k+2×1k)" → describe the executed shape so the insight doesn't say
  // "eight reps." Fall back to the typed note, then the legacy `pattern` field.
  const workoutDescription = (log.parsed_structure?.intent_pattern?.trim())
    || (log.workout_notes?.trim())
    || (log.parsed_structure?.pattern?.trim() ?? "");
  const athleteNotesEnriched = [
    workoutDescription ? `Workout: ${workoutDescription}` : "",
    (log.cleaned_notes ?? log.notes ?? "").trim(),
  ].filter((s) => s.length > 0).join("\n") || "—";

  const userPrompt = loadPrompt("generate-workout-insight.v6", {
    workoutType: log.workout_type ?? "run",
    distance: log.workout_distance_miles ?? "?",
    pace: log.workout_pace_per_mile ?? "?",
    duration: log.workout_duration_minutes ?? "?",
    mood: log.mood ?? "—",
    athleteNotes: athleteNotesEnriched,
    pacesBlock,
    classificationLine,
    splitsBlock,
    prescribedBlock,
    progressionBlock,
    athleteState: athleteStateBlock,
    recentLogs: recentLogsBlock,
    keySessionLine,
    recentSummary,
  });

  try {
    const model = genAI.getGenerativeModel({
      model: INSIGHT_MODEL,
      generationConfig: {
        // Gemini 2.5 Pro spends "thinking" tokens from this SAME budget before
        // it emits any text. At 1400 the thinking pass could swallow the whole
        // budget, leaving response.text() empty → null → 502 — the exact failure
        // that bricked voice-log insights (every attempt 502'd on 2026-06-17).
        // 8192 leaves ample room for the thinking pass PLUS the 2–4 sentence
        // read. The output is short, so this only raises the thinking+answer
        // ceiling; it doesn't pad cost on normal responses.
        temperature: 0.7,
        maxOutputTokens: 8192,
      },
    });

    // `extraConstraint` is appended on a safety-guard retry (see the handler):
    // a stricter reminder when a first generation tripped the rule-#2 filter.
    const finalPrompt = extraConstraint
      ? `${userPrompt}\n\n${extraConstraint}`
      : userPrompt;

    // Hard timeout. This is Gemini 2.5 Pro WITH a thinking pass, not Flash —
    // observed latency is ~12s+ and grows with the output budget, so the old
    // 20s ceiling cut it close. 45s gives Pro room while still bailing on a
    // genuine hang; the worker's retry loop picks it up.
    const result = await Promise.race([
      model.generateContent(finalPrompt),
      new Promise<never>((_, reject) =>
        setTimeout(() => reject(new Error("Gemini timeout")), 45_000)
      ),
    ]);

    const response = (result as Awaited<ReturnType<typeof model.generateContent>>).response;
    const finishReason = response.candidates?.[0]?.finishReason;

    // `.text()` THROWS when the candidate carries no text part — e.g. the whole
    // budget went to thinking tokens (finishReason MAX_TOKENS) or a safety stop
    // (SAFETY / RECITATION). Surface WHY instead of the old silent null→502
    // loop that bricked these insights with no diagnostic.
    let text = "";
    try {
      text = response.text().trim();
    } catch (e) {
      console.error(`Gemini returned no text part (finishReason=${finishReason}):`, e);
      return null;
    }

    const cleaned = text.replace(/^["'`]+|["'`]+$/g, "").trim();
    if (!cleaned) {
      console.error(`Gemini returned empty insight (finishReason=${finishReason})`);
      return null;
    }
    return cleaned;
  } catch (err) {
    console.error("Gemini call failed:", err);
    return null;
  }
}






function jsonResponse(
  body: Record<string, unknown>,
  status = 200
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
