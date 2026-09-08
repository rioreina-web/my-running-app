// ============================================================================
// expectedHr.ts — what heart rate SHOULD have been, and what the gap means.
//
// A heart rate on its own says nothing. 164 bpm is a hard session or an easy
// one depending on the pace, the air, and how far into the workout it was.
// So the signal is not the heart rate — it is the difference between the
// heart rate and what that pace, in that heat, at that point in the session,
// should have cost.
//
//     expected = f(speed, dew point, time into session)
//     residual = actual − expected        (negative = cheaper than expected)
//
// A residual trending negative over weeks is the athlete getting fitter: the
// same work for fewer beats. That is the fitness marker, and it needs no max
// heart rate, no race heart rate, and no assumption about what the athlete
// could sustain in a race — all of which are either unknown or, on this
// athlete's file, absent entirely (neither 10K race has HR recorded).
//
// WHY THE CONTROLS ARE NOT OPTIONAL. Measured on the calibration athlete,
// quality reps at 4:50–5:40/mi, raw efficiency by month:
//
//     Apr  EF 1.888   dew 68.5
//     Aug  EF 1.832   dew 75.5
//
// Read naively that is a 3% decline — the athlete getting worse. But dew rose
// seven degrees over the same stretch, and at the measured heat sensitivity
// (−0.0089 EF per °F) seven degrees predicts −0.062 against an observed
// −0.056. The entire decline is the weather. Controlled, efficiency is flat.
// Without the controls the signal reads BACKWARDS, which is why heart rate
// has never been trusted here.
//
// FITTED PER ATHLETE, NOT ASSUMED. The coefficients come from the athlete's
// own reps. There is no population HR model, no percentage-of-max, no
// reserve formula. Two runners at the same pace and the same heart rate are
// not making the same statement, and nothing here pretends otherwise.
//
// WHAT THIS DOES NOT DO. It does not detect fatigue. That was tested against
// this athlete's history on 2026-08-07 and failed for a structural reason:
// when a runner feels rough they run easier, so heart-rate-at-pace falls
// instead of rising, and the physiological and behavioural signals point
// opposite ways. This asks a different question — at a pace the athlete DID
// run, was it cheaper than before — where the behaviour is an input rather
// than a confound.
//
// Pure functions, no I/O. Tests: expectedHr.test.ts.
// ============================================================================

const METERS_PER_MILE = 1609.344;

/** Below this there is not enough history to fit anything honest. */
export const MIN_SAMPLES = 20;

/**
 * Bounds wide enough for any runner, not for one.
 *
 * These exist to exclude GPS lies and stopped clocks, nothing else. An earlier
 * draft used 240–700 s/mi, which is 4:00 to 11:40 — a range drawn from the
 * calibration athlete and one that would have discarded the quality work of
 * most people who will ever use this. 150 s/mi is faster than a world record
 * mile; 1500 is a brisk walk. If a rep is outside that, it is not a rep.
 */
const MIN_HR = 80;
const MAX_HR = 220;
const MIN_PACE_SEC = 150;
const MAX_PACE_SEC = 1500;

export interface HrSample {
  /** "yyyy-MM-dd". */
  date: string;
  /** Observed pace, sec/mile. RAW — heat is a model input, not pre-removed. */
  paceSecPerMile: number;
  /** Observed average heart rate for the rep. */
  hr: number;
  /** Rep duration in seconds. */
  durationSeconds: number;
  /** Dew point °F on the day. Heat's grip is humidity, not temperature. */
  dewPointF: number;
}

export interface ExpectedHrModel {
  /** intercept, bpm per m/min, bpm per °F dew, bpm per ln(second). */
  coefficients: [number, number, number, number];
  /** Residual standard deviation, bpm — how tightly it actually predicts. */
  residualSd: number;
  samples: number;
  why: string;
}

export interface EfficiencyTrend {
  /** Mean residual in the recent window, bpm. Negative = cheaper than expected. */
  recentBpm: number;
  /** Mean residual in the baseline window, bpm. */
  baselineBpm: number;
  /** recent − baseline. Negative = getting fitter. */
  deltaBpm: number;
  /**
   * The same change expressed as pace, sec/mile, using the model's own
   * speed coefficient: how much faster the athlete could run at unchanged
   * heart rate. Negative = faster. Derived, never a separate constant.
   */
  deltaPaceSecPerMile: number;
  recentSamples: number;
  baselineSamples: number;
  why: string;
}

const dayOf = (iso: string): number | null => {
  const t = Date.parse(`${iso.slice(0, 10)}T00:00:00Z`);
  return Number.isFinite(t) ? t / 86_400_000 : null;
};

const usable = (s: HrSample): boolean =>
  Number.isFinite(s.hr) && s.hr >= MIN_HR && s.hr <= MAX_HR &&
  s.paceSecPerMile >= MIN_PACE_SEC && s.paceSecPerMile <= MAX_PACE_SEC &&
  s.durationSeconds >= 60 && Number.isFinite(s.dewPointF) &&
  dayOf(s.date) !== null;

/** Predictor row: [1, speed m/min, dew °F, ln(duration s)]. */
const row = (s: HrSample): number[] => [
  1,
  METERS_PER_MILE * 60 / s.paceSecPerMile,
  s.dewPointF,
  Math.log(Math.max(s.durationSeconds, 1)),
];

/** Gaussian elimination on the normal equations. */
function solve(A: number[][], b: number[]): number[] | null {
  const n = b.length;
  const M = A.map((r, i) => [...r, b[i]]);
  for (let i = 0; i < n; i++) {
    let p = i;
    for (let r = i + 1; r < n; r++) if (Math.abs(M[r][i]) > Math.abs(M[p][i])) p = r;
    if (Math.abs(M[p][i]) < 1e-10) return null;
    [M[i], M[p]] = [M[p], M[i]];
    for (let r = 0; r < n; r++) {
      if (r === i) continue;
      const f = M[r][i] / M[i][i];
      for (let c = i; c <= n; c++) M[r][c] -= f * M[i][c];
    }
  }
  return M.map((r, i) => r[n] / M[i][i]);
}

/** Fit expected heart rate from the athlete's own reps. */
export function fitExpectedHr(samples: readonly HrSample[]): ExpectedHrModel | null {
  const pts = samples.filter(usable);
  if (pts.length < MIN_SAMPLES) return null;

  const X = pts.map(row);
  const y = pts.map((s) => s.hr);

  // A predictor that never varies carries no information and makes the normal
  // equations singular — an athlete who runs every rep the same length, or
  // trains in one climate, is not a broken input. Drop those columns into the
  // intercept and fit on what actually moves.
  const varies = (col: number): boolean => {
    if (col === 0) return true; // intercept
    const first = X[0][col];
    return X.some((r) => Math.abs(r[col] - first) > 1e-9);
  };
  const keep = [0, 1, 2, 3].filter(varies);
  const k = keep.length;

  const A = Array.from({ length: k }, (_, a) =>
    Array.from({ length: k }, (_, b) => X.reduce((t, r) => t + r[keep[a]] * r[keep[b]], 0))
  );
  const B = Array.from({ length: k }, (_, a) => X.reduce((t, r, i) => t + r[keep[a]] * y[i], 0));
  const reduced = solve(A, B);
  if (reduced === null) return null;

  // Map back to the full coefficient vector; dropped predictors get 0.
  const beta: [number, number, number, number] = [0, 0, 0, 0];
  keep.forEach((col, i) => { beta[col] = reduced[i]; });

  let sse = 0;
  for (let i = 0; i < pts.length; i++) {
    const pred = X[i].reduce((t, v, j) => t + v * beta[j], 0);
    sse += (y[i] - pred) ** 2;
  }
  const residualSd = Math.sqrt(sse / Math.max(pts.length - k, 1));

  const dropped = [0, 1, 2, 3].filter((c) => !keep.includes(c))
    .map((c) => ["intercept", "speed", "dew", "rep length"][c]);
  return {
    coefficients: beta,
    residualSd,
    samples: pts.length,
    why: `fitted on ${pts.length} reps — ${beta[1].toFixed(3)} bpm per m/min, ` +
      `${beta[2].toFixed(3)} bpm per °F dew, ±${residualSd.toFixed(1)} bpm` +
      (dropped.length ? ` (no variation in ${dropped.join(", ")} — not fitted)` : ""),
  };
}

/** What this rep's heart rate should have been. */
export function expectedHr(sample: HrSample, model: ExpectedHrModel): number {
  return row(sample).reduce((t, v, i) => t + v * model.coefficients[i], 0);
}

/** Actual minus expected, bpm. Negative = cheaper than the model predicted. */
export function hrResidual(sample: HrSample, model: ExpectedHrModel): number {
  return sample.hr - expectedHr(sample, model);
}

/**
 * Has the athlete been running cheaper lately than they used to?
 *
 * Compares mean residual in the last `recentDays` against the window before
 * it. Both windows are drawn from the same fitted model, so pace, heat and
 * rep length are already accounted for on both sides — what is left is the
 * athlete.
 */
export function efficiencyTrend(
  samples: readonly HrSample[],
  model: ExpectedHrModel,
  now: Date,
  recentDays = 28,
  baselineDays = 84,
): EfficiencyTrend | null {
  const nowDay = now.getTime() / 86_400_000;
  const recent: number[] = [];
  const baseline: number[] = [];

  for (const s of samples) {
    if (!usable(s)) continue;
    const age = nowDay - dayOf(s.date)!;
    if (age < 0) continue;
    if (age <= recentDays) recent.push(hrResidual(s, model));
    else if (age <= baselineDays) baseline.push(hrResidual(s, model));
  }
  if (recent.length < 3 || baseline.length < 3) return null;

  const mean = (xs: number[]) => xs.reduce((t, x) => t + x, 0) / xs.length;
  const recentBpm = mean(recent);
  const baselineBpm = mean(baseline);
  const deltaBpm = recentBpm - baselineBpm;

  // Convert beats to pace through the model's OWN speed coefficient: a
  // residual of −d bpm means the athlete could hold d/coef more m/min at
  // unchanged heart rate. Using the fitted slope keeps this free of any
  // separate tuning constant.
  //
  // The reference pace it is expressed AT comes from this athlete's own
  // fastest quartile of work, not a fixed number — a bpm saving is worth a
  // different number of seconds per mile to a 5-minute miler than to a
  // 10-minute one, and an earlier draft hardcoded the calibration athlete's
  // 10K pace here, which would have mispriced everyone else.
  const usedPaces = samples.filter(usable).map((s) => s.paceSecPerMile).sort((a, b) => a - b);
  const refPace = usedPaces.length > 0
    ? usedPaces[Math.floor(usedPaces.length * 0.25)]
    : 0;

  const bpmPerSpeed = model.coefficients[1];
  let deltaPaceSecPerMile = 0;
  if (Math.abs(bpmPerSpeed) > 1e-6 && refPace > 0) {
    const refSpeed = METERS_PER_MILE * 60 / refPace;
    const newSpeed = refSpeed - deltaBpm / bpmPerSpeed;
    if (newSpeed > 0) deltaPaceSecPerMile = (METERS_PER_MILE * 60 / newSpeed) - refPace;
  }

  const dir = deltaBpm < -0.5 ? "cheaper" : deltaBpm > 0.5 ? "dearer" : "unchanged";
  return {
    recentBpm,
    baselineBpm,
    deltaBpm,
    deltaPaceSecPerMile,
    recentSamples: recent.length,
    baselineSamples: baseline.length,
    why: `same work is ${Math.abs(deltaBpm).toFixed(1)} bpm ${dir} than the prior window ` +
      `(${recent.length} recent reps vs ${baseline.length}) — worth ` +
      `${deltaPaceSecPerMile <= 0 ? "" : "+"}${deltaPaceSecPerMile.toFixed(1)} s/mi at held effort`,
  };
}
