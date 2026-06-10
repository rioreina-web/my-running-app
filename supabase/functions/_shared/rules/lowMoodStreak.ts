/**
 * Rule 2 — low_mood_streak
 *
 * Fires when the last 3 voice logs (with a mood label) are all in
 * { tired, struggling, injured }. Mood labels match the vocabulary
 * written by process-training-memo / process-check-in.
 *
 * → severity: med, action: suggest_deload
 *
 * Spec: docs/specs/coachable_moment.md, rule 2
 *
 * Note: the original spec called for "mood ≤ 2 on 1–5 scale," but the
 * actual training_logs.mood column is a string label, not a number.
 * V1 uses the label set above; V2 may introduce a numeric mood score.
 */

import {
  LOW_MOOD_LABELS,
  type CoachableMomentInsert,
  type RuleContext,
  type RuleEvaluator,
} from "./types.ts";

const STREAK_LENGTH = 3;

export const lowMoodStreak: RuleEvaluator = (
  ctx: RuleContext,
): CoachableMomentInsert | null => {
  const { athleteUserId, coachId, logs } = ctx;

  // Most recent 3 logs that actually have a mood label.
  // logs are passed in newest-first; if not, sort defensively.
  const sorted = [...logs].sort((a, b) => {
    const aTs = a.workout_date ? new Date(a.workout_date).getTime() : 0;
    const bTs = b.workout_date ? new Date(b.workout_date).getTime() : 0;
    return bTs - aTs;
  });

  const withMood = sorted.filter((l) => l.mood && l.mood.trim().length > 0);
  if (withMood.length < STREAK_LENGTH) return null;

  const lastThree = withMood.slice(0, STREAK_LENGTH);
  const allLow = lastThree.every((l) =>
    LOW_MOOD_LABELS.has((l.mood ?? "").toLowerCase().trim()),
  );
  if (!allLow) return null;

  const moodList = lastThree.map((l) => l.mood).join(", ");
  const summary =
    `Last ${STREAK_LENGTH} voice logs all flagged low mood (${moodList}). ` +
    `Source: ${STREAK_LENGTH} voice logs, 0 workouts.`;

  return {
    athlete_user_id: athleteUserId,
    coach_id: coachId,
    rule_id: "low_mood_streak",
    severity: "med",
    action_type: "suggest_deload",
    summary,
    source_log_ids: lastThree.map((l) => l.id),
  };
};
