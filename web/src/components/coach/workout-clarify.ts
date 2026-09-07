// Turning "I didn't understand this" into a question the coach can answer.
//
// The August 2026 audit ended with the parser honest but passive: it printed
// "no pace given for the 1km step — set it before saving" and left the coach to
// find the row and fix it. That is better than the silent guessing it replaced,
// but it still hands the work back.
//
// A question is different from a warning in three ways that matter:
//   - it names ONE thing and has one answer;
//   - its answers are a closed list, because the pace vocabulary is closed, so
//     answering is a tap rather than a form;
//   - answering resolves the step in place, with no re-parse and no chance for
//     the parse to drift on a second pass.
//
// Questions are grouped by (reason, what-is-being-asked-about) so a 12-step
// expansion where every 1km leg lacks a pace asks ONCE and applies the answer
// to all twelve. Asking twelve times would be its own kind of unusable.

import { PACE_ZONES, type PaceZone, type WorkoutStep } from "./workout-helpers";
import type { UnresolvedReason } from "./workout-nl-parser";

export interface ClarifyOption {
  label: string;
  value: string;
}

export interface Clarification {
  id: string;
  /** Asked in the coach's own terms, naming the thing it is about. */
  question: string;
  /** Why we're asking — lets the UI group or style, and aids debugging. */
  reason: UnresolvedReason | "cooldown_at_start";
  /** Every step this answer applies to. */
  stepIds: string[];
  kind: "pace" | "choice";
  options: ClarifyOption[];
}

const QUESTION_BY_REASON: Record<UnresolvedReason, (what: string) => string> = {
  no_pace_written: (what) => `No pace written for ${what}. What should it be?`,
  effort_word_not_a_zone: (what) => `${what} is written as an effort, not a pace. Which zone?`,
  progression_without_paces: (what) => `${what} is a progression with no paces given. Where does it start?`,
  ambiguous: (what) => `The pace for ${what} is ambiguous. Which did you mean?`,
};

/** How a step reads in a question: "6 x 1km", "2mi", "3'". */
export function describeStep(s: WorkoutStep): string {
  const v = s.durationValue;
  const body =
    s.durationType === "time_seconds"
      ? v >= 60 ? `${Math.round(v / 60)}'` : `${Math.round(v)}s`
      : s.durationType === "distance_meters" ? `${Math.round(v)}m`
      : s.durationType === "distance_km" ? `${v}km`
      : `${v}mi`;
  return s.repeats && s.repeats > 1 ? `${s.repeats} × ${body}` : body;
}

const paceOptions = (): ClarifyOption[] =>
  PACE_ZONES.map((z) => ({ label: z.shortName, value: z.value }));

/**
 * Build the questions for a parse. Steps that share a reason AND a description
 * are asked about together — the 1km legs of a set are one question, not six.
 */
export function buildClarifications(
  steps: WorkoutStep[],
  unresolved: Record<string, UnresolvedReason>,
): Clarification[] {
  const byId = new Map(steps.map((s) => [s.id, s]));
  const groups = new Map<string, { reason: UnresolvedReason; what: string; stepIds: string[] }>();

  for (const [stepId, reason] of Object.entries(unresolved)) {
    const step = byId.get(stepId);
    if (!step) continue;
    const what = describeStep(step);
    const key = `${reason}::${what}`;
    const g = groups.get(key) ?? { reason, what, stepIds: [] };
    g.stepIds.push(stepId);
    groups.set(key, g);
  }

  const out: Clarification[] = [];
  for (const [key, g] of groups) {
    // "the 1km legs" reads better than "1km" once there is more than one.
    const subject = g.stepIds.length > 1 ? `the ${g.what} legs` : `the ${g.what} step`;
    out.push({
      id: key,
      question: QUESTION_BY_REASON[g.reason](subject),
      reason: g.reason,
      stepIds: g.stepIds,
      kind: "pace",
      options: paceOptions(),
    });
  }

  // A cooldown before any warmup is a typo, not a session — this coach wrote
  // "2mi CD + ... + 2Mi CD" and meant WU at the front. Worth one question:
  // silently correcting it would be exactly the guessing this work removed.
  const firstReal = steps.findIndex((s) => s.stepType !== "rest");
  if (firstReal >= 0 && steps[firstReal].stepType === "cooldown") {
    const hasLaterCooldown = steps.slice(firstReal + 1).some((s) => s.stepType === "cooldown");
    if (hasLaterCooldown) {
      out.unshift({
        id: "cooldown-at-start",
        question: `The opening ${describeStep(steps[firstReal])} is marked as a cooldown. Warm-up instead?`,
        reason: "cooldown_at_start",
        stepIds: [steps[firstReal].id],
        kind: "choice",
        options: [
          { label: "Warm-up", value: "warmup" },
          { label: "Leave as cooldown", value: "cooldown" },
        ],
      });
    }
  }

  return out;
}

/**
 * Apply one answer. Returns new steps — never mutates — so the caller can keep
 * the coach's own hand edits and undo cleanly.
 */
export function applyClarification(
  steps: WorkoutStep[],
  c: Clarification,
  value: string,
): WorkoutStep[] {
  const targets = new Set(c.stepIds);
  return steps.map((s) => {
    if (!targets.has(s.id)) return s;
    if (c.kind === "choice") {
      return { ...s, stepType: value as WorkoutStep["stepType"] };
    }
    return { ...s, paceZone: value as PaceZone };
  });
}
