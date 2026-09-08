/**
 * Assembling a WatchContext from athlete_state.
 *
 * The watches are pure and read a narrow structural context; this is the one
 * place that knows how to get there from the assembled brain. Keeping the
 * mapping here means a watch never learns the shape of `athlete_state`, and
 * `athlete_state` never learns that watches exist.
 *
 * Everything here degrades to null rather than guessing. A watch that gets
 * null reports a gap, which is the honest outcome — the alternative is a
 * confident reading built on a default the athlete never earned.
 */

import { deriveAveragePace, parsePaceSec } from "../context.ts";
import type { WatchContext } from "./types.ts";

/**
 * Workout types that count as a genuinely easy day.
 *
 * Long runs are excluded on purpose. They are not easy days — they carry
 * their own pace band and their own intent, and folding them in would flag
 * every athlete whose long run sits above easy pace, which is most of them.
 */
const EASY_RUN_TOKENS: readonly string[] = [
  "easy",
  "recovery",
  "shakeout",
  "aerobic",
  "base",
];

/**
 * Types whose pace targets matter enough that a niggle should hold them.
 * Mirrors QUALITY_WORKOUT_TOKENS in rules/types.ts, minus the long-run
 * entries — a niggle holds a rep session sooner than it holds a long run.
 */
const QUALITY_TOKENS: readonly string[] = [
  "tempo",
  "threshold",
  "interval",
  "intervals",
  "repeat",
  "repeats",
  "race",
  "time_trial",
  "progression",
  "marathon_pace",
];

function hasToken(value: string | null | undefined, tokens: readonly string[]): boolean {
  if (!value) return false;
  const v = value.toLowerCase();
  return tokens.some((t) => v.includes(t));
}

/**
 * Pace strings arrive in several shapes across the codebase — "8:30",
 * "8:30/mi", occasionally padded. Normalize, then delegate to the existing
 * parser rather than adding a third pace implementation to this repo.
 */
export function paceStringToSec(s: string | null | undefined): number | null {
  if (!s) return null;
  const cleaned = s.trim().replace(/\s*\/\s*mi(le)?$/i, "").trim();
  return parsePaceSec(cleaned);
}

/** Whole days from `now` to an ISO date, negative for the past. */
function daysUntil(iso: string, now: Date): number | null {
  const t = Date.parse(iso.length === 10 ? `${iso}T00:00:00Z` : iso);
  if (Number.isNaN(t)) return null;
  return Math.round((t - now.getTime()) / 86_400_000);
}

// ─── The slice of athlete_state watches need ────────────────────────────────

export interface WatchStateInput {
  user_id: string;
  recent_workouts?: Array<{
    date: string;
    type?: string | null;
    mood?: string | null;
    pace?: string | null;
    work_pace?: string | null;
    /**
     * Distance and duration, for deriving pace when the stored pace string is
     * null. On real data this is not an edge case: of 87 easy/recovery runs
     * in one athlete's last 75 days, 2 carried `workout_pace_per_mile` and 86
     * carried distance + duration. Ignoring these drops the watch to blind on
     * an athlete whose data is entirely present.
     */
    distance_miles?: number | null;
    duration_minutes?: number | null;
  }> | null;
  load_distribution?: {
    zone_pct_7d?: { easy: number; moderate: number; threshold: number; hard: number } | null;
    zone_pct_28d?: { easy: number; moderate: number; threshold: number; hard: number } | null;
  } | null;
  pace_zone_ranges?: {
    easy?: { paceFast: number; paceSlow: number } | null;
    moderate?: { paceFast: number; paceSlow: number } | null;
  } | null;
  niggle_recurrence?: WatchContext["niggles"];
  upcoming_workouts?: Array<Record<string, unknown>> | null;
}

/**
 * Nearest upcoming quality session, in days. Null when nothing qualifies or
 * the scheduled rows don't carry a readable date/type.
 *
 * `upcoming_workouts` is typed as loose records in athlete_state, so every
 * field access here is defensive by necessity.
 */
export function nextQualityWithinDays(
  upcoming: Array<Record<string, unknown>> | null | undefined,
  now: Date,
): number | null {
  if (!upcoming?.length) return null;
  let nearest: number | null = null;

  for (const w of upcoming) {
    const type = typeof w.workout_type === "string"
      ? w.workout_type
      : typeof w.type === "string"
      ? w.type
      : null;
    if (!hasToken(type, QUALITY_TOKENS)) continue;

    const dateRaw = typeof w.date === "string"
      ? w.date
      : typeof w.workout_date === "string"
      ? w.workout_date
      : null;
    if (!dateRaw) continue;

    const d = daysUntil(dateRaw, now);
    if (d === null || d < 0) continue; // already past
    if (nearest === null || d < nearest) nearest = d;
  }
  return nearest;
}

/**
 * Build the context every watch reads.
 *
 * `now` is injected rather than read from the clock so a sweep is
 * reproducible and the whole layer stays unit-testable.
 */
export function buildWatchContext(
  state: WatchStateInput,
  now: Date,
): WatchContext {
  const recent = state.recent_workouts ?? [];

  // Mood: every logged workout that carried a label. Newest-first is the
  // convention upstream, but the watches sort by age themselves, so order
  // here is not load-bearing.
  const moodHistory = recent
    .filter((w) => w.date)
    .map((w) => ({ date: w.date, mood: w.mood ?? null }));

  // Easy runs: genuinely easy types only, with a parseable pace. `work_pace`
  // is preferred wherever it exists — on anything with structure, average
  // pace is a blend of work and recovery and means very little.
  const easyRuns = recent
    .filter((w) => w.date && hasToken(w.type, EASY_RUN_TOKENS))
    .map((w) => ({
      date: w.date,
      // Preference order: parsed work pace, stored average, then derived from
      // distance and duration. The derivation is the one that actually carries
      // most real rows — see the note on distance_miles above.
      paceSecPerMile: paceStringToSec(w.work_pace) ??
        paceStringToSec(w.pace) ??
        deriveAveragePace(w.distance_miles ?? null, w.duration_minutes ?? null),
      workoutType: w.type ?? "easy",
      distanceMiles: w.distance_miles ?? null,
    }))
    .filter((w) => w.paceSecPerMile !== null);

  const band = (
    z: { paceFast?: number; paceSlow?: number } | null | undefined,
  ): { paceFast: number; paceSlow: number } | null =>
    z && typeof z.paceFast === "number" && typeof z.paceSlow === "number"
      ? { paceFast: z.paceFast, paceSlow: z.paceSlow }
      : null;

  const easyBand = band(state.pace_zone_ranges?.easy);
  const moderateBand = band(state.pace_zone_ranges?.moderate);

  return {
    athleteUserId: state.user_id,
    now,
    moodHistory,
    zonePct7d: state.load_distribution?.zone_pct_7d ?? null,
    zonePct28d: state.load_distribution?.zone_pct_28d ?? null,
    easyBand,
    moderateBand,
    easyRuns,
    niggles: state.niggle_recurrence ?? null,
    upcomingQualityWithinDays: nextQualityWithinDays(state.upcoming_workouts, now),
  };
}
