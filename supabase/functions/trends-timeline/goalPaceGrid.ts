/**
 * Goal-pace laps — every lap the watch recorded, as the watch recorded it,
 * measured against goal race pace.
 *
 * THE UNIT IS THE WATCH LAP, NOT THE PARSER'S BLOCK (2026-09-08, Rio: "you
 * keep trying to figure out the 'parsed' workout and totally mess it up").
 * The previous version of this module deposited one mark per
 * `parsed_structure.blocks[]` entry. On a clean 4 × 1 mi with quarter-mile
 * jogs (log `1e99591a`, 2026-09-08: 5:24 · 5:28 · 5:44 · 5:42) the parser
 * swallowed the jog between miles 2 and 3 and emitted one 2.25 mi block at
 * 5:42, so the athlete's four specific miles were unrecoverable before the
 * client ever saw them. The same rule already governs every effort chart in
 * the app (`WorkoutRepChart`, 2026-09-08): split geometry on a visual is the
 * watch's laps. Nothing here joins two laps, averages a session, or asks a
 * classifier what a lap was for.
 *
 * Source: `training_logs.pace_segments` — `distance_miles` and
 * `duration_seconds` per lap, in recorded order. Pace is duration / distance,
 * never the segment's `pace_per_mile` string (a display field). Segment
 * `label`s are classifier output and are ignored entirely — see
 * `feedback_no_pace_segment_labels_as_fitness_signal`.
 *
 * SESSIONS. Only KEY SESSIONS AND LONG RUNS deposit (2026-09-08, Rio:
 * "ideally this would be for key sessions and long runs"). Key is the one
 * shared definition, `_shared/sessions.ts:isQuality` — threshold, intervals,
 * fartlek, progression, long_wo, race; long is `long_run` / `long_wo`. Easy,
 * recovery, moderate and steady runs are counted in `summary.total_miles`
 * and never drawn. This is also what keeps warm-up and cool-down jogs off
 * the chart for an athlete who logs them as separate recovery runs.
 *
 * FLOOR, PER SESSION KIND. Within those sessions, only laps at or above a
 * floor ship. Long runs (`long_run`, `long_wo`) use `LONG_FLOOR_PCT` = 75%
 * so a long-run mile at 6:30 against a 5:20 goal (82%) is drawn where it
 * belongs. Every other key session uses `KEY_FLOOR_PCT` = 85%, which is
 * what keeps the quarter-mile jogs between interval reps (~81%) out of the
 * chart and out of the day's readout — the athlete asked for the specific
 * miles, and "5:24 · 6:28 · 5:28 · 6:36" is not that. Laps under the floor
 * are counted in `summary.session_miles`, just not drawn. A lap qualifies
 * if EITHER its raw or its heat-adjusted percent clears the floor, so
 * toggling heat on the client can only reposition marks, never conjure one.
 *
 * WHOLE-SESSION FALLBACK. A log with no `pace_segments` at all (53 of one
 * athlete's 291 logs, 115 miles — mostly manual entries) still has a
 * distance and a duration. That is one honest number, so it becomes one
 * deposit with `lap_index: null`, subject to the same floor. It is never
 * split into invented laps.
 *
 * HEAT. Every deposit carries `pct_of_goal` and `pct_of_goal_heat_adj`. Raw
 * is never replaced, the goal never moves; only the credited-for-conditions
 * pace differs. See `_shared/pace-heat-adjustment.ts`.
 *
 * Pure: no IO. See `goalPaceGrid.test.ts`.
 */

import { heatNeutralPace, isBeyondChart } from "../_shared/pace-heat-adjustment.ts";
import { isQuality, normalizeWorkoutType } from "../_shared/sessions.ts";

/** Floor for key sessions that are not long runs — cuts the recovery jogs. */
export const KEY_FLOOR_PCT = 85;
/** Floor for long runs — a 6:30 mile against a 5:20 goal is real evidence. */
export const LONG_FLOOR_PCT = 75;
/** The slowest anything drawn can be; the chart's y-axis bottom. */
export const PLOT_FLOOR_PCT = Math.min(KEY_FLOOR_PCT, LONG_FLOOR_PCT);

function isLongSession(workoutType: string | null): boolean {
  const n = normalizeWorkoutType(workoutType);
  return n === "long_run" || n === "long_wo";
}

/** The population: key sessions and long runs. Everything else is context. */
export function isGoalPaceSession(workoutType: string | null): boolean {
  return isQuality(workoutType) || isLongSession(workoutType);
}

/** Below ~80m a "lap" is a traffic-light stop or GPS drift, not running. */
const MIN_LAP_MILES = 0.05;

export interface GoalPaceLapSegment {
  distance_miles?: number | string | null;
  duration_seconds?: number | string | null;
}

export interface GoalPaceGridLog {
  id: string;
  workout_date: string;
  workout_type: string | null;
  workout_distance_miles?: number | null;
  workout_duration_minutes?: number | null;
  pace_segments?: GoalPaceLapSegment[] | null;
}

export interface SessionWeather {
  temp_f: number | null;
  dew_point_f: number | null;
}

export interface GoalPaceDeposit {
  workout_id: string;
  date: string;
  workout_type: string | null;
  /** Position in the watch's lap list. Null for a whole-session fallback. */
  lap_index: number | null;
  miles: number;
  pace_sec: number;
  pace_sec_heat_adj: number;
  pct_of_goal: number;
  pct_of_goal_heat_adj: number;
  is_key: boolean;
  is_long: boolean;
  /** COMPAT (2026-09-08): the previous client build decodes these as
   *  required keys. Nothing new reads them; drop once no installed build
   *  predates the lap redesign. */
  pace_row: number;
  pace_row_heat_adj: number;
}

/** COMPAT: 5-point bands from 115%+ down to <75%, as the old client expects. */
const COMPAT_ROW_LABELS = [
  "115%+", "110–115", "105–110", "100–105", "95–100",
  "90–95", "85–90", "80–85", "75–80", "<75%",
] as const;
function compatRowOf(pct: number): number {
  const thresholds = [115, 110, 105, 100, 95, 90, 85, 80, 75];
  for (let i = 0; i < thresholds.length; i++) if (pct >= thresholds[i]) return i;
  return thresholds.length;
}

export interface GoalPaceGridOut {
  goal: {
    race_key: string;
    time_seconds: number;
    pace_sec_per_mile: number;
    source: string;
    /** ISO date, when known. Null goals still render — the chart just has no
     *  right edge to draw the runway against. */
    race_date: string | null;
  };
  /** The chart's y-axis bottom: the slower of the two floors below. */
  floor_pct: number;
  /** Floor applied to key sessions that are not long runs. */
  key_floor_pct: number;
  /** Floor applied to long runs (`long_run`, `long_wo`). */
  long_floor_pct: number;
  /** COMPAT — see GoalPaceDeposit. */
  row_labels: readonly string[];
  deposits: GoalPaceDeposit[];
  summary: {
    /** Every logged mile in the window, any session type. */
    total_miles: number;
    /** Miles logged in key sessions and long runs — the population. */
    session_miles: number;
    /** Miles that shipped as deposits. */
    plotted_miles: number;
    /** total − plotted: everything not drawn, for the footer. */
    unplotted_miles: number;
    /** Miles within ±5% of goal, raw pace. */
    near_goal_miles: number;
    near_goal_pct: number;
    lap_count: number;
    plotted_lap_count: number;
    /** COMPAT — always 0; the lenses they fed are gone. */
    key_miles: number;
    long_miles: number;
  };
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
function round1(n: number): number {
  return Math.round(n * 10) / 10;
}
function num(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? v : null;
  if (typeof v === "string" && v.trim() !== "") {
    const n = Number(v);
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/**
 * @param logs          every log in the window, with `pace_segments`
 * @param goal          resolved goal, including race_date when known
 * @param weatherByLog  per-session temp + dew point, for the heat column
 */
export function buildGoalPaceGrid(
  logs: GoalPaceGridLog[],
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
  let totalMiles = 0;
  let sessionMilesTotal = 0;
  let plottedMiles = 0;
  let nearMiles = 0;
  let lapCount = 0;

  for (const log of logs) {
    const logMiles = num(log.workout_distance_miles) ?? 0;
    if (!isGoalPaceSession(log.workout_type)) {
      // Counted so the footer can say how much running is not in view;
      // never a deposit.
      if (logMiles > 0) totalMiles += logMiles;
      continue;
    }
    const isKey = isQuality(log.workout_type);
    const isLong = isLongSession(log.workout_type);
    const floor = isLong ? LONG_FLOOR_PCT : KEY_FLOOR_PCT;
    const wx = weatherByLog?.get(log.id);
    const hasWeather = !!wx && wx.temp_f != null && wx.dew_point_f != null &&
      !isBeyondChart(wx.temp_f, wx.dew_point_f);

    const consider = (
      lapIndex: number | null,
      miles: number,
      paceSec: number,
    ) => {
      lapCount += 1;
      const adjSec = hasWeather
        ? heatNeutralPace(paceSec, wx!.temp_f!, wx!.dew_point_f!, null)
        : paceSec;
      const pct = (goal.pace_sec_per_mile / paceSec) * 100;
      const pctAdj = (goal.pace_sec_per_mile / adjSec) * 100;
      if (pct >= 95 && pct <= 105) nearMiles += miles;
      if (pct < floor && pctAdj < floor) return;
      plottedMiles += miles;
      deposits.push({
        workout_id: log.id,
        date: log.workout_date,
        workout_type: log.workout_type,
        lap_index: lapIndex,
        miles: round2(miles),
        pace_sec: Math.round(paceSec),
        pace_sec_heat_adj: Math.round(adjSec),
        pct_of_goal: round1(pct),
        pct_of_goal_heat_adj: round1(pctAdj),
        is_key: isKey,
        is_long: isLong,
        pace_row: compatRowOf(pct),
        pace_row_heat_adj: compatRowOf(pctAdj),
      });
    };

    const segs = Array.isArray(log.pace_segments) ? log.pace_segments : [];
    let lapMiles = 0;
    let sawLap = false;
    segs.forEach((s, i) => {
      const miles = num(s?.distance_miles);
      const secs = num(s?.duration_seconds);
      if (miles == null || secs == null || miles < MIN_LAP_MILES || secs <= 0) return;
      sawLap = true;
      lapMiles += miles;
      consider(i, miles, secs / miles);
    });

    const sessionMiles = num(log.workout_distance_miles) ?? 0;
    const sessionMins = num(log.workout_duration_minutes) ?? 0;

    if (!sawLap) {
      // No laps at all: the session is one honest number, or nothing.
      if (sessionMiles >= MIN_LAP_MILES && sessionMins > 0) {
        totalMiles += sessionMiles;
        sessionMilesTotal += sessionMiles;
        consider(null, sessionMiles, (sessionMins * 60) / sessionMiles);
      }
      continue;
    }

    // The watch's laps are the geometry; the session total is the mileage
    // of record. When they disagree the total wins for COUNTING (so the
    // footer never under-reports a run), but no mark is invented for the
    // difference — a mile that has no lap has no pace worth plotting.
    const counted = Math.max(sessionMiles, lapMiles);
    totalMiles += counted;
    sessionMilesTotal += counted;
  }

  if (lapCount === 0) return null;

  deposits.sort((a, b) =>
    a.date.localeCompare(b.date) || (a.lap_index ?? -1) - (b.lap_index ?? -1)
  );

  const plottedLapCount = deposits.length;
  return {
    goal,
    floor_pct: PLOT_FLOOR_PCT,
    key_floor_pct: KEY_FLOOR_PCT,
    long_floor_pct: LONG_FLOOR_PCT,
    row_labels: COMPAT_ROW_LABELS,
    deposits,
    summary: {
      total_miles: round2(totalMiles),
      session_miles: round2(sessionMilesTotal),
      plotted_miles: round2(plottedMiles),
      unplotted_miles: round2(Math.max(0, totalMiles - plottedMiles)),
      near_goal_miles: round2(nearMiles),
      near_goal_pct: totalMiles > 0 ? round1((nearMiles / totalMiles) * 100) : 0,
      lap_count: lapCount,
      plotted_lap_count: plottedLapCount,
      key_miles: 0,
      long_miles: 0,
    },
  };
}
