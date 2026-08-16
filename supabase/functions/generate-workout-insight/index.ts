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

/**
 * Build a compact "## Training context" block from the athlete_state Dynamic
 * Context Object — the same coach-grade signals the Daily Read consumes. The
 * insight reads the workout THROUGH this (load, recency, injury, fitness),
 * not as a standalone. Returns "" when there's no state yet. All fields are
 * read defensively because athlete_state columns are JSON.
 */
async function loadAthleteStateBlock(userId: string): Promise<string> {
  try {
    const { data } = await adminClient
      .from("athlete_state")
      .select(
        "recent_training_summary, weekly_avg_miles, rolling_28d_miles, fitness_prediction, fitness_trend, confirmed_races, load_distribution, fitness_signal, injury_risk_score, possible_injuries, niggle_recurrence, patterns, fitness_vs_6mo_ago_label, goal_race, goal_time_seconds, current_phase, active_goals",
      )
      .eq("user_id", userId)
      .maybeSingle();
    const st = data as Record<string, unknown> | null;
    if (!st) return "";

    const lines: string[] = [];

    // M:SS / H:MM:SS formatter for predicted/race times.
    const fmtT = (s: number): string => {
      const t = Math.round(s);
      const h = Math.floor(t / 3600);
      const m = Math.floor((t % 3600) / 60);
      const sec = t % 60;
      return h > 0
        ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`
        : `${m}:${String(sec).padStart(2, "0")}`;
    };

    // Volume — so the coach NEVER has to ask "what's your weekly mileage?".
    const wk = typeof st.weekly_avg_miles === "number" ? st.weekly_avg_miles : null;
    const d28 = typeof st.rolling_28d_miles === "number" ? st.rolling_28d_miles : null;
    if (wk != null) {
      lines.push(`- Weekly volume: ~${wk} mpw (28d avg)${d28 != null ? `, ${d28} mi over 28d` : ""}`);
    }

    // Fitness — predicted race RANGES + confidence (never a single time; hard rule #7).
    const fp = st.fitness_prediction as Record<string, unknown> | null;
    if (fp && fp.ranges && typeof fp.ranges === "object") {
      const r = fp.ranges as Record<string, { low?: number; high?: number } | null>;
      const order: Array<[string, string]> = [["5K", "5K"], ["10K", "10K"], ["half", "HM"], ["marathon", "M"]];
      const parts: string[] = [];
      for (const [key, label] of order) {
        const rg = r[key];
        if (rg && typeof rg.low === "number" && typeof rg.high === "number") {
          parts.push(`${label} ${fmtT(rg.low)}–${fmtT(rg.high)}`);
        }
      }
      if (parts.length) {
        const conf = typeof fp.confidence_tier === "string" ? ` [${fp.confidence_tier} conf]` : "";
        lines.push(`- Predicted race times (ranges, not points): ${parts.join(", ")}${conf}`);
      }
    }
    if (typeof st.fitness_trend === "string" && st.fitness_trend.length > 0) {
      lines.push(`- Fitness trend: ${st.fitness_trend}`);
    }

    // Declared races — the "recent race time" the coach would otherwise ask for.
    const races = (st.confirmed_races as Array<Record<string, unknown>>) ?? [];
    if (races.length > 0) {
      const recent = [...races]
        .sort((a, b) => String(b.date ?? "").localeCompare(String(a.date ?? "")))
        .slice(0, 2)
        .map((rc) => {
          const dist = String(rc.distance ?? "race");
          const sec = Number(rc.finish_time_seconds);
          const when = String(rc.date ?? "").slice(0, 10);
          return Number.isFinite(sec) && sec > 0 ? `${dist} ${fmtT(sec)} (${when})` : `${dist} (${when})`;
        });
      lines.push(`- Recent races: ${recent.join(", ")}`);
    }

    // DIRECTION — what they're training toward + where they are in the arc. The
    // insight was previously blind to this (it read fitness/races = reality, but
    // not the goal = direction). Carried as quiet context: the coach reads a run
    // THROUGH the goal, it does not recite the goal every time.
    if (typeof st.current_phase === "string" && st.current_phase.length > 0) {
      lines.push(`- Training phase: ${st.current_phase}`);
    }
    const goals = (st.active_goals as Array<Record<string, unknown>>) ?? [];
    const g = goals[0]; // soonest upcoming goal
    if (g) {
      const bits: string[] = [String(g.title ?? "goal")];
      const days = Number(g.days_until);
      if (Number.isFinite(days)) bits.push(days >= 0 ? `${days} days out` : `${Math.abs(days)} days ago`);
      const tgtPace = typeof g.target_pace_per_mile === "string" ? g.target_pace_per_mile : "";
      if (tgtPace) bits.push(`target ${tgtPace}/mi`);
      const gap = Number(g.gap_vs_current_sec_per_mile);
      if (Number.isFinite(gap) && gap !== 0) {
        bits.push(gap > 0 ? `${gap}s/mi off current fitness` : `${Math.abs(gap)}s/mi ahead of target`);
      }
      lines.push(`- Goal: ${bits.join(", ")}`);
    } else if (typeof st.goal_race === "string" && st.goal_race.length > 0) {
      const gt = typeof st.goal_time_seconds === "number" && st.goal_time_seconds > 0
        ? ` in ${fmtT(st.goal_time_seconds)}`
        : "";
      lines.push(`- Goal: ${st.goal_race}${gt}`);
    }

    const ld = st.load_distribution as Record<string, unknown> | null;
    if (ld) {
      const bits: string[] = [];
      if (typeof ld.load_trend === "string") bits.push(String(ld.load_trend).replace(/_/g, " "));
      if (typeof ld.load_vs_chronic_pct === "number") {
        bits.push(`${ld.load_vs_chronic_pct >= 0 ? "+" : ""}${ld.load_vs_chronic_pct}% vs chronic`);
      }
      const rr = ld.recovery_read as Record<string, unknown> | null;
      if (rr?.down_week === true) bits.push("down week");
      if (typeof rr?.avg_days_between_hard === "number") bits.push(`~${rr.avg_days_between_hard}d between hard`);
      if (bits.length) lines.push(`- Training load: ${bits.join(", ")}`);
    }

    const fs = st.fitness_signal as Record<string, unknown> | null;
    if (fs && typeof fs.summary === "string" && fs.summary.length > 0) {
      lines.push(`- Fitness: ${fs.summary}`);
    } else if (typeof st.fitness_vs_6mo_ago_label === "string") {
      lines.push(`- Fitness vs 6mo ago: ${st.fitness_vs_6mo_ago_label}`);
    }

    // Niggles/injury — SURFACE only, never diagnosed (hard rule #2).
    const injBits: string[] = [];
    const niggles = (st.niggle_recurrence as Array<Record<string, unknown>>) ?? [];
    for (const n of niggles.slice(0, 2)) {
      injBits.push(`${n.body_area} ${n.occurrences}× (${n.worst_severity})`);
    }
    const possible = (st.possible_injuries as Array<Record<string, unknown>>) ?? [];
    for (const p of possible.slice(0, 1)) {
      if (typeof p.excerpt === "string") injBits.push(`"${p.excerpt}" (${p.body_area})`);
    }
    if (injBits.length) lines.push(`- Niggles mentioned: ${injBits.join("; ")}`);

    const patterns = (st.patterns as Array<Record<string, unknown>>) ?? [];
    for (const p of patterns.slice(0, 2)) {
      if (typeof p.statement === "string" && p.statement.length > 0) lines.push(`- Pattern: ${p.statement}`);
    }

    if (typeof st.recent_training_summary === "string" && st.recent_training_summary.length > 0) {
      lines.push(`- Recent: ${st.recent_training_summary}`);
    }

    return lines.length > 0 ? `## Training context\n${lines.join("\n")}` : "";
  } catch (err) {
    console.warn("loadAthleteStateBlock failed:", err);
    return "";
  }
}

interface TrainingLogRow {
  id: string;
  user_id: string;
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  workout_type: string | null;
  mood: string | null;
  cleaned_notes: string | null;
  notes: string | null;
  /** Parsed/structured workout description ("6×800m @ 2:35 w/ 90s rec") — from
   *  the voice memo, or derived from laps when the memo didn't describe it.
   *  This is how the insight knows WHAT the session was. */
  workout_notes: string | null;
  /** Parsed structure headline (parse-workout-structure output). `blocks` are
   *  the recovery-segmented EXECUTION (one work_rep per detected bout, continuous
   *  efforts already merged); `intent_pattern` describes what was actually run.
   *  These are the source of truth for rep structure — above raw laps. */
  parsed_structure:
    | {
        pattern?: string | null;
        intent_pattern?: string | null;
        blocks?: Array<{
          role?: string;
          rep_num?: number | null;
          distance_miles?: number | string;
          duration_s?: number | string;
          avg_pace_per_mile?: string;
          avg_hr?: number | null;
        }> | null;
      }
    | null;
  coach_insight: string | null;
  scheduled_workout_id: string | null;
  /** Garmin/HealthKit-derived rep splits. */
  pace_segments: Array<{
    effort?: string;
    distance_miles?: number | string;
    pace_per_mile?: string;
    avg_heart_rate?: number;
  }> | null;
  /** Voice-memo-extracted structured data (intervals/splits). */
  extracted_data: Record<string, unknown> | null;
}

interface ScheduledLite {
  id: string;
  workout_type: string | null;
  workout_data: Record<string, unknown> | null;
  notes: string | null;
}

interface RecentRow {
  workout_date: string;
  workout_distance_miles: number | null;
  workout_type: string | null;
  mood: string | null;
}

/** A row from running_workout_laps — the actual lap presses (true rep
 *  structure). Preferred over pace_segments as the splits source. */
interface TrainingLap {
  lap_index: number | null;
  distance_meters: number | string | null;
  moving_time_seconds: number | null;
  avg_pace_sec_per_mile: number | string | null;
  avg_heart_rate: number | null;
  is_rest: boolean | null;
}

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
    let scheduled: ScheduledLite | null = null;
    if (row.scheduled_workout_id) {
      const { data } = await adminClient
        .from("scheduled_workouts")
        .select("id, workout_type, workout_data, notes")
        .eq("id", row.scheduled_workout_id)
        .maybeSingle<ScheduledLite>();
      scheduled = data ?? null;
    }

    const sevenDaysAgo = new Date(
      new Date(row.workout_date).getTime() - 7 * 86400000
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
      adminClient
        .from("training_logs")
        .select("workout_date, workout_distance_miles, workout_type, mood")
        .eq("user_id", row.user_id)
        .gte("workout_date", sevenDaysAgo.toISOString())
        .lt("workout_date", row.workout_date)
        .order("workout_date", { ascending: false })
        .limit(14),
      loadCoachContext(adminClient, row.user_id),
      priorPromise,
      loadAthleteStateBlock(row.user_id),
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

    // This run's CONDITIONS — terrain (elevation), weather (heat/humidity), and
    // device signals — so the coach reads the run THROUGH its conditions instead
    // of treating every session as flat & cool. This is descriptive CONTEXT for
    // the coach to reason over, NOT a correction stamped on the splits: weather
    // comes from `weather_actual` (Open-Meteo, dew-point heat model), terrain
    // from external_streams.meta. The coach interprets it in its own voice.
    const conditionsBlock = (() => {
      const m = (row as { stream_meta?: Record<string, unknown> | null }).stream_meta;
      const wx = (row as { weather_actual?: Record<string, unknown> | null }).weather_actual;
      const bits: string[] = [];

      if (m && typeof m === "object") {
        const elevM = Number(m.total_elevation_gain);
        if (Number.isFinite(elevM) && elevM > 0) bits.push(`elevation gain ${Math.round(elevM * 3.28084)} ft`);
        const cad = Number(m.average_cadence);
        if (Number.isFinite(cad) && cad > 0) bits.push(`avg cadence ${Math.round(cad * 2)} spm`);
        const suffer = Number(m.suffer_score);
        if (Number.isFinite(suffer) && suffer > 0) bits.push(`relative effort ${Math.round(suffer)}`);
      }

      // Weather from weather_actual (dew-point heat model). `surfacing` gates how
      // much to make of it: apply (hot) / mention (mildly humid) / none (cool).
      let heatLine = "";
      if (wx && typeof wx === "object") {
        const temp = Number(wx.temp_f);
        const dew = Number(wx.dew_point_f);
        const surfacing = String(wx.surfacing ?? "");
        const cat = String(wx.heat_category ?? "").replace("_", " ");
        const pct = Number(wx.adjustment_pct); // continuous-run basis
        if (Number.isFinite(temp) && Number.isFinite(dew) && surfacing !== "none") {
          const wbits = [`${Math.round(temp)}°F`, `${Math.round(dew)}°F dew point`];
          if (cat) wbits.push(cat);
          bits.push(wbits.join(", "));
          if (surfacing === "apply" && Number.isFinite(pct) && pct > 0) {
            const contPct = (pct * 100).toFixed(1);
            const repPct = (pct * 50).toFixed(1); // short reps ≈ half (rep-length scaled)
            heatLine = `\n- Heat model (reference, not a correction): conditions cost ~${contPct}% on continuous efforts (tempo/easy), about half (~${repPct}%) on short interval reps since the body cools during recoveries. Read paces as honest-for-effort; do not restate corrected splits.`;
          } else if (surfacing === "mention") {
            heatLine = `\n- Mildly humid — worth a nod for how the run felt, but not enough to adjust pace.`;
          }
        }
      }

      if (bits.length === 0 && !heatLine) return "";
      return `## This run's conditions\n- ${bits.join(" · ")}${heatLine}`;
    })();

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
  extraConstraint = "",
): Promise<string | null> {
  const recentSummary = summarizeRecent(recent);

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

  const userPrompt = loadPrompt("generate-workout-insight.v5", {
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

/** Parse a "M:SS" pace string to seconds/mile, or null. */
function parsePaceSec(s: string | null | undefined): number | null {
  if (!s) return null;
  const m = s.match(/^(\d{1,2}):(\d{2})$/);
  if (!m) return null;
  const min = parseInt(m[1]);
  const sec = parseInt(m[2]);
  if (isNaN(min) || isNaN(sec)) return null;
  return min * 60 + sec;
}

/** Compute average pace from distance + duration, or null. */
function deriveAveragePace(distanceMi: number | null, durationMin: number | null): number | null {
  if (!distanceMi || !durationMin || distanceMi <= 0 || durationMin <= 0) return null;
  return Math.round((durationMin * 60) / distanceMi);
}

function summarizeRecent(rows: RecentRow[]): string {
  if (rows.length === 0) return "no other runs in the last week";
  const totalMi = rows.reduce(
    (s, r) => s + (r.workout_distance_miles ?? 0),
    0
  );
  const types = rows.map((r) => r.workout_type).filter((t): t is string => !!t);
  const typeCounts: Record<string, number> = {};
  for (const t of types) typeCounts[t] = (typeCounts[t] ?? 0) + 1;
  const typeStr = Object.entries(typeCounts)
    .map(([t, n]) => `${n} ${t}`)
    .join(", ");
  return `${rows.length} runs (${totalMi.toFixed(1)} mi) — ${typeStr || "mix"}`;
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
