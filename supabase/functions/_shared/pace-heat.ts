/**
 * Dew-point pace adjustment.
 *
 * Ported verbatim from RunningLog/Workouts/PaceCalculator.swift
 * (calculateDewPointAdjustment + interpolateAdjustment + heatCategory).
 * Keep this in lockstep with the Swift version — drift between the iOS
 * predictor and the server reconciliation is a prime cause of "the app said
 * I hit my pace, why does the coach card say I didn't" bug reports.
 */

export type HeatCategory =
  | "ideal"
  | "warm"
  | "hot"
  | "very_hot"
  | "dangerous";

export interface DewPointAdjustment {
  adjustedSeconds: number;
  compositeScore: number;
  adjustmentPercent: number;
  heatCategory: HeatCategory;
  multiplier: number;
}

/** Composite-score → adjustment-percent interpolation table (matches
 *  PaceCalculator.adjustmentTable exactly). */
const ADJUSTMENT_TABLE: ReadonlyArray<readonly [number, number]> = [
  [100, 0.000],
  [110, 0.004],
  [120, 0.010],
  [130, 0.015],
  [140, 0.021],
  [150, 0.030],
  [160, 0.045],
  [170, 0.065],
  [180, 0.090],
  [190, 0.120],
];

function interpolate(score: number): number {
  const first = ADJUSTMENT_TABLE[0];
  const last = ADJUSTMENT_TABLE[ADJUSTMENT_TABLE.length - 1];
  if (score <= first[0]) return 0;
  if (score >= last[0]) return last[1];
  for (let i = 0; i < ADJUSTMENT_TABLE.length - 1; i++) {
    const [loScore, loPct] = ADJUSTMENT_TABLE[i];
    const [hiScore, hiPct] = ADJUSTMENT_TABLE[i + 1];
    if (score >= loScore && score < hiScore) {
      const frac = (score - loScore) / (hiScore - loScore);
      return loPct + frac * (hiPct - loPct);
    }
  }
  return last[1];
}

export function heatCategoryFromScore(score: number): HeatCategory {
  if (score < 100) return "ideal";
  if (score < 130) return "warm";
  if (score < 150) return "hot";
  if (score < 170) return "very_hot";
  return "dangerous";
}

export function adjustPaceForHeat(
  paceSeconds: number,
  tempF: number,
  dewPointF: number
): DewPointAdjustment {
  // 1. Dew-point multiplier (baseline at 55°F dew point).
  const multiplier = 1.0 + Math.max(0, (dewPointF - 55) * 0.003495);

  // 2. Composite score.
  const compositeScore = tempF + dewPointF * multiplier;

  // 3. Look up adjustment percent.
  const adjustmentPercent = interpolate(compositeScore);

  // 4. Adjusted pace.
  const adjustedSeconds = paceSeconds * (1 + adjustmentPercent);

  return {
    adjustedSeconds,
    compositeScore,
    adjustmentPercent,
    multiplier,
    heatCategory: heatCategoryFromScore(compositeScore),
  };
}

// ── Dev-mode sanity checks ─────────────────────────────────────────
// Run when the module is imported under DENO_ENV=dev. Verifies three known
// fixtures against the Swift implementation so drift gets caught early.
if (Deno.env.get("DENO_ENV") === "dev") {
  const cases: Array<{ pace: number; temp: number; dp: number; expectPct: number }> = [
    // Cool morning: 50F / 45F DP → composite < 100 → 0% adjustment.
    { pace: 420, temp: 50, dp: 45, expectPct: 0.0 },
    // Warm: 72F / 62F DP → composite ~136 → ~1.8%.
    { pace: 420, temp: 72, dp: 62, expectPct: 0.018 },
    // Hot: 85F / 72F DP → composite ~163 → ~5.5%.
    { pace: 420, temp: 85, dp: 72, expectPct: 0.055 },
  ];
  for (const c of cases) {
    const r = adjustPaceForHeat(c.pace, c.temp, c.dp);
    if (Math.abs(r.adjustmentPercent - c.expectPct) > 0.01) {
      console.error(
        `[pace-heat] drift: temp=${c.temp} dp=${c.dp} expected≈${c.expectPct} got ${r.adjustmentPercent}`
      );
    }
  }
}
