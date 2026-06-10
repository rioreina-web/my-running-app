/**
 * Rule 3 — missed_workouts
 *
 * Fires when 2+ scheduled workouts in the current week (Mon-Sun) have
 * status = 'skipped'.
 *
 * → severity: low, action: send_check_in
 *
 * Spec: docs/specs/coachable_moment.md, rule 3
 *
 * V2: split into 3a (body — hurt/tired) and 3b (schedule — busy) once
 * skip-reason is captured on the workout. See spec "Out of scope".
 */

import type {
  CoachableMomentInsert,
  RuleContext,
  RuleEvaluator,
} from "./types.ts";

const MISSED_THRESHOLD = 2;

export const missedWorkouts: RuleEvaluator = (
  ctx: RuleContext,
): CoachableMomentInsert | null => {
  const { athleteUserId, coachId, scheduledThisWeek } = ctx;

  const skipped = scheduledThisWeek.filter((w) => w.status === "skipped");
  if (skipped.length < MISSED_THRESHOLD) return null;

  const totalScheduled = scheduledThisWeek.length;

  const summary =
    `${skipped.length} of ${totalScheduled} scheduled workouts skipped this week. ` +
    `Reason unknown — recommend a check-in. ` +
    `Source: 0 voice logs, ${skipped.length} workouts.`;

  return {
    athlete_user_id: athleteUserId,
    coach_id: coachId,
    rule_id: "missed_workouts",
    severity: "low",
    action_type: "send_check_in",
    summary,
    // No training_log evidence; source_log_ids is logs only per the spec.
    // The skipped scheduled_workouts are the evidence; the coach drills in
    // via athlete detail to see them.
    source_log_ids: [],
  };
};
