/**
 * Goal-pace convergence — every key session in one currency: PERCENT OF GOAL
 * RACE PACE.
 *
 * Backs the goal-pace surface in Trends. The question is the one a goal-chasing
 * runner actually has — "is my training converging on the pace I intend to
 * race?" — and the answer only reads if past and future share a unit.
 *
 * WHY PERCENT AND NOT PACE. Raw pace makes the chart unreadable in two ways.
 * A 5:20 goal and a 7:30 easy day share no scale, so the aerobic work squashes
 * the specific work into a band. And the moment the athlete re-targets, every
 * historical point is measured against a goal that no longer exists. Percent of
 * goal SPEED fixes both: one axis, and a re-target re-prices the whole history
 * coherently because nothing is stored.
 *
 * The bands are not invented here. They are the workout library's own
 * constants (`generate-training-plan`): 80% easy, 85% moderate, 90% steady,
 * 95% the fast leg of an alternation, 100% race pace. So a session's height on
 * this chart is directly comparable to what a plan would have prescribed —
 * WITHOUT needing a plan to exist. `training_plans` may be empty.
 *
 * FLOATS COUNT. An alternation's float leg is aerobic support, not rest, so a
 * float session is reported at its AGGREGATE pace over the whole continuous
 * span rather than the pace of its fast legs alone. Classification is
 * `_shared/floatLegs.ts`, against the athlete's own MP. Getting this wrong
 * reports a 13.7-mile structured long run as 12 miles of reps.
 *
 * KEY SESSIONS ONLY — `_shared/sessions.ts:isQuality`: threshold · intervals ·
 * fartlek · progression · long_wo · race.
 *
 * NOT plain `long_run`. The taxonomy separates `long_run` ("Long run") from
 * `long_wo` ("Long run workout") deliberately, and only the second is a key
 * session. An 18-miler at 6:40 is volume; it belongs in the volume surfaces,
 * not here. An earlier build included it and the aerobic mass swamped the
 * workouts — the same failure as charting every easy run, one step subtler.
 *
 * HEAT. Every pace is carried twice: raw, and adjusted for the conditions it
 * was run in (`_shared/pace-heat-adjustment.ts`, Emy's calculator). The
 * adjusted value NEVER replaces the raw one — same invariant `paceBands.ts`
 * holds — so the surface can show the correction being applied rather than
 * silently restating the athlete's session.
 *
 * THE GOAL IS NEVER ADJUSTED. Only the sessions move. Adjust both and the
 * whole picture rescales together and the toggle appears to do nothing —
 * exactly the self-normalising bug that made the heat work look broken on the
 * splits chart. The reference has to stand still for the correction to read.
 *
 * Pure: no IO. Callers hand in logs, their parsed blocks, the goal and the
 * athlete's MP. See `goalPace.test.ts`.
 */

import { readFloatLegs } from "../_shared/floatLegs.ts";
import { isQuality } from "../_shared/sessions.ts";
import { heatNeutralPace, isBeyondChart } from "../_shared/pace-heat-adjustment.ts";

/** The library's own ladder. Percent of goal-race-pace SPEED. */
export const LIBRARY_BANDS = [
  { pct: 80, label: "Easy" },
  { pct: 85, label: "Moderate" },
  { pct: 90, label: "Steady" },
  { pct: 95, label: "Alternation fast leg" },
  { pct: 100, label: "Race pace" },
] as const;

/** Sessions below this are aerobic volume, not specific work — kept, but marked. */
const SPECIFIC_PCT = 95;

/** Per-session conditions, keyed by workout id. Absent → no correction. */
export interface SessionWeather {
  temp_f: number | null;
  dew_point_f: number | null;
}

export interface GoalPaceLog {
  id: string;
  workout_date: string;
  workout_type: string | null;
  workout_distance_miles: number | null;
}

export interface GoalPaceSession {
  workout_id: string;
  date: string;
  workout_type: string | null;
  /** Percent of goal-race-pace speed. 100 = exactly goal pace. */
  pct_of_goal: number;
  /** Work + float. The span actually run without stopping to jog. */
  continuous_miles: number;
  /** Seconds per mile over `continuous_miles`. RAW — what the watch recorded. */
  pace_sec: number;
  /** The same span corrected for heat. Equals `pace_sec` when no weather is
   *  on file, so a consumer can always read this field without branching. */
  pace_sec_heat_adj: number;
  /** `pace_sec - pace_sec_heat_adj`, ≥ 0. Zero when uncorrected. */
  heat_gain_sec: number;
  /** Percent of goal using the heat-adjusted pace. */
  pct_of_goal_heat_adj: number;
  /** Fast legs only — null unless this is a float session. */
  fast_pace_sec: number | null;
  float_pace_sec: number | null;
  is_float_session: boolean;
  /** Fast legs, or reps. A 20k alternation is 10 cycles, not 20 reps. */
  cycles: number;
  at_or_above_specific: boolean;
}

export interface GoalPaceOut {
  goal: {
    race_key: string;
    time_seconds: number;
    pace_sec_per_mile: number;
    /** So the client can label the axis without recomputing. */
    source: string;
  };
  bands: Array<{ pct: number; label: string; pace_sec: number }>;
  sessions: GoalPaceSession[];
  summary: {
    sessions: number;
    /** Continuous miles at or above the specific band, across the window. */
    specific_miles: number;
    /** The longest single continuous span at goal pace or faster. */
    longest_specific_miles: number;
    /** Mean percent across sessions, first half vs second. */
    mean_pct_first_half: number | null;
    mean_pct_second_half: number | null;
  };
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}
function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

/**
 * @param logs           key sessions, newest first or oldest first — order agnostic
 * @param blocksByWorkout `parsed_structure.blocks` per workout id
 * @param goalPaceSec    goal race pace, seconds per mile
 * @param mpSecPerMile   the athlete's CURRENT marathon pace, for float classification
 */
export function buildGoalPace(
  logs: GoalPaceLog[],
  blocksByWorkout: Map<string, unknown[]>,
  goal: { race_key: string; time_seconds: number; pace_sec_per_mile: number; source: string },
  mpSecPerMile: number | null,
  weatherByLog?: Map<string, SessionWeather>,
): GoalPaceOut | null {
  if (!(goal.pace_sec_per_mile > 0)) return null;

  const sessions: GoalPaceSession[] = [];

  for (const log of logs) {
    if (!isQuality(log.workout_type)) continue;
    const blocks = blocksByWorkout.get(log.id);
    if (!Array.isArray(blocks) || blocks.length === 0) continue;

    const read = readFloatLegs(blocks as never[], mpSecPerMile);
    if (!(read.continuousMiles > 0) || read.aggregatePaceSec == null) continue;

    const paceSec = read.aggregatePaceSec;
    // Percent of goal SPEED, so faster is a higher number. Reciprocal of pace.
    const pct = (goal.pace_sec_per_mile / paceSec) * 100;

    // Heat: this is the CREDIT direction, not the prescription. `adjustPace`
    // answers "how much slower should I run today?" and returns a SLOWER pace;
    // a completed session needs "what was this effort worth on a neutral day?",
    // which is `heatNeutralPace` and returns a faster one. Using the
    // prescription here moved every hot session the wrong way — caught by the
    // test that asserts a hot session corrects toward goal, not away from it.
    //
    // No rep-length scaling: the aggregate spans a continuous effort, and the
    // module's contract says omit `distanceMiles` for continuous running.
    const wx = weatherByLog?.get(log.id);
    let adjSec = paceSec;
    if (
      wx && wx.temp_f != null && wx.dew_point_f != null &&
      !isBeyondChart(wx.temp_f, wx.dew_point_f)
    ) {
      // Past the end of the chart the correction is a clamped extrapolation —
      // decline rather than publish a guess.
      adjSec = heatNeutralPace(paceSec, wx.temp_f, wx.dew_point_f, null);
    }
    const pctAdj = (goal.pace_sec_per_mile / adjSec) * 100;

    sessions.push({
      workout_id: log.id,
      date: log.workout_date,
      workout_type: log.workout_type,
      pct_of_goal: round1(pct),
      pace_sec_heat_adj: Math.round(adjSec),
      heat_gain_sec: Math.max(0, Math.round(paceSec - adjSec)),
      pct_of_goal_heat_adj: round1(pctAdj),
      continuous_miles: round2(read.continuousMiles),
      pace_sec: Math.round(paceSec),
      fast_pace_sec: read.isFloatSession && read.fastPaceSec != null
        ? Math.round(read.fastPaceSec)
        : null,
      float_pace_sec: read.floatPaceSec != null ? Math.round(read.floatPaceSec) : null,
      is_float_session: read.isFloatSession,
      cycles: read.cycles,
      at_or_above_specific: pct >= SPECIFIC_PCT,
    });
  }

  if (sessions.length === 0) return null;
  sessions.sort((a, b) => a.date.localeCompare(b.date));

  // Longest single continuous span at goal pace or faster. THE convergence
  // number: a 2:20 build wants this climbing toward 10–15 miles.
  let longest = 0;
  let specificMiles = 0;
  for (const s of sessions) {
    if (!s.at_or_above_specific) continue;
    specificMiles += s.continuous_miles;
    if (s.continuous_miles > longest) longest = s.continuous_miles;
  }

  const mid = Math.floor(sessions.length / 2);
  const mean = (arr: GoalPaceSession[]) =>
    arr.length === 0 ? null : round1(arr.reduce((a, s) => a + s.pct_of_goal, 0) / arr.length);

  return {
    goal,
    bands: LIBRARY_BANDS.map((b) => ({
      pct: b.pct,
      label: b.label,
      pace_sec: Math.round(goal.pace_sec_per_mile / (b.pct / 100)),
    })),
    sessions,
    summary: {
      sessions: sessions.length,
      specific_miles: round2(specificMiles),
      longest_specific_miles: round2(longest),
      mean_pct_first_half: mean(sessions.slice(0, mid)),
      mean_pct_second_half: mean(sessions.slice(mid)),
    },
  };
}
