/**
 * Rule 5 — build_vs_last_cycle (Phase 2 sub-task F)
 *
 * The first race-aware coachable-moment rule. Fires when:
 *   1. the athlete has a stated goal race in the next ~6 months,
 *   2. a prior race of the same distance exists in confirmed_races
 *      (when the goal's distance is unknown — user_goals carries only a
 *      title + date — any anchor race qualifies),
 *   3. the current 28-day volume is meaningfully above the build
 *      baseline from the cycle before that race, and
 *   4. there's enough data on both sides for the comparison to be honest.
 *
 * Output is a *pattern observation*, not an operational ask — for Maya
 * this is one of the journey-anchored observations from
 * outputs/maya-data-aware-journey-2026-05-28.md. It reports what is
 * (volume vs. last build, easy-pace shift at similar effort) and never
 * prescribes. action_type `journey_comparison` keeps it out of the
 * operational buckets (per the Q17 follow-up: pattern observations may
 * surface to self-coached athletes; operational moments stay coach-only).
 *
 *   "5 months out from a 3:28:00 marathon (Houston Marathon). Volume is
 *    averaging 42.1 mpw, ~10% above the pre-race build baseline
 *    (38.3 mpw). Easy runs are averaging 15 sec/mi quicker."
 *
 * → severity: low, action: journey_comparison
 *
 * Spec: outputs/phase-2-race-anchoring-plan-2026-06-04.md sub-task F.
 */

import type {
  CoachableMomentInsert,
  ConfirmedRaceSummary,
  RuleContext,
  RuleEvaluator,
  WeatherAwareTrainingLogRow,
} from "./types.ts";
import { pickAnchorRace, raceKeyForInput } from "../paces.ts";

// Goal race must be within this many days of "now" to count as an active build.
const GOAL_WINDOW_DAYS = 183;
// Current volume must exceed the prior-cycle baseline by at least this factor.
const ABOVE_BASELINE_FACTOR = 1.05;
// Minimum runs on each side for the volume comparison to be honest.
const MIN_CURRENT_LOGS = 8;
const MIN_PRIOR_LOGS = 6;
// Easy-pace delta below this (sec/mi) isn't worth mentioning.
const MIN_EASY_DELTA_SEC = 5;
// Minimum easy runs per window for the pace comparison.
const MIN_EASY_RUNS = 3;
// Window definitions (must match the evaluator's priorCycleLogs fetch).
const CURRENT_WINDOW_WEEKS = 4;
const PRIOR_WINDOW_WEEKS = 6; // race-day −63d … −21d (build, taper excluded)

export const buildVsLastCycle: RuleEvaluator = (
  ctx: RuleContext,
): CoachableMomentInsert | null => {
  const { athleteUserId, coachId, now, logs, goalRace, confirmedRaces, priorCycleLogs } = ctx;

  // 1. Stated goal race in the next ~6 months.
  if (!goalRace?.date) return null;
  const goalTs = new Date(goalRace.date).getTime();
  if (!Number.isFinite(goalTs)) return null;
  const daysToGoal = (goalTs - now.getTime()) / 86400000;
  if (daysToGoal <= 0 || daysToGoal > GOAL_WINDOW_DAYS) return null;

  // 2. Anchor race — most recent qualifying confirmed race. When the goal
  //    distance is known, require the same race key ("similar distance").
  const anchor = pickAnchorRace(confirmedRaces as ConfirmedRaceSummary[] | null | undefined);
  if (!anchor) return null;
  if (anchor.date >= goalRace.date) return null; // anchor must be a PRIOR race
  if (goalRace.distance) {
    try {
      if (raceKeyForInput(goalRace.distance) !== raceKeyForInput(anchor.distanceKey)) {
        return null;
      }
    } catch {
      return null; // unmappable goal distance — don't guess
    }
  }

  // 3. Volume comparison: current 28d weekly average vs. prior-cycle build
  //    baseline. Both windows need enough runs to mean anything.
  const current = logs ?? [];
  const prior = priorCycleLogs ?? [];
  if (current.length < MIN_CURRENT_LOGS || prior.length < MIN_PRIOR_LOGS) return null;

  const currentWeekly = totalMiles(current) / CURRENT_WINDOW_WEEKS;
  const priorWeekly = totalMiles(prior) / PRIOR_WINDOW_WEEKS;
  if (currentWeekly <= 0 || priorWeekly <= 0) return null;
  if (currentWeekly < priorWeekly * ABOVE_BASELINE_FACTOR) return null;

  // 4. Optional easy-pace shift — only when both windows have enough easy
  //    runs and the delta is meaningful. Quicker-only: slower easy paces
  //    aren't a build signal and reporting them here would read as judgment.
  const currentEasy = medianEasyPace(current);
  const priorEasy = medianEasyPace(prior);
  let easySentence = "";
  if (currentEasy !== null && priorEasy !== null) {
    const delta = Math.round(priorEasy - currentEasy);
    if (delta >= MIN_EASY_DELTA_SEC) {
      easySentence = ` Easy runs are averaging ${delta} sec/mi quicker than that build.`;
    }
  }

  const monthsOut = Math.max(1, Math.round((now.getTime() - new Date(anchor.date).getTime()) / (30.44 * 86400000)));
  const pctAbove = Math.round((currentWeekly / priorWeekly - 1) * 100);
  const raceLabel = formatRaceLabel(anchor.distanceKey);
  const eventName = (confirmedRaces ?? []).find((r) => r?.date === anchor.date)?.event_name;

  const summary =
    `${monthsOut} month${monthsOut === 1 ? "" : "s"} out from a ` +
    `${formatFinishTime(anchor.finishTimeSeconds)} ${raceLabel}` +
    `${eventName ? ` (${eventName})` : ""}. ` +
    `Volume is averaging ${round1(currentWeekly)} mpw, ~${pctAbove}% above the ` +
    `pre-race build baseline (${round1(priorWeekly)} mpw).` +
    easySentence +
    ` Source: ${current.length} workouts (28d) vs ${prior.length} workouts in the prior build.`;

  return {
    athlete_user_id: athleteUserId,
    coach_id: coachId,
    rule_id: "build_vs_last_cycle",
    severity: "low",
    action_type: "journey_comparison",
    summary,
    source_log_ids: current.slice(0, 10).map((l) => l.id),
  };
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function totalMiles(logs: WeatherAwareTrainingLogRow[]): number {
  return logs.reduce((sum, l) => sum + (l.workout_distance_miles ?? 0), 0);
}

function round1(n: number): number {
  return Math.round(n * 10) / 10;
}

/** Median easy/recovery pace in sec/mi, or null when fewer than
 * MIN_EASY_RUNS easy runs carry a parseable pace. */
function medianEasyPace(logs: WeatherAwareTrainingLogRow[]): number | null {
  const paces = logs
    .filter((l) => {
      const t = (l.workout_type ?? "").toLowerCase();
      return t.includes("easy") || t.includes("recovery");
    })
    .map((l) => parsePaceSeconds(l.workout_pace_per_mile))
    .filter((p): p is number => p !== null)
    .sort((a, b) => a - b);
  if (paces.length < MIN_EASY_RUNS) return null;
  const mid = Math.floor(paces.length / 2);
  return paces.length % 2 === 1 ? paces[mid] : (paces[mid - 1] + paces[mid]) / 2;
}

/** Parse "8:45" / "8:45/mi" / "08:45" into seconds per mile. */
function parsePaceSeconds(raw: string | null | undefined): number | null {
  if (!raw) return null;
  const m = raw.trim().match(/^(\d{1,2}):(\d{2})/);
  if (!m) return null;
  const sec = parseInt(m[1], 10) * 60 + parseInt(m[2], 10);
  return sec > 0 && sec < 1800 ? sec : null;
}

function formatFinishTime(totalSeconds: number): string {
  const h = Math.floor(totalSeconds / 3600);
  const m = Math.floor((totalSeconds % 3600) / 60);
  const s = Math.round(totalSeconds % 60);
  const mm = String(m).padStart(2, "0");
  const ss = String(s).padStart(2, "0");
  return h > 0 ? `${h}:${mm}:${ss}` : `${m}:${ss}`;
}

function formatRaceLabel(distanceKey: string): string {
  const k = distanceKey.toLowerCase();
  if (k.startsWith("half") || k === "hm") return "half marathon";
  if (k === "marathon" || k === "m") return "marathon";
  if (k === "10k" || k === "tenk") return "10K";
  if (k === "5k" || k === "fivek") return "5K";
  if (k === "3k" || k === "threek") return "3K";
  if (k === "mile" || k === "1mi" || k === "one_mile") return "mile";
  return distanceKey;
}
