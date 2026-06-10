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
  computeWeightedLoadForLog,
  type TrainingLogRow as WeeklyAnalyticsLogRow,
  type WorkoutFeaturesRow,
} from "./weeklyAnalytics.ts";

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
  }

  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 86400000).toISOString();
  const fourteenDaysAgo = new Date(now.getTime() - 14 * 86400000).toISOString();
  const twentyEightDaysAgo = new Date(now.getTime() - 28 * 86400000).toISOString();
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
    // Latest fitness snapshot
    supabase
      .from("fitness_snapshots")
      .select("*")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1),
    // Active injuries
    supabase
      .from("injuries")
      .select("body_area, severity, status, first_reported_at")
      .eq("user_id", userId)
      .in("status", ["active", "monitoring"])
      .order("severity", { ascending: false }),
    // Active training plan
    supabase
      .from("training_plans")
      .select("id, name, target_race_distance, target_time_seconds, status")
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
      .select("training_log_id, intensity_score, total_duration_seconds")
      .eq("user_id", userId)
      .gte("workout_date", twentyEightDaysAgo),
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
  ]);

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

  // ── Compute load metrics ──
  const workoutsWithMilesRaw = logs.filter(
    (l) => (l.workout_distance_miles as number) > 0
  );

  // Cross-source dedup. The same workout can appear 2-3 times in training_logs:
  // once from Strava auto-sync, once as a voice_log the user created, once as
  // auto_sync from HealthKit. Different timestamps, same workout. Strictest
  // match: same calendar day + distance within 0.2mi + duration within 2min.
  // Source priority: strava > auto_sync > voice_log > manual (keep the richest).
  function sourcePriority(src: unknown): number {
    switch (src) {
      case "strava": return 4;
      case "auto_sync": return 3;
      case "voice_log": return 2;
      case "check_in": return 1;
      default: return 0;
    }
  }
  const workoutsWithMiles: Array<Record<string, unknown>> = [];
  for (const row of workoutsWithMilesRaw) {
    const day = String(row.workout_date ?? "").slice(0, 10);
    const rDist = row.workout_distance_miles as number;
    const rDur = (row.workout_duration_minutes as number) ?? 0;
    // Find an existing dedup partner
    const dupIdx = workoutsWithMiles.findIndex((existing) => {
      const eDay = String(existing.workout_date ?? "").slice(0, 10);
      if (eDay !== day) return false;
      const eDist = existing.workout_distance_miles as number;
      const eDur = (existing.workout_duration_minutes as number) ?? 0;
      return Math.abs(eDist - rDist) <= 0.2 && Math.abs(eDur - rDur) <= 2;
    });
    if (dupIdx < 0) {
      workoutsWithMiles.push(row);
    } else {
      // Keep whichever has higher source priority (richer data)
      if (sourcePriority(row.source) > sourcePriority(workoutsWithMiles[dupIdx].source)) {
        workoutsWithMiles[dupIdx] = row;
      }
    }
  }

  // Session-level dedup: multiple uploads that happen close together in time
  // (warmup + workout + cooldown saved as separate entries, commonly from
  // Strava/Garmin) collapse into ONE "session." Uses gap-based clustering:
  // if two workouts start within 3 hours of each other AND are on the same
  // calendar day, they're the same session. Total mileage still summed per
  // session but session count reflects reality.
  function groupIntoSessions(rows: Array<Record<string, unknown>>) {
    if (rows.length === 0) return [];
    // Sort ascending by workout_date
    const sorted = [...rows].sort((a, b) =>
      String(a.workout_date ?? "").localeCompare(String(b.workout_date ?? ""))
    );
    const sessions: Array<Array<Record<string, unknown>>> = [[sorted[0]]];
    for (let i = 1; i < sorted.length; i++) {
      const prev = sorted[i - 1];
      const cur = sorted[i];
      const prevTime = new Date(prev.workout_date as string).getTime();
      const curTime = new Date(cur.workout_date as string).getTime();
      const sameDay = (prev.workout_date as string)?.slice(0, 10)
        === (cur.workout_date as string)?.slice(0, 10);
      const gapHours = (curTime - prevTime) / 3600000;
      // Also consider prev duration — a 2h run ending at 2pm + next run at 3pm is same session
      const prevDurMin = (prev.workout_duration_minutes as number) ?? 0;
      const prevEndGapHours = (curTime - prevTime) / 3600000 - (prevDurMin / 60);

      if (sameDay && (gapHours <= 3 || prevEndGapHours <= 1.5)) {
        sessions[sessions.length - 1].push(cur);
      } else {
        sessions.push([cur]);
      }
    }
    return sessions;
  }

  const last7d = workoutsWithMiles.filter(
    (l) => new Date(l.workout_date as string) >= new Date(sevenDaysAgo)
  );
  const last28d = workoutsWithMiles.filter(
    (l) => new Date(l.workout_date as string) >= new Date(twentyEightDaysAgo)
  );
  const sessions7d = groupIntoSessions(last7d);
  const sessions28d = groupIntoSessions(last28d);

  const rolling7dMiles = last7d.reduce(
    (s, l) => s + ((l.workout_distance_miles as number) || 0), 0
  );
  const rolling28dMiles = last28d.reduce(
    (s, l) => s + ((l.workout_distance_miles as number) || 0), 0
  );

  const weeklyAvg28d = rolling28dMiles / 4;

  // ── Intensity-weighted load (drives ACWR) ──
  // For each training log, derive a weighted-minutes load using the
  // shared helper. Preferred path: workout_features.intensity_score ×
  // duration_seconds / 60. Fallback: workout_type × duration_minutes
  // when features haven't been computed for that log yet.
  function computeLoadForLog(l: Record<string, unknown>): number {
    return computeWeightedLoadForLog(
      l as unknown as WeeklyAnalyticsLogRow,
      featuresByLogId.get(l.id as string),
    );
  }
  const rolling7dLoad = last7d.reduce((s, l) => s + computeLoadForLog(l), 0);
  const rolling28dLoad = last28d.reduce((s, l) => s + computeLoadForLog(l), 0);
  const weeklyAvgLoad28d = rolling28dLoad / 4;
  const acwr = weeklyAvgLoad28d > 0 ? rolling7dLoad / weeklyAvgLoad28d : null;

  // Compute MP pace early — needed for hard session classification below.
  const marathonSec = (snapshot?.predicted_marathon_seconds as number) || 0;
  const earlyMpPace = marathonSec > 0 ? marathonSec / 26.2188 : 0;

  // Tempo, intervals, race, progression are always hard.
  // Long runs are hard only if 18+ miles OR run at 80%+ of MP (faster pace = lower number).
  const alwaysHardTypes = new Set(["tempo", "intervals", "interval", "race", "progression"]);
  const easyTypes = new Set(["easy", "recovery"]);

  const mpPace = earlyMpPace;
  function isHardSession(log: Record<string, unknown>): boolean {
    if (alwaysHardTypes.has(log.workout_type as string)) return true;
    if (log.workout_type === "long_run") {
      const miles = (log.workout_distance_miles as number) || 0;
      if (miles >= 18) return true;
      // Check if pace is 80%+ of MP (i.e., pace <= MP / 0.80)
      // Since lower pace = faster, "80% of MP effort" means pace is at most MP * 1.25
      if (mpPace > 0) {
        const duration = (log.workout_duration_minutes as number) || 0;
        if (duration > 0 && miles > 0) {
          const avgPaceSec = (duration * 60) / miles;
          if (avgPaceSec <= mpPace * 1.25) return true; // faster than 80% MP effort
        }
      }
    }
    return false;
  }

  const hardSessions7d = last7d.filter(isHardSession).length;
  const easySessions7d = last7d.filter((l) => easyTypes.has(l.workout_type as string)).length;

  const last14d = workoutsWithMiles.filter(
    (l) => new Date(l.workout_date as string) >= new Date(fourteenDaysAgo)
  );
  const longestRun14d = last14d.reduce(
    (max, l) => Math.max(max, (l.workout_distance_miles as number) || 0), 0
  );

  // ── Mood trend ──
  // Broader mood signal — include both formal check-ins AND voice-log moods.
  // Most athletes won't do dedicated check-ins daily, but they leave mood hints
  // in every voice memo. Use both, sorted by date desc.
  type MoodSource = { mood: string; at: string };
  const moodSources: MoodSource[] = [
    ...checkIns.map((c) => ({ mood: c.mood, at: c.created_at })),
    ...logs
      .filter((l) => l.mood && l.workout_date)
      .map((l) => ({ mood: l.mood as string, at: l.workout_date as string })),
  ]
    .filter((m) => m.mood)
    .sort((a, b) => b.at.localeCompare(a.at))
    .slice(0, 8);

  const moodScores: Record<string, number> = {
    energized: 5, positive: 4, neutral: 3, tired: 2, struggling: 1, injured: 0,
  };
  let moodTrend: string | null = null;
  if (moodSources.length >= 3) {
    const scores = moodSources.map((m) => moodScores[m.mood] ?? 3);
    const recent = scores.slice(0, 3).reduce((a, b) => a + b, 0) / 3;
    const older = scores.slice(3).reduce((a, b) => a + b, 0) / Math.max(scores.length - 3, 1);
    moodTrend = recent > older + 0.5 ? "improving" : recent < older - 0.5 ? "declining" : "stable";
  }

  // ── Fitness trajectory ──
  let fitnessTrend: string | null = null;
  // Could compare last 2 snapshots, but for now just use the latest
  if (snapshot) {
    fitnessTrend = "maintaining"; // TODO: compare with previous snapshot
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
  if (acwr) summaryParts.push(`ACWR ${acwr.toFixed(2)}`);
  if (longestRun14d > 0) summaryParts.push(`longest run 14d: ${longestRun14d.toFixed(1)} mi`);
  if (checkIns[0]) summaryParts.push(`last check-in: ${checkIns[0].mood}`);
  if (injuries.length > 0) summaryParts.push(`${injuries.length} active injury(ies): ${injuries.map((i) => i.body_area).join(", ")}`);
  const recentTrainingSummary = summaryParts.join(" · ");

  // ── Scheduled workouts (need plan_id) ──
  let todayWorkout: Record<string, unknown> | null = null;
  let upcomingWorkouts: Array<Record<string, unknown>> = [];
  if (plan?.id) {
    const { data: scheduled } = await supabase
      .from("scheduled_workouts")
      .select("date, workout_type, workout_data, status")
      .eq("plan_id", plan.id)
      .gte("date", today)
      .eq("status", "scheduled")
      .order("date", { ascending: true })
      .limit(6);

    if (scheduled?.length) {
      const todayRow = scheduled.find((w: any) => w.date === today);
      if (todayRow) todayWorkout = todayRow;
      upcomingWorkouts = scheduled.filter((w: any) => w.date !== today).slice(0, 5);
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
    }
  }
  // Sort by severity (sharp > pain > sore > tight) then date desc
  const sevOrder: Record<string, number> = { sharp: 4, pain: 3, sore: 2, tight: 1 };
  possibleInjuries.sort((a, b) =>
    (sevOrder[b.severity_hint] ?? 0) - (sevOrder[a.severity_hint] ?? 0)
    || b.date.localeCompare(a.date)
  );

  // ── Training blocks (6 × 4-week rollups) ──
  // Computes block-over-block comparison signals. Each block summarizes volume,
  // quality sessions, easy sessions, injury mentions, and mood trend for a
  // 28-day window. Coach uses this for "this block vs last" framing.
  const blockHistoryRaw = (blockHistoryRes?.data ?? []) as Array<Record<string, unknown>>;
  // Cross-source dedup (same logic as current workouts) — blocks would otherwise double-count
  const blockHistoryDeduped: Array<Record<string, unknown>> = [];
  for (const row of blockHistoryRaw) {
    const day = String(row.workout_date ?? "").slice(0, 10);
    const rDist = row.workout_distance_miles as number;
    const rDur = (row.workout_duration_minutes as number) ?? 0;
    const dupIdx = blockHistoryDeduped.findIndex((e) => {
      const eDay = String(e.workout_date ?? "").slice(0, 10);
      if (eDay !== day) return false;
      const eDist = e.workout_distance_miles as number;
      const eDur = (e.workout_duration_minutes as number) ?? 0;
      return Math.abs(eDist - rDist) <= 0.2 && Math.abs(eDur - rDur) <= 2;
    });
    if (dupIdx < 0) blockHistoryDeduped.push(row);
    else if (sourcePriority(row.source) > sourcePriority(blockHistoryDeduped[dupIdx].source)) {
      blockHistoryDeduped[dupIdx] = row;
    }
  }

  const recentBlocks: AthleteState["recent_blocks"] = [];
  for (let blockIdx = 0; blockIdx < 6; blockIdx++) {
    const blockEnd = new Date(now.getTime() - blockIdx * 28 * 86400000);
    const blockStart = new Date(blockEnd.getTime() - 28 * 86400000);

    const rowsInBlock = blockHistoryDeduped.filter((r) => {
      const t = new Date(r.workout_date as string).getTime();
      return t >= blockStart.getTime() && t < blockEnd.getTime();
    });
    if (rowsInBlock.length === 0) continue;

    const totalMiles = rowsInBlock.reduce((s, r) => s + ((r.workout_distance_miles as number) || 0), 0);
    let quality = 0;
    let easy = 0;
    let races = 0;
    let injuryMentions = 0;
    const easyPaces: number[] = [];
    const moodCounts: Record<string, number> = {};

    for (const r of rowsInBlock) {
      const parsed = r.parsed_structure as Record<string, unknown> | null;
      const parsedType = parsed && typeof parsed === "object" ? parsed["type"] as string | undefined : undefined;
      const t = parsedType ?? "";
      if (t === "interval" || t === "tempo" || t === "progression") quality++;
      else if (t === "race") { quality++; races++; }
      else if (t === "easy" || t === "recovery" || t === "long_run") easy++;
      else easy++; // fallback unlabeled to easy

      // Easy pace for easy/recovery workouts — prefer workout_pace_per_mile column,
      // fall back to derived (duration/distance) when null (Strava imports often
      // don't populate the column but have distance + duration).
      if (t === "easy" || t === "recovery") {
        let paceSec: number | null = null;
        if (r.workout_pace_per_mile) {
          const parts = (r.workout_pace_per_mile as string).split(":").map(Number);
          if (parts.length === 2 && !isNaN(parts[0])) paceSec = parts[0] * 60 + parts[1];
        }
        if (paceSec === null) {
          const dist = r.workout_distance_miles as number;
          const dur = r.workout_duration_minutes as number;
          if (dist > 0 && dur > 0) paceSec = Math.round((dur * 60) / dist);
        }
        if (paceSec !== null && paceSec >= 300 && paceSec <= 840) {
          easyPaces.push(paceSec);
        }
      }
      if (r.mood) {
        const m = r.mood as string;
        moodCounts[m] = (moodCounts[m] ?? 0) + 1;
      }
    }
    const avgEasyPace = easyPaces.length > 0
      ? Math.round(easyPaces.reduce((a, b) => a + b, 0) / easyPaces.length)
      : null;
    const domMood = Object.entries(moodCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;

    recentBlocks.push({
      block_start: blockStart.toISOString().slice(0, 10),
      block_end: blockEnd.toISOString().slice(0, 10),
      total_miles: Math.round(totalMiles * 10) / 10,
      weekly_avg_miles: Math.round((totalMiles / 4) * 10) / 10,
      quality_sessions: quality,
      easy_sessions: easy,
      races_entered: races,
      avg_easy_pace_sec: avgEasyPace,
      injury_mentions: injuryMentions,
      mood_summary: domMood,
    });
  }

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

  // Trajectory framing — ego-safe tone gate
  // Rules (conservative; bias toward "maintaining" when uncertain):
  //   returning: recent volume < 50% of 4-week prior avg AND either injury resolved recently OR prior volume gap >14 days
  //   declining: recent volume < 70% of prior AND no recent injury (unintentional drop)
  //   peaking: recent volume ≥ 90% of prior AND ≥2 hard sessions/wk AND plan active with race <8 weeks
  //   building: recent volume > 110% of prior AND fitness trend = improving
  //   maintaining: default
  const priorBlockAvg = weeklyAvg28d - (rolling7dMiles / 4); // approx prior 3-week avg
  const recentVsPrior = priorBlockAvg > 0 ? rolling7dMiles / priorBlockAvg : 1;
  const recentlyResolvedInjury = injuryHistory.some((i) =>
    i.status === "resolved" && i.resolved_at &&
    new Date(i.resolved_at).getTime() > now.getTime() - 45 * 86400000
  );
  const hasActiveInjury = injuries.length > 0;
  let trajectoryFraming = "maintaining";
  let trajectoryReason = "volume stable near recent average";
  if (rolling7dMiles < priorBlockAvg * 0.5 && (recentlyResolvedInjury || hasActiveInjury)) {
    trajectoryFraming = "returning";
    trajectoryReason = `volume at ${Math.round(rolling7dMiles)}mi is ${Math.round(recentVsPrior * 100)}% of recent avg; ${hasActiveInjury ? "active" : "recently resolved"} injury`;
  } else if (rolling7dMiles < priorBlockAvg * 0.7 && !hasActiveInjury) {
    trajectoryFraming = "declining";
    trajectoryReason = `volume dropped to ${Math.round(recentVsPrior * 100)}% of recent avg, no injury reason`;
  } else if (recentVsPrior >= 0.9 && hardSessions7d >= 2 && plan?.target_time_seconds) {
    // TODO: also check race date within 8 weeks once plan has race_date
    trajectoryFraming = "peaking";
    trajectoryReason = `high volume + ${hardSessions7d} hard sessions + active race plan`;
  } else if (recentVsPrior > 1.1 && fitnessTrend === "improving") {
    trajectoryFraming = "building";
    trajectoryReason = `volume up ${Math.round((recentVsPrior - 1) * 100)}% vs recent avg, fitness improving`;
  }

  // ── Phase derivation from volume + quality + trajectory ──
  // Fixes the "70mi/wk but state says off_season" bug. Real phases:
  //   recovery: <50% of 28-day avg volume + <1 hard session/wk
  //   base: 70-100% of avg volume, 1-2 hard sessions, no race soon
  //   build: 100-120% of avg volume, 2-3 hard sessions
  //   peak: >120% of avg OR ≥3 hard sessions + race <4wk
  //   taper: volume dropping after peak, still quality, race <2wk
  //   off_season: <30% of historical avg + no quality for 2+ weeks
  const historicalAvg = (profile as Record<string, unknown> | null)?.lifetime_weekly_avg as number
    ?? weeklyAvg28d;
  let derivedPhase: string;
  if (rolling7dMiles < historicalAvg * 0.3 && hardSessions7d === 0) {
    derivedPhase = "off_season";
  } else if (rolling7dMiles < historicalAvg * 0.6 && hardSessions7d <= 1) {
    derivedPhase = "recovery";
  } else if (hardSessions7d >= 3 && rolling7dMiles >= historicalAvg * 1.1) {
    derivedPhase = "peak";
  } else if (rolling7dMiles >= historicalAvg * 1.0 && hardSessions7d >= 2) {
    derivedPhase = "build";
  } else {
    derivedPhase = "base";
  }

  // ── Experience level inference from profile + pace zones ──
  // profile.experience_level is often null — infer from volume + pace when missing.
  let derivedExperience = (profile?.experience_level as string) ?? null;
  if (!derivedExperience) {
    const easyPaceSec = paceZones.easy ?? 0;
    if (weeklyAvg28d >= 50 && easyPaceSec > 0 && easyPaceSec < 480) {
      derivedExperience = "advanced";
    } else if (weeklyAvg28d >= 25) {
      derivedExperience = "intermediate";
    } else if (weeklyAvg28d > 0) {
      derivedExperience = "beginner";
    }
  }

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

  // ── Build the state ──
  const state: AthleteState = {
    user_id: userId,
    experience_level: derivedExperience,
    current_phase: derivedPhase,
    active_plan_id: plan?.id ?? null,
    goal_race: plan ? `${plan.target_race_distance} plan` : null,
    goal_time_seconds: plan?.target_time_seconds ?? null,

    acwr: acwr ? Math.round(acwr * 100) / 100 : null,
    monotony_7d: null, // TODO: compute from workout_features
    strain_7d: null,
    rolling_7d_miles: Math.round(rolling7dMiles * 10) / 10,
    rolling_28d_miles: Math.round(rolling28dMiles * 10) / 10,
    weekly_avg_miles: Math.round(weeklyAvg28d * 10) / 10,
    hard_sessions_7d: hardSessions7d,
    easy_sessions_7d: easySessions7d,
    // Use session count (deduped warmup/cool-down uploads), not raw upload count
    runs_last_7d: sessions7d.length,
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

    pace_zones: paceZones,
    pace_zone_ranges: paceZoneRanges,

    recent_training_summary: recentTrainingSummary,
    recent_workouts: recentWorkouts,

    today_workout: todayWorkout,
    upcoming_workouts: upcomingWorkouts,
    week_compliance_pct: null, // TODO: compute

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

    last_updated_at: new Date().toISOString(),
    last_updated_by: "rebuild",
    version: 1,
  };

  // Upsert the state. Clear rebuild_started_at so the next claimer sees
  // an idle row. The column isn't part of AthleteState so we null it in a
  // follow-up update rather than widening the type.
  await supabase
    .from("athlete_state")
    .upsert(state, { onConflict: "user_id" });
  await supabase
    .from("athlete_state")
    .update({ rebuild_started_at: null })
    .eq("user_id", userId);

  return state;
}

// ── Prompt Helper ────────────────────────────────────────

/**
 * Compress the athlete state into a concise context block for AI prompts.
 * Returns ~200-400 tokens of structured context that replaces the 6-8
 * independent queries each function was doing.
 */
export function stateToPromptContext(state: AthleteState): string {
  const lines: string[] = [];

  lines.push("=== ATHLETE STATE ===");

  // Identity
  if (state.experience_level) lines.push(`Level: ${state.experience_level}`);
  if (state.current_phase) lines.push(`Phase: ${state.current_phase}`);

  // ── GOALS (what they're training for) ──
  // Plan-based goal first, then user-declared goals with countdown.
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

  // Load
  lines.push(`\nTraining Load (7d): ${state.rolling_7d_miles ?? 0} mi, ${state.runs_last_7d} runs (${state.hard_sessions_7d} hard, ${state.easy_sessions_7d} easy)`);
  lines.push(`28d avg: ${state.weekly_avg_miles ?? 0} mpw`);
  if (state.acwr) lines.push(`ACWR: ${state.acwr} ${state.acwr > 1.3 ? "⚠ HIGH" : state.acwr < 0.8 ? "⚠ LOW" : "✓ OK"}`);
  if (state.longest_run_14d) lines.push(`Longest run (14d): ${state.longest_run_14d} mi`);

  // Fitness + Predicted Race Times
  if (state.predicted_marathon_seconds) {
    lines.push(`\nPredicted race times:`);
    if (state.predicted_5k_seconds) lines.push(`  5K: ${formatTime(state.predicted_5k_seconds)}`);
    if (state.predicted_10k_seconds) lines.push(`  10K: ${formatTime(state.predicted_10k_seconds)}`);
    if (state.predicted_half_seconds) lines.push(`  Half Marathon: ${formatTime(state.predicted_half_seconds)}`);
    lines.push(`  Marathon: ${formatTime(state.predicted_marathon_seconds)}`);
    if (state.fitness_trend) lines.push(`Fitness trend: ${state.fitness_trend}`);
  }

  // Training pace zones (CRITICAL — the AI must quote these exactly, never invent paces)
  // Effort zones are RANGES (Easy / Moderate / Steady / HMP). Race anchors
  // are single targets (MP, 10K, 5K, Mile). Coach-honest framing — no midpoints.
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

  // Vibe
  if (state.last_mood) {
    lines.push(`\nRecent vibe: ${state.last_mood}${state.last_readiness_score ? ` (readiness ${state.last_readiness_score}/10)` : ""}`);
    if (state.mood_trend) lines.push(`Mood trend: ${state.mood_trend}`);
  }

  // Injuries (current + history + newly detected mentions in notes)
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

  // Biographical framing (ego-safe tone gate)
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

  // Confirmed races (user-declared via training_logs.race_result)
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

  // Training blocks — block-over-block comparison (last 6 × 4 weeks)
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

  // Schedule
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

  // Recent workouts — priority order for describing each run:
  //   1. User's own notes (most reliable — they know what the workout WAS)
  //   2. Observer-parsed pattern ("5×1mi @ 5:19")
  //   3. Work pace from parsed_structure (avg of the hard portion)
  //   4. Raw avg pace (least useful — averages over warmup/recovery/cooldown)
  //
  // IMPORTANT: avg pace is misleading for interval/tempo workouts. Always prefer
  // user notes + work pace when available. Never lead with avg pace for a workout
  // the user described as intervals or tempo.
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

  return lines.join("\n");
}

function formatPace(secondsPerMile: number): string {
  const mins = Math.floor(secondsPerMile / 60);
  const secs = Math.round(secondsPerMile % 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

function formatTime(seconds: number): string {
  if (!seconds || seconds <= 0) return "?";
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

/**
 * Format a time delta. Signed. Under 60s → "45s faster". Over 60s → "1:39 slower".
 * Runners read time in M:SS, not raw seconds — "99 seconds slower" is jarring.
 */
function formatTimeDelta(seconds: number): string {
  if (!seconds || seconds === 0) return "same";
  const abs = Math.abs(seconds);
  const direction = seconds > 0 ? "slower" : "faster";
  if (abs < 60) return `${abs}s ${direction}`;
  const m = Math.floor(abs / 60);
  const s = abs % 60;
  return `${m}:${s.toString().padStart(2, "0")} ${direction}`;
}
