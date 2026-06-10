/**
 * Registry of all coachable_moment rules.
 *
 * Adding a new rule: write a new file exporting a RuleEvaluator,
 * import it here, and append to ALL_RULES. Each rule is independent —
 * the main edge function evaluates them in order and inserts whichever fire.
 *
 * Spec: docs/specs/coachable_moment.md
 */

import { buildVsLastCycle } from "./buildVsLastCycle.ts";
import { loadSpikePlusInjury } from "./loadSpikePlusInjury.ts";
import { lowMoodStreak } from "./lowMoodStreak.ts";
import { missedWorkouts } from "./missedWorkouts.ts";
import { weatherImpactedQuality } from "./weatherImpactedQuality.ts";
import type { RuleEvaluator } from "./types.ts";

export const ALL_RULES: readonly RuleEvaluator[] = [
  loadSpikePlusInjury,
  lowMoodStreak,
  missedWorkouts,
  weatherImpactedQuality,
  buildVsLastCycle,
];

export * from "./types.ts";
export {
  buildVsLastCycle,
  loadSpikePlusInjury,
  lowMoodStreak,
  missedWorkouts,
  weatherImpactedQuality,
};
