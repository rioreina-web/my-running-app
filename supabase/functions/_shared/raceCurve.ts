// ============================================================================
// raceCurve.ts — the athlete's own distance curve, fitted from their races.
//
// WHY THIS EXISTS. The predictor carries ONE number — a 10K-equivalent — and
// derives every other distance from it through a fixed ratio table. That table
// encodes a single fatigue exponent (~1.06, the Riegel default) applied to
// everyone. It is a population average wearing the costume of a fact.
//
// Race time scales with distance as  T = a · D^b.  `b` is how much you slow
// down as the distance grows, and it is the thing that separates two runners
// with identical 10Ks into a four-minute marathon gap. It IS marathon fitness,
// expressed as a number: a low exponent means you hold pace.
//
// Measured on the calibration athlete, before any fitting:
//
//     half 1:08:39 vs 10K 31:20   →  b = 1.051
//     marathon 2:22:43 vs 10K 31:20 →  b = 1.053
//     generic                      →  b = 1.059 – 1.062
//
// Two independent races, thirteen months apart, agreeing to 0.002. That is a
// stable property of the runner, and the model was throwing it away and
// substituting someone else's.
//
// THE SPLIT THAT MAKES THIS WORK. Two parameters, estimated from different
// evidence and over different timescales:
//
//   • LEVEL — how fast you are now. Moves week to week. Comes from recent
//     training and recent races. NOT this module's job.
//   • EXPONENT — how well you hold it. A structural property of the runner
//     that changes over seasons, not sessions. Fitted here from EVERY race
//     they have, at any age, because a two-year-old marathon still tells you
//     about durability even though it says nothing about current speed.
//
// That split is also what stops any single race being load-bearing. One race
// gives a level and a borrowed exponent. Two at different distances give both.
// Five give both plus a drift term. No athlete's model rests on one result.
//
// SHRINKAGE, NOT A CLIFF. A fit from two close-together races is barely
// evidence; a fit from five spread across 5K to marathon is strong. Rather
// than a coverage rule with a threshold, the fitted exponent is shrunk toward
// the generic one in proportion to its own standard error (empirical Bayes).
// Thin evidence lands near 1.06 on its own; good evidence overrides it. There
// is no minimum-races rule to tune, and no athlete falls off a cliff.
//
// Pure functions, no I/O. Tests: raceCurve.test.ts.
// ============================================================================

/** Riegel's exponent — the population default this shrinks toward. */
export const GENERIC_EXPONENT = 1.06;

/**
 * Prior spread of `b` across runners, used as the shrinkage scale. Real
 * exponents run roughly 1.02 (track-speed types who fade) to 1.10 (durable
 * aerobic types), so a standard deviation near 0.02 is the honest prior.
 * A fitted `b` with standard error much below this survives largely intact;
 * one with error much above it is pulled back to generic.
 */
export const EXPONENT_PRIOR_SD = 0.02;

/** Exponents outside this are a data error, not a runner. */
export const MIN_EXPONENT = 1.00;
export const MAX_EXPONENT = 1.14;

/** Two races closer than this in log-distance barely constrain the slope. */
const MIN_LOG_SPREAD = Math.log(1.5);

export interface RacePoint {
  /** "yyyy-MM-dd". */
  date: string;
  /** Race distance in kilometres. */
  distanceKm: number;
  /**
   * Finish time in seconds. Prefer the CONDITIONS-NORMALIZED time when one is
   * available — a hot hilly race and a cool flat one are different statements
   * about durability, and the exponent should be fitted on the flat-cool
   * equivalent. Raw is acceptable; it just adds noise.
   */
  seconds: number;
}

export interface RaceCurve {
  /** The exponent actually to use: fitted, shrunk toward generic by evidence. */
  exponent: number;
  /** The raw least-squares fit, before shrinkage. Null when unfittable. */
  fittedExponent: number | null;
  /** Standard error of the raw fit. Null when unfittable. */
  fittedStandardError: number | null;
  /** Weight the fit received, 0..1. 0 = pure generic, 1 = pure athlete. */
  evidenceWeight: number;
  /** Fitness drift in %/year implied by the fit (negative = getting faster). */
  driftPctPerYear: number | null;
  racesUsed: number;
  distinctDistances: number;
  /** Plain-language account, for the honesty surface. */
  why: string;
}

/** Solve a small symmetric normal-equation system by Gaussian elimination. */
function solve(A: number[][], b: number[]): number[] | null {
  const n = b.length;
  const M = A.map((row, i) => [...row, b[i]]);
  for (let i = 0; i < n; i++) {
    let p = i;
    for (let r = i + 1; r < n; r++) if (Math.abs(M[r][i]) > Math.abs(M[p][i])) p = r;
    if (Math.abs(M[p][i]) < 1e-12) return null;
    [M[i], M[p]] = [M[p], M[i]];
    for (let r = 0; r < n; r++) {
      if (r === i) continue;
      const f = M[r][i] / M[i][i];
      for (let c = i; c <= n; c++) M[r][c] -= f * M[i][c];
    }
  }
  return M.map((row, i) => row[n] / M[i][i]);
}

const dayNumber = (iso: string): number | null => {
  const t = Date.parse(`${iso.slice(0, 10)}T00:00:00Z`);
  return Number.isFinite(t) ? t / 86_400_000 : null;
};

/**
 * Fit the athlete's distance curve.
 *
 * `ln T = c + b·ln D + k·yearsAgo` — the drift term is included only when
 * there are enough races to afford it, and it matters: without it, a runner
 * whose 5K is from two years ago and whose 10K is current has their fitness
 * improvement absorbed into the exponent, which is exactly the wrong place
 * for it.
 *
 * `now` is passed rather than read so this stays pure and testable.
 */
export function fitRaceCurve(races: readonly RacePoint[], now: Date): RaceCurve {
  const pts = races
    .map((r) => ({ ...r, day: dayNumber(r.date) }))
    .filter((r): r is RacePoint & { day: number } =>
      r.day !== null && r.distanceKm > 0 && r.seconds > 0
    );

  const distances = new Set(pts.map((p) => Math.round(p.distanceKm * 100) / 100));
  const generic = (why: string): RaceCurve => ({
    exponent: GENERIC_EXPONENT,
    fittedExponent: null,
    fittedStandardError: null,
    evidenceWeight: 0,
    driftPctPerYear: null,
    racesUsed: pts.length,
    distinctDistances: distances.size,
    why,
  });

  if (pts.length < 2 || distances.size < 2) {
    return generic(
      `${pts.length} race${pts.length === 1 ? "" : "s"} at ${distances.size} distance${
        distances.size === 1 ? "" : "s"
      } — need two distances to see a curve, so using the generic exponent ${GENERIC_EXPONENT}`,
    );
  }

  const logD = pts.map((p) => Math.log(p.distanceKm));
  const spread = Math.max(...logD) - Math.min(...logD);
  if (spread < MIN_LOG_SPREAD) {
    return generic(
      `races span only ${(Math.exp(spread)).toFixed(1)}× in distance — too narrow to fit a slope`,
    );
  }

  const nowDay = now.getTime() / 86_400_000;
  const y = pts.map((p) => Math.log(p.seconds));
  // Drift costs a degree of freedom; only afford it with a race to spare.
  const useDrift = pts.length >= 4;
  const X = pts.map((p, i) =>
    useDrift ? [1, logD[i], (nowDay - p.day) / 365.25] : [1, logD[i]]
  );
  const k = X[0].length;

  const A = Array.from({ length: k }, (_, a) =>
    Array.from({ length: k }, (_, b) => X.reduce((s, row) => s + row[a] * row[b], 0))
  );
  const B = Array.from({ length: k }, (_, a) => X.reduce((s, row, i) => s + row[a] * y[i], 0));
  const beta = solve(A, B);
  if (beta === null) return generic("race times are collinear — no unique curve");

  const fitted = beta[1];
  const drift = useDrift ? beta[2] : null;

  // Residual variance → standard error of the slope, via (XᵀX)⁻¹ diagonal.
  const dof = pts.length - k;
  let sse = 0;
  for (let i = 0; i < pts.length; i++) {
    const pred = X[i].reduce((s, v, j) => s + v * beta[j], 0);
    sse += (y[i] - pred) ** 2;
  }
  // With zero degrees of freedom the fit is exact and tells us nothing about
  // its own reliability — fall back to the prior scale rather than claim
  // perfect precision, which would let two races override everything.
  const sigma2 = dof > 0 ? sse / dof : NaN;
  const inv = solve(A, Array.from({ length: k }, (_, i) => (i === 1 ? 1 : 0)));
  const se = dof > 0 && inv !== null && sigma2 >= 0
    ? Math.sqrt(Math.max(sigma2 * inv[1], 0))
    : EXPONENT_PRIOR_SD;

  // Empirical-Bayes shrinkage toward the generic exponent.
  const w = EXPONENT_PRIOR_SD ** 2 / (EXPONENT_PRIOR_SD ** 2 + Math.max(se, 1e-6) ** 2);
  let exponent = GENERIC_EXPONENT + w * (fitted - GENERIC_EXPONENT);
  exponent = Math.min(Math.max(exponent, MIN_EXPONENT), MAX_EXPONENT);

  const pct = (w * 100).toFixed(0);
  return {
    exponent,
    fittedExponent: fitted,
    fittedStandardError: se,
    evidenceWeight: w,
    driftPctPerYear: drift === null ? null : (Math.exp(drift) - 1) * 100,
    racesUsed: pts.length,
    distinctDistances: distances.size,
    why: `${pts.length} races across ${distances.size} distances → b = ${fitted.toFixed(4)} ` +
      `(±${se.toFixed(4)}), weighted ${pct}% against generic ${GENERIC_EXPONENT} → ${exponent.toFixed(4)}`,
  };
}

/**
 * Convert a time at one distance to another along the athlete's own curve.
 *
 *   T2 = T1 · (D2 / D1)^b
 *
 * This is the seam that replaces the fixed ratio table. Pass the same
 * `RaceCurve` everywhere so one athlete has one curve — the whole point is
 * that the mile and the marathon come off the same fitted shape rather than
 * off a table nobody measured on this runner.
 */
export function convertAlongCurve(
  seconds: number,
  fromKm: number,
  toKm: number,
  curve: Pick<RaceCurve, "exponent">,
): number {
  if (!(seconds > 0) || !(fromKm > 0) || !(toKm > 0)) return seconds;
  return seconds * Math.pow(toKm / fromKm, curve.exponent);
}

/** Race distances in km, for callers holding the app's RaceType vocabulary. */
export const RACE_KM = {
  mile: 1.609344,
  threeK: 3,
  fiveK: 5,
  tenK: 10,
  tenMi: 16.09344,
  half: 21.0975,
  marathon: 42.195,
} as const;
