/**
 * Typed reader for the `athlete_state` fields the analyzers wrap.
 *
 * WHY READ STATE RATHER THAN RECOMPUTE. `athlete_state` is already the app's
 * computed layer — `fitness_prediction`, `fitness_signal`, `niggle_recurrence`
 * and friends are built by the state builders and are what every other surface
 * (Trends, the Daily Read) displays. An analyzer that recomputed them from raw
 * rows would be a second implementation of a number the athlete already sees,
 * and the two would drift. Reading state means **Ask can never disagree with
 * the Trends tile.**
 *
 * The exceptions are `zone_trend` and `compare_session`, which need per-session
 * detail that state doesn't carry, so they go to the laps.
 *
 * Every field here is optional and defensively parsed. `athlete_state` is
 * rebuilt asynchronously and a field can legitimately be null for a new
 * athlete — that must produce an honest empty state, never a zero.
 */

import type { SupabaseLike } from "./types.ts";

// ── Shapes, as actually stored (verified against prod 2026-08-07) ──

export interface PredictionRange {
  low?: number | null;
  high?: number | null;
  point?: number | null;
}

/**
 * The exact keys `athlete-state.ts` writes into `fitness_prediction.ranges`.
 *
 * Spelled out rather than `Record<string, …>` because an open index cannot
 * catch a typo: `currentFitness` read `ranges["10k"]` against stored `"10K"`
 * for its whole first day in production and silently rendered no capacity at
 * all — a lowercase miss that compiled fine. Keep this union in lockstep with
 * the writer (athlete-state.ts, the `fitnessPrediction` literal).
 */
export type RaceRangeKey = "mile" | "5K" | "10K" | "half" | "marathon";

export interface FitnessPrediction {
  ranges?: Partial<Record<RaceRangeKey, PredictionRange | null>> | null;
  workout_count?: number | null;
  confidence_tier?: string | null;
}

export interface EfficiencyBucket {
  bucket?: string | null; // "easy" | "threshold" | "interval"
  direction?: string | null; // "improving" | "flat" | "declining"
  ef_recent?: number | null;
  ef_baseline?: number | null;
  ef_delta_pct?: number | null;
  hr_recent?: number | null;
  hr_baseline?: number | null;
  pace_recent_sec?: number | null;
  pace_baseline_sec?: number | null;
  recent_samples?: number | null;
  baseline_samples?: number | null;
  baseline_days?: number | null;
  confidence?: string | null;
}

export interface DecouplingBlock {
  direction?: string | null;
  recent_pct?: number | null;
  baseline_pct?: number | null;
  recent_samples?: number | null;
  baseline_samples?: number | null;
}

export interface FitnessSignal {
  verdict?: string | null;
  confidence?: string | null;
  decoupling?: DecouplingBlock | null;
  efficiency?: EfficiencyBucket[] | null;
  window_days?: number | null;
}

export interface NiggleRecurrence {
  body_area?: string | null;
  side?: string | null;
  first_seen?: string | null;
  last_seen?: string | null;
  occurrences?: number | null;
  worst_severity?: string | null;
}

export interface ActiveGoal {
  title?: string | null;
  target_date?: string | null;
  days_until?: number | null;
}

export interface AthleteStateRow {
  goal_race: string | null;
  goal_time_seconds: number | null;
  last_mood: string | null;
  mood_trend: string | null;
  data_depth: number | null;
  fitness_prediction: FitnessPrediction | null;
  fitness_signal: FitnessSignal | null;
  niggle_recurrence: NiggleRecurrence[] | null;
  active_goals: ActiveGoal[] | null;
  confirmed_races: unknown;
  pace_zones: Record<string, unknown> | null;
}

const STATE_COLUMNS =
  "goal_race, goal_time_seconds, last_mood, mood_trend, data_depth, fitness_prediction, fitness_signal, niggle_recurrence, active_goals, confirmed_races, pace_zones";

export async function fetchAthleteState(
  supabase: SupabaseLike,
  userId: string,
): Promise<AthleteStateRow | null> {
  const { data } = await supabase
    .from("athlete_state")
    .select(STATE_COLUMNS)
    .eq("user_id", userId)
    .maybeSingle();
  return (data ?? null) as AthleteStateRow | null;
}

// ── Helpers ──────────────────────────────────────────────────────

/** Seconds → "3:21" for race times ≥ an hour, "18:22" below. */
export function fmtRaceTime(totalSeconds: number, roundToMinute: boolean): string {
  const s = roundToMinute ? Math.round(totalSeconds / 60) * 60 : Math.round(totalSeconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}`;
  return `${m}:${String(sec).padStart(2, "0")}`;
}

/**
 * Hard rule #7: marathon and half are rounded to the whole minute. Shorter
 * races keep their seconds — a 5K projection to the minute would be useless.
 */
export function roundsToMinute(raceKey: string): boolean {
  const k = raceKey.toLowerCase();
  return k === "marathon" || k === "half" || k === "half_marathon";
}

/** Canonical distances in miles, for turning a goal time into a goal pace. */
export const RACE_DISTANCE_MILES: Record<string, number> = {
  mile: 1,
  "5k": 3.10686,
  "10k": 6.21371,
  "15k": 9.32057,
  "10mile": 10,
  half: 13.1094,
  half_marathon: 13.1094,
  marathon: 26.2188,
};

export function raceDistanceMiles(raceKey: string | null | undefined): number | null {
  if (!raceKey) return null;
  const k = raceKey.toLowerCase().replace(/[\s-]/g, "_");
  return RACE_DISTANCE_MILES[k] ?? RACE_DISTANCE_MILES[k.replace("_", "")] ?? null;
}

export function raceLabel(raceKey: string): string {
  const k = raceKey.toLowerCase();
  if (k === "5k") return "5K";
  if (k === "10k") return "10K";
  if (k === "half" || k === "half_marathon") return "Half";
  if (k === "marathon") return "Marathon";
  if (k === "mile") return "Mile";
  return raceKey;
}
