/**
 * Rule 1 — load_spike_plus_injury
 *
 * Fires when:
 *   - Weekly volume in last 7d is >20% above the rolling average of the
 *     prior 3 weeks (days 8-28 ago)
 *   - AND any voice log in the last 14d mentions an injury keyword
 *
 * → severity: high, action: recommend_evaluation
 *
 * Spec: docs/specs/coachable_moment.md, rule 1
 */

import {
  INJURY_KEYWORDS,
  type CoachableMomentInsert,
  type RuleContext,
  type RuleEvaluator,
} from "./types.ts";

const SPIKE_THRESHOLD = 1.2; // 20% above rolling average

const LOAD_WINDOW_DAYS = 7;
const ROLLING_WINDOW_DAYS = 28;
const INJURY_SCAN_DAYS = 14;

function daysAgo(now: Date, days: number): Date {
  const d = new Date(now);
  d.setUTCDate(d.getUTCDate() - days);
  return d;
}

function milesInRange(
  logs: RuleContext["logs"],
  startInclusive: Date,
  endExclusive: Date,
): number {
  let total = 0;
  for (const log of logs) {
    if (!log.workout_date || !log.workout_distance_miles) continue;
    const d = new Date(log.workout_date);
    if (d >= startInclusive && d < endExclusive) {
      total += log.workout_distance_miles;
    }
  }
  return total;
}

function findInjuryMentions(
  logs: RuleContext["logs"],
  since: Date,
): { logIds: string[]; firstKeyword: string | null } {
  const matched: string[] = [];
  let firstKeyword: string | null = null;

  for (const log of logs) {
    const d = log.workout_date ? new Date(log.workout_date) : null;
    if (d && d < since) continue;

    const text = [log.notes, log.cleaned_notes, log.coach_insight]
      .filter(Boolean)
      .join(" ")
      .toLowerCase();

    if (!text) continue;

    for (const kw of INJURY_KEYWORDS) {
      if (text.includes(kw)) {
        matched.push(log.id);
        if (!firstKeyword) firstKeyword = kw;
        break;
      }
    }
  }

  return { logIds: matched, firstKeyword };
}

export const loadSpikePlusInjury: RuleEvaluator = (
  ctx: RuleContext,
): CoachableMomentInsert | null => {
  const { athleteUserId, coachId, now, logs } = ctx;

  // ─── Volume math ──────────────────────────────────────────────────────────
  const sevenDaysAgo = daysAgo(now, LOAD_WINDOW_DAYS);
  const twentyEightDaysAgo = daysAgo(now, ROLLING_WINDOW_DAYS);

  const lastWeekMiles = milesInRange(logs, sevenDaysAgo, now);
  const priorThreeWeeksMiles = milesInRange(
    logs,
    twentyEightDaysAgo,
    sevenDaysAgo,
  );
  const priorThreeWeeksAvg = priorThreeWeeksMiles / 3;

  // Need at least *some* prior baseline to compare against. If the athlete
  // is brand new with no history, don't fire.
  if (priorThreeWeeksAvg <= 0) return null;

  const ratio = lastWeekMiles / priorThreeWeeksAvg;
  if (ratio <= SPIKE_THRESHOLD) return null;

  // ─── Injury scan ──────────────────────────────────────────────────────────
  const fourteenDaysAgo = daysAgo(now, INJURY_SCAN_DAYS);
  const injury = findInjuryMentions(logs, fourteenDaysAgo);
  if (injury.logIds.length === 0) return null;

  // ─── Build moment ─────────────────────────────────────────────────────────
  const pctOver = Math.round((ratio - 1) * 100);
  const workoutsCounted = logs.filter((l) => {
    if (!l.workout_date || !l.workout_distance_miles) return false;
    const d = new Date(l.workout_date);
    return d >= sevenDaysAgo && d < now;
  }).length;

  const summary =
    `Weekly volume ${pctOver}% above 4-week average ` +
    `(${lastWeekMiles.toFixed(1)} mi vs ${priorThreeWeeksAvg.toFixed(1)} mi avg) ` +
    `with "${injury.firstKeyword}" mentioned in ${injury.logIds.length} of last ${injury.logIds.length === 1 ? "14d" : "14d of"} logs. ` +
    `Source: ${injury.logIds.length} voice logs, ${workoutsCounted} workouts.`;

  return {
    athlete_user_id: athleteUserId,
    coach_id: coachId,
    rule_id: "load_spike_plus_injury",
    severity: "high",
    action_type: "recommend_evaluation",
    summary,
    source_log_ids: injury.logIds,
  };
};
