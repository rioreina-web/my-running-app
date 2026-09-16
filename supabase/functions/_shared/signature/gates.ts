/**
 * Athlete Signature — gates + scoring (addendum §4.2).
 *
 * Applies the non-negotiable gates, IN ORDER, to a single hypothesis, and
 * grades what survives. Anything that fails any gate returns null and never
 * reaches the database. `low` confidence is likewise dropped here — only
 * medium/high observations are emitted (§ principle 3: nothing on a hunch).
 */

import { dayDiff, patternKey, resolveCategory } from "./grammar.ts";
import {
  continuousEffect,
  type ContinuousEffect,
  rateEffect,
  type RateEffect,
  splitHalf,
} from "./stats.ts";
import type {
  AthleteDay,
  Evidence,
  GateConfig,
  Hypothesis,
  SignatureObservation,
} from "./types.ts";

/** Confidence promotion thresholds — a passing pattern is ≥ medium. */
const HIGH_MIN_SUPPORT = 12;
const HIGH_MIN_EFFECT_SD = 0.8;
const HIGH_MIN_EFFECT_RATE = 0.3;
const HIGH_MIN_STABILITY = 0.6;

interface PresentDay {
  day: AthleteDay;
  /** continuous value, or 1/0 for a rate event. */
  x: number;
  exposed: boolean;
}

/** Partition an outcome's present days into exposed vs baseline for a hypothesis. */
function buildGroups(days: AthleteDay[], h: Hypothesis): PresentDay[] {
  const { antecedent, lag, outcome } = h;

  const present = days.filter((d) => outcome.present(d));
  const valueOf = (d: AthleteDay): number =>
    outcome.kind === "continuous" ? (outcome.value!(d) ?? NaN) : outcome.event!(d) ? 1 : 0;

  if (antecedent.sameDayOnly) {
    // Condition contrast: arm-A vs arm-B on the same day. Days in neither arm
    // are excluded entirely (they carry no contrast signal).
    const out: PresentDay[] = [];
    for (const d of present) {
      if (antecedent.exposed(d)) out.push({ day: d, x: valueOf(d), exposed: true });
      else if (antecedent.baseline ? antecedent.baseline(d) : false) {
        out.push({ day: d, x: valueOf(d), exposed: false });
      }
    }
    return out;
  }

  // Event antecedent: a present day is "exposed" if it lands `lag` days after
  // at least one trigger day.
  const triggerDates = days.filter((d) => antecedent.exposed(d)).map((d) => d.date);
  const [lo, hi] = lag.offset;
  return present.map((d) => {
    const exposed = triggerDates.some((t) => {
      const delta = dayDiff(t, d.date);
      return delta >= lo && delta <= hi;
    });
    return { day: d, x: valueOf(d), exposed };
  });
}

/**
 * Run every gate on one hypothesis. Returns a validated observation, or null if
 * any gate fails. Gate order matches §4.2: support → effect → split-half.
 * (Survivorship re-test and the cap are handled at the miner level.)
 */
export function evaluateHypothesis(
  days: AthleteDay[],
  h: Hypothesis,
  cfg: GateConfig,
): SignatureObservation | null {
  const groups = buildGroups(days, h);
  const exposed = groups.filter((g) => g.exposed);
  const baseline = groups.filter((g) => !g.exposed);

  // Gate 1 — support floor (both arms).
  if (exposed.length < cfg.minSupport || baseline.length < cfg.minSupport) return null;

  // Gate 2 — effect floor, measured against the athlete's own baseline.
  const isContinuous = h.outcome.kind === "continuous";
  const floor = isContinuous ? cfg.minEffectSd : cfg.minEffectRate;

  let effect: number;
  let base_rate: number;
  let conditional_rate: number;
  let cont: ContinuousEffect | null = null;
  let rat: RateEffect | null = null;

  if (isContinuous) {
    cont = continuousEffect(
      exposed.map((g) => g.x),
      baseline.map((g) => g.x),
      groups.map((g) => g.x),
    );
    effect = cont.effect;
    base_rate = cont.baselineMean;
    conditional_rate = cont.exposedMean;
  } else {
    rat = rateEffect(
      exposed.map((g) => g.x === 1),
      baseline.map((g) => g.x === 1),
    );
    effect = rat.effect;
    base_rate = rat.baselineRate;
    conditional_rate = rat.exposedRate;
  }

  if (!Number.isFinite(effect) || Math.abs(effect) < floor) return null;
  const overallSign = Math.sign(effect);

  // Gate 3 — split-half confirmation.
  const sh = splitHalf(
    groups.map((g) => ({ x: g.x, exposed: g.exposed, order: g.day.date })),
    isContinuous ? "continuous" : "rate",
    cfg.minHalfSupport,
    floor * cfg.halfEffectFraction,
    overallSign,
  );
  if (!sh.consistent) return null;

  // Passed all gates → grade and package.
  const stability =
    Math.abs(effect) > 0
      ? Math.min(Math.abs(sh.first.effect), Math.abs(sh.second.effect)) / Math.abs(effect)
      : 0;

  const highEffect = isContinuous
    ? Math.abs(effect) >= HIGH_MIN_EFFECT_SD
    : Math.abs(effect) >= HIGH_MIN_EFFECT_RATE;
  const confidence: "medium" | "high" =
    exposed.length >= HIGH_MIN_SUPPORT && highEffect && stability >= HIGH_MIN_STABILITY
      ? "high"
      : "medium";

  const presentDates = groups.map((g) => g.day.date).sort();
  const exposedDates = exposed.map((g) => g.day.date).sort();
  const example_log_ids = exposed
    .map((g) => g.day.logId)
    .filter((id): id is string => id != null)
    .slice(0, 8);

  const evidence: Evidence = {
    n: exposed.length,
    baseline_n: baseline.length,
    base_rate: round(base_rate),
    conditional_rate: round(conditional_rate),
    effect: round(effect),
    effect_unit: isContinuous ? "personal_sd" : "rate_diff",
    window_start: presentDates[0],
    window_end: presentDates[presentDates.length - 1],
    example_log_ids,
    last_instance_at: exposedDates[exposedDates.length - 1],
    split_half: {
      first: { effect: round(sh.first.effect), n: sh.first.n },
      second: { effect: round(sh.second.effect), n: sh.second.n },
    },
    antecedent: h.antecedent.key,
    outcome: h.outcome.key,
    lag: h.lag.key,
  };

  return {
    patternKey: patternKey(h),
    category: resolveCategory(h.antecedent, h.outcome),
    statement: null,
    evidence,
    confidence,
    status: "candidate",
  };
}

/**
 * De-duplicate near-identical patterns and cap the set (§4.2 gate 5).
 * Near-dup = same (antecedent, outcome) pair differing only in lag — we keep
 * the strongest lag. Then rank by confidence × effect × support and cap.
 */
export function capAndDedup(
  observations: SignatureObservation[],
  cap: number,
): SignatureObservation[] {
  const score = (o: SignatureObservation): number => {
    const conf = o.confidence === "high" ? 2 : 1;
    const eff =
      o.evidence.effect_unit === "personal_sd"
        ? Math.abs(o.evidence.effect)
        : Math.abs(o.evidence.effect) / 0.4;
    const support = Math.min(o.evidence.n / 16, 1);
    return conf * 100 + eff * 10 + support;
  };

  const ranked = [...observations].sort((a, b) => score(b) - score(a));

  const seen = new Set<string>();
  const deduped: SignatureObservation[] = [];
  for (const o of ranked) {
    const family = `${o.evidence.antecedent}:${o.evidence.outcome}`;
    if (seen.has(family)) continue;
    seen.add(family);
    deduped.push(o);
  }

  return deduped.slice(0, cap);
}

function round(x: number): number {
  return Number.isFinite(x) ? Math.round(x * 1000) / 1000 : x;
}
