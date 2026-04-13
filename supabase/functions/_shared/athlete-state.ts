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

  // Pace Zones
  pace_zones: Record<string, number>;

  // Recent Training
  recent_training_summary: string | null;
  recent_workouts: Array<{
    date: string;
    type: string;
    miles: number;
    pace: string | null;
    mood: string | null;
  }>;

  // Scheduled Context
  today_workout: Record<string, unknown> | null;
  upcoming_workouts: Array<Record<string, unknown>>;
  week_compliance_pct: number | null;

  // Metadata
  last_updated_at: string;
  last_updated_by: string | null;
  version: number;
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
  const now = new Date();
  const sevenDaysAgo = new Date(now.getTime() - 7 * 86400000).toISOString();
  const fourteenDaysAgo = new Date(now.getTime() - 14 * 86400000).toISOString();
  const twentyEightDaysAgo = new Date(now.getTime() - 28 * 86400000).toISOString();
  const today = now.toISOString().split("T")[0];

  // Parallel fetch everything we need
  const [
    recentLogsRes,
    profileRes,
    snapshotRes,
    injuriesRes,
    planRes,
    goalsRes,
    checkInsRes,
  ] = await Promise.all([
    // Last 28 days of training logs
    supabase
      .from("training_logs")
      .select("workout_date, workout_distance_miles, workout_duration_minutes, workout_type, workout_pace_per_mile, mood, cleaned_notes, source")
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
    // Active goals
    supabase
      .from("user_goals")
      .select("goal_title, target_date")
      .eq("status", "active")
      .order("target_date", { ascending: true })
      .limit(3),
    // Recent check-ins (for mood trend)
    supabase
      .from("training_logs")
      .select("mood, created_at, extracted_data")
      .eq("user_id", userId)
      .eq("source", "check_in")
      .not("mood", "is", null)
      .order("created_at", { ascending: false })
      .limit(5),
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

  // ── Compute load metrics ──
  const workoutsWithMiles = logs.filter(
    (l) => (l.workout_distance_miles as number) > 0
  );

  const last7d = workoutsWithMiles.filter(
    (l) => new Date(l.workout_date as string) >= new Date(sevenDaysAgo)
  );
  const last28d = workoutsWithMiles.filter(
    (l) => new Date(l.workout_date as string) >= new Date(twentyEightDaysAgo)
  );

  const rolling7dMiles = last7d.reduce(
    (s, l) => s + ((l.workout_distance_miles as number) || 0), 0
  );
  const rolling28dMiles = last28d.reduce(
    (s, l) => s + ((l.workout_distance_miles as number) || 0), 0
  );

  const weeklyAvg28d = rolling28dMiles / 4;
  const acwr = weeklyAvg28d > 0 ? rolling7dMiles / weeklyAvg28d : null;

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
  const recentMoods = checkIns.map((c) => c.mood);
  const moodScores: Record<string, number> = {
    energized: 5, positive: 4, neutral: 3, tired: 2, struggling: 1, injured: 0,
  };
  let moodTrend: string | null = null;
  if (recentMoods.length >= 3) {
    const scores = recentMoods.map((m) => moodScores[m] ?? 3);
    const recent = scores.slice(0, 2).reduce((a, b) => a + b, 0) / 2;
    const older = scores.slice(2).reduce((a, b) => a + b, 0) / Math.max(scores.length - 2, 1);
    moodTrend = recent > older + 0.5 ? "improving" : recent < older - 0.5 ? "declining" : "stable";
  }

  // ── Fitness trajectory ──
  let fitnessTrend: string | null = null;
  // Could compare last 2 snapshots, but for now just use the latest
  if (snapshot) {
    fitnessTrend = "maintaining"; // TODO: compare with previous snapshot
  }

  // ── Pace zones from snapshot ──
  const paceZones: Record<string, number> = {};
  if (snapshot) {
    const marathonSec = snapshot.predicted_marathon_seconds as number;
    const halfSec = snapshot.predicted_half_seconds as number;
    const tenKSec = snapshot.predicted_10k_seconds as number;
    const fiveKSec = snapshot.predicted_5k_seconds as number;
    if (marathonSec) {
      const mp = marathonSec / 26.2188;
      paceZones.recovery = Math.round(mp * 1.35); // ~35% slower than MP, not 50%
      paceZones.easy = Math.round(mp * 1.28);
      paceZones.longRun = Math.round(mp * 1.21);
      paceZones.moderate = Math.round(mp * 1.14);
      paceZones.steady = Math.round(mp * 1.07);
      paceZones.mp = Math.round(mp);
    }
    if (halfSec) paceZones.hm = Math.round(halfSec / 13.1094);
    if (tenKSec) paceZones.tenK = Math.round(tenKSec / 6.2137);
    if (fiveKSec) paceZones.fiveK = Math.round(fiveKSec / 3.1069);
  }

  // ── Recent workouts (last 7) ──
  const recentWorkouts = last7d.slice(0, 7).map((l) => ({
    date: (l.workout_date as string)?.split("T")[0] ?? "",
    type: (l.workout_type as string) ?? "unknown",
    miles: Math.round(((l.workout_distance_miles as number) || 0) * 10) / 10,
    pace: (l.workout_pace_per_mile as string) ?? null,
    mood: (l.mood as string) ?? null,
  }));

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

  // ── Latest check-in data ──
  const lastCheckIn = checkIns[0];
  const lastReadiness = lastCheckIn?.extracted_data?.readiness_score as number ?? null;

  // ── Build the state ──
  const state: AthleteState = {
    user_id: userId,
    experience_level: profile?.experience_level ?? null,
    current_phase: plan ? "active" : "off_season", // TODO: derive from plan week position
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
    runs_last_7d: last7d.length,
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

    pace_zones: paceZones,

    recent_training_summary: recentTrainingSummary,
    recent_workouts: recentWorkouts,

    today_workout: todayWorkout,
    upcoming_workouts: upcomingWorkouts,
    week_compliance_pct: null, // TODO: compute

    last_updated_at: new Date().toISOString(),
    last_updated_by: "rebuild",
    version: 1,
  };

  // Upsert the state
  await supabase
    .from("athlete_state")
    .upsert(state, { onConflict: "user_id" });

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
  if (state.goal_race) lines.push(`Goal: ${state.goal_race}${state.goal_time_seconds ? ` in ${formatTime(state.goal_time_seconds)}` : ""}`);

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
  if (state.pace_zones && Object.keys(state.pace_zones).length > 0) {
    const z = state.pace_zones;
    lines.push(`\nTraining pace zones (USE THESE — do not calculate or invent paces):`);
    if (z.recovery) lines.push(`  Recovery: ${formatPace(z.recovery)}/mi`);
    if (z.easy) lines.push(`  Easy: ${formatPace(z.easy)}/mi`);
    if (z.longRun) lines.push(`  Long Run: ${formatPace(z.longRun)}/mi`);
    if (z.moderate) lines.push(`  Moderate: ${formatPace(z.moderate)}/mi`);
    if (z.steady) lines.push(`  Steady: ${formatPace(z.steady)}/mi`);
    if (z.mp) lines.push(`  Marathon Pace: ${formatPace(z.mp)}/mi`);
    if (z.hm) lines.push(`  Half Marathon / Tempo / Threshold: ${formatPace(z.hm)}/mi`);
    if (z.tenK) lines.push(`  10K Pace: ${formatPace(z.tenK)}/mi`);
    if (z.fiveK) lines.push(`  5K Pace / Intervals: ${formatPace(z.fiveK)}/mi`);
  }

  // Vibe
  if (state.last_mood) {
    lines.push(`\nRecent vibe: ${state.last_mood}${state.last_readiness_score ? ` (readiness ${state.last_readiness_score}/10)` : ""}`);
    if (state.mood_trend) lines.push(`Mood trend: ${state.mood_trend}`);
  }

  // Injuries
  if (state.active_injuries.length > 0) {
    lines.push(`\n⚠ Active injuries: ${state.active_injuries.map((i) => `${i.body_area} (${i.status}, severity ${i.severity})`).join(", ")}`);
  }
  if (state.injury_risk_score && state.injury_risk_score >= 3) {
    lines.push(`Injury risk: ${state.injury_risk_score}/10`);
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

  // Recent workouts
  if (state.recent_workouts.length > 0) {
    lines.push("\nRecent runs:");
    for (const w of state.recent_workouts.slice(0, 5)) {
      lines.push(`  ${w.date}: ${w.type} ${w.miles}mi${w.pace ? ` @ ${w.pace}` : ""}${w.mood ? ` [${w.mood}]` : ""}`);
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
