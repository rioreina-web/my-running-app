// ============================================================================
// fitnessEstimator.ts — one uncertainty-weighted estimator.
//
// Replaces the clamp stack (FITNESS-REDESIGN-APPLY.md Phase 1). The shipped
// engine reaches its number by anchoring on the last race and then defending
// that anchor with eight stacked bounds — a decay ladder, a maintenance
// factor, a build gate, athlete-aware credit caps, displacement caps, a
// one-way EF gate, an unproven-improvement ceiling and a continuous-training
// 2% cap. Replay measured the consequence: across the 56 days before the April
// race the estimate moved TEN SECONDS. The clamps do not express a belief
// about fitness; they express distrust of the evidence, and they are applied
// after the fact rather than while weighing it.
//
// THE MODEL. State is a level with a variance. Every performance is an
// observation with a variance. Combining them is one line of arithmetic —
// the same empirical-Bayes shrinkage `raceCurve.ts` already uses for the
// exponent, applied recursively:
//
//     K    = priorVar / (priorVar + obsVar)      ← how much to believe this
//     post = prior + K · (obs − prior)
//     var  = (1 − K) · priorVar
//
// A clamp is what you write when you cannot say how much you trust something.
// Once observations carry variances, "don't let training move the number more
// than 2%" stops being a rule and becomes an outcome: thin evidence has a
// large variance, so K is small, so it moves the number a little. Strong
// evidence moves it a lot. Nothing has to be capped, because nothing was ever
// unconditionally trusted.
//
// WHY LOG SPACE. Fitness effects are multiplicative — heat costs a percentage,
// a rep is a percentage off race pace, a week of detraining is a percentage.
// In log-pace space those are additive with a scale-free variance, so one
// process variance is meaningful for a 15:00 5K runner and a 30:00 one alike.
// It also makes the posterior range multiplicative, which is what an honest
// range on a pace actually is.
//
// THE PROCESS MODEL IS A RANDOM WALK, NOT A DRIFT. Between observations the
// estimate does not move on its own; only its variance grows. That is the
// direct fix for "the number is pinned to the last race": as a race ages its
// evidence does not decay, but the state's uncertainty grows, so the next
// session is weighed against a wider prior and moves it further. Deterministic
// drift enters in exactly one place — sustained load collapse (`detrainDrift`)
// — because that is the one case where the ABSENCE of evidence is itself
// evidence. The decay ladder tried to do this for every athlete at all times.
//
// WHAT IS DELIBERATELY NOT HERE: no anchor, no displacement cap, no validation
// band, no build gate, no credit ceiling. The PR floor survives as the only
// bound and is applied by the caller, same-distance only, because it encodes a
// fact (they ran that) rather than a doubt.
//
// Pure functions, no I/O. Tests: fitnessEstimator.test.ts.
// ============================================================================

/**
 * How much a genuinely-training athlete's fitness moves in a week, as a
 * fraction — the random walk's step. This is the estimator's one true
 * responsiveness knob and it replaces roughly eight of them.
 *
 * 0.9%/week is the scale at which real training blocks move real runners: an
 * eight-week build closing a 5-7% race-to-training gap is the case
 * `evidenceBlend.ts` was built around and the one this has to reproduce. Set
 * it much lower and the estimate pins to its last race exactly as the clamp
 * stack did; much higher and a single mis-parsed session swings the number.
 *
 * It is scored, not asserted. Swept against the session-residual loss on the
 * calibration athlete (2026-08-27, `--estimator --process-sd=`):
 *
 *     0.002 → 2.72%   0.004 → 2.51%   0.006 → 2.49%   0.009 → 2.55%
 *
 * A shallow minimum at 0.006, which is what ships here. Read the number with
 * its context, though: every one of those is WORSE than the shipped model's
 * 2.28% on the same 23 sessions. This constant is at its measured best and the
 * estimator still does not pass its gate — see FITNESS-G0-FINISH-APPLY §8.
 */
export const PROCESS_SD_PER_WEEK = 0.006;

/** Prior width at a true cold start — before any observation, ±12% at 1σ. */
export const COLD_START_SD = 0.12;

/**
 * Ceiling on state uncertainty. Without it a long layoff drives the variance
 * so wide that the first session back is believed almost completely, which is
 * how you get a single workout after eight weeks off declaring a PR.
 */
export const MAX_STATE_SD = 0.15;

/**
 * Sustained load collapse drifts the estimate slower, per week, at total
 * collapse. This is the ONE deterministic term: when an athlete stops
 * training, the absence of sessions is itself the evidence, and a pure random
 * walk would hold the old number forever with growing error bars.
 *
 * Athlete-relative — driven by load against the athlete's OWN reference
 * volume, never an absolute mileage (see feedback_no_hardcoded_paces).
 */
export const DETRAIN_PCT_PER_WEEK = 0.006;

/** Below this fraction of reference load, detraining drift starts. */
export const DETRAIN_LOAD_THRESHOLD = 0.6;

export type ObservationKind = "race" | "session" | "efficiency";

export interface Observation {
  /** "yyyy-MM-dd" — when the performance happened, not when it synced. */
  date: string;
  kind: ObservationKind;
  /**
   * What this performance says the athlete's pace is at the state's reference
   * distance (sec/mile). The caller converts along the athlete's own curve.
   */
  pace: number;
  /**
   * How uncertain that statement is, as a fraction of pace at 1σ. 0.01 means
   * "this says 10K pace to within about 1%". This is the whole interface —
   * everything the old model expressed as a cap is expressed here instead.
   */
  sd: number;
  /** Plain-language account, carried into diagnostics. */
  why: string;
}

export interface LoadDay {
  date: string;
  /** Weekly-equivalent load at this date, as a fraction of the athlete's own
   *  reference (1.0 = their normal). Athlete-relative by construction. */
  relativeLoad: number;
}

export interface EstimatorInput {
  observations: readonly Observation[];
  now: Date;
  /** Optional; without it the process model is a pure random walk. */
  load?: readonly LoadDay[];
  /** Seed for the recursion. Omit for a cold start. */
  prior?: { pace: number; sd: number; date: string } | null;
  /** Override the random-walk step. Exists so the replay can SWEEP it against
   *  the session-residual loss rather than assert it — see PROCESS_SD_PER_WEEK. */
  processSdPerWeek?: number;
}

export interface EstimatorStep {
  date: string;
  kind: ObservationKind;
  observed: number;
  /** Kalman gain — how much of this observation was believed, 0..1. */
  gain: number;
  before: number;
  after: number;
  sdAfter: number;
  why: string;
}

export interface EstimatorResult {
  /** Posterior mean pace at the reference distance, sec/mile. */
  pace: number;
  /** Posterior SD as a fraction of pace — the honest range, not a tier. */
  sd: number;
  observationCount: number;
  /** Every update, in order. The workings, for `diagnostics`. */
  steps: EstimatorStep[];
  why: string;
}

const DAY = 86_400_000;
const parseDay = (s: string): Date | null => {
  const d = new Date(`${s}T00:00:00.000Z`);
  return Number.isNaN(d.getTime()) ? null : d;
};
const clampSd = (sd: number) => Math.min(Math.max(sd, 1e-4), MAX_STATE_SD);

/**
 * Advance the state to `days` later: variance grows by the random walk, and
 * sustained load collapse drifts the level slower.
 *
 * Variances add in log space, which is why the walk is `sd² · weeks` and not
 * `sd · weeks` — two weeks of uncertainty is √2 times one week's, not twice.
 */
function advance(
  level: number,
  variance: number,
  days: number,
  relativeLoad: number | null,
  processSd: number,
): { level: number; variance: number } {
  if (!(days > 0)) return { level, variance };
  const weeks = days / 7;
  let v = variance + (processSd ** 2) * weeks;
  v = Math.min(v, MAX_STATE_SD ** 2);

  let l = level;
  if (relativeLoad !== null && relativeLoad < DETRAIN_LOAD_THRESHOLD) {
    // Linear in the shortfall: at half the threshold, half the drift. A step
    // function here would make the estimate jump on a single light week.
    const shortfall = (DETRAIN_LOAD_THRESHOLD - relativeLoad) / DETRAIN_LOAD_THRESHOLD;
    l += DETRAIN_PCT_PER_WEEK * shortfall * weeks; // +log pace = slower
  }
  return { level: l, variance: v };
}

/** Mean relative load over a window, or null when nothing is on file. */
function loadBetween(load: readonly LoadDay[], from: Date, to: Date): number | null {
  const inRange = load.filter((d) => {
    const t = parseDay(d.date)?.getTime();
    return t != null && t > from.getTime() && t <= to.getTime() && Number.isFinite(d.relativeLoad);
  });
  if (inRange.length === 0) return null;
  return inRange.reduce((s, d) => s + d.relativeLoad, 0) / inRange.length;
}

/**
 * Run the recursion. Observations are applied oldest-first; each one is
 * weighed against the state as it stood at that moment, never against a state
 * that already contains it.
 *
 * Returns null when there is nothing to say. Abstention is a feature: a
 * fabricated number with a wide range is still fabricated.
 */
export function estimateFitness(input: EstimatorInput): EstimatorResult | null {
  const usable = input.observations
    .filter((o) => o.pace > 0 && Number.isFinite(o.pace) && o.sd > 0 && Number.isFinite(o.sd) && parseDay(o.date))
    .slice()
    .sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));

  if (usable.length === 0 && !input.prior) return null;

  const load = input.load ?? [];
  const processSd = input.processSdPerWeek && input.processSdPerWeek > 0
    ? input.processSdPerWeek
    : PROCESS_SD_PER_WEEK;
  const steps: EstimatorStep[] = [];

  // Cold start = a wide prior at the first observation, then the ordinary
  // update. There is no separate cold-start path to keep in sync — the
  // difference between "no history" and "lots of history" is a variance.
  let level: number;
  let variance: number;
  let at: Date;
  if (input.prior && input.prior.pace > 0) {
    level = Math.log(input.prior.pace);
    variance = clampSd(input.prior.sd) ** 2;
    at = parseDay(input.prior.date) ?? parseDay(usable[0]!.date)!;
  } else {
    const first = usable[0]!;
    level = Math.log(first.pace);
    variance = COLD_START_SD ** 2;
    at = parseDay(first.date)!;
  }

  for (const o of usable) {
    const when = parseDay(o.date)!;
    const days = (when.getTime() - at.getTime()) / DAY;
    const adv = advance(level, variance, days, loadBetween(load, at, when), processSd);
    level = adv.level;
    variance = adv.variance;
    at = when;

    const obsVar = clampSd(o.sd) ** 2;
    const gain = variance / (variance + obsVar);
    const before = Math.exp(level);
    level = level + gain * (Math.log(o.pace) - level);
    variance = (1 - gain) * variance;

    steps.push({
      date: o.date,
      kind: o.kind,
      observed: o.pace,
      gain,
      before,
      after: Math.exp(level),
      sdAfter: Math.sqrt(variance),
      why: o.why,
    });
  }

  // Carry the state forward to `now` — an estimate quoted today off a race
  // eight weeks ago is more uncertain than it was on the day, and says so.
  const tail = advance(
    level, variance, (input.now.getTime() - at.getTime()) / DAY,
    loadBetween(load, at, input.now), processSd,
  );
  level = tail.level;
  variance = tail.variance;

  const sd = clampSd(Math.sqrt(variance));
  const races = usable.filter((o) => o.kind === "race").length;
  const sessions = usable.filter((o) => o.kind === "session").length;
  return {
    pace: Math.exp(level),
    sd,
    observationCount: usable.length,
    steps,
    why: `${usable.length} observations (${races} race, ${sessions} session) → ` +
      `${Math.exp(level).toFixed(1)} s/mi ±${(sd * 100).toFixed(1)}%`,
  };
}

// ---------------------------------------------------------------------------
// Observation builders — where "how much do we trust this" is actually decided.
// ---------------------------------------------------------------------------

/** Base uncertainty of a raced result at a known distance, before conditions. */
export const RACE_BASE_SD = 0.006;

/**
 * A race, priced by how much correcting it required.
 *
 * `correctionFraction` is the size of the conditions adjustment already
 * applied (0.02 = the neutral time is 2% faster than the raw). A race run in
 * ideal conditions is the strongest evidence this model ever sees; one that
 * needed a 4% heat correction is a 4%-corrected number and its uncertainty
 * should say so. This REPLACES `SHAPE_MAX_CORRECTION_PCT` and the
 * race-beats-floor special case: instead of excluding a heavily-corrected race
 * by rule, it is admitted with the weight its correction earns it.
 */
export function raceObservation(
  neutralPace: number,
  correctionFraction: number,
  date: string,
  label: string,
): Observation {
  const c = Math.abs(Number.isFinite(correctionFraction) ? correctionFraction : 0);
  // Half the correction as added uncertainty: a 4% correction is not 4%
  // uncertain — the dew-point model is better than that — but it is not free.
  const sd = RACE_BASE_SD + c * 0.5;
  return {
    date,
    kind: "race",
    pace: neutralPace,
    sd,
    why: c > 0.001
      ? `${label} — neutralized ${(c * 100).toFixed(1)}%, ±${(sd * 100).toFixed(1)}%`
      : `${label} — ideal conditions, ±${(sd * 100).toFixed(1)}%`,
  };
}

/**
 * A quality session, priced by how much of it there was and how far off the
 * curve it landed.
 *
 * The zone signal's ratio is already a duration-local statement about the
 * level and the anchor cancels out of it, so it needs no conversion — only a
 * variance. Three things widen it, and none of them is a cap:
 *
 *   - thin work. 8 minutes of reps says less than 40. Scales as 1/√minutes,
 *     the ordinary standard-error-of-a-mean shape, so this is not a knob.
 *   - low parser confidence, which is uncertainty about the GEOMETRY rather
 *     than the performance and belongs here rather than in an exclusion rule.
 *   - distance from the curve. A session 8% off is more likely to be a
 *     mis-parse than one 1% off, and inflating its variance is the graceful
 *     version of the plausibility window's hard cut.
 */
export const SESSION_BASE_SD = 0.010;
export const SESSION_REFERENCE_MINUTES = 25;

export function sessionObservation(
  equivalentPace: number,
  workMinutes: number,
  ratio: number,
  confidence: number,
  date: string,
  label: string,
): Observation {
  const minutes = Math.max(workMinutes, 1);
  const thinness = Math.sqrt(SESSION_REFERENCE_MINUTES / minutes);
  const conf = Math.min(Math.max(Number.isFinite(confidence) ? confidence : 0.5, 0.1), 1);
  const offCurve = Math.abs((Number.isFinite(ratio) ? ratio : 1) - 1);
  const sd = SESSION_BASE_SD * thinness / conf + offCurve * 0.5;
  return {
    date,
    kind: "session",
    pace: equivalentPace,
    sd,
    why: `${label} — ${Math.round(minutes)} min work, ${(offCurve * 100).toFixed(1)}% off curve, ±${(sd * 100).toFixed(1)}%`,
  };
}
