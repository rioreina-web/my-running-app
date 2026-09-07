/**
 * Goal-pace grid — every BLOCK of every candidate session, plotted by how
 * close its pace was to goal race pace and how many miles it carried.
 *
 * REPLACES the single-number-per-session model in `goalPace.ts`. That model
 * broke on any workout with more than one pace in it: a 2mi warm-up + 16mi at
 * MP + 2mi cool-down averaged to one mediocre number instead of showing 16
 * miles of goal-pace work. This module never averages a workout — a session
 * with three paces in it deposits into three rows.
 *
 * THE UNIT IS THE BLOCK, NOT THE SESSION. Every `parsed_structure.blocks[]`
 * entry with role other than `recovery` is one deposit: its own distance, its
 * own pace, its own percent of goal. `role: 'steady'` is INCLUDED — an earlier
 * version of the single-number model (`readFloatLegs`) excluded `steady`
 * blocks from continuous-mile totals, which silently dropped whole sessions
 * (a 14-mile steady threshold run, two races) that had no `work_rep` block at
 * all. This module has no such gate: every non-recovery mile counts.
 *
 * SESSION SELECTION. Every logged session participates — there is no
 * candidate-type gate. An easy or recovery run with no internal structure
 * still produced one deterministic block covering its full distance/pace
 * (`parse-workout-structure`'s `mergeToSingleBout`), so excluding it wasn't
 * protecting against bad data, it was just hiding real training: a prior
 * version gated on `isQuality` OR `long_run` and silently dropped 160 of one
 * athlete's 204 logged runs in a single 20-week window. Each deposit still
 * carries `is_key` (`_shared/sessions.ts:isQuality` — threshold, intervals,
 * fartlek, progression, long_wo, race) and `is_long` flags so the client can
 * slice by either lens (or both — `long_wo` is genuinely both) without a
 * second round trip, but inclusion in "all" no longer depends on either.
 *
 * PACE ROWS. Ten bands of 5 percentage points from 115%+ down to <75%, each
 * band spanning [v, v+5). This is a plain "largest threshold the value
 * clears" search over a DESCENDING threshold list, checked in descending
 * order — get the iteration direction wrong and every value between the
 * extremes collapses into one row. That exact bug shipped in the HTML
 * prototype this module replaces (ascending threshold order but returning on
 * first match), which is why `goalPaceGrid.test.ts` pins the boundary of every
 * band explicitly rather than trusting a handful of examples.
 *
 * HEAT. Every deposit carries pct_of_goal and pct_of_goal_heat_adj, same
 * invariant as the session-level model: raw is never replaced, the goal never
 * moves, only credited-for-conditions paces do. See `_shared/pace-heat-adjustment.ts`.
 *
 * Pure: no IO. Callers hand in logs, their parsed blocks, the goal and the
 * athlete's MP. See `goalPaceGrid.test.ts`.
 */

import { paceStringToSeconds } from "../_shared/floatLegs.ts";
import { isQuality, normalizeWorkoutType } from "../_shared/sessions.ts";
import { heatNeutralPace, isBeyondChart } from "../_shared/pace-heat-adjustment.ts";

/** Descending thresholds. Row i spans [PACE_ROW_THRESHOLDS[i], next one up). */
export const PACE_ROW_THRESHOLDS = [115, 110, 105, 100, 95, 90, 85, 80, 75] as const;

/** One row per threshold, plus a catch-all "<75%" row at the end. */
export const PACE_ROW_LABELS = [
  "115%+", "110–115", "105–110", "100–105", "95–100",
  "90–95", "85–90", "80–85", "75–80", "<75%",
] as const;

/**
 * The row index for a percent-of-goal value. Bands are [threshold, next
 * higher threshold) — e.g. 93.5 lands in the 90–95 row (index 5), not the
 * 75–80 row. Iterates thresholds HIGH TO LOW and returns on first clear,
 * which is the only direction that finds the LARGEST threshold a value
 * clears rather than the smallest.
 */
export function paceRowOf(pctOfGoal: number): number {
  for (let i = 0; i < PACE_ROW_THRESHOLDS.length; i++) {
    if (pctOfGoal >= PACE_ROW_THRESHOLDS[i]) return i;
  }
  return PACE_ROW_THRESHOLDS.length; // catch-all "<75%" row
}

/// EVERY role counts, recovery included (2026-09-01). A jog between two reps
/// is still real mileage run at a real pace, and excluding it made the map
/// under-report volume by ~61 miles over 27 weeks on one athlete. It lands in
/// the slow bands where it belongs rather than vanishing. The only thing that
/// still drops a block is the 0.05mi noise floor below.
const ROLES_COUNTED = new Set([
  "work_rep",
  "steady",
  "warmup",
  "cooldown",
  "recovery",
]);

function isLongSession(workoutType: string | null): boolean {
  const n = normalizeWorkoutType(workoutType);
  return n === "long_run" || n === "long_wo";
}

export interface GoalPaceGridLog {
  id: string;
  workout_date: string;
  workout_type: string | null;
  /** Whole-session totals, used ONLY as the no-blocks fallback below. */
  workout_distance_miles?: number | null;
  workout_duration_minutes?: number | null;
}

export interface SessionWeather {
  temp_f: number | null;
  dew_point_f: number | null;
}

export interface GoalPaceDeposit {
  workout_id: string;
  date: string;
  workout_type: string | null;
  miles: number;
  pace_sec: number;
  pace_sec_heat_adj: number;
  pct_of_goal: number;
  pct_of_goal_heat_adj: number;
  pace_row: number;
  pace_row_heat_adj: number;
  is_key: boolean;
  is_long: boolean;
}

export interface GoalPaceGridOut {
  goal: {
    race_key: string;
    time_seconds: number;
    pace_sec_per_mile: number;
    source: string;
    /** ISO date, when known. Null goals still render — the grid just has no
     *  right edge to draw the runway against. */
    race_date: string | null;
  };
  row_labels: readonly string[];
  deposits: GoalPaceDeposit[];
  summary: {
    total_miles: number;
    key_miles: number;
    long_miles: number;
    near_goal_miles: number;
    near_goal_pct: number;
  };
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

/**
 * @param logs            candidate + non-candidate logs; filtered internally
 * @param blocksByWorkout `parsed_structure.blocks` per workout id
 * @param goal            resolved goal, including race_date when known
 * @param mpSecPerMile    unused today; kept for signature parity with the
 *                        session-level model in case a future band needs it
 */
export function buildGoalPaceGrid(
  logs: GoalPaceGridLog[],
  blocksByWorkout: Map<string, unknown[]>,
  goal: {
    race_key: string;
    time_seconds: number;
    pace_sec_per_mile: number;
    source: string;
    race_date: string | null;
  },
  weatherByLog?: Map<string, SessionWeather>,
): GoalPaceGridOut | null {
  if (!(goal.pace_sec_per_mile > 0)) return null;

  const deposits: GoalPaceDeposit[] = [];

  // Every logged session participates now — an easy or recovery run with no
  // internal structure still produced one deterministic block covering its
  // full distance/pace (see parse-workout-structure's mergeToSingleBout), so
  // there is no real gap to gate on. Excluding "non-quality" types here was
  // what made the grid feel like it was hiding real training: 160 of an
  // athlete's 204 logged runs in one 20-week window (easy + recovery +
  // steady) never appeared at all. `is_key`/`is_long` still carry the
  // quality/long distinction for the Key/Long filters — inclusion in "All"
  // no longer depends on it.
  for (const log of logs) {
    const blocks = blocksByWorkout.get(log.id);

    const isKey = isQuality(log.workout_type);
    const isLong = isLongSession(log.workout_type);
    const wx = weatherByLog?.get(log.id);
    const hasWeather = !!wx && wx.temp_f != null && wx.dew_point_f != null &&
      !isBeyondChart(wx.temp_f, wx.dew_point_f);

    // WHOLE-SESSION FALLBACK (2026-09-01). A run that never got parsed — the
    // structure pass never fired, or fired and correctly found no measurable
    // geometry — has no blocks to deposit, so its miles used to vanish
    // entirely: 100 of one athlete's 1565 logged miles over 27 weeks, all of
    // it real running. The log itself still knows its distance and duration,
    // which is exactly what `mergeToSingleBout` would have produced upstream
    // for an unstructured run, so synthesize that one block here rather than
    // drop the session. Deliberately NOT a guess: if there is no distance or
    // no duration there is no pace, and nothing is invented.
    if (!Array.isArray(blocks) || blocks.length === 0) {
      const miles = Number(log.workout_distance_miles ?? 0);
      const mins = Number(log.workout_duration_minutes ?? 0);
      if (miles >= 0.05 && mins > 0) {
        const paceSec = (mins * 60) / miles;
        const adjSec = hasWeather
          ? heatNeutralPace(paceSec, wx!.temp_f!, wx!.dew_point_f!, null)
          : paceSec;
        const pct = (goal.pace_sec_per_mile / paceSec) * 100;
        const pctAdj = (goal.pace_sec_per_mile / adjSec) * 100;
        deposits.push({
          workout_id: log.id,
          date: log.workout_date,
          workout_type: log.workout_type,
          miles: round2(miles),
          pace_sec: Math.round(paceSec),
          pace_sec_heat_adj: Math.round(adjSec),
          pct_of_goal: round1(pct),
          pct_of_goal_heat_adj: round1(pctAdj),
          pace_row: paceRowOf(pct),
          pace_row_heat_adj: paceRowOf(pctAdj),
          is_key: isKey,
          is_long: isLong,
        });
      }
      continue;
    }

    let countedMiles = 0;
    for (const raw of blocks) {
      const b = raw as {
        role?: string;
        distance_miles?: number;
        avg_pace_per_mile?: string | null;
      };
      if (!b || !ROLES_COUNTED.has(b.role ?? "")) continue;
      const miles = Number(b.distance_miles ?? 0);
      // Below ~80m a "block" is a traffic-light stop or GPS drift, not a
      // training segment — the widened session set (2026-09-01) surfaced 25
      // of these on one athlete's 20-week window, several implying paces
      // like 55:00/mi. A real short rep (100m strides) still clears this;
      // recording noise does not.
      if (!(miles >= 0.05)) continue;
      const paceSec = paceStringToSeconds(b.avg_pace_per_mile);
      if (paceSec == null) continue;

      const adjSec = hasWeather
        ? heatNeutralPace(paceSec, wx!.temp_f!, wx!.dew_point_f!, null)
        : paceSec;

      const pct = (goal.pace_sec_per_mile / paceSec) * 100;
      const pctAdj = (goal.pace_sec_per_mile / adjSec) * 100;

      deposits.push({
        workout_id: log.id,
        date: log.workout_date,
        workout_type: log.workout_type,
        miles: round2(miles),
        pace_sec: Math.round(paceSec),
        pace_sec_heat_adj: Math.round(adjSec),
        pct_of_goal: round1(pct),
        pct_of_goal_heat_adj: round1(pctAdj),
        pace_row: paceRowOf(pct),
        pace_row_heat_adj: paceRowOf(pctAdj),
        is_key: isKey,
        is_long: isLong,
      });
      countedMiles += miles;
    }

    // REMAINDER (2026-09-01). A parsed session's blocks routinely do not add
    // up to the distance the watch recorded for it — the segmenter assigns
    // reps and recoveries but leaves the connecting running unassigned, and a
    // standing-rest block carries distance with pace "—" that can't be
    // placed. That was 44 miles across 28 logs on one athlete: real running,
    // in no block, invisible. Deposit the difference at the SESSION's own
    // average pace, which is the only honest pace available for miles whose
    // individual splits were never resolved.
    const sessionMiles = Number(log.workout_distance_miles ?? 0);
    const sessionMins = Number(log.workout_duration_minutes ?? 0);
    const remainder = sessionMiles - countedMiles;
    if (remainder >= 0.05 && sessionMiles > 0 && sessionMins > 0) {
      const paceSec = (sessionMins * 60) / sessionMiles;
      const adjSec = hasWeather
        ? heatNeutralPace(paceSec, wx!.temp_f!, wx!.dew_point_f!, null)
        : paceSec;
      const pct = (goal.pace_sec_per_mile / paceSec) * 100;
      const pctAdj = (goal.pace_sec_per_mile / adjSec) * 100;
      deposits.push({
        workout_id: log.id,
        date: log.workout_date,
        workout_type: log.workout_type,
        miles: round2(remainder),
        pace_sec: Math.round(paceSec),
        pace_sec_heat_adj: Math.round(adjSec),
        pct_of_goal: round1(pct),
        pct_of_goal_heat_adj: round1(pctAdj),
        pace_row: paceRowOf(pct),
        pace_row_heat_adj: paceRowOf(pctAdj),
        is_key: isKey,
        is_long: isLong,
      });
    }
  }

  if (deposits.length === 0) return null;
  deposits.sort((a, b) => a.date.localeCompare(b.date));

  let total = 0, key = 0, long = 0, near = 0;
  for (const d of deposits) {
    total += d.miles;
    if (d.is_key) key += d.miles;
    if (d.is_long) long += d.miles;
    if (d.pct_of_goal >= 95 && d.pct_of_goal <= 105) near += d.miles;
  }

  return {
    goal,
    row_labels: PACE_ROW_LABELS,
    deposits,
    summary: {
      total_miles: round2(total),
      key_miles: round2(key),
      long_miles: round2(long),
      near_goal_miles: round2(near),
      near_goal_pct: total > 0 ? round1((near / total) * 100) : 0,
    },
  };
}
