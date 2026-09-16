/**
 * Athlete Signature — miner entry point (addendum §4).
 *
 * Pure orchestration. The mine-athlete-signature edge function (a later pass)
 * loads an athlete's day-level timeline from the existing tables, calls
 * mineSignature(), and upserts the results under the service role. This module
 * itself does NO I/O — which is exactly what makes it unit-testable and cheap.
 *
 * Pipeline:
 *   1. history gate (min span) — below it, the athlete isn't mined at all.
 *   2. tag derived antecedents (back-to-back quality).
 *   3. enumerate the grammar's hypothesis space.
 *   4. run the gates on each hypothesis (support → effect → split-half).
 *   5. cap + de-duplicate the survivors.
 *
 * Output: candidate observations. Promotion to `active` (the survivorship
 * re-test, §4.2 gate 4) and decay/refutation (§6) live in the weekly
 * lifecycle, which compares this run's candidates against what's stored.
 */

import { dayDiff, enumerateHypotheses, tagDerivedAntecedents } from "./grammar.ts";
import { capAndDedup, evaluateHypothesis } from "./gates.ts";
import { type AthleteDay, DEFAULT_GATES, type GateConfig, type SignatureObservation } from "./types.ts";

export interface MineResult {
  observations: SignatureObservation[];
  /** Why the run produced what it did — handy for the dark-run precision review. */
  meta: {
    dayCount: number;
    historySpanDays: number;
    mined: boolean;
    reason?: string;
    hypothesesTested: number;
    passedGates: number;
  };
}

/**
 * Mine an athlete's signature from their day-level history.
 *
 * @param days one entry per calendar date, ascending or not (sorted here).
 * @param config gate thresholds; defaults to the pilot-proven DEFAULT_GATES.
 */
export function mineSignature(
  days: AthleteDay[],
  config: GateConfig = DEFAULT_GATES,
): MineResult {
  const sorted = [...days].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));

  const span =
    sorted.length >= 2 ? dayDiff(sorted[0].date, sorted[sorted.length - 1].date) : 0;

  if (span < config.minHistoryDays) {
    return {
      observations: [],
      meta: {
        dayCount: sorted.length,
        historySpanDays: span,
        mined: false,
        reason: `history span ${span}d < ${config.minHistoryDays}d minimum`,
        hypothesesTested: 0,
        passedGates: 0,
      },
    };
  }

  tagDerivedAntecedents(sorted);

  const hypotheses = enumerateHypotheses();
  const passed: SignatureObservation[] = [];
  for (const h of hypotheses) {
    const obs = evaluateHypothesis(sorted, h, config);
    if (obs) passed.push(obs);
  }

  const observations = capAndDedup(passed, config.cap);

  return {
    observations,
    meta: {
      dayCount: sorted.length,
      historySpanDays: span,
      mined: true,
      hypothesesTested: hypotheses.length,
      passedGates: passed.length,
    },
  };
}

export { DEFAULT_GATES } from "./types.ts";
export type { AthleteDay, SignatureObservation } from "./types.ts";
