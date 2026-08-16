// ============================================================================
// fitnessCurve.ts — damping for the fitness estimate.
//
// WHY THIS EXISTS. `generateFitnessPrediction` re-derives the estimate from
// near-scratch every night, off a rolling 14-day window of quality work. That
// window turns over as sessions age in and out, so the raw estimate moves for
// reasons that have nothing to do with the athlete. Observed on the
// calibration athlete, two runs on the SAME DAY:
//
//     2026-08-15 03:30   32:00
//     2026-08-15 15:03   33:44      ← 104 s apart, same body
//
// What has been hiding this is not smoothing — it is the ±2% validation band
// and the ±5% race clamp, which pin the number flat until the pin moves and
// then it jumps. Flat, flat, flat, jump is the wrong shape twice over.
//
// THE MODEL. Fitness is an ACCUMULATION. One session is evidence, not a
// measurement: some days are tired, some are worn down, some are the best
// you've felt in a month. A single workout should nudge the curve; a month of
// them should move it. So the state moves a fraction of the way toward each
// new observation rather than jumping to it:
//
//     smoothed = prior + (raw − prior) · α,     α = 1 − exp(−Δt / τ)
//
// Exponential, so old evidence fades on its own. That is the crucial
// difference from the "snapshots feed snapshots" ratchet the anti-ratchet
// comment in fitnessPrediction.ts warns about: THAT compounds the OUTPUT, so a
// transient fast reading persists for months. THIS accumulates EVIDENCE with
// decay, so a flattering day is outvoted by the fortnight around it and then
// forgotten.
//
// Irregular sampling is handled honestly. Δt is real elapsed days, so a gap
// (missed cron, app closed for a week) lets the curve travel further rather
// than pretending the last sample was yesterday.
//
// WHAT IS ALLOWED TO MOVE IT HARD. A declared race or time trial. That is a
// measurement, not evidence, and it resets the level outright — the same
// principle the anchor already runs on: races are declared, never inferred.
//
// Pure functions, no I/O. Tests: fitnessCurve.test.ts.
// ============================================================================

/** Days for the curve to close ~63% of a gap. Three weeks: a strong week
 *  nudges, a strong month moves it. Deliberately slower than a training block
 *  is long, so the curve describes the block rather than chasing it. */
export const DEFAULT_TAU_DAYS = 21;

/** Hard ceiling on one day's movement, as a fraction of pace. 0.5% of a ~5:10
 *  10K pace is ~1.5 s/mi ≈ 10 s over 10K. Enough for a genuine block to move
 *  the curve in a fortnight; not enough for any single session to jolt it,
 *  whatever the evidence claims. Belt and braces with α — α alone already
 *  limits movement, but a huge raw swing (window turnover, a mis-parsed
 *  session) can still clear it. */
export const MAX_DAILY_MOVE_PCT = 0.005;

/** Beyond this gap, treat the prior as too stale to damp against — the athlete
 *  has been away and the curve should re-seat on current evidence rather than
 *  crawl back from a months-old level. */
export const STALE_PRIOR_DAYS = 45;

export interface CurveInput {
  /** Tonight's raw estimate (sec/mile at 10K pace). */
  rawPace: number;
  /** The last SMOOTHED value, or null on first run / after a long gap. */
  priorPace: number | null;
  /** Real elapsed days since `priorPace` was recorded. */
  deltaDays: number;
  /** A race or time trial was declared in this window — reset, don't damp. */
  hardReset?: boolean;
  tauDays?: number;
  maxDailyMovePct?: number;
}

export interface CurveResult {
  /** What to store and serve. */
  pace: number;
  /** Fraction of the gap actually travelled (0 = held, 1 = jumped to raw). */
  alpha: number;
  /** True when MAX_DAILY_MOVE_PCT bound the step rather than α. */
  capped: boolean;
  /** Why the curve behaved as it did — for the honest-coverage note. */
  reason: "first-sample" | "stale-prior" | "hard-reset" | "damped";
}

/**
 * Move the fitness curve toward tonight's raw estimate.
 *
 * Returns `rawPace` unchanged on the first sample, after a stale gap, or on a
 * declared race — those are the three cases where damping would be lying about
 * what we know. Otherwise the step is `α` of the gap, then clamped to
 * `maxDailyMovePct` of the prior.
 */
export function smoothFitnessPace(input: CurveInput): CurveResult {
  const {
    rawPace,
    priorPace,
    deltaDays,
    hardReset = false,
    tauDays = DEFAULT_TAU_DAYS,
    maxDailyMovePct = MAX_DAILY_MOVE_PCT,
  } = input;

  if (!(rawPace > 0) || !isFinite(rawPace)) {
    return { pace: rawPace, alpha: 1, capped: false, reason: "first-sample" };
  }
  if (hardReset) {
    return { pace: rawPace, alpha: 1, capped: false, reason: "hard-reset" };
  }
  if (priorPace == null || !(priorPace > 0) || !isFinite(priorPace)) {
    return { pace: rawPace, alpha: 1, capped: false, reason: "first-sample" };
  }
  if (!(deltaDays >= 0) || !isFinite(deltaDays) || deltaDays > STALE_PRIOR_DAYS) {
    return { pace: rawPace, alpha: 1, capped: false, reason: "stale-prior" };
  }

  // Two samples the same day (a manual run alongside the cron) must not each
  // take a full day's step — that is how 32:00 and 33:44 landed hours apart.
  // A zero gap moves nothing; the curve advances on elapsed time, not on how
  // often we happened to recompute.
  const alpha = 1 - Math.exp(-Math.max(deltaDays, 0) / Math.max(tauDays, 0.5));

  let next = priorPace + (rawPace - priorPace) * alpha;

  // Cap scales with the gap too, so a legitimate week-long absence can still
  // travel a week's worth rather than one day's.
  const maxMove = priorPace * maxDailyMovePct * Math.max(deltaDays, 1);
  const move = next - priorPace;
  let capped = false;
  if (Math.abs(move) > maxMove) {
    next = priorPace + Math.sign(move) * maxMove;
    capped = true;
  }

  return { pace: next, alpha, capped, reason: "damped" };
}

/**
 * Pick the most recent prior smoothed value from snapshot history.
 *
 * Deliberately MOST RECENT, never fastest. "Fastest in N weeks" is the
 * ratchet — it lets one flattering reading set a floor that outlives the
 * fitness that produced it. The curve's own decay is what protects against
 * noise; the selection rule must not add a second, one-directional memory.
 */
export function mostRecentPrior<T extends { createdAt: string; estimated10kPaceSeconds: number }>(
  snapshots: readonly T[],
  before: Date,
): { pace: number; deltaDays: number } | null {
  let best: T | null = null;
  let bestMs = -Infinity;
  const beforeMs = before.getTime();

  for (const s of snapshots) {
    const ms = new Date(s.createdAt).getTime();
    if (!isFinite(ms) || ms > beforeMs) continue;
    if (!(s.estimated10kPaceSeconds > 0)) continue;
    if (ms > bestMs) { bestMs = ms; best = s; }
  }
  if (best == null) return null;
  return {
    pace: best.estimated10kPaceSeconds,
    deltaDays: (beforeMs - bestMs) / 86_400_000,
  };
}
