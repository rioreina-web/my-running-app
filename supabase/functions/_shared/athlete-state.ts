/**
 * Athlete State — Dynamic Context Object (DCO)
 *
 * The central nervous system of the AI architecture. Every AI function imports
 * this module to read the current athlete state instead of independently
 * querying 6-8 tables.
 *
 * Usage in an edge function:
 *   import { getAthleteState, updateAthleteState } from "../_shared/athlete-state.ts";
 *
 *   const state = await getAthleteState(supabase, userId);
 *   // ... use state in AI prompt ...
 *   await updateAthleteState(supabase, userId, { last_mood: "tired", last_readiness_score: 3 });
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  computePaceZones,
  type AthletePaceProfileRow,
  type FitnessSnapshotRow,
  type TrainingPlanRow,
  type TrainingLogRow as PaceEngineLogRow,
} from "./pace-engine.ts";
import {
  type WorkoutFeaturesRow,
} from "./weeklyAnalytics.ts";
import {
  segmentFromLaps,
  type LapInput,
  type PaceZones,
} from "./workoutSegmentation.ts";
import {
  computeFitnessSignal,
  type FitnessSignal,
  type SessionInput as FitnessSessionInput,
} from "./fitnessSignal.ts";
import { formatPace, formatTime, formatTimeDelta } from "./shared/format.ts";
import { buildMoodTrend, type MoodLogRow } from "./builders/buildMoodTrend.ts";
import { buildLoadMetrics } from "./builders/buildLoadMetrics.ts";
import { buildTrajectory, derivePhase, deriveExperience } from "./builders/buildTrajectory.ts";
import { buildLoadDistribution } from "./builders/buildLoadDistribution.ts";
import { buildBlocks } from "./builders/buildBlocks.ts";

// Re-exported for backwards compatibility — existing importers (and tests)
// pull `formatPace` from this module.
export { formatPace };

// Schema version stamped onto every rebuilt state. Currently informational
// only — no consumer reads it (verified 2026-06-18). Bump when a shape change
// needs a real migration/invalidation story; until then it documents intent
// rather than driving behavior.
export const ATHLETE_STATE_SCHEMA_VERSION = 1;

// ── Types ────────────────────────────────────────────────

export interface AthleteState {
  user_id: string;

  // Identity & Phase
  experience_level: string | null;
  current_phase: string | null;
  active_plan_id: string | null;
  goal_race: string | null;
  goal_time_seconds: number | null;

  // Load & Fitness
  acwr: number | null;
  monotony_7d: number | null;
  strain_7d: number | null;
  rolling_7d_miles: number | null;
  rolling_28d_miles: number | null;
  weekly_avg_miles: number | null;
  hard_sessions_7d: number;
  easy_sessions_7d: number;
  runs_last_7d: number;
  longest_run_14d: number | null;

  // Fitness Trajectory
  predicted_5k_seconds: number | null;
  predicted_10k_seconds: number | null;
  predicted_half_seconds: number | null;
  predicted_marathon_seconds: number | null;
  fitness_trend: string | null;
  fitness_snapshot_id: string | null;
  fitness_snapshot_at: string | null;

  // Recent Vibe
  last_mood: string | null;
  last_readiness_score: number | null;
  mood_trend: string | null;
  last_check_in_at: string | null;

  // Injury & Risk
  active_injuries: Array<{
    body_area: string;
    severity: number;
    status: string;
    first_reported_at: string;
  }>;
  injury_risk_score: number | null;
  injury_risk_signals: Array<{ signal: string; level: string; detail: string }>;
  /** Body-part mentions detected in recent voice memos/notes — NOT declared injuries yet. */
  possible_injuries: Array<{
    body_area: string;
    excerpt: string;
    date: string;
    severity_hint: string; // "tight" | "sore" | "pain" | "sharp"
    volume_context: string | null; // e.g. "2wk volume +40% before mention"
  }>;
  /**
   * Durable niggle recurrence from the `body_mentions` table (12 months).
   * The pattern view a coach actually cares about — "left knee, 3× over
   * 6 weeks." Surface the pattern; never diagnose (hard rule #2).
   */
  niggle_recurrence: Array<{
    body_area: string;
    occurrences: number;
    first_seen: string;
    last_seen: string;
    worst_severity: string;
  }>;

  // Pace Zones
  // `pace_zones` keeps single-number values for race anchors (mp, hm, tenK,
  // fiveK, mile) and for surfaces that need a single target (workoutSelection).
  // `pace_zone_ranges` carries the engine's range output for Easy / Moderate /
  // Steady / Threshold — used by the prompt path so AI sees coach-style bands,
  // not midpoint approximations.
  pace_zones: Record<string, number>;
  pace_zone_ranges: {
    easy?:     { paceFast: number; paceSlow: number; effortPercent: string };
    moderate?: { paceFast: number; paceSlow: number; effortPercent: string };
    steady?:   { paceFast: number; paceSlow: number; effortPercent: string };
    hmp?:      { paceFast: number; paceSlow: number; effortPercent: string };
  };

  // Recent Training
  recent_training_summary: string | null;
  recent_workouts: Array<{
    date: string;
    type: string;
    miles: number;
    /** Avg pace from the DB. MISLEADING for interval/tempo workouts — always prefer work_pace when present. */
    pace: string | null;
    mood: string | null;
    /** Observer-parsed pattern, e.g. "5×1mi @ 5:19/mi with 0.25mi jog recovery". Null when unparsed. */
    structure_pattern: string | null;
    /** Equivalent race pace derived by the Observer, e.g. "tenK @ 5:15/mi". Null when unparsed. */
    equivalent_race: string | null;
    /** User-written workout notes — the single most reliable signal for WHAT the workout was. */
    user_notes: string | null;
    /** Avg pace of the actual WORK portion (intervals, tempo) when parsed. Beats `pace` for quality sessions. */
    work_pace: string | null;
  }>;

  // Scheduled Context
  today_workout: Record<string, unknown> | null;
  upcoming_workouts: Array<Record<string, unknown>>;
  week_compliance_pct: number | null;

  // ── Biographical context (the athlete arc, not just today) ──
  /** Predicted 10K delta vs 6-month-ago snapshot (sec). Positive = slower now. */
  fitness_vs_6mo_ago_seconds: number | null;
  /** Human label: "much faster" / "faster" / "similar" / "slower" / "much slower" */
  fitness_vs_6mo_ago_label: string | null;
  /** Last 12 months of injuries with recurrence flags */
  injury_history_summary: Array<{
    body_area: string;
    first_at: string;
    last_at: string;
    occurrences: number;
    status: string;
  }>;
  /** Ego-safe framing: building | peaking | maintaining | returning | declining */
  trajectory_framing: string | null;
  /** One-line rationale for trajectory (why we chose that label). */
  trajectory_reason: string | null;
  /** Upcoming goals with days-until countdown. Empty array when none set. */
  active_goals: Array<{
    title: string;
    target_date: string;
    days_until: number;
    /** Parsed target distance ("5K", "10K", "half", "marathon", "mile") if the title has one */
    target_distance_key: string | null;
    /** Parsed target finish time in seconds ("sub 15 5K" → 900) if parseable */
    target_time_seconds: number | null;
    /** Derived target pace in sec/mi */
    target_pace_per_mile: string | null;
    /** Current predicted pace at that distance vs target (positive = slower than goal) */
    gap_vs_current_sec_per_mile: number | null;
  }>;
  /** Last 6 four-week blocks (most recent first) for block-over-block coaching. */
  recent_blocks: Array<{
    block_start: string;          // YYYY-MM-DD
    block_end: string;             // YYYY-MM-DD
    total_miles: number;
    weekly_avg_miles: number;
    quality_sessions: number;      // interval/tempo/race count from parsed_structure
    easy_sessions: number;
    races_entered: number;
    avg_easy_pace_sec: number | null;
    injury_mentions: number;
    mood_summary: string | null;   // dominant mood label for the block
  }>;
  /**
   * User-declared races (from training_logs.race_result). Trusted source —
   * populated only when the athlete marks a workout as a race.
   */
  confirmed_races: Array<{
    date: string;              // ISO
    distance: string;          // '5K' | '10K' | 'half' | 'marathon' | 'mile' | 'other'
    finish_time_seconds: number;
    official: boolean;
    event_name: string | null;
  }>;

  /**
   * UI register gate (0..3). Drives editorial voice on Today and gates pull-quote
   * surfaces. Recomputed in rebuildAthleteState — see computeDataDepth.
   *   0 — new account, no training data
   *   1 — 1+ run or voice log
   *   2 — 7+ distinct training days
   *   3 — 21+ distinct training days, or goal set with 1+ run
   */
  data_depth: number;

  // ── v2 satellites (coach-grade) ──
  /**
   * Volume × intensity distribution — the prompt-facing load model.
   * Replaces ACWR (still computed in `acwr` for one release, but not
   * surfaced). Sourced from `workout_features` time-in-zone, mirroring
   * `PaceVolumeSpectrumChart`. Null when no workout_features exist yet.
   */
  load_distribution: {
    window_days: number;
    /** Volume × Intensity — pace-weighted load in weighted minutes (7d / 28d). */
    volume_x_intensity_7d: number;
    volume_x_intensity_28d: number;
    minutes_7d: { easy: number; moderate: number; threshold: number; hard: number };
    minutes_28d: { easy: number; moderate: number; threshold: number; hard: number };
    zone_pct_7d: { easy: number; moderate: number; threshold: number; hard: number };
    effort_distribution: string | null;
    intensity_score_latest: number | null;
    monotony_7d: number | null;
    strain_7d: number | null;
    hr_pace_efficiency: number | null;
    // WS3 — the surfaced load STORY (replaces the ACWR ratio). Trend is the
    // recent weekly load vs an 8-week chronic baseline; the recovery read is
    // hard-day spacing + whether the current week is a down week.
    load_trend: "building" | "holding" | "spiking" | "backing_off" | null;
    chronic_window_days: number;
    load_vs_chronic_pct: number | null; // recent weekly load vs chronic norm (+/- %)
    recovery_read: {
      avg_days_between_hard: number | null;
      hard_sessions_28d: number;
      down_week: boolean; // current 7d load well below the chronic norm
    } | null;
  } | null;

  /**
   * Range + confidence predictions (never point estimates — hard rule #7).
   * Each range is { low, high, point } in seconds. Sourced from the latest
   * `fitness_snapshots` row's range_* bands.
   */
  fitness_prediction: {
    confidence_tier: string | null;
    workout_count: number | null;
    ranges: Record<string, { low: number; high: number; point: number } | null>;
  } | null;

  /** Durable coach memory from `user_memories` (preferences, life context). */
  memories: Array<{ category: string; content: string; importance: number }>;

  /**
   * Per-run environment from `running_workout_laps` — lets the Read
   * contextualize pace against conditions ("7:45 but 78°F, heat-adjusted
   * 7:28"). Most recent first, up to 10.
   */
  environment: Array<{
    date: string;
    temp_f: number | null;
    dew_point_f: number | null;
    heat_category: string | null;
    heat_adjustment_pct: number | null;   // % the heat slowed pace
    actual_pace: string | null;           // M:SS/mi, distance-weighted
    heat_adjusted_pace: string | null;    // M:SS/mi
    elevation_gain_ft: number | null;
  }>;

  /**
   * Per-quality-session execution from `running_workout_laps` — did the
   * workout land? Splits, fade, rep consistency, HR drift. Up to 4 most
   * recent structured sessions.
   */
  execution: Array<{
    date: string;
    type: string | null;
    rep_count: number;
    rep_paces: string[];          // M:SS per work rep
    fade_pct: number | null;      // last rep vs first (+ = slowed)
    pace_cv_pct: number | null;   // coefficient of variation across reps
    hr_drift_pct: number | null;  // last work HR vs first (+ = drifted up)
    shape: string;                // "negative split" | "even" | "faded"
    structure?: string | null;    // WS1: "9×1K @ 5:07 (5K)" when structured
  }>;

  /**
   * Objective fitness backbone — pace-at-HR efficiency trend over 12 weeks.
   * Rolls per-rep pace+HR (from `running_workout_laps`) UP across sessions,
   * bucketed by comparable effort (easy / threshold / interval): "same pace,
   * HR direction" = the fitness verdict the Read expects, plus long-run
   * aerobic decoupling. Direction + window + sample-based confidence — never a
   * point estimate (hard rule #7). Computed by `_shared/fitnessSignal.ts`.
   * Null until ≥2 comparable sessions exist in each of the recent/baseline
   * windows.
   */
  fitness_signal: FitnessSignal | null;

  /**
   * Longitudinal patterns — the coach's edge. Rule-based observations over
   * the joined data (niggle-vs-load, pacing tendency, heat sensitivity,
   * easy-day discipline, mood-vs-monotony). Each is a plain-language
   * statement plus the numbers behind it; the Read may surface one.
   */
  patterns: Array<{
    kind: string;
    statement: string;
    evidence: string;
    confidence: "high" | "medium" | "low";
  }>;

  /**
   * Computed blind spots — the honest "what I can't see" list (Rec #5).
   * Grounds the Read's `cant_see` block in real gaps instead of the model
   * inventing one. `gap` is a 2-4 word mono eyebrow; `detail` is one
   * plain sentence.
   */
  data_gaps: Array<{ gap: string; detail: string }>;

  // Metadata
  last_updated_at: string;
  last_updated_by: string | null;
  version: number;
}

/**
 * Derives data_depth (0..3) from athlete signals. Goal-set fast-tracks to 3
 * only when there's at least one workout — a brand-new user who sets a goal in
 * onboarding stays at 1 until they log something. See CLAUDE.md "data_depth"
 * and outputs/new-user-action-plan.md.
 */
export function computeDataDepth(args: {
  workoutCount: number;
  uniqueDayCount: number;
  hasActiveGoal: boolean;
}): number {
  if (args.uniqueDayCount >= 21) return 3;
  if (args.hasActiveGoal && args.workoutCount >= 1) return 3;
  if (args.uniqueDayCount >= 7) return 2;
  if (args.workoutCount >= 1) return 1;
  return 0;
}

// ── Read ─────────────────────────────────────────────────

/**
 * Get the current athlete state. Returns null if no state exists yet
 * (first-time user). Callers should handle null by calling
 * rebuildAthleteState() to initialize.
 */
export async function getAthleteState(
  supabase: SupabaseClient,
  userId: string
): Promise<AthleteState | null> {
  const { data, error } = await supabase
    .from("athlete_state")
    .select("*")
    .eq("user_id", userId)
    .maybeSingle();

  if (error) {
    console.error("[AthleteState] Failed to fetch:", error.message);
    return null;
  }

  return data as AthleteState | null;
}

/**
 * Get the athlete state, rebuilding it from source tables if it doesn't
 * exist or is stale (> maxAgeMinutes). This is the primary entry point
 * for AI functions.
 */
export async function getOrBuildAthleteState(
  supabase: SupabaseClient,
  userId: string,
  maxAgeMinutes: number = 60
): Promise<AthleteState> {
  const existing = await getAthleteState(supabase, userId);

  if (existing) {
    const age = Date.now() - new Date(existing.last_updated_at).getTime();
    if (age < maxAgeMinutes * 60 * 1000) {
      return existing;
    }
  }

  // Rebuild from source tables
  return await rebuildAthleteState(supabase, userId);
}

// ── Write (partial update) ───────────────────────────────

/**
 * Partially update the athlete state. Only sends the fields you provide.
 * Automatically sets last_updated_at and last_updated_by.
 */
export async function updateAthleteState(
  supabase: SupabaseClient,
  userId: string,
  patch: Partial<AthleteState> & { last_updated_by: string }
): Promise<void> {
  const payload = {
    ...patch,
    user_id: userId,
    last_updated_at: new Date().toISOString(),
  };

  const { error } = await supabase
    .from("athlete_state")
    .upsert(payload, { onConflict: "user_id" });

  if (error) {
    console.error("[AthleteState] Failed to update:", error.message);
  }
}

// ── Full Rebuild ─────────────────────────────────────────

/**
 * Rebuild the entire athlete state from source tables. Expensive but
 * comprehensive. Called on first use or when state is stale.
 */
export async function rebuildAthleteState(
  supabase: SupabaseClient,
  userId: string
): Promise<AthleteState> {
  // HOTFIX-H.2: serialize concurrent rebuilds. The claim RPC holds a
  // per-user advisory lock for the claim check, and stamps
  // rebuild_started_at to prevent in-flight overlap.
  const { data: shouldRebuild } = await supabase.rpc(
    "claim_athlete_state_rebuild",
    { p_user_id: userId }
  );
  if (shouldRebuild === false) {
    // Either the state is fresh (<30s) or another rebuild is in flight.
    // Poll briefly for the in-flight case so callers don't return stale.
    for (let i = 0; i < 10; i++) {
      const existing = await getAthleteState(supabase, userId);
      if (existing) {
        const age = Date.now() - new Date(existing.last_updated_at).getTime();
        if (age < 30 * 1000) return existing;
      }
      await new Promise((r) => setTimeout(r, 300));
    }
    // Still stale after ~3s of waiting — the in-flight build stalled.
    // Fall through and rebuild ourselves rather than return bad state.
    //
    // KNOWN LIMITATION (residual concurrency risk): the advisory lock is held
    // only for the claim RPC, not the rebuild body. This fall-through can run a
    // second full rebuild concurrently with a slow in-flight one; the final
    // upsert is last-write-wins, so two rebuilds can interleave. It's bounded
    // (only after a ~3s stall) and self-healing (both write a valid state), but
    // it is NOT fully serialized. A true fix holds the lock for the whole body
    // (refactor design R4 / §3 lock.ts) — deferred.
  }

  const rebuildStartMs = Date.now();
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 86400000).toISOString();
  const fourteenDaysAgo = new Date(now.getTime() - 14 * 86400000).toISOString();
  const twentyEightDaysAgo = new Date(now.getTime() - 28 * 86400000).toISOString();
  // WS3 — 12-week window for the load trend + 8-week chronic baseline (a coach
  // reads cycles, not fortnights). The 7d/28d zone aggregates still slice 28d.
  const eightyFourDaysAgo = new Date(now.getTime() - 84 * 86400000).toISOString();
  const today = now.toISOString().split("T")[0];

  // Parallel fetch everything we need
  const sixMonthsAgoISO = new Date(now.getTime() - 183 * 86400000).toISOString();
  const twelveMonthsAgoISO = new Date(now.getTime() - 365 * 86400000).toISOString();

  const [
    recentLogsRes,
    profileRes,
    snapshotRes,
    injuriesRes,
    planRes,
    goalsRes,
    checkInsRes,
    snapshot6moRes,
    injuryHistoryRes,
    blockHistoryRes,
    paceProfileRes,
    workoutFeaturesRes,
    confirmedRacesRes,
    memoriesRes,
  ] = await Promise.all([
    // Last 28 days of training logs for current load/state.
    supabase
      .from("training_logs")
      .select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, mood, cleaned_notes, notes, workout_notes, source, parsed_structure, pace_segments")
      .eq("user_id", userId)
      .gte("workout_date", twentyEightDaysAgo)
      .order("workout_date", { ascending: false })
      .limit(100),
    // Athlete profile
    supabase
      .from("athlete_profiles")
      .select("*")
      .eq("user_id", userId)
      .maybeSingle(),
    // Latest TWO fitness snapshots — [0] current, [1] prior (for fitness_trend).
    supabase
      .from("fitness_snapshots")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(2),
    // Active injuries
    supabase
      .from("injuries")
      .select("body_area, severity, status, first_reported_at")
      .eq("user_id", userId)
      .in("status", ["active", "monitoring"])
      .order("severity", { ascending: false }),
    // Active training plan (end_date = race date; drives the peaking guard).
    supabase
      .from("training_plans")
      .select("id, name, target_race_distance, target_time_seconds, status, end_date")
      .eq("user_id", userId)
      .eq("status", "active")
      .maybeSingle(),
    // Active goals — strictly scoped to the authenticated user. Null user_id
    // rows in this table are legacy creation-flow bugs and must never leak
    // across tenants, so we require an exact match.
    supabase
      .from("user_goals")
      .select("goal_title, target_date, user_id")
      .eq("status", "active")
      .eq("user_id", userId)
      .not("user_id", "is", null)
      .order("target_date", { ascending: true })
      .limit(10),
    // Recent check-ins (for mood trend)
    supabase
      .from("training_logs")
      .select("mood, created_at, extracted_data")
      .eq("user_id", userId)
      .eq("source", "check_in")
      .not("mood", "is", null)
      .order("created_at", { ascending: false })
      .limit(5),
    // Fitness snapshot from ~6 months ago (for biographical context)
    supabase
      .from("fitness_snapshots")
      .select("predicted_10k_seconds, created_at")
      .eq("user_id", userId)
      .lte("created_at", new Date(now.getTime() - 150 * 86400000).toISOString())
      .gte("created_at", new Date(now.getTime() - 210 * 86400000).toISOString())
      .order("created_at", { ascending: false })
      .limit(1),
    // 12-month injury history (all statuses, for recurrence detection)
    supabase
      .from("injuries")
      .select("body_area, severity, status, first_reported_at, resolved_at")
      .eq("user_id", userId)
      .gte("first_reported_at", twelveMonthsAgoISO)
      .order("first_reported_at", { ascending: false }),
    // 24 weeks of workout data — for training_blocks rollups (6×4wk),
    // race history regex scanning, AND PaceEngine's observed-easy
    // computation. workout_type added so the engine can filter easy/recovery
    // runs without depending only on parsed_structure.
    supabase
      .from("training_logs")
      .select("id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, source, parsed_structure, cleaned_notes, notes, workout_notes")
      .eq("user_id", userId)
      .gte("workout_date", new Date(now.getTime() - 168 * 86400000).toISOString())
      .gt("workout_distance_miles", 0)
      .order("workout_date", { ascending: false })
      .limit(400),
    // Athlete pace profile — the single source of truth for pace zones.
    // When present, we read reference paces directly instead of deriving them
    // from snapshot predictions × hardcoded multipliers. See
    // athlete-state-refactor-design.md § R7.
    supabase
      .from("athlete_pace_profiles")
      .select("easy_pace_seconds, marathon_pace_seconds, half_pace_seconds, ten_k_pace_seconds, five_k_pace_seconds, mile_pace_seconds, updated_at")
      .eq("user_id", userId)
      .maybeSingle(),
    // Workout features for the same 28-day window — feeds intensity-weighted
    // ACWR. We pull intensity_score and total_duration_seconds, then load =
    // intensity_score × duration / 60 per workout. Logs without features
    // (e.g. compute-workout-features hasn't run yet) fall back to
    // workout_type × duration in computeWeightedLoadForLog().
    supabase
      .from("workout_features")
      .select("training_log_id, intensity_score, total_duration_seconds, workout_date, easy_seconds, moderate_seconds, threshold_seconds, hard_seconds, effort_distribution, monotony_7d, strain_7d, hr_pace_efficiency")
      .eq("user_id", userId)
      // WS3: 12 weeks so the load trend has a chronic baseline. The 7d/28d
      // aggregates below slice this set down to their own windows.
      .gte("workout_date", eightyFourDaysAgo)
      .order("workout_date", { ascending: false }),
    // 2-year window of user-declared races — the canonical source for
    // athlete_state.confirmed_races (the derived cache that downstream
    // surfaces read for race-anchored fitness reasoning). Window mirrors
    // the 2-year HealthKit back-fill scope. race_result is non-null only
    // when the athlete has explicitly marked a workout as a race; we
    // exclude rows without a populated result. Phase 2 sub-task A —
    // see outputs/phase-2-race-anchoring-plan-2026-06-04.md.
    supabase
      .from("training_logs")
      .select("workout_date, race_result")
      .eq("user_id", userId)
      .eq("workout_type", "race")
      .not("race_result", "is", null)
      .gte("workout_date", new Date(now.getTime() - 730 * 86400000).toISOString())
      .order("workout_date", { ascending: false })
      .limit(50),
    // Durable coach memory — preferences, life context, constraints,
    // decisions. Highest-importance first; expiry filtered in code.
    supabase
      .from("user_memories")
      .select("category, content, importance, expires_at")
      .eq("user_id", userId)
      .order("importance", { ascending: false })
      .limit(12),
  ]);

  // Surface partial-failure: any of these reads erroring silently degrades the
  // state (e.g. an empty training_logs read flips current_phase/trajectory with
  // no signal). Log each failure so the degradation is visible in prod. NOTE:
  // this is observability only — the design's "preserve previous slice on
  // failure" (refactor §6) is still pending; a failed read currently yields an
  // empty/zero slice, not the prior value.
  for (const [name, res] of ([
    ["training_logs", recentLogsRes],
    ["athlete_profiles", profileRes],
    ["fitness_snapshots", snapshotRes],
    ["injuries", injuriesRes],
    ["training_plans", planRes],
    ["user_goals", goalsRes],
    ["check_ins", checkInsRes],
    ["fitness_snapshots_6mo", snapshot6moRes],
    ["injury_history", injuryHistoryRes],
    ["block_history", blockHistoryRes],
    ["athlete_pace_profiles", paceProfileRes],
    ["workout_features", workoutFeaturesRes],
    ["confirmed_races", confirmedRacesRes],
    ["user_memories", memoriesRes],
  ] as Array<[string, { error: { message: string } | null }]>)) {
    if (res?.error) {
      console.warn(`[AthleteState] source read '${name}' failed (slice degraded): ${res.error.message}`);
    }
  }

  const logs = (recentLogsRes.data ?? []) as Array<Record<string, unknown>>;
  const profile = profileRes.data;
  const snapshot = (snapshotRes.data as Array<Record<string, unknown>> | null)?.[0];
  const injuries = (injuriesRes.data ?? []) as Array<{
    body_area: string; severity: number; status: string; first_reported_at: string;
  }>;
  const plan = planRes.data;
  const checkIns = (checkInsRes.data ?? []) as Array<{
    mood: string; created_at: string; extracted_data: Record<string, unknown> | null;
  }>;

  // Build features map keyed by training_log.id for the intensity-weighted
  // ACWR computation. Logs without a feature row fall back to
  // workout_type × duration in computeWeightedLoadForLog().
  const featuresByLogId = new Map<string, WorkoutFeaturesRow>();
  for (const f of (workoutFeaturesRes.data ?? []) as WorkoutFeaturesRow[]) {
    if (f.training_log_id) featuresByLogId.set(f.training_log_id, f);
  }
  const paceProfile = paceProfileRes.data as {
    easy_pace_seconds: number | null;
    marathon_pace_seconds: number | null;
    half_pace_seconds: number | null;
    ten_k_pace_seconds: number | null;
    five_k_pace_seconds: number | null;
    mile_pace_seconds: number | null;
    updated_at: string;
  } | null;

  // ── Compute load metrics ── (see _shared/builders/buildLoadMetrics.ts)
  const {
    workoutsWithMiles,
    last7d,
    rolling7dMiles,
    rolling28dMiles,
    weeklyAvg28d,
    acwr,
    hardSessions7d,
    easySessions7d,
    longestRun14d,
    runsLast7d,
  } = buildLoadMetrics({
    logs,
    featuresByLogId,
    snapshot,
    sevenDaysAgo,
    fourteenDaysAgo,
    twentyEightDaysAgo,
  });

  // ── Mood trend ── (see _shared/builders/buildMoodTrend.ts)
  const moodTrend = buildMoodTrend(checkIns, logs as MoodLogRow[]);

  // ── Fitness trajectory ──
  // Compare the latest two fitness_snapshots on predicted 10K (lower = faster).
  // Fixes the v1 stub that hardcoded "maintaining" — which also meant the
  // trajectory "building" branch (gated on fitnessTrend === "improving")
  // could never fire.
  let fitnessTrend: string | null = null;
  if (snapshot) {
    const prevSnapshot = (snapshotRes.data as Array<Record<string, unknown>> | null)?.[1];
    const cur10k = Number(snapshot.predicted_10k_seconds ?? NaN);
    const prev10k = prevSnapshot ? Number(prevSnapshot.predicted_10k_seconds ?? NaN) : NaN;
    if (isFinite(cur10k) && isFinite(prev10k) && prev10k > 0) {
      const deltaPct = ((prev10k - cur10k) / prev10k) * 100; // + = faster now
      fitnessTrend = deltaPct >= 1 ? "improving" : deltaPct <= -1 ? "declining" : "maintaining";
    } else {
      fitnessTrend = "maintaining"; // single snapshot — no trend to read yet
    }
  }

  // ── Pace zones ──
  // SOURCE OF TRUTH: _shared/pace-engine.ts. Cascade is observed easy runs
  // (≥8 sessions in 90d) > athlete_pace_profiles columns > fitness_snapshot
  // predictions > active plan goal time. The engine handles partial sources
  // gracefully (e.g. profile.marathon_pace + snapshot for the rest).
  //
  // The flat numeric `paceZones` map below is a backwards-compat projection
  // for downstream consumers (race-intel, training-analysis, post-run-analysis,
  // parse-workout-shorthand). They will read the engine's structured output
  // directly in a later phase; until then, they keep working unchanged.
  const enginePaceZones = computePaceZones({
    athleteUserId: userId,
    profile: paceProfile as AthletePaceProfileRow | null,
    snapshot: (snapshot ?? null) as FitnessSnapshotRow | null,
    plan: (plan ?? null) as TrainingPlanRow | null,
    recentLogs: ((blockHistoryRes?.data ?? []) as unknown as PaceEngineLogRow[]),
    now,
  });

  const paceZones: Record<string, number> = {};
  // Project engine output into the legacy flat shape. Effort ranges collapse
  // to single numbers (anchor for Easy = paceFast; midpoint for Moderate /
  // Steady) so consumers expecting one number still get one.
  if (enginePaceZones.easy) {
    paceZones.easy = enginePaceZones.easy.paceFast;
  }
  if (enginePaceZones.moderate) {
    paceZones.moderate = Math.round(
      (enginePaceZones.moderate.paceFast + enginePaceZones.moderate.paceSlow) / 2
    );
  }
  if (enginePaceZones.steady) {
    paceZones.steady = Math.round(
      (enginePaceZones.steady.paceFast + enginePaceZones.steady.paceSlow) / 2
    );
  }
  if (enginePaceZones.marathon)     paceZones.mp = enginePaceZones.marathon.pace;
  if (enginePaceZones.halfMarathon) paceZones.hm = enginePaceZones.halfMarathon.pace;
  if (enginePaceZones.tenK)         paceZones.tenK = enginePaceZones.tenK.pace;
  if (enginePaceZones.fiveK)        paceZones.fiveK = enginePaceZones.fiveK.pace;
  if (enginePaceZones.mile)         paceZones.mile = enginePaceZones.mile.pace;

  // Range form for the prompt path. AI sees Easy / Moderate / Steady as
  // bands with effort %, not midpoint approximations.
  const paceZoneRanges: AthleteState["pace_zone_ranges"] = {};
  if (enginePaceZones.easy) {
    paceZoneRanges.easy = {
      paceFast: enginePaceZones.easy.paceFast,
      paceSlow: enginePaceZones.easy.paceSlow,
      effortPercent: enginePaceZones.easy.effortPercent,
    };
  }
  if (enginePaceZones.moderate) {
    paceZoneRanges.moderate = {
      paceFast: enginePaceZones.moderate.paceFast,
      paceSlow: enginePaceZones.moderate.paceSlow,
      effortPercent: enginePaceZones.moderate.effortPercent,
    };
  }
  if (enginePaceZones.steady) {
    paceZoneRanges.steady = {
      paceFast: enginePaceZones.steady.paceFast,
      paceSlow: enginePaceZones.steady.paceSlow,
      effortPercent: enginePaceZones.steady.effortPercent,
    };
  }
  // HMP rendered as a tight range (HM pace ± 5s) so it sits consistently
  // alongside Easy / Moderate / Steady. Same coach-honest framing — a band,
  // not a single point. Replaces the old "Threshold" label which was fuzzy.
  if (enginePaceZones.halfMarathon) {
    const a = enginePaceZones.halfMarathon.pace;
    paceZoneRanges.hmp = {
      paceFast: a - 5,
      paceSlow: a + 5,
      effortPercent: "Half Marathon Pace",
    };
  }

  // Map the engine's richer source enum into the legacy two-state label.
  // "observed" rolls into "profile" because both are athlete-truth (not
  // formula-derived). "race_derived" / "goal_only" both roll into "prediction".
  const paceZonesSource: "profile" | "prediction" | "none" =
    enginePaceZones.primarySource === "profile" || enginePaceZones.primarySource === "observed"
      ? "profile"
      : enginePaceZones.primarySource === "race_derived" || enginePaceZones.primarySource === "goal_only"
      ? "prediction"
      : "none";

  // ── Recent workouts (last 7) ──
  // Prefer Observer-parsed type/pattern over raw workout_type when parsed_structure
  // is present — "5×1mi @ 5:19 (interval)" beats "long_run @ 7:30 avg".
  // Always include the last 2 parsed quality sessions in context, even if older
  // than 7 days. Otherwise a coach never sees your intervals during easy weeks.
  const parsedQualityTypes = new Set(["interval", "tempo", "race", "progression"]);
  const parsedQuality = workoutsWithMiles.filter((l) => {
    const p = l.parsed_structure as Record<string, unknown> | null;
    const t = (p && typeof p === "object") ? (p["type"] as string | undefined) : undefined;
    return t && parsedQualityTypes.has(t);
  }).slice(0, 2);

  const recentPool = [...last7d.slice(0, 7)];
  for (const q of parsedQuality) {
    if (!recentPool.some((r) => r.id === q.id)) recentPool.push(q);
  }
  recentPool.sort((a, b) =>
    String(b.workout_date ?? "").localeCompare(String(a.workout_date ?? ""))
  );

  const recentWorkouts = recentPool.slice(0, 9).map((l) => {
    const parsed = l.parsed_structure as Record<string, unknown> | null;
    const parsedObj = parsed && typeof parsed === "object" ? parsed : null;
    const parsedType = parsedObj?.["type"] as string | undefined;
    // New synthesizer uses intent_pattern; legacy parses used pattern. Prefer new.
    const parsedPattern = (parsedObj?.["intent_pattern"] as string | undefined)
      ?? (parsedObj?.["pattern"] as string | undefined);
    const parsedEq = parsedObj?.["equivalent_race_pace"] as Record<string, string> | null | undefined;
    // New synthesizer uses work.actual_pace_per_mile; legacy used work_summary.avg_work_pace_per_mile
    const workObj = parsedObj?.["work"] as Record<string, unknown> | null | undefined;
    const workSummary = parsedObj?.["work_summary"] as Record<string, unknown> | null | undefined;
    const workPace = (workObj && typeof workObj === "object"
        ? (workObj["actual_pace_per_mile"] as string | undefined)
        : undefined)
      ?? (workSummary && typeof workSummary === "object"
        ? (workSummary["avg_work_pace_per_mile"] as string | undefined)
        : undefined);

    // User-written notes — prefer workout_notes (structured) → cleaned_notes → notes.
    // These are the single most reliable source for WHAT the workout was.
    const userNotesRaw = (l.workout_notes as string)
      ?? (l.cleaned_notes as string)
      ?? (l.notes as string)
      ?? null;
    const userNotes = userNotesRaw && userNotesRaw.length > 0
      ? userNotesRaw.slice(0, 300)
      : null;

    return {
      date: (l.workout_date as string)?.split("T")[0] ?? "",
      type: parsedType ?? (l.workout_type as string) ?? "unknown",
      miles: Math.round(((l.workout_distance_miles as number) || 0) * 10) / 10,
      pace: (l.workout_pace_per_mile as string) ?? null,
      mood: (l.mood as string) ?? null,
      structure_pattern: parsedPattern ?? null,
      equivalent_race: parsedEq ? `${parsedEq["distance_key"]} @ ${parsedEq["pace_per_mile"]}/mi` : null,
      user_notes: userNotes,
      work_pace: workPace ?? null,
    };
  });

  // ── Training summary (compressed for prompts) ──
  const summaryParts: string[] = [];
  summaryParts.push(`${last7d.length} runs / ${Math.round(rolling7dMiles)} mi last 7d`);
  summaryParts.push(`${hardSessions7d} hard, ${easySessions7d} easy`);
  // WS3: ACWR is no longer surfaced — it's an internal injury-risk input only.
  // The load story is load_distribution.load_trend + hard/easy split + recovery.
  if (longestRun14d > 0) summaryParts.push(`longest run 14d: ${longestRun14d.toFixed(1)} mi`);
  if (checkIns[0]) summaryParts.push(`last check-in: ${checkIns[0].mood}`);
  if (injuries.length > 0) summaryParts.push(`${injuries.length} active injury(ies): ${injuries.map((i) => i.body_area).join(", ")}`);
  const recentTrainingSummary = summaryParts.join(" · ");

  // ── Scheduled workouts (need plan_id) ──
  let todayWorkout: Record<string, unknown> | null = null;
  let upcomingWorkouts: Array<Record<string, unknown>> = [];
  let weekCompliancePct: number | null = null;
  if (plan?.id) {
    const { data: scheduled, error: scheduledErr } = await supabase
      .from("scheduled_workouts")
      .select("date, workout_type, workout_data, status")
      .eq("plan_id", plan.id)
      .gte("date", today)
      .eq("status", "scheduled")
      .order("date", { ascending: true })
      .limit(6);
    if (scheduledErr) console.warn(`[AthleteState] scheduled_workouts read failed: ${scheduledErr.message}`);

    if (scheduled?.length) {
      const todayRow = scheduled.find((w: any) => w.date === today);
      if (todayRow) todayWorkout = todayRow;
      upcomingWorkouts = scheduled.filter((w: any) => w.date !== today).slice(0, 5);
    }

    // Week compliance (was hardcoded null in v1). The status column is
    // unreliable, so we match scheduled NON-REST days in the trailing 7d
    // against days the athlete actually trained (by date vs training_logs).
    const weekAgo = new Date(now.getTime() - 7 * 86400000).toISOString().slice(0, 10);
    const { data: weekScheduled, error: weekScheduledErr } = await supabase
      .from("scheduled_workouts")
      .select("date, workout_type")
      .eq("plan_id", plan.id)
      .gte("date", weekAgo)
      .lte("date", today);
    if (weekScheduledErr) console.warn(`[AthleteState] weekly scheduled_workouts read failed: ${weekScheduledErr.message}`);
    const planned = (weekScheduled ?? []).filter(
      (w: any) => String(w.workout_type ?? "").toLowerCase() !== "rest",
    );
    if (planned.length > 0) {
      const trainedDates = new Set(
        (logs as Array<Record<string, unknown>>)
          .map((l) => String(l.workout_date ?? "").slice(0, 10))
          .filter(Boolean),
      );
      const done = planned.filter((w: any) => trainedDates.has(String(w.date).slice(0, 10))).length;
      weekCompliancePct = Math.round((done / planned.length) * 100);
    }
  }

  // ── Possible-injury scan (body-part keywords in last 30 days of notes/memos) ──
  // Catches injuries BEFORE the user formally logs them in the injuries table.
  // Bias: prefer false positives (flag + ask) over false negatives (miss and
  // push volume into a brewing injury). Coach decides how to respond based on
  // severity hint.
  const bodyParts = [
    "achilles", "calf", "shin", "knee", "hamstring", "quad", "glute", "hip",
    "piriformis", "lower back", "back", "foot", "arch", "plantar", "heel",
    "ankle", "IT band", "itband", "it band", "hip flexor",
  ];
  const severityWords: Array<[RegExp, string]> = [
    [/\b(sharp|stabbing|burning|sudden)\b/i, "sharp"],
    [/\b(pain|hurts|hurting|injured|injury|strained|pulled|tear|torn)\b/i, "pain"],
    [/\b(sore|soreness|ache|aching|stiff|stiffness|nagging|niggle|bothering)\b/i, "sore"],
    [/\b(tight|tightness|tweak|tweaky|cranky)\b/i, "tight"],
  ];
  const thirtyDaysAgoISO = new Date(now.getTime() - 30 * 86400000).toISOString();
  const notesRows = logs.filter((l) => {
    const d = (l.workout_date as string) ?? "";
    return d >= thirtyDaysAgoISO;
  });

  const possibleInjuries: Array<{
    body_area: string; excerpt: string; date: string; severity_hint: string; volume_context: string | null;
  }> = [];
  // Parallel list shaped for the durable body_mentions table (Phase C).
  const detectedMentions: Array<Record<string, unknown>> = [];
  const alreadyFlagged = new Set<string>(); // dedupe by body_area + date

  for (const row of notesRows) {
    const text = [
      row.workout_notes as string | undefined,
      row.cleaned_notes as string | undefined,
      row.notes as string | undefined,
    ].filter(Boolean).join(" ").toLowerCase();
    if (!text) continue;

    for (const part of bodyParts) {
      const partRegex = new RegExp(`\\b${part.replace(/\s+/g, "\\s+")}\\b`, "i");
      if (!partRegex.test(text)) continue;

      // Require a severity word WITHIN 60 chars of the body-part mention.
      // Prevents false flags when "knee" shows up in unrelated context.
      const partMatch = text.match(partRegex);
      if (!partMatch) continue;
      const partIdx = text.indexOf(partMatch[0].toLowerCase());
      const windowStart = Math.max(0, partIdx - 60);
      const windowEnd = Math.min(text.length, partIdx + partMatch[0].length + 60);
      const nearbyText = text.slice(windowStart, windowEnd);

      let severityHint: string | null = null;
      for (const [re, label] of severityWords) {
        if (re.test(nearbyText)) { severityHint = label; break; }
      }
      // No severity word near body-part mention → not a flag. Benign reference
      // (e.g. "shin guards", "knee-high socks") — skip.
      if (!severityHint) continue;

      // Skip pure "sore from lifting" / "gym-sore legs" noise — cross-training soreness, not injury
      if (/\b(lifting|gym|weights|squats|deadlifts)\b/i.test(nearbyText) && severityHint === "sore") {
        continue;
      }
      const rowDate = (row.workout_date as string)?.slice(0, 10) ?? "";
      const key = `${part}__${rowDate}`;
      if (alreadyFlagged.has(key)) continue;
      alreadyFlagged.add(key);

      // Compute volume context: 2 weeks before this mention vs 2 weeks prior
      const mentionTime = new Date(row.workout_date as string).getTime();
      const twoWkBefore = mentionTime - 14 * 86400000;
      const fourWkBefore = mentionTime - 28 * 86400000;
      const milesInWindow = (from: number, to: number) =>
        workoutsWithMiles
          .filter((w) => {
            const t = new Date(w.workout_date as string).getTime();
            return t >= from && t < to;
          })
          .reduce((sum, w) => sum + ((w.workout_distance_miles as number) || 0), 0);
      const recentVol = milesInWindow(twoWkBefore, mentionTime);
      const priorVol = milesInWindow(fourWkBefore, twoWkBefore);
      let volCtx: string | null = null;
      if (priorVol > 5) {
        const delta = (recentVol - priorVol) / priorVol;
        if (delta >= 0.3) volCtx = `2wk volume +${Math.round(delta * 100)}% before mention (${Math.round(priorVol)} → ${Math.round(recentVol)}mi)`;
        else if (delta <= -0.3) volCtx = `2wk volume ${Math.round(delta * 100)}% (${Math.round(priorVol)} → ${Math.round(recentVol)}mi)`;
      }

      // Short excerpt around the body-part mention
      const idx = text.indexOf(part);
      const start = Math.max(0, idx - 40);
      const end = Math.min(text.length, idx + part.length + 60);
      const excerpt = text.slice(start, end).replace(/\n/g, " ").trim();

      possibleInjuries.push({
        body_area: part,
        excerpt: `...${excerpt}...`,
        date: rowDate,
        severity_hint: severityHint,
        volume_context: volCtx,
      });
      detectedMentions.push({
        user_id: userId,
        training_log_id: (row.id as string) ?? null,
        body_area: part,
        verbatim_quote: `...${excerpt}...`.slice(0, 400),
        severity_hint: severityHint,
        mentioned_at: rowDate,
        volume_context: volCtx,
        source: "notes_scan",
        updated_at: new Date().toISOString(),
      });
    }
  }
  // Sort by severity (sharp > pain > sore > tight) then date desc
  const sevOrder: Record<string, number> = { sharp: 4, pain: 3, sore: 2, tight: 1 };
  possibleInjuries.sort((a, b) =>
    (sevOrder[b.severity_hint] ?? 0) - (sevOrder[a.severity_hint] ?? 0)
    || b.date.localeCompare(a.date)
  );

  // ── v2 Phase C: persist mentions + read durable niggle recurrence ──
  // Upsert the freshly-detected mentions so niggles stop evaporating
  // between rebuilds. Under the service-role path (cron/trigger) this
  // persists; under the anon path it no-ops on RLS — same as the
  // athlete_state upsert itself. Either way we read history back below.
  if (detectedMentions.length > 0) {
    const { error: bmErr } = await supabase
      .from("body_mentions")
      .upsert(detectedMentions, { onConflict: "user_id,training_log_id,body_area" });
    if (bmErr) console.warn("[AthleteState] body_mentions upsert failed:", bmErr.message);
  }

  // Build the 12-month recurrence view from the stored table.
  const niggleRecurrence: AthleteState["niggle_recurrence"] = [];
  // Deduped mention dates (date|area) — feed per-block injury_mentions counts.
  // Union of the freshly-detected mentions (covers the anon path where the
  // body_mentions upsert no-ops on RLS) and the stored 12-month history.
  const niggleMentionKeys = new Set<string>();
  const niggleMentionDates: string[] = [];
  const addMentionDate = (rawDate: string, area: string) => {
    const d = String(rawDate ?? "").slice(0, 10);
    if (!d) return;
    const key = `${d}|${area}`;
    if (niggleMentionKeys.has(key)) return;
    niggleMentionKeys.add(key);
    niggleMentionDates.push(d);
  };
  for (const dm of detectedMentions) {
    addMentionDate(String(dm.mentioned_at ?? ""), String(dm.body_area ?? ""));
  }
  {
    const { data: bmHist, error: bmHistErr } = await supabase
      .from("body_mentions")
      .select("body_area, severity_hint, mentioned_at")
      .eq("user_id", userId)
      .gte("mentioned_at", twelveMonthsAgoISO.slice(0, 10))
      .order("mentioned_at", { ascending: false });
    if (bmHistErr) console.warn(`[AthleteState] body_mentions history read failed (niggle recurrence degraded): ${bmHistErr.message}`);
    const byArea = new Map<string, { count: number; first: string; last: string; worst: string }>();
    for (const m of (bmHist ?? []) as Array<Record<string, unknown>>) {
      const area = String(m.body_area);
      const at = String(m.mentioned_at).slice(0, 10);
      const sev = String(m.severity_hint ?? "");
      addMentionDate(at, area);
      const cur = byArea.get(area);
      if (!cur) {
        byArea.set(area, { count: 1, first: at, last: at, worst: sev });
      } else {
        cur.count++;
        if (at < cur.first) cur.first = at;
        if (at > cur.last) cur.last = at;
        if ((sevOrder[sev] ?? 0) > (sevOrder[cur.worst] ?? 0)) cur.worst = sev;
      }
    }
    for (const [area, v] of byArea.entries()) {
      niggleRecurrence.push({
        body_area: area,
        occurrences: v.count,
        first_seen: v.first,
        last_seen: v.last,
        worst_severity: v.worst,
      });
    }
    niggleRecurrence.sort((a, b) =>
      b.occurrences - a.occurrences || b.last_seen.localeCompare(a.last_seen)
    );
  }

  // ── Training blocks (6 × 4-week rollups) ──
  // (see _shared/builders/buildBlocks.ts)
  const recentBlocks: AthleteState["recent_blocks"] = buildBlocks({
    blockHistoryRows: (blockHistoryRes?.data ?? []) as Array<Record<string, unknown>>,
    niggleMentionDates,
    now,
  });

  // ── Latest check-in data ──
  const lastCheckIn = checkIns[0];
  const lastReadiness = lastCheckIn?.extracted_data?.readiness_score as number ?? null;

  // ── Biographical context ──
  // Fitness vs 6 months ago
  const snapshot6mo = ((snapshot6moRes.data ?? []) as Array<{predicted_10k_seconds: number}>)[0];
  const currentPred10k = (snapshot?.predicted_10k_seconds as number) || 0;
  const prior10k = snapshot6mo?.predicted_10k_seconds || 0;
  let fitnessVs6moSec: number | null = null;
  let fitnessVs6moLabel: string | null = null;
  if (currentPred10k > 0 && prior10k > 0) {
    fitnessVs6moSec = currentPred10k - prior10k;
    const absSec = Math.abs(fitnessVs6moSec);
    if (absSec < 15) fitnessVs6moLabel = "similar";
    else if (fitnessVs6moSec < -60) fitnessVs6moLabel = "much faster";
    else if (fitnessVs6moSec < 0) fitnessVs6moLabel = "faster";
    else if (fitnessVs6moSec > 60) fitnessVs6moLabel = "much slower";
    else fitnessVs6moLabel = "slower";
  }

  // Injury history summary — group by body_area, count recurrences
  const injuryHistory = (injuryHistoryRes.data ?? []) as Array<{
    body_area: string; status: string; first_reported_at: string; resolved_at: string | null;
  }>;
  const injuryByArea: Record<string, {
    body_area: string; first_at: string; last_at: string; occurrences: number; status: string;
  }> = {};
  for (const inj of injuryHistory) {
    const key = inj.body_area.toLowerCase();
    if (!injuryByArea[key]) {
      injuryByArea[key] = {
        body_area: inj.body_area,
        first_at: inj.first_reported_at,
        last_at: inj.first_reported_at,
        occurrences: 0,
        status: inj.status,
      };
    }
    injuryByArea[key].occurrences++;
    if (inj.first_reported_at > injuryByArea[key].last_at) {
      injuryByArea[key].last_at = inj.first_reported_at;
      injuryByArea[key].status = inj.status;
    }
    if (inj.first_reported_at < injuryByArea[key].first_at) {
      injuryByArea[key].first_at = inj.first_reported_at;
    }
  }
  const injuryHistorySummary = Object.values(injuryByArea).sort((a, b) => b.last_at.localeCompare(a.last_at));

  // ── Trajectory framing, phase, experience ──
  // (see _shared/builders/buildTrajectory.ts)
  const { framing: trajectoryFraming, reason: trajectoryReason } = buildTrajectory({
    rolling7dMiles,
    rolling28dMiles,
    hardSessions7d,
    fitnessTrend,
    activeInjuryCount: injuries.length,
    injuryHistory,
    plan: plan as { target_time_seconds?: number | null; end_date?: string | null } | null,
    now,
  });

  const derivedPhase = derivePhase({
    rolling7dMiles,
    hardSessions7d,
    weeklyAvg28d,
    profile: (profile as Record<string, unknown> | null) ?? null,
  });

  const derivedExperience = deriveExperience({
    profile: (profile as { experience_level?: unknown } | null) ?? null,
    weeklyAvg28d,
    easyPaceSec: paceZones.easy ?? 0,
  });

  // ── data_depth (UI register gate) ──
  // Count workouts + distinct training days from the deduped 28-day window.
  // active_goals (post-filter) is counted from raw goalsRes so depth=3 fires
  // even when the inline goal mapping in the state literal hasn't run yet.
  const distinctDays = new Set(
    workoutsWithMiles
      .map((l) => String(l.workout_date ?? "").slice(0, 10))
      .filter(Boolean)
  ).size;
  const activeGoalCount = ((goalsRes.data ?? []) as Array<{user_id: string | null; target_date: string}>)
    .filter((g) => g.user_id === userId)
    .filter((g) => g.target_date && new Date(g.target_date).getTime() >= now.getTime() - 30 * 86400000)
    .length;
  const dataDepth = computeDataDepth({
    workoutCount: workoutsWithMiles.length,
    uniqueDayCount: distinctDays,
    hasActiveGoal: activeGoalCount > 0,
  });

  // ── v2: Load distribution (volume × intensity, NOT ACWR) ──
  // (see _shared/builders/buildLoadDistribution.ts)
  const featureRows = (workoutFeaturesRes.data ?? []) as Array<Record<string, unknown>>;
  const num = (v: unknown): number | null => (v == null ? null : Number(v));
  const { loadDistribution, latestMonotony, latestStrain } = buildLoadDistribution({
    featureRows,
    sevenDaysAgo,
    twentyEightDaysAgo,
    now,
  });

  // ── v2: Fitness prediction as range + confidence (never a point) ──
  // range_*_seconds is a ± half-width band around the point prediction.
  const snap = snapshot as Record<string, unknown> | undefined;
  const confTier = ((snap?.confidence_tier as string) ?? (snap?.confidence as string) ?? "").toLowerCase();
  // WS4 — the snapshot's range_*_seconds bands are frequently null, which
  // collapsed every prediction to low==high==point (a false-precision point —
  // hard rule #7). When the stored band is missing, synthesize one as a
  // fraction of the predicted time, scaled by confidence (more evidence →
  // tighter band). A range is never a single time.
  const bandFractionFor = (tier: string): number => {
    if (tier.startsWith("high")) return 0.010;
    if (tier.startsWith("med")) return 0.020;
    if (tier.startsWith("low")) return 0.035;
    return 0.025;
  };
  const rangeOf = (predKey: string, bandKey: string) => {
    const pred = num(snap?.[predKey]);
    if (pred == null || !isFinite(pred) || pred <= 0) return null;
    let band = num(snap?.[bandKey]);
    if (band == null || !isFinite(band) || band <= 0) {
      band = Math.round(pred * bandFractionFor(confTier));
    }
    return { low: Math.round(pred - band), high: Math.round(pred + band), point: Math.round(pred) };
  };
  const fitnessPrediction = snap ? {
    confidence_tier: (snap.confidence_tier as string) ?? (snap.confidence as string) ?? null,
    workout_count: num(snap.workout_count),
    ranges: {
      mile: rangeOf("predicted_mile_seconds", "range_mile_seconds"),
      "5K": rangeOf("predicted_5k_seconds", "range_5k_seconds"),
      "10K": rangeOf("predicted_10k_seconds", "range_10k_seconds"),
      half: rangeOf("predicted_half_seconds", "range_half_seconds"),
      marathon: rangeOf("predicted_marathon_seconds", "range_marathon_seconds"),
    },
  } : null;

  // ── v2: Durable coach memory ──
  const nowMs = now.getTime();
  const memories = ((memoriesRes.data ?? []) as Array<{
    category: string; content: string; importance: number | null; expires_at: string | null;
  }>)
    .filter((m) => !m.expires_at || new Date(m.expires_at).getTime() > nowMs)
    .map((m) => ({
      category: m.category,
      content: String(m.content ?? "").slice(0, 300),
      importance: m.importance ?? 0,
    }));

  // ── v2 Phase B + fitness: ONE laps fetch feeding BOTH consumers ──
  // laps.workout_id == training_logs.id. Two consumers need laps:
  //   (1) execution + environment — the 28-day recent set (`logs`)
  //   (2) the objective fitness signal — the 84-day block-history set
  // These windows overlap heavily, so previously this module issued a recent
  // fetch here AND a second serial chunked fetch below — re-pulling rows the
  // first already had. Unified into a single wide-column fetch over the UNION
  // of ids, chunked and run in PARALLEL. A workout's laps live entirely within
  // one chunk (chunked by id), so per-workout lap_index order is preserved.
  const recentIds = (logs as Array<{ id: string }>).map((l) => l.id).filter(Boolean);

  // 84-day block logs drive the fitness signal's longitudinal window. Computed
  // up front so its ids join the single laps fetch below.
  const blockLogs84 = ((blockHistoryRes?.data ?? []) as Array<Record<string, unknown>>)
    .filter((l) => {
      const d = String(l.workout_date ?? "");
      return d && d >= eightyFourDaysAgo;
    });
  const blockMetaById = new Map<string, string>(); // id -> YYYY-MM-DD
  for (const l of blockLogs84) {
    blockMetaById.set(String(l.id), String(l.workout_date ?? "").slice(0, 10));
  }

  // Union of ids (recent ∪ 84-day). Recent isn't strictly a subset — the recent
  // query admits 0-distance rows the block query filters out — so union, dedup.
  const lapsWorkoutIds = [...new Set([...recentIds, ...blockMetaById.keys()])];

  const lapsFetchStart = Date.now();
  const lapsByWorkout = new Map<string, Array<Record<string, unknown>>>();
  if (lapsWorkoutIds.length > 0) {
    const LAPS_CHUNK = 200;
    const chunks: string[][] = [];
    for (let i = 0; i < lapsWorkoutIds.length; i += LAPS_CHUNK) {
      chunks.push(lapsWorkoutIds.slice(i, i + LAPS_CHUNK));
    }
    const results = await Promise.all(chunks.map((chunk) =>
      supabase
        .from("running_workout_laps")
        .select("workout_id, lap_index, distance_meters, avg_pace_sec_per_mile, heat_adjusted_pace_sec_per_mile, avg_heart_rate, is_rest, moving_time_seconds, elapsed_time_seconds, temp_f, dew_point_f, heat_category, heat_adjustment_pct, total_elevation_gain")
        .eq("user_id", userId)
        .in("workout_id", chunk)
        .order("lap_index", { ascending: true })
    ));
    for (const { data: lapsData, error: lapsErr } of results) {
      if (lapsErr) console.warn(`[AthleteState] running_workout_laps chunk read failed (execution/environment/fitness degraded): ${lapsErr.message}`);
      for (const lap of (lapsData ?? []) as Array<Record<string, unknown>>) {
        const wid = String(lap.workout_id);
        const arr = lapsByWorkout.get(wid) ?? [];
        arr.push(lap);
        lapsByWorkout.set(wid, arr);
      }
    }
  }
  const lapsFetchMs = Date.now() - lapsFetchStart;

  const logMetaById = new Map<string, { date: string; type: string | null }>();
  for (const l of logs as Array<Record<string, unknown>>) {
    logMetaById.set(String(l.id), {
      date: String(l.workout_date ?? "").slice(0, 10),
      type: (l.workout_type as string) ?? null,
    });
  }

  const fmtPaceSec = (sec: number): string | null => {
    if (!isFinite(sec) || sec <= 0) return null;
    const t = Math.round(sec);
    return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`;
  };

  const environment: AthleteState["environment"] = [];
  const execution: AthleteState["execution"] = [];

  // WS1: classify execution via the shared segmentation module (same module
  // compute-workout-features uses — single source of truth for rep detection).
  const execZones: PaceZones = {
    mile: paceZones.mile, fiveK: paceZones.fiveK, tenK: paceZones.tenK,
    hm: paceZones.hm, mp: paceZones.mp, steady: paceZones.steady,
    moderate: paceZones.moderate, easy: paceZones.easy,
  };

  const workoutEntries = Array.from(lapsByWorkout.entries())
    .map(([wid, laps]) => ({ wid, laps, meta: logMetaById.get(wid) }))
    .filter((e) => e.meta != null)
    .sort((a, b) => String(b.meta!.date).localeCompare(String(a.meta!.date)));

  for (const { laps, meta } of workoutEntries) {
    let distSum = 0, paceWeighted = 0, adjWeighted = 0, elevSum = 0;
    let tempSum = 0, tempN = 0, dewSum = 0, dewN = 0, adjPctSum = 0, adjPctN = 0;
    const catCounts: Record<string, number> = {};
    for (const lap of laps) {
      const dist = Number(lap.distance_meters ?? 0);
      const pace = Number(lap.avg_pace_sec_per_mile ?? 0);
      const adj = Number(lap.heat_adjusted_pace_sec_per_mile ?? 0);
      if (dist > 0 && pace > 0) {
        distSum += dist;
        paceWeighted += pace * dist;
        if (adj > 0) adjWeighted += adj * dist;
      }
      elevSum += Number(lap.total_elevation_gain ?? 0);
      if (lap.temp_f != null) { tempSum += Number(lap.temp_f); tempN++; }
      if (lap.dew_point_f != null) { dewSum += Number(lap.dew_point_f); dewN++; }
      if (lap.heat_adjustment_pct != null) { adjPctSum += Number(lap.heat_adjustment_pct); adjPctN++; }
      const cat = lap.heat_category as string | null;
      if (cat) catCounts[cat] = (catCounts[cat] ?? 0) + 1;
    }
    const dominantCat = Object.entries(catCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;

    if (environment.length < 10 && distSum > 0) {
      environment.push({
        date: meta!.date,
        temp_f: tempN > 0 ? Math.round(tempSum / tempN) : null,
        dew_point_f: dewN > 0 ? Math.round(dewSum / dewN) : null,
        heat_category: dominantCat,
        // laps store heat_adjustment_pct as a FRACTION (0.019 = 1.9%); ×100 to
        // the percent the field name and the Read display imply. Without this
        // the value rounded to 0.0 and the "hot runs" list was always empty. WS2.
        heat_adjustment_pct: adjPctN > 0 ? Math.round((adjPctSum / adjPctN) * 1000) / 10 : null,
        actual_pace: fmtPaceSec(paceWeighted / distSum),
        heat_adjusted_pace: adjWeighted > 0 ? fmtPaceSec(adjWeighted / distSum) : null,
        elevation_gain_ft: elevSum > 0 ? Math.round(elevSum * 3.28084) : null,
      });
    }

    // Execution — classify structured sessions via the shared module. Reps,
    // fade, CV, HR drift, shape, and the structure string all come from one
    // place; the float-lap and pace-vs-zone handling lives in the module.
    if (execution.length < 4) {
      const seg = segmentFromLaps(laps as unknown as LapInput[], execZones);
      if (seg.reps.length >= 2) {
        execution.push({
          date: meta!.date,
          type: meta!.type ?? seg.workoutKind,
          rep_count: seg.repCount,
          rep_paces: seg.repPaces,
          fade_pct: seg.fadePct,
          pace_cv_pct: seg.paceCvPct,
          hr_drift_pct: seg.hrDriftPct,
          shape: seg.shape ?? "even",
          structure: seg.structure,
        });
      }
    }
  }

  // ── Objective fitness signal — pace-at-HR efficiency trend (WS-fitness) ──
  // The Read's fitness verdict wants "same pace, HR direction over weeks."
  // Reuses the SINGLE laps fetch above (the union covers the 84-day window),
  // selecting the longitudinal set via the 84-day `blockMetaById`. Best-effort:
  // any failure leaves the signal null (the Read degrades to its other inputs).
  let fitnessSignal: FitnessSignal | null = null;
  try {
    const fitnessSessions: FitnessSessionInput[] = [];
    for (const [wid, laps] of lapsByWorkout) {
      const date = blockMetaById.get(wid);
      if (date) fitnessSessions.push({ date, laps: laps as unknown as LapInput[] });
    }
    if (fitnessSessions.length > 0) {
      fitnessSignal = computeFitnessSignal(fitnessSessions, execZones, now);
    }
  } catch (err) {
    console.warn("[AthleteState] fitness-signal computation failed:", err);
  }

  // ── v2 Phase D: pattern layer (the coach's edge — noticing, not just
  //    reporting). Each rule is a pure function over data already joined
  //    above, emitting a plain-language statement + the numbers behind it.
  //    The LLM narrates; the math stays here (Coach voice: "never explains
  //    math"; hard rule #2). ──
  const patterns: AthleteState["patterns"] = [];

  // 1. Pacing discipline — fade tendency across quality sessions.
  const fadeVals = execution
    .map((e) => e.fade_pct)
    .filter((f): f is number => f != null);
  if (fadeVals.length >= 2) {
    const faded = fadeVals.filter((f) => f > 1.5).length;
    const negative = fadeVals.filter((f) => f < -1).length;
    const avgFade = Math.round((fadeVals.reduce((s, f) => s + f, 0) / fadeVals.length) * 10) / 10;
    if (faded >= Math.ceil(fadeVals.length * 0.6)) {
      patterns.push({
        kind: "pacing_fade",
        statement: "You tend to go out too hot — most quality sessions slow through the reps.",
        evidence: `${faded} of ${fadeVals.length} sessions faded (avg ${avgFade > 0 ? "+" : ""}${avgFade}%)`,
        confidence: fadeVals.length >= 3 ? "medium" : "low",
      });
    } else if (negative >= Math.ceil(fadeVals.length * 0.6)) {
      patterns.push({
        kind: "pacing_control",
        statement: "Strong pacing control — you've been negative-splitting your quality work.",
        evidence: `${negative} of ${fadeVals.length} sessions got faster through the reps`,
        confidence: fadeVals.length >= 3 ? "medium" : "low",
      });
    }
  }

  // 2. Niggle ↔ volume spike — body mentions that followed a volume jump.
  const spikeMentions = possibleInjuries.filter(
    (p) => p.volume_context && /\+\d+%/.test(p.volume_context)
  );
  if (spikeMentions.length >= 1) {
    const areas = [...new Set(spikeMentions.map((p) => p.body_area))];
    patterns.push({
      kind: "niggle_load",
      statement: `${areas.join(" and ")} ${areas.length > 1 ? "tend" : "tends"} to flag right after volume jumps.`,
      evidence: spikeMentions.slice(0, 2).map((p) => `${p.body_area} ${p.date} (${p.volume_context})`).join("; "),
      confidence: spikeMentions.length >= 2 ? "medium" : "low",
    });
  }

  // 3. Personal heat sensitivity — how much hot days actually cost this athlete.
  const hotAdj = environment
    .map((e) => e.heat_adjustment_pct)
    .filter((x): x is number => x != null && x >= 3);
  if (hotAdj.length >= 2) {
    const avgAdj = Math.round((hotAdj.reduce((s, x) => s + x, 0) / hotAdj.length) * 10) / 10;
    patterns.push({
      kind: "heat_sensitivity",
      statement: "Heat costs you real pace — on warm days your effort reads slower than your fitness.",
      evidence: `${hotAdj.length} hot runs averaged ${avgAdj}% heat slowdown`,
      confidence: "medium",
    });
  }

  // 4. Easy-day discipline — is the easy volume actually easy?
  if (loadDistribution) {
    const easyPct = loadDistribution.zone_pct_7d.easy;
    const totalMin = loadDistribution.minutes_7d.easy + loadDistribution.minutes_7d.moderate +
      loadDistribution.minutes_7d.threshold + loadDistribution.minutes_7d.hard;
    if (easyPct < 65 && totalMin > 90) {
      patterns.push({
        kind: "easy_discipline",
        statement: "Your easy days are creeping fast — not enough of the week is truly easy.",
        evidence: `only ${easyPct}% of the last 7d was easy-zone time`,
        confidence: "low",
      });
    }
  }

  // 5. Easy-pace creep — block-over-block easy pace at (proxy) stable effort.
  if (recentBlocks.length >= 2) {
    const cur = recentBlocks[0].avg_easy_pace_sec;
    const prev = recentBlocks[1].avg_easy_pace_sec;
    if (cur != null && prev != null && prev > 0) {
      const deltaSec = Math.round(prev - cur); // + = faster now
      if (Math.abs(deltaSec) >= 8) {
        patterns.push({
          kind: "easy_pace_trend",
          statement: deltaSec > 0
            ? "Your easy runs are getting faster block-over-block — aerobic base is taking."
            : "Your easy pace has drifted slower this block — worth watching against how you feel.",
          evidence: `easy pace ${deltaSec > 0 ? "−" : "+"}${Math.abs(deltaSec)}s/mi vs last block`,
          confidence: "low",
        });
      }
    }
  }

  // 6. Down-week response — execution quality the block after a volume drop.
  if (recentBlocks.length >= 2) {
    const curVol = recentBlocks[0].weekly_avg_miles;
    const prevVol = recentBlocks[1].weekly_avg_miles;
    if (prevVol > 0 && curVol / prevVol <= 0.8 && fadeVals.length >= 1) {
      const cleanReps = fadeVals.filter((f) => f <= 1.5).length;
      if (cleanReps >= Math.ceil(fadeVals.length * 0.6)) {
        patterns.push({
          kind: "down_week_response",
          statement: "You absorb down weeks well — quality held up after the volume came off.",
          evidence: `volume −${Math.round((1 - curVol / prevVol) * 100)}% vs last block, ${cleanReps}/${fadeVals.length} sessions held pace`,
          confidence: "low",
        });
      }
    }
  }

  // ── Rec #5: computed blind spots — grounds the Read's cant_see block ──
  const dataGaps: AthleteState["data_gaps"] = [];

  // No recent mood signal (no mood on recent runs AND no recent check-in).
  const hasRecentMood = recentWorkouts.some((w) => w.mood) ||
    (lastCheckIn?.created_at != null &&
      new Date(lastCheckIn.created_at as string).getTime() > now.getTime() - 10 * 86400000);
  if (!hasRecentMood && last7d.length > 0) {
    dataGaps.push({ gap: "NO RECENT MOOD", detail: "Haven't heard how you're feeling in over a week." });
  }

  // No lap data on recent runs → no execution / heat read possible.
  if (recentWorkouts.length > 0 && execution.length === 0 && environment.length === 0) {
    dataGaps.push({
      gap: "NO SPLIT DATA",
      detail: "No lap data on recent runs — can't read splits, HR drift, or heat impact.",
    });
  }

  // Thin or absent fitness estimate.
  if (!fitnessPrediction || String(fitnessPrediction.confidence_tier ?? "").toLowerCase() === "low") {
    dataGaps.push({ gap: "THIN FITNESS ESTIMATE", detail: "The fitness prediction is on light evidence." });
  }

  // A niggle on a single data point — not a pattern yet.
  const onePointNiggle = niggleRecurrence.find((n) => n.occurrences === 1);
  if (onePointNiggle && possibleInjuries.length > 0) {
    dataGaps.push({
      gap: "ONE DATA POINT",
      detail: `${onePointNiggle.body_area} has come up once — not enough to call a pattern.`,
    });
  }

  // ── Build the state ──
  const state: AthleteState = {
    user_id: userId,
    experience_level: derivedExperience,
    current_phase: derivedPhase,
    active_plan_id: plan?.id ?? null,
    goal_race: plan ? `${plan.target_race_distance} plan` : null,
    goal_time_seconds: plan?.target_time_seconds ?? null,

    // ACWR retained for one release but no longer surfaced to the Read —
    // load is now read from load_distribution (volume × intensity).
    acwr: acwr ? Math.round(acwr * 100) / 100 : null,
    monotony_7d: latestMonotony,
    strain_7d: latestStrain,
    rolling_7d_miles: Math.round(rolling7dMiles * 10) / 10,
    rolling_28d_miles: Math.round(rolling28dMiles * 10) / 10,
    weekly_avg_miles: Math.round(weeklyAvg28d * 10) / 10,
    hard_sessions_7d: hardSessions7d,
    easy_sessions_7d: easySessions7d,
    // Use session count (deduped warmup/cool-down uploads), not raw upload count
    runs_last_7d: runsLast7d,
    longest_run_14d: longestRun14d > 0 ? Math.round(longestRun14d * 10) / 10 : null,

    predicted_5k_seconds: (snapshot?.predicted_5k_seconds as number) ?? null,
    predicted_10k_seconds: (snapshot?.predicted_10k_seconds as number) ?? null,
    predicted_half_seconds: (snapshot?.predicted_half_seconds as number) ?? null,
    predicted_marathon_seconds: (snapshot?.predicted_marathon_seconds as number) ?? null,
    fitness_trend: fitnessTrend,
    fitness_snapshot_id: (snapshot?.id as string) ?? null,
    fitness_snapshot_at: (snapshot?.created_at as string) ?? null,

    last_mood: lastCheckIn?.mood ?? null,
    last_readiness_score: lastReadiness,
    mood_trend: moodTrend,
    last_check_in_at: lastCheckIn?.created_at ?? null,

    active_injuries: injuries,
    injury_risk_score: null, // set by injury-early-warning
    injury_risk_signals: [],
    possible_injuries: possibleInjuries,
    niggle_recurrence: niggleRecurrence,

    pace_zones: paceZones,
    pace_zone_ranges: paceZoneRanges,

    recent_training_summary: recentTrainingSummary,
    recent_workouts: recentWorkouts,

    today_workout: todayWorkout,
    upcoming_workouts: upcomingWorkouts,
    week_compliance_pct: weekCompliancePct,

    // ── Biographical fields ──
    fitness_vs_6mo_ago_seconds: fitnessVs6moSec,
    fitness_vs_6mo_ago_label: fitnessVs6moLabel,
    injury_history_summary: injuryHistorySummary,
    trajectory_framing: trajectoryFraming,
    trajectory_reason: trajectoryReason,
    // Show future goals + recently-past goals (≤ 30 days) so coach can reference
    // goal pace and gap even if target date just slipped.
    active_goals: ((goalsRes.data ?? []) as Array<{goal_title: string; target_date: string; user_id: string | null}>)
      // Redundant defense: the query is already .eq('user_id', userId), but
      // drop anything without a real match client-side too.
      .filter((g) => g.user_id === userId)
      .filter((g) => g.target_date && new Date(g.target_date).getTime() >= now.getTime() - 30 * 86400000)
      .map((g) => {
        // Parse distance + target time from goal title
        // Examples: "sub 15 5k", "sub-3 marathon", "break 1:30 half", "4:50 mile"
        const titleLower = g.goal_title.toLowerCase();
        const distancePatterns: Array<[RegExp, string, number]> = [
          [/\bmarathon\b/i, "marathon", 26.2188],
          [/\bhalf\s*marathon\b|\bhalf\b|\bhm\b/i, "half", 13.1094],
          [/\b10\s*k\b/i, "10K", 6.2137],
          [/\b5\s*k\b/i, "5K", 3.1069],
          [/\bmile\b/i, "mile", 1.0],
        ];
        let distKey: string | null = null;
        let distMi = 0;
        for (const [re, key, mi] of distancePatterns) {
          if (re.test(titleLower)) { distKey = key; distMi = mi; break; }
        }

        // Parse time: "sub 15", "break 3:00", "1:30", "sub-1:30", "sub 3"
        let targetSec: number | null = null;
        const timeMatch = g.goal_title.match(/(?:sub[-\s]*|break[-\s]*|under[-\s]*)?(\d{1,2}):(\d{2})(?::(\d{2}))?|sub[-\s]*(\d{1,3})(?:\s*min)?/i);
        if (timeMatch) {
          if (timeMatch[1] && timeMatch[2]) {
            const h = timeMatch[3] ? parseInt(timeMatch[1]) : 0;
            const m = timeMatch[3] ? parseInt(timeMatch[2]) : parseInt(timeMatch[1]);
            const s = timeMatch[3] ? parseInt(timeMatch[3]) : parseInt(timeMatch[2]);
            targetSec = h * 3600 + m * 60 + s;
          } else if (timeMatch[4]) {
            // "sub 15" bare number — interpret as minutes if distance is 5K/mile, as hours otherwise
            const n = parseInt(timeMatch[4]);
            targetSec = distMi > 10 ? n * 3600 : n * 60;
          }
        }
        // Sanity: pace must be between 3:00-15:00/mi
        let targetPaceSec: number | null = null;
        if (targetSec && distMi > 0) {
          const pace = targetSec / distMi;
          if (pace >= 180 && pace <= 900) targetPaceSec = pace;
        }
        const targetPacePerMile = targetPaceSec
          ? `${Math.floor(targetPaceSec / 60)}:${String(Math.round(targetPaceSec % 60)).padStart(2, "0")}`
          : null;

        // Gap vs current predicted pace at that distance
        let gap: number | null = null;
        if (targetPaceSec && distKey) {
          const predKey = distKey === "5K" ? "predicted_5k_seconds"
            : distKey === "10K" ? "predicted_10k_seconds"
            : distKey === "half" ? "predicted_half_seconds"
            : distKey === "marathon" ? "predicted_marathon_seconds"
            : null;
          if (predKey) {
            const predTotal = (snapshot as Record<string, unknown> | undefined)?.[predKey] as number;
            if (predTotal && distMi > 0) {
              const currentPace = predTotal / distMi;
              gap = Math.round(currentPace - targetPaceSec);
            }
          }
        }

        return {
          title: g.goal_title,
          target_date: g.target_date,
          days_until: Math.round((new Date(g.target_date).getTime() - now.getTime()) / 86400000),
          target_distance_key: distKey,
          target_time_seconds: targetSec,
          target_pace_per_mile: targetPacePerMile,
          gap_vs_current_sec_per_mile: gap,
        };
      }),
    recent_blocks: recentBlocks,
    // Confirmed races — user-declared via training_logs.race_result.
    // The query in the Promise.all above pulls the 2-year window of
    // race-tagged training_logs; here we project to the AthleteState
    // confirmed_races shape. Defensive: drop rows with malformed
    // race_result (missing finish_time_seconds or distance) so a
    // partially-filled race entry can't crash downstream consumers.
    // Phase 2 sub-task A.
    confirmed_races: ((confirmedRacesRes.data ?? []) as Array<{
      workout_date: string;
      race_result: {
        distance?: string;
        finish_time_seconds?: number;
        official?: boolean;
        event_name?: string | null;
      } | null;
    }>)
      .filter((row) =>
        row.race_result &&
        typeof row.race_result.distance === "string" &&
        typeof row.race_result.finish_time_seconds === "number"
      )
      .map((row) => ({
        date: row.workout_date,
        distance: row.race_result!.distance as string,
        finish_time_seconds: row.race_result!.finish_time_seconds as number,
        official: row.race_result!.official ?? true,
        event_name: row.race_result!.event_name ?? null,
      })),

    data_depth: dataDepth,

    // ── v2 satellites ──
    load_distribution: loadDistribution,
    fitness_prediction: fitnessPrediction,
    memories: memories,
    environment: environment,
    execution: execution,
    fitness_signal: fitnessSignal,
    patterns: patterns,
    data_gaps: dataGaps,

    last_updated_at: new Date().toISOString(),
    last_updated_by: "rebuild",
    version: ATHLETE_STATE_SCHEMA_VERSION,
  };

  // Upsert the state. Clear rebuild_started_at so the next claimer sees
  // an idle row. The column isn't part of AthleteState so we null it in a
  // follow-up update rather than widening the type.
  const { error: upsertErr } = await supabase
    .from("athlete_state")
    .upsert(state, { onConflict: "user_id" });
  if (upsertErr) {
    // A failed persist means this rebuild's work is lost — the next caller
    // re-runs it. Loud, because it directly causes stale/empty served state.
    console.error(`[AthleteState] state upsert FAILED (rebuild not persisted): ${upsertErr.message}`);
  }
  const { error: clearErr } = await supabase
    .from("athlete_state")
    .update({ rebuild_started_at: null })
    .eq("user_id", userId);
  if (clearErr) {
    // Leaves rebuild_started_at stamped → the claim RPC may block the next
    // rebuild until its staleness window elapses. Worth knowing.
    console.warn(`[AthleteState] clearing rebuild_started_at failed: ${clearErr.message}`);
  }

  // Timing instrumentation — read these off logs to compute p50/p95 in prod.
  // `laps_fetch` is the unified parallel laps query (Fix 2); a high share of
  // total here flags the laps path as the cold-rebuild bottleneck.
  const rebuildMs = Date.now() - rebuildStartMs;
  console.log(
    `[AthleteState] rebuild user=${userId} total=${rebuildMs}ms ` +
    `laps_fetch=${lapsFetchMs}ms laps_workouts=${lapsByWorkout.size} ` +
    `logs=${logs.length} block_logs_84d=${blockLogs84.length}`,
  );

  return state;
}

// ── Prompt Helper ────────────────────────────────────────

// Heuristic token estimate: ~4 chars/token. We prune WHOLE sections, not
// words, so ±10% precision doesn't change which sections survive — a tokenizer
// dependency isn't worth it in the edge runtime.
const APPROX_CHARS_PER_TOKEN = 4;

// The design's stated envelope (athlete-state-refactor-design.md §4 R11).
// Currently a SOFT target: when the rendered prompt exceeds it we log, so we
// can read real token distributions off prod before choosing an enforced cap.
const PROMPT_SOFT_TARGET_TOKENS = 420;

/** Heuristic token count for a string (~4 chars/token). */
export function approxTokenCount(s: string): number {
  return Math.ceil(s.length / APPROX_CHARS_PER_TOKEN);
}

/**
 * A render section: a priority (LOWER number = kept first / more important) and
 * its already-rendered lines. Sections render in declaration order (so output
 * is stable and, under no pruning, byte-identical to the pre-budget version),
 * but are DROPPED in descending priority-number order when over budget.
 * Priority 1 sections are never dropped (identity, pace zones, injuries —
 * correctness- and safety-critical).
 */
interface PromptSection {
  key: string;
  priority: number;
  lines: string[];
}

function assemblePromptSections(
  header: string,
  sections: PromptSection[],
  budget: number,
): { text: string; tokens: number; dropped: string[] } {
  let kept = sections.filter((s) => s.lines.length > 0);
  const dropped: string[] = [];
  const render = (ss: PromptSection[]) =>
    [header, ...ss.flatMap((s) => s.lines)].join("\n");

  while (approxTokenCount(render(kept)) > budget) {
    // Drop the LAST section in the highest priority-number tier (later/least
    // important within a tier goes first). Priority-1 sections are protected.
    let victimIdx = -1;
    let victimPriority = -Infinity;
    for (let i = 0; i < kept.length; i++) {
      if (kept[i].priority <= 1) continue;
      if (kept[i].priority >= victimPriority) {
        victimPriority = kept[i].priority;
        victimIdx = i;
      }
    }
    if (victimIdx === -1) break; // only priority-1 sections remain — stop
    dropped.push(kept[victimIdx].key);
    kept = kept.filter((_, i) => i !== victimIdx);
  }

  const text = render(kept);
  return { text, tokens: approxTokenCount(text), dropped };
}

/**
 * Compress the athlete state into a concise context block for AI prompts.
 *
 * Sections are priority-ranked and assembled under a token budget (Fix 1 of
 * outputs/athlete-state-review-2026-06-18.md). The default budget is `Infinity`
 * — i.e. NO pruning, so production output is byte-identical to the pre-budget
 * version until a finite cap is chosen from measured token data. The rendered
 * size is logged whenever it exceeds the soft target.
 *
 * @param opts.budget hard token cap; sections drop (lowest priority first,
 *   never priority-1) until under it. Defaults to Infinity (log-only).
 */
export function stateToPromptContext(
  state: AthleteState,
  opts: { budget?: number } = {},
): string {
  const sections: PromptSection[] = [];
  // Collect a section's lines via the same `lines.push(...)` calls as before —
  // the closure param is named `lines`, so each block's body is unchanged.
  const section = (
    key: string,
    priority: number,
    build: (lines: string[]) => void,
  ) => {
    const lines: string[] = [];
    build(lines);
    if (lines.length > 0) sections.push({ key, priority, lines });
  };

  // Identity (P1 — never drop)
  section("identity", 1, (lines) => {
    if (state.experience_level) lines.push(`Level: ${state.experience_level}`);
    if (state.current_phase) lines.push(`Phase: ${state.current_phase}`);
  });

  // ── GOALS (what they're training for) ──
  // Plan-based goal first, then user-declared goals with countdown.
  section("goals", 2, (lines) => {
    if (state.goal_race) lines.push(`Plan goal: ${state.goal_race}${state.goal_time_seconds ? ` in ${formatTime(state.goal_time_seconds)}` : ""}`);
    if (state.active_goals && state.active_goals.length > 0) {
      lines.push("Active goals:");
      for (const g of state.active_goals) {
        const when = g.days_until <= 0 ? "past due"
          : g.days_until < 14 ? `in ${g.days_until} days ⚠`
          : g.days_until < 60 ? `in ${g.days_until} days`
          : `in ${Math.round(g.days_until / 7)} weeks`;
        const paceLine = g.target_pace_per_mile
          ? ` → ${g.target_distance_key} @ ${g.target_pace_per_mile}/mi`
          : "";
        lines.push(`  • "${g.title}" — ${when} (${g.target_date.slice(0, 10)})${paceLine}`);
        if (g.gap_vs_current_sec_per_mile != null) {
          const gap = g.gap_vs_current_sec_per_mile;
          if (Math.abs(gap) < 3) {
            lines.push(`    ✓ on target (current predicted pace essentially matches goal)`);
          } else {
            lines.push(`    Current predicted pace is ${formatTimeDelta(gap)}/mi than goal`);
          }
        }
      }
    }
  });

  // Load — volume × intensity distribution (NOT ACWR). Same shape the
  // athlete sees in PaceVolumeSpectrumChart.
  section("load", 2, (lines) => {
    lines.push(`\nTraining Load (7d): ${state.rolling_7d_miles ?? 0} mi, ${state.runs_last_7d} runs (${state.hard_sessions_7d} hard, ${state.easy_sessions_7d} easy)`);
    lines.push(`28d avg: ${state.weekly_avg_miles ?? 0} mpw`);
    const ld = state.load_distribution;
    if (ld) {
      const p = ld.zone_pct_7d;
      // WS3 — lead with the plain-language load STORY (the ACWR-ratio replacement):
      // trend vs the 8-week norm, then the hard/easy split, then the recovery read.
      if (ld.load_trend) {
        const trendWord = ld.load_trend === "backing_off" ? "backing off" : ld.load_trend;
        const vs = ld.load_vs_chronic_pct != null
          ? ` (${ld.load_vs_chronic_pct >= 0 ? "+" : ""}${ld.load_vs_chronic_pct}% vs the prior 8-week norm)`
          : "";
        lines.push(`Load trend: ${trendWord}${vs} — intensity-weighted, last 2 weeks vs the 8-week baseline.`);
      }
      // The single pace-weighted load number — volume scaled by intensity.
      lines.push(`Volume × Intensity load (7d): ${ld.volume_x_intensity_7d} weighted-min · 28d: ${ld.volume_x_intensity_28d} (a hard mile ≈ 5× an easy mile)`);
      lines.push(
        `Hard/easy split (7d): easy ${p.easy}% · moderate ${p.moderate}% · threshold ${p.threshold}% · hard ${p.hard}%` +
        (ld.effort_distribution ? ` (${ld.effort_distribution})` : "") +
        ` — ~80% easy is the guide.`
      );
      if (ld.recovery_read) {
        const rr = ld.recovery_read;
        const spacing = rr.avg_days_between_hard != null
          ? `hard days ~${rr.avg_days_between_hard}d apart`
          : `${rr.hard_sessions_28d} hard session${rr.hard_sessions_28d === 1 ? "" : "s"} in 28d`;
        lines.push(`Recovery: ${spacing}${rr.down_week ? " · this is a down week (load well below norm)" : ""}.`);
      }
      if (ld.monotony_7d != null) {
        lines.push(`Monotony (7d): ${ld.monotony_7d.toFixed(2)}${ld.strain_7d != null ? ` · strain ${Math.round(ld.strain_7d)}` : ""}`);
      }
    }
    if (state.longest_run_14d) lines.push(`Longest run (14d): ${state.longest_run_14d} mi`);
  });

  // Fitness + Predicted Race Times — ranges + confidence, never a single
  // time (hard rule #7).
  section("predicted", 2, (lines) => {
    const fp = state.fitness_prediction;
    if (fp && fp.ranges) {
      lines.push(`\nPredicted race times (quote the RANGE, never a single time):`);
      const emit = (label: string, key: string) => {
        const r = fp.ranges[key];
        if (r) lines.push(`  ${label}: ${formatTime(r.low)}–${formatTime(r.high)}`);
      };
      emit("5K", "5K");
      emit("10K", "10K");
      emit("Half Marathon", "half");
      emit("Marathon", "marathon");
      if (fp.confidence_tier) {
        // Cite the evidence behind the confidence: workout count + a recent race
        // anchor if one exists (race anchors beat goal time — hard rule #7 / WS4).
        const recentRace = (state.confirmed_races ?? [])
          .filter((r) => r.date && (Date.now() - new Date(r.date).getTime()) <= 180 * 86400000)
          .sort((a, b) => b.date.localeCompare(a.date))[0];
        const evidence = [
          fp.workout_count ? `${fp.workout_count} workouts` : null,
          recentRace ? `recent ${recentRace.distance}` : null,
        ].filter(Boolean).join(" + ");
        lines.push(`  Confidence: ${fp.confidence_tier}${evidence ? ` (${evidence})` : ""}`);
      }
      if (state.fitness_trend) lines.push(`Fitness trend: ${state.fitness_trend}`);
    } else if (state.predicted_marathon_seconds) {
      // Fallback only when no range bands exist yet.
      lines.push(`\nPredicted race times (approximate — no confidence band yet):`);
      if (state.predicted_5k_seconds) lines.push(`  5K: ~${formatTime(state.predicted_5k_seconds)}`);
      if (state.predicted_10k_seconds) lines.push(`  10K: ~${formatTime(state.predicted_10k_seconds)}`);
      if (state.predicted_half_seconds) lines.push(`  Half Marathon: ~${formatTime(state.predicted_half_seconds)}`);
      lines.push(`  Marathon: ~${formatTime(state.predicted_marathon_seconds)}`);
      if (state.fitness_trend) lines.push(`Fitness trend: ${state.fitness_trend}`);
    }
  });

  // Fitness signal (objective) — pace-at-HR efficiency trend. The Read's
  // FITNESS section pairs this with the predicted ranges and how training has
  // felt. It's a DIRECTION over a real window with a confidence — narrate it,
  // don't recompute it. "Same pace, HR trending down = fitter."
  section("fitness_signal", 4, (lines) => {
    const fs = state.fitness_signal;
    if (fs && (fs.efficiency.length > 0 || fs.verdict)) {
      lines.push(`\nFitness signal (objective — same effort, HR/pace direction over ~12 weeks; narrate, don't recompute):`);
      if (fs.verdict) lines.push(`  ${fs.verdict}`);
      const bucketName: Record<string, string> = {
        easy: "Easy runs",
        threshold: "Threshold (LT)",
        interval: "Intervals (VO2)",
      };
      for (const e of fs.efficiency) {
        const weeks = Math.max(1, Math.round(e.baseline_days / 7));
        const arrow = e.direction === "improving" ? "↑ fitter"
          : e.direction === "declining" ? "↓ slipping" : "→ holding";
        lines.push(
          `  ${bucketName[e.bucket] ?? e.bucket}: ${formatPace(e.pace_baseline_sec)}/mi @ ${e.hr_baseline} → ` +
          `${formatPace(e.pace_recent_sec)}/mi @ ${e.hr_recent} ` +
          `(efficiency ${e.ef_delta_pct > 0 ? "+" : ""}${e.ef_delta_pct}%, ${arrow}) ` +
          `[${e.confidence}: ${e.recent_samples} recent vs ${e.baseline_samples} prior, ~${weeks}wk]`,
        );
      }
      const d = fs.decoupling;
      if (d && d.recent_pct != null && d.direction) {
        const arrow = d.direction === "improving" ? "↑ more durable"
          : d.direction === "declining" ? "↓ less durable" : "→ steady";
        const base = d.baseline_pct != null ? `${d.baseline_pct}% → ` : "";
        lines.push(`  Long-run decoupling: ${base}${d.recent_pct}% (${arrow}) [${d.recent_samples} recent / ${d.baseline_samples} prior long runs]`);
      }
      lines.push(`→ This is the OBJECTIVE half of the fitness read. Pair it with how training has felt; don't read heat-inflated HR as lost fitness (see Conditions).`);
    }
  });

  // Training pace zones (CRITICAL — the AI must quote these exactly, never invent paces)
  // Effort zones are RANGES (Easy / Moderate / Steady / HMP). Race anchors
  // are single targets (MP, 10K, 5K, Mile). Coach-honest framing — no midpoints.
  section("pace_zones", 1, (lines) => {
    if (state.pace_zones && Object.keys(state.pace_zones).length > 0) {
      const z = state.pace_zones;
      const r = state.pace_zone_ranges ?? {};
      lines.push(`\nTraining pace zones (USE THESE — do not calculate or invent paces):`);
      if (r.easy) {
        lines.push(`  Easy: ${formatPace(r.easy.paceFast)}–${formatPace(r.easy.paceSlow)}/mi (${r.easy.effortPercent})`);
      }
      if (r.moderate) {
        lines.push(`  Moderate: ${formatPace(r.moderate.paceFast)}–${formatPace(r.moderate.paceSlow)}/mi (${r.moderate.effortPercent})`);
      }
      if (r.steady) {
        lines.push(`  Steady: ${formatPace(r.steady.paceFast)}–${formatPace(r.steady.paceSlow)}/mi (${r.steady.effortPercent})`);
      }
      if (r.hmp) {
        lines.push(`  HMP: ${formatPace(r.hmp.paceFast)}–${formatPace(r.hmp.paceSlow)}/mi (${r.hmp.effortPercent})`);
      }
      if (z.mp) lines.push(`  Marathon Pace: ${formatPace(z.mp)}/mi`);
      if (z.tenK) lines.push(`  10K Pace: ${formatPace(z.tenK)}/mi`);
      if (z.fiveK) lines.push(`  5K Pace / Intervals: ${formatPace(z.fiveK)}/mi`);
      if (z.mile) lines.push(`  Mile Pace / VO2 Max: ${formatPace(z.mile)}/mi`);
    }
  });

  // Vibe
  section("vibe", 3, (lines) => {
    if (state.last_mood) {
      lines.push(`\nRecent vibe: ${state.last_mood}${state.last_readiness_score ? ` (readiness ${state.last_readiness_score}/10)` : ""}`);
      if (state.mood_trend) lines.push(`Mood trend: ${state.mood_trend}`);
    }
  });

  // What I remember about this athlete — durable memory (preferences, life
  // context, constraints, prior decisions). Use to sound like you know them.
  section("memories", 6, (lines) => {
    if (state.memories && state.memories.length > 0) {
      lines.push(`\nWhat I remember about you:`);
      for (const m of state.memories.slice(0, 8)) {
        lines.push(`  • ${m.content}`);
      }
    }
  });

  // Execution — did recent quality sessions land? Splits, fade, HR drift.
  section("execution", 4, (lines) => {
    if (state.execution && state.execution.length > 0) {
      lines.push(`\nRecent quality sessions (did they land?):`);
      for (const e of state.execution.slice(0, 4)) {
        const reps = e.rep_paces.length > 0 ? ` [${e.rep_paces.join(", ")}]` : "";
        const fade = e.fade_pct != null ? ` · fade ${e.fade_pct > 0 ? "+" : ""}${e.fade_pct}%` : "";
        const drift = e.hr_drift_pct != null ? ` · HR drift ${e.hr_drift_pct > 0 ? "+" : ""}${e.hr_drift_pct}%` : "";
        lines.push(`  ${e.date} ${e.type ?? "workout"} — ${e.rep_count} reps${reps} · ${e.shape}${fade}${drift}`);
      }
    }
  });

  // Conditions — so a slow pace in heat isn't read as lost fitness. Only
  // surface runs the heat actually affected (≥1.5% adjustment — env value is
  // now a percent; a 67°F/67°dew run is ~1.9%, an 85°F/71°dew run ~4.3%).
  section("conditions", 5, (lines) => {
    if (state.environment && state.environment.length > 0) {
      const hot = state.environment.filter(
        (e) => e.heat_adjustment_pct != null && e.heat_adjustment_pct >= 1.5
      );
      if (hot.length > 0) {
        lines.push(`\nConditions (don't read heat as lost fitness):`);
        for (const e of hot.slice(0, 4)) {
          const t = e.temp_f != null ? `${e.temp_f}°F` : "";
          const dp = e.dew_point_f != null ? `, dew ${e.dew_point_f}°F` : "";
          const adj = e.actual_pace && e.heat_adjusted_pace
            ? ` — ran ${e.actual_pace}/mi, heat-adjusted ${e.heat_adjusted_pace}/mi (${e.heat_adjustment_pct}% slower from heat)`
            : "";
          lines.push(`  ${e.date}: ${t}${dp}${adj}`);
        }
      }
    }
  });

  // Injuries (current + history + newly detected mentions in notes) — P1,
  // safety-critical, never dropped.
  section("injuries", 1, (lines) => {
    if (state.active_injuries.length > 0) {
      lines.push(`\n⚠ Active injuries: ${state.active_injuries.map((i) => `${i.body_area} (${i.status}, severity ${i.severity})`).join(", ")}`);
    }
    if (state.injury_risk_score && state.injury_risk_score >= 3) {
      lines.push(`Injury risk: ${state.injury_risk_score}/10`);
    }
    if (state.injury_history_summary && state.injury_history_summary.length > 0) {
      const recurring = state.injury_history_summary.filter((h) => h.occurrences >= 2);
      const recent = state.injury_history_summary.slice(0, 3);
      if (recurring.length > 0) {
        lines.push(`Recurring issues (12mo): ${recurring.map((h) => `${h.body_area} (${h.occurrences}x)`).join(", ")}`);
      } else if (recent.length > 0 && state.active_injuries.length === 0) {
        lines.push(`Prior injuries (12mo): ${recent.map((h) => h.body_area).join(", ")}`);
      }
    }
    // Possible injuries detected in recent notes/memos — NOT declared, just mentions
    if (state.possible_injuries && state.possible_injuries.length > 0) {
      lines.push(`\nBody-part mentions (recent notes — NOT declared injuries, surface carefully):`);
      for (const p of state.possible_injuries.slice(0, 4)) {
        const vol = p.volume_context ? ` — ${p.volume_context}` : "";
        lines.push(`  ${p.date}: ${p.body_area} [${p.severity_hint}]${vol}`);
        lines.push(`    "${p.excerpt}"`);
      }
      lines.push(`→ If any of these mentions are new to you, ask about them gently. If mentioned multiple times or with pain words, treat as active.`);
    }
  });

  // Durable niggle recurrence (12mo) — the pattern, from the body_mentions
  // store. Surface the recurrence; never name a diagnosis (hard rule #2).
  section("niggle_recurrence", 4, (lines) => {
    if (state.niggle_recurrence && state.niggle_recurrence.length > 0) {
      const recurring = state.niggle_recurrence.filter((n) => n.occurrences >= 2);
      if (recurring.length > 0) {
        lines.push(`\nNiggle recurrence (12mo — surface the pattern, don't diagnose):`);
        for (const n of recurring.slice(0, 4)) {
          lines.push(`  ${n.body_area}: ${n.occurrences}× (${n.first_seen} → ${n.last_seen}, worst: ${n.worst_severity})`);
        }
      }
    }
  });

  // Patterns — pre-computed coach observations. Narrate at most one or
  // two; the math is already done, so state them plainly (don't re-derive).
  section("patterns", 5, (lines) => {
    if (state.patterns && state.patterns.length > 0) {
      lines.push(`\nPatterns I've noticed (pre-computed — state plainly, don't explain the math):`);
      for (const p of state.patterns.slice(0, 4)) {
        lines.push(`  • ${p.statement} [${p.confidence}: ${p.evidence}]`);
      }
    }
  });

  // What I can't see — real, computed blind spots. Ground the cant_see block
  // in one of these (eyebrow = the gap label); never invent a blind spot.
  section("data_gaps", 5, (lines) => {
    if (state.data_gaps && state.data_gaps.length > 0) {
      lines.push(`\nWhat I can't see right now (use for the cant_see block; don't invent others):`);
      for (const g of state.data_gaps.slice(0, 4)) {
        lines.push(`  • ${g.gap} — ${g.detail}`);
      }
    }
  });

  // Biographical framing (ego-safe tone gate) + fitness vs 6 months ago.
  section("trajectory", 4, (lines) => {
    if (state.trajectory_framing) {
      lines.push(`\nTrajectory: ${state.trajectory_framing} — ${state.trajectory_reason ?? ""}`);
      // Prompt guidance to the coach based on framing
      const framingGuidance: Record<string, string> = {
        returning: "Frame progress relative to where they are now, NOT peak fitness. Celebrate consistency over pace. Avoid references to prior PRs unless they bring them up.",
        declining: "Acknowledge the drop without judgment. Ask what's changed (life stress, motivation, injury niggle). Don't assume they need to ramp back immediately.",
        peaking: "They're near race-ready. Keep tone sharp, trust the work, focus on execution and recovery. Don't introduce new stressors.",
        building: "Growth phase. Reinforce what's working, gently raise the bar. Fitness is improving — help them see it.",
        maintaining: "Steady state. No drama needed. Look for subtle fitness signals and help them see what's working.",
      };
      const guidance = framingGuidance[state.trajectory_framing];
      if (guidance) lines.push(`Coaching tone: ${guidance}`);
    }

    // Fitness trajectory vs 6 months ago
    if (state.fitness_vs_6mo_ago_label && state.fitness_vs_6mo_ago_seconds != null) {
      const sec = state.fitness_vs_6mo_ago_seconds;
      lines.push(`Fitness vs 6mo ago: ${state.fitness_vs_6mo_ago_label} (${formatTimeDelta(sec)} on 10K)`);
    }
  });

  // Confirmed races (user-declared via training_logs.race_result)
  section("confirmed_races", 6, (lines) => {
    if (state.confirmed_races && state.confirmed_races.length > 0) {
      lines.push(`\nRaces (declared by athlete):`);
      for (const r of state.confirmed_races.slice(0, 6)) {
        const event = r.event_name ? ` — ${r.event_name}` : "";
        const official = r.official ? "" : " (unofficial)";
        const mins = Math.floor(r.finish_time_seconds / 60);
        const secs = r.finish_time_seconds % 60;
        const hrs = Math.floor(mins / 60);
        const timeFmt = hrs > 0
          ? `${hrs}:${String(mins % 60).padStart(2, "0")}:${String(secs).padStart(2, "0")}`
          : `${mins}:${String(secs).padStart(2, "0")}`;
        lines.push(`  ${r.date.slice(0, 10)}: ${r.distance} @ ${timeFmt}${event}${official}`);
      }
    }
  });

  // Training blocks — block-over-block comparison (last 6 × 4 weeks)
  section("blocks", 6, (lines) => {
    if (state.recent_blocks && state.recent_blocks.length > 0) {
      lines.push(`\nTraining blocks (most recent first, 28-day rollups):`);
      for (const b of state.recent_blocks.slice(0, 6)) {
        const easyPace = b.avg_easy_pace_sec
          ? `, easy ${Math.floor(b.avg_easy_pace_sec / 60)}:${String(b.avg_easy_pace_sec % 60).padStart(2, "0")}`
          : "";
        const races = b.races_entered > 0 ? `, ${b.races_entered} race${b.races_entered > 1 ? "s" : ""}` : "";
        const mood = b.mood_summary ? `, mood: ${b.mood_summary}` : "";
        lines.push(`  ${b.block_start} → ${b.block_end}: ${b.total_miles}mi (${b.weekly_avg_miles}/wk), ${b.quality_sessions} quality + ${b.easy_sessions} easy${easyPace}${races}${mood}`);
      }
      // Block-over-block delta (current vs prior)
      if (state.recent_blocks.length >= 2) {
        const cur = state.recent_blocks[0];
        const prior = state.recent_blocks[1];
        const volDelta = cur.weekly_avg_miles - prior.weekly_avg_miles;
        const qualDelta = cur.quality_sessions - prior.quality_sessions;
        const deltaParts: string[] = [];
        if (Math.abs(volDelta) >= 3) deltaParts.push(`volume ${volDelta > 0 ? "+" : ""}${volDelta.toFixed(1)}mi/wk`);
        if (qualDelta !== 0) deltaParts.push(`quality ${qualDelta > 0 ? "+" : ""}${qualDelta} session${Math.abs(qualDelta) > 1 ? "s" : ""}`);
        if (deltaParts.length > 0) {
          lines.push(`→ Block-over-block: ${deltaParts.join(", ")}`);
        }
      }
    }
  });

  // Schedule
  section("schedule", 2, (lines) => {
    if (state.today_workout) {
      const tw = state.today_workout as Record<string, unknown>;
      lines.push(`\nToday's workout: ${tw.workout_data ? (tw.workout_data as Record<string, string>).name : tw.workout_type}`);
    }
    if (state.upcoming_workouts.length > 0) {
      lines.push("Upcoming: " + state.upcoming_workouts.slice(0, 3).map((w) => {
        const wd = w as Record<string, unknown>;
        return `${(wd.date as string)?.split("T")[0]}: ${wd.workout_data ? (wd.workout_data as Record<string, string>).name : wd.workout_type}`;
      }).join(", "));
    }
  });

  // Recent workouts — priority order for describing each run:
  //   1. User's own notes (most reliable — they know what the workout WAS)
  //   2. Observer-parsed pattern ("5×1mi @ 5:19")
  //   3. Work pace from parsed_structure (avg of the hard portion)
  //   4. Raw avg pace (least useful — averages over warmup/recovery/cooldown)
  //
  // IMPORTANT: avg pace is misleading for interval/tempo workouts. Always prefer
  // user notes + work pace when available. Never lead with avg pace for a workout
  // the user described as intervals or tempo.
  section("recent_workouts", 3, (lines) => {
    if (state.recent_workouts.length > 0) {
      lines.push("\nRecent runs (trust user notes + work pace over avg pace):");
      for (const w of state.recent_workouts.slice(0, 9)) {
        // Build the descriptor — prefer notes, then pattern, then work pace, then avg.
        const parts: string[] = [];
        if (w.structure_pattern) parts.push(w.structure_pattern);
        if (w.work_pace && !w.structure_pattern) parts.push(`work @ ${w.work_pace}`);
        if (!w.structure_pattern && !w.work_pace && w.pace) parts.push(`@ ${w.pace} avg`);
        const headline = parts.length > 0 ? ` — ${parts.join(" | ")}` : "";
        const equiv = w.equivalent_race ? ` (≈ ${w.equivalent_race})` : "";
        const mood = w.mood ? ` [${w.mood}]` : "";
        const notes = w.user_notes ? `\n      notes: "${w.user_notes.replace(/\n/g, " ")}"` : "";
        lines.push(`  ${w.date}: ${w.type} ${w.miles}mi${headline}${equiv}${mood}${notes}`);
      }
    }
  });

  const budget = opts.budget ?? Infinity;
  const { text, tokens, dropped } = assemblePromptSections(
    "=== ATHLETE STATE ===",
    sections,
    budget,
  );

  // Log when over the soft target (or when we actually pruned) so the enforced
  // budget can be chosen from real token distributions. See Fix 1 in
  // outputs/athlete-state-review-2026-06-18.md (open question: final cap #).
  if (tokens > PROMPT_SOFT_TARGET_TOKENS || dropped.length > 0) {
    console.log(
      `[AthleteState] prompt tokens≈${tokens} (soft target ${PROMPT_SOFT_TARGET_TOKENS})` +
      (dropped.length > 0 ? ` dropped=[${dropped.join(",")}]` : ""),
    );
  }

  return text;
}

// formatPace / formatTime / formatTimeDelta moved to _shared/shared/format.ts
// (imported at the top; formatPace re-exported for backwards compatibility).
