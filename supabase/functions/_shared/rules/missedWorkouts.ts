/**
 * Rule 3 — missed_workouts (cause-aware)
 *
 * Fires on skipped sessions in the current week (Mon-Sun), and branches on
 * *why* they were skipped. This is the 3a/3b split the V1 rule left as a TODO
 * — "split into 3a (body — hurt/tired) and 3b (schedule — busy) once
 * skip-reason is captured on the workout." Skip-reason is now captured
 * (20260821140000_skip_cause_attribution.sql), so the split lands here.
 *
 * The whole point: two missed Tuesdays are not the same event. Work blew up
 * → move the day, keep the load, low-key. The athlete is cooked → that's a
 * fatigue signal, and the week around it probably needs easing. Surfacing
 * both as one undifferentiated "2 workouts skipped, recommend a check-in"
 * was the thing that made the moment easy to ignore.
 *
 * Cause → response comes from the single table in `_shared/cause.ts`; this
 * rule only translates that into the coachable-moment vocabulary. Two
 * surfaces, one decision table.
 *
 * Spec: docs/specs/coachable_moment.md, rule 3
 */

import { CAUSE_RESPONSES, type SkipCause } from "../cause.ts";
import type {
  ActionType,
  CoachableMomentInsert,
  RuleContext,
  RuleEvaluator,
  ScheduledWorkoutRow,
  Severity,
} from "./types.ts";

/** Two misses is the baseline pattern; see SOLO_FIRE_CAUSES for the exception. */
const MISSED_THRESHOLD = 2;

/**
 * Causes worth surfacing on a single missed session.
 *
 * A body mention around a skipped workout is the earliest honest warning the
 * system gets, and waiting for a second miss to mention it defeats the point
 * of catching things before they become injuries. Everything else holds at
 * the two-miss threshold so the coach's queue stays worth reading.
 */
const SOLO_FIRE_CAUSES: ReadonlySet<SkipCause> = new Set(["niggle"]);

/**
 * Cause → what the coach is being asked to do about it.
 *
 * The coachable-moment action vocabulary is separate from the plan-adjustment
 * one (`monitor` is not a plan change), so the mapping is explicit rather
 * than shared. Note `illness` lands on `monitor`, not `recommend_evaluation`:
 * the system reports what the athlete said and stops. It does not route
 * people to medical care off a keyword (hard rule #2).
 */
const CAUSE_ACTIONS: Readonly<Record<SkipCause, ActionType>> = {
  schedule: "monitor",
  fatigue: "suggest_extra_recovery",
  illness: "monitor",
  niggle: "recommend_evaluation",
  weather: "monitor",
  unknown: "send_check_in",
};

/** Attributed cause, or `unknown` when nothing was captured. */
function causeOf(w: ScheduledWorkoutRow): SkipCause {
  return w.skip_cause ?? "unknown";
}

/**
 * The cause that should drive the moment when a week holds several.
 *
 * Highest severity wins, ties broken by frequency. A week with one niggle
 * skip and two "work was mad" skips is a niggle week — the loudest signal is
 * the one the coach needs to see, not the most common one.
 */
function dominantCause(skipped: ScheduledWorkoutRow[]): SkipCause {
  const rank: Record<Severity, number> = { low: 0, med: 1, high: 2 };
  const counts = new Map<SkipCause, number>();
  for (const w of skipped) {
    const c = causeOf(w);
    counts.set(c, (counts.get(c) ?? 0) + 1);
  }
  let best: SkipCause = "unknown";
  let bestScore = -1;
  let bestCount = 0;
  for (const [cause, count] of counts) {
    const score = rank[CAUSE_RESPONSES[cause].severity];
    if (score > bestScore || (score === bestScore && count > bestCount)) {
      best = cause;
      bestScore = score;
      bestCount = count;
    }
  }
  return best;
}

/** "2 of 5 scheduled workouts" / "1 of 5 scheduled workouts" */
function countPhrase(skipped: number, total: number): string {
  return `${skipped} of ${total} scheduled workout${total === 1 ? "" : "s"}`;
}

export const missedWorkouts: RuleEvaluator = (
  ctx: RuleContext,
): CoachableMomentInsert | null => {
  const { athleteUserId, coachId, scheduledThisWeek } = ctx;

  const skipped = scheduledThisWeek.filter((w) => w.status === "skipped");
  if (skipped.length === 0) return null;

  const cause = dominantCause(skipped);
  const response = CAUSE_RESPONSES[cause];

  // Below threshold, only a high-signal cause is worth the coach's attention.
  if (skipped.length < MISSED_THRESHOLD && !SOLO_FIRE_CAUSES.has(cause)) {
    return null;
  }

  const totalScheduled = scheduledThisWeek.length;

  // A cause a person confirmed reads differently from one the model inferred,
  // and the coach should be able to tell at a glance which they're looking at.
  const attributed = skipped.filter((w) => w.skip_cause);
  const anyConfirmed = attributed.some(
    (w) => w.skip_cause_source === "coach_confirmed" ||
      w.skip_cause_source === "athlete_confirmed",
  );
  const provenance = cause === "unknown"
    ? "No reason captured"
    : anyConfirmed
    ? `Reason: ${cause} (confirmed)`
    : `Reason: ${cause} (inferred — correctable)`;

  // Escalate a quiet cause when it keeps happening. Three "work was mad"
  // weeks in a row is not a scheduling problem, it's a plan that doesn't fit
  // the athlete's life — and that IS the coach's business.
  const severity: Severity = skipped.length >= 3 && response.severity === "low"
    ? "med"
    : response.severity;

  const summary = `${countPhrase(skipped.length, totalScheduled)} skipped this week. ` +
    `${provenance}. ${response.rationale} ` +
    `Source: 0 voice logs, ${skipped.length} workouts.`;

  return {
    athlete_user_id: athleteUserId,
    coach_id: coachId,
    rule_id: "missed_workouts",
    severity,
    action_type: CAUSE_ACTIONS[cause],
    summary,
    // Evidence is the skipped scheduled_workouts, not training_logs;
    // source_log_ids stays logs-only per the spec.
    source_log_ids: [],
  };
};
