/**
 * Prompt library — single home for every LLM prompt the backend ships.
 *
 * Why centralize:
 *   - Versioning. We can A/B against prior prompt versions when the eval
 *     harness lands. Filename suffix `.v1`/`.v2` is the version.
 *   - Drift control. Prompts live in dedicated files we can diff in PR
 *     review. No more "find the system prompt buried in line 397 of an
 *     edge function."
 *   - Eval coverage. The eval harness runs prompts as inputs; centralizing
 *     them is what lets the harness exist at all.
 *
 * How:
 *   1. Save the prompt as `_shared/prompts/<name>.v<n>.ts`, exporting
 *      a `TEMPLATE` string constant. Use `{{variable}}` placeholders for
 *      runtime substitution.
 *   2. Register it in the REGISTRY map below (one line).
 *   3. From the edge function: `loadPrompt("name.v1", { variable: "..." })`
 *
 * Why .ts and not .txt: Supabase's edge-function bundler traces ES module
 * imports. Static `.ts` imports are bundled with the function; arbitrary
 * disk reads are NOT. Keeping prompts as `.ts` files in `_shared/prompts/`
 * means every prompt deploys atomically with every function that uses it.
 *
 * Conditional content (e.g. "show this section only if X") should be
 * PRE-COMPUTED by the caller and passed in as a single substitution
 * string — keep the templating dumb. Strict by default: an unresolved
 * `{{placeholder}}` throws, an unused variable throws.
 */

import { TEMPLATE as BLOCK_REVIEW_V1 } from "./prompts/block-review.v1.ts";
import { TEMPLATE as COACHING_AGENT_SIMPLE_V1 } from "./prompts/coaching-agent-simple.v1.ts";
import { TEMPLATE as COACHING_AGENT_MODERATE_V1 } from "./prompts/coaching-agent-moderate.v1.ts";
import { TEMPLATE as COACHING_AGENT_COMPLEX_V1 } from "./prompts/coaching-agent-complex.v1.ts";
import { TEMPLATE as COACHING_AGENT_PROACTIVE_V1 } from "./prompts/coaching-agent-proactive.v1.ts";
import { TEMPLATE as DAILY_READ_V1 } from "./prompts/daily-read.v1.ts";
import { TEMPLATE as DAILY_READ_V2 } from "./prompts/daily-read.v2.ts";
import { TEMPLATE as FITNESS_PREDICTOR_V1 } from "./prompts/fitness-predictor.v1.ts";
import { TEMPLATE as GENERATE_WORKOUT_INSIGHT_V1 } from "./prompts/generate-workout-insight.v1.ts";
import { TEMPLATE as GENERATE_WORKOUT_INSIGHT_V2 } from "./prompts/generate-workout-insight.v2.ts";
import { TEMPLATE as GENERATE_WORKOUT_INSIGHT_V3 } from "./prompts/generate-workout-insight.v3.ts";
import { TEMPLATE as GENERATE_WORKOUT_INSIGHT_V4 } from "./prompts/generate-workout-insight.v4.ts";
import { TEMPLATE as INJURY_ANALYSIS_V1 } from "./prompts/injury-analysis.v1.ts";
import { TEMPLATE as INJURY_EARLY_WARNING_V1 } from "./prompts/injury-early-warning.v1.ts";
import { TEMPLATE as PARSE_TRAINING_WEEK_V1 } from "./prompts/parse-training-week.v1.ts";
import { TEMPLATE as PARSE_WORKOUT_STRUCTURE_V1 } from "./prompts/parse-workout-structure.v1.ts";
import { TEMPLATE as POST_RUN_ANALYSIS_V1 } from "./prompts/post-run-analysis.v1.ts";
import { TEMPLATE as PROCESS_CHECK_IN_V1 } from "./prompts/process-check-in.v1.ts";
import { TEMPLATE as PROCESS_TRAINING_MEMO_V1 } from "./prompts/process-training-memo.v1.ts";
import { TEMPLATE as RACE_INTEL_V1 } from "./prompts/race-intel.v1.ts";
import { TEMPLATE as RACE_READINESS_V1 } from "./prompts/race-readiness.v1.ts";
import { TEMPLATE as RESCHEDULE_PLAN_V1 } from "./prompts/reschedule-plan.v1.ts";
import { TEMPLATE as TRAINING_ANALYSIS_V1 } from "./prompts/training-analysis.v1.ts";
import { TEMPLATE as WEEKLY_COACHING_REPORT_V1 } from "./prompts/weekly-coaching-report.v1.ts";
import { TEMPLATE as WEEKLY_PLAN_REVIEW_V1 } from "./prompts/weekly-plan-review.v1.ts";

/**
 * Static registry of every prompt the backend can load. Adding a prompt
 * is a 2-line change: create the .ts file, add an entry here.
 */
const REGISTRY: Record<string, string> = {
  "block-review.v1": BLOCK_REVIEW_V1,
  "coaching-agent-simple.v1": COACHING_AGENT_SIMPLE_V1,
  "coaching-agent-moderate.v1": COACHING_AGENT_MODERATE_V1,
  "coaching-agent-complex.v1": COACHING_AGENT_COMPLEX_V1,
  "coaching-agent-proactive.v1": COACHING_AGENT_PROACTIVE_V1,
  "daily-read.v1": DAILY_READ_V1,
  "daily-read.v2": DAILY_READ_V2,
  "fitness-predictor.v1": FITNESS_PREDICTOR_V1,
  "generate-workout-insight.v1": GENERATE_WORKOUT_INSIGHT_V1,
  "generate-workout-insight.v2": GENERATE_WORKOUT_INSIGHT_V2,
  "generate-workout-insight.v3": GENERATE_WORKOUT_INSIGHT_V3,
  "generate-workout-insight.v4": GENERATE_WORKOUT_INSIGHT_V4,
  "injury-analysis.v1": INJURY_ANALYSIS_V1,
  "injury-early-warning.v1": INJURY_EARLY_WARNING_V1,
  "parse-training-week.v1": PARSE_TRAINING_WEEK_V1,
  "parse-workout-structure.v1": PARSE_WORKOUT_STRUCTURE_V1,
  "post-run-analysis.v1": POST_RUN_ANALYSIS_V1,
  "process-check-in.v1": PROCESS_CHECK_IN_V1,
  "process-training-memo.v1": PROCESS_TRAINING_MEMO_V1,
  "race-intel.v1": RACE_INTEL_V1,
  "race-readiness.v1": RACE_READINESS_V1,
  "reschedule-plan.v1": RESCHEDULE_PLAN_V1,
  "training-analysis.v1": TRAINING_ANALYSIS_V1,
  "weekly-coaching-report.v1": WEEKLY_COACHING_REPORT_V1,
  "weekly-plan-review.v1": WEEKLY_PLAN_REVIEW_V1,
};

/**
 * Load a prompt template and substitute `{{variable}}` placeholders.
 *
 * @param name      Registered prompt name + version (e.g. `injury-analysis.v1`).
 * @param vars      Substitution values. Every key in `vars` MUST appear in
 *                  the template; every `{{placeholder}}` in the template
 *                  MUST be in `vars`. Mismatch throws.
 * @returns The fully-substituted prompt string.
 */
export function loadPrompt(
  name: string,
  vars: Record<string, string | number> = {},
): string {
  const template = REGISTRY[name];
  if (template === undefined) {
    throw new Error(
      `Prompt "${name}" not found in registry. ` +
        `Available: ${Object.keys(REGISTRY).join(", ") || "(empty)"}`,
    );
  }

  const placeholders = new Set<string>();
  template.replace(/\{\{(\w+)\}\}/g, (_, key) => {
    placeholders.add(key);
    return "";
  });

  for (const key of Object.keys(vars)) {
    if (!placeholders.has(key)) {
      throw new Error(
        `Prompt "${name}": variable "${key}" passed in but no {{${key}}} placeholder exists in the template`,
      );
    }
  }
  for (const key of placeholders) {
    if (!(key in vars)) {
      throw new Error(
        `Prompt "${name}": template has {{${key}}} but no value was passed in`,
      );
    }
  }

  return template.replace(/\{\{(\w+)\}\}/g, (_, key) => String(vars[key]));
}

/** Test-only: list every registered prompt name. */
export function _listPrompts(): string[] {
  return Object.keys(REGISTRY).sort();
}
