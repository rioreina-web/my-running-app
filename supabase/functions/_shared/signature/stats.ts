/**
 * Athlete Signature — statistics (addendum §4.2).
 *
 * The honest core. Thousands of hypotheses over months of one human's data is
 * a spurious-correlation machine unless gated hard, so every number here is
 * measured against the ATHLETE'S OWN baseline — never a population norm.
 *
 * Two outcome families:
 *   continuous (pace, HR, effort, fade) → effect in the athlete's personal SDs.
 *   rate       (mood, niggle, feel)     → effect as a difference in event rate.
 *
 * All functions are pure and side-effect free.
 */

export function mean(xs: number[]): number {
  if (xs.length === 0) return NaN;
  return xs.reduce((a, b) => a + b, 0) / xs.length;
}

/** Population standard deviation (divides by n). NaN for < 2 points. */
export function stdev(xs: number[]): number {
  if (xs.length < 2) return NaN;
  const m = mean(xs);
  const v = xs.reduce((a, b) => a + (b - m) * (b - m), 0) / xs.length;
  return Math.sqrt(v);
}

export function rate(events: boolean[]): number {
  if (events.length === 0) return NaN;
  return events.filter(Boolean).length / events.length;
}

// ── Effect sizes ──────────────────────────────────────────────────────────────

export interface ContinuousEffect {
  kind: "continuous";
  exposedMean: number;
  baselineMean: number;
  /** (exposedMean − baselineMean) / personalSD. Signed. */
  effect: number;
  personalSd: number;
}

export interface RateEffect {
  kind: "rate";
  exposedRate: number;
  baselineRate: number;
  /** exposedRate − baselineRate. Signed. */
  effect: number;
}

/**
 * Continuous effect in personal-SD units. `personalSd` is the spread of the
 * outcome across ALL measured days (exposed + baseline) — the athlete's own
 * natural variation, so the effect answers "how many of THIS athlete's typical
 * days' worth of difference is this?"
 */
export function continuousEffect(
  exposed: number[],
  baseline: number[],
  allValues: number[],
): ContinuousEffect {
  const personalSd = stdev(allValues);
  const exposedMean = mean(exposed);
  const baselineMean = mean(baseline);
  const effect = personalSd > 0 ? (exposedMean - baselineMean) / personalSd : NaN;
  return { kind: "continuous", exposedMean, baselineMean, effect, personalSd };
}

export function rateEffect(exposed: boolean[], baseline: boolean[]): RateEffect {
  const exposedRate = rate(exposed);
  const baselineRate = rate(baseline);
  return { kind: "rate", exposedRate, baselineRate, effect: exposedRate - baselineRate };
}

// ── Split-half confirmation (§4.2 gate 3) ─────────────────────────────────────

export interface HalfResult {
  effect: number;
  n: number;
}

export interface SplitHalf {
  first: HalfResult;
  second: HalfResult;
  /** True when both halves show the same-signed effect at adequate support. */
  consistent: boolean;
}

/**
 * Split the observations by their position in the history window (first half vs
 * second half by date) and recompute the effect in each. A real pattern holds
 * in both halves independently; a fluke usually shows up in only one. This is
 * the single most flike-killing gate (pilot §method).
 *
 * @param items paired (value/event, isExposed, orderKey) records, already
 *   restricted to the outcome's present days. orderKey is typically the date.
 */
export function splitHalf(
  items: { x: number; exposed: boolean; order: string }[],
  kind: "continuous" | "rate",
  minHalfSupport: number,
  minHalfEffect: number,
  overallSign: number,
): SplitHalf {
  const sorted = [...items].sort((a, b) => (a.order < b.order ? -1 : a.order > b.order ? 1 : 0));
  const mid = Math.floor(sorted.length / 2);
  const halves = [sorted.slice(0, mid), sorted.slice(mid)];

  const results = halves.map<HalfResult>((half) => {
    const exp = half.filter((i) => i.exposed);
    const base = half.filter((i) => !i.exposed);
    let effect = NaN;
    if (kind === "continuous") {
      effect = continuousEffect(
        exp.map((i) => i.x),
        base.map((i) => i.x),
        half.map((i) => i.x),
      ).effect;
    } else {
      effect = rateEffect(
        exp.map((i) => i.x === 1),
        base.map((i) => i.x === 1),
      ).effect;
    }
    return { effect, n: exp.length };
  });

  const consistent = results.every(
    (r) =>
      r.n >= minHalfSupport &&
      Number.isFinite(r.effect) &&
      Math.sign(r.effect) === overallSign &&
      Math.abs(r.effect) >= minHalfEffect,
  );

  return { first: results[0], second: results[1], consistent };
}
