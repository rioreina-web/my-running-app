/**
 * Pace Grade Adjustment — grade-adjusted pace (GAP) for hilly running.
 *
 * Twin of `pace-heat-adjustment.ts`: produces an *adjusted* pace stored beside
 * the raw pace, never in place of it. Grade adjustment is a model, not a
 * measurement — the athlete owns the interpretation.
 *
 * MODEL — asymmetric (full uphill cost, DAMPED downhill credit)
 * ------------------------------------------------------------------
 * The energy cost of running vs. gradient comes from Minetti et al. (2002),
 * J. Appl. Physiol. 93:1039 — the academic standard:
 *
 *   C(i) = 155.4·i^5 − 30.4·i^4 − 43.3·i^3 + 46.3·i^2 + 19.5·i + 3.6   [J·kg⁻¹·m⁻¹]
 *   (i = gradient as a fraction; C(0) = 3.6 = flat baseline)
 *
 * The factor is C(i)/C(0): >1 uphill (cost), <1 downhill (cheaper).
 *
 * IMPORTANT: raw Minetti measures METABOLIC cost. Metabolically a gentle
 * descent is cheap, but that cheap energy does NOT convert to proportional
 * speed — turnover cap, eccentric braking, leg preservation all limit it. So on
 * the clock an uphill slows you MORE than the matching downhill speeds you back
 * up. Raw symmetric Minetti misses this and reports rolling/loop courses as
 * "neutral" when they are not (validated on the Cap 10K — see the test fixture
 * and outputs/grade-adjusted-pace-plan-2026-06-21.md §10.1).
 *
 * We therefore keep Minetti's uphill side and DAMP the downhill credit by
 * DOWNHILL_CREDIT. Tuned against the Cap 10K calibration case (target: that
 * race reads as a net hill cost of ~45–90 s, not neutral).
 *
 * Keep this in sync with the SQL `grade_factor()` function and the iOS
 * PaceCalculator grade twin (cross-language parity test guards drift).
 */

// ── Tunable constants ──────────────────────────────────────────
// Fraction of Minetti's downhill credit we actually count. 1.0 = raw Minetti
// (over-credits descents — do NOT ship). 0.0 = downhills give nothing back.
// 0.5 is the calibrated default; see the Cap 10K test.
export const DOWNHILL_CREDIT = 0.5;

// Clamp gradient before lookup — Minetti's fit degrades past ±30%, and grade
// streams throw GPS spikes well beyond anything runnable.
export const GRADE_CLAMP_PCT = 30;

const MINETTI_FLAT = minettiCost(0); // C(0) = 3.6

/** Minetti energy cost of running, J·kg⁻¹·m⁻¹. `i` is gradient as a fraction. */
export function minettiCost(i: number): number {
  return (
    155.4 * i ** 5 -
    30.4 * i ** 4 -
    43.3 * i ** 3 +
    46.3 * i ** 2 +
    19.5 * i +
    3.6
  );
}

/**
 * Grade factor: multiplier on *effort-equivalent speed* for a given gradient.
 * >1 uphill (you're working harder than your pace shows — adjusted pace is
 * faster); <1 downhill (some free speed removed — but LESS than raw Minetti,
 * per DOWNHILL_CREDIT). Flat = 1.0.
 */
export function gradeFactor(gradePct: number): number {
  const clamped = Math.max(-GRADE_CLAMP_PCT, Math.min(GRADE_CLAMP_PCT, gradePct));
  const raw = minettiCost(clamped / 100) / MINETTI_FLAT;
  if (raw < 1) {
    // Downhill: keep only a fraction of the credit.
    return 1 + DOWNHILL_CREDIT * (raw - 1);
  }
  return raw; // Uphill: full cost.
}

export interface GradeAdjustment {
  originalPaceSeconds: number;
  adjustedPaceSeconds: number; // neutral-grade equivalent (per-mile)
  gradePct: number;
  factor: number;
  adjustmentSecondsPerMile: number; // adjusted − original (negative uphill)
}

/**
 * Adjust a single pace (sec/mile) for a single average gradient. Uphill returns
 * a faster (lower) equivalent pace; downhill a slower one (damped).
 */
export function adjustPaceForGrade(paceSeconds: number, gradePct: number): GradeAdjustment {
  const factor = gradeFactor(gradePct);
  const adjusted = paceSeconds / factor;
  return {
    originalPaceSeconds: paceSeconds,
    adjustedPaceSeconds: adjusted,
    gradePct,
    factor,
    adjustmentSecondsPerMile: adjusted - paceSeconds,
  };
}

export interface RunSegment {
  seconds: number; // time spent on this segment
  gradePct: number; // average gradient of the segment
  meters?: number; // optional, for distance-weighting display paces
}

export interface RunGradeAdjustment {
  rawSeconds: number;
  adjustedSeconds: number; // neutral-grade equivalent total time
  hillCostSeconds: number; // rawSeconds − adjustedSeconds; >0 = hills cost time
}

/**
 * Aggregate grade adjustment over a whole run (per-second or per-lap segments).
 * `hillCostSeconds > 0` means the terrain cost net time (flat-equivalent is
 * faster). On a net-flat loop this is small but, with damped downhills, still
 * positive — the honest answer raw Minetti gets wrong.
 */
export function gradeAdjustRun(segments: RunSegment[]): RunGradeAdjustment {
  let rawSeconds = 0;
  let adjustedSeconds = 0;
  for (const s of segments) {
    if (s.seconds <= 0) continue;
    rawSeconds += s.seconds;
    adjustedSeconds += s.seconds / gradeFactor(s.gradePct);
  }
  return {
    rawSeconds,
    adjustedSeconds,
    hillCostSeconds: rawSeconds - adjustedSeconds,
  };
}

export interface ConditionsAdjustment {
  originalPaceSeconds: number;
  conditionsAdjustedPaceSeconds: number; // grade + heat removed (neutral & cool)
  gradeFactor: number;
  heatPct: number;
}

/**
 * Combine grade and heat into ONE conditions-adjusted pace — "what this effort
 * was worth in neutral, cool conditions." `heatPct` is the fractional heat
 * slowdown from pace-heat-adjustment.ts (e.g. 0.0236 = 2.36%).
 */
export function combineConditions(
  paceSeconds: number,
  gradePct: number,
  heatPct: number,
): ConditionsAdjustment {
  const gf = gradeFactor(gradePct);
  const adjusted = paceSeconds / gf / (1 + heatPct);
  return {
    originalPaceSeconds: paceSeconds,
    conditionsAdjustedPaceSeconds: adjusted,
    gradeFactor: gf,
    heatPct,
  };
}
