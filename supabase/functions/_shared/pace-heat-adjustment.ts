/**
 * Pace Heat Adjustment — Emy's Calculator (backend single source of truth)
 *
 * Ported verbatim from PaceCalculator.swift lines 296-441.
 * iOS should eventually call this via edge function to prevent drift.
 *
 * Formula:
 *   1. dpMultiplier  = 1.0 + max(0, (dewPointF - 55) * 0.003495)
 *   2. compositeScore = tempF + (dewPointF × dpMultiplier)
 *   3. adjustmentPct  = interpolate(compositeScore, adjustmentTable)
 *   4. repFactor      = repLengthFactor(distanceMiles)
 *   5. adjustedPace   = paceSeconds × (1 + adjustmentPct × repFactor)
 *
 * Validation (2026-06-23): the table is a faithful (slightly conservative)
 * implementation of Coach Mark Hadley's "temperature + dew point" chart, which
 * aligns with Daniels VDOT heat guidance and Runner's Connect dew-point work.
 * Dew point (not relative humidity) is the right moisture metric for runners.
 *
 * REP-LENGTH SCALING (decision 2026-06-23, Rio): the table is calibrated for
 * CONTINUOUS running of ~1.5 mi or longer. Shorter reps get less of the penalty
 * because the body sheds heat during the recovery between them:
 *   • ≤ 0.75 mi  → 0.5 × adjustment (half)
 *   • 0.75–1.5mi → ramps linearly 0.5 × → 1.0 ×
 *   • ≥ 1.5 mi   → 1.0 × adjustment (full)
 * Apply PER BOUT: an easy run / tempo (≥1.5 mi) gets the full adjustment; 1k /
 * 600m interval reps get the scaled-down amount. Unknown length → full.
 */

// ── Adjustment Table ───────────────────────────────────────────
// Composite score → adjustment percentage (from dew point research v2)

const ADJUSTMENT_TABLE: Array<{ score: number; pct: number }> = [
  { score: 100, pct: 0.000 },
  { score: 110, pct: 0.004 },
  { score: 120, pct: 0.010 },
  { score: 130, pct: 0.015 },
  { score: 140, pct: 0.021 },
  { score: 150, pct: 0.030 },
  { score: 160, pct: 0.045 },
  { score: 170, pct: 0.065 },
  { score: 180, pct: 0.090 },
  { score: 190, pct: 0.120 },
];

// ── Rep-length scaling ─────────────────────────────────────────

export const HEAT_FULL_MILES = 1.5;   // ≥ this → full adjustment
export const HEAT_HALF_MILES = 0.75;  // ≤ this → half adjustment

/**
 * Fraction of the heat adjustment to apply to a bout of the given length:
 * 0.5 for short reps, ramping to 1.0 at 1.5 mi. Continuous runs (length
 * unknown / null) get the full 1.0.
 */
export function repLengthFactor(distanceMiles?: number | null): number {
  if (distanceMiles == null || !isFinite(distanceMiles)) return 1.0;
  if (distanceMiles >= HEAT_FULL_MILES) return 1.0;
  if (distanceMiles <= HEAT_HALF_MILES) return 0.5;
  const frac = (distanceMiles - HEAT_HALF_MILES) / (HEAT_FULL_MILES - HEAT_HALF_MILES);
  return 0.5 + frac * 0.5;
}

// ── Heat Category ──────────────────────────────────────────────

export type HeatCategory = "ideal" | "warm" | "hot" | "very_hot" | "dangerous";

export function heatCategory(compositeScore: number): HeatCategory {
  if (compositeScore < 100) return "ideal";
  if (compositeScore < 130) return "warm";
  if (compositeScore < 150) return "hot";
  if (compositeScore < 170) return "very_hot";
  return "dangerous";
}

export function heatCategoryLabel(cat: HeatCategory): string {
  switch (cat) {
    case "ideal": return "Ideal";
    case "warm": return "Warm";
    case "hot": return "Hot";
    case "very_hot": return "Very Hot";
    case "dangerous": return "Dangerous";
  }
}

// ── Surfacing decision (when to act vs. just mention) ──────────
// Decision 2026-06-23 (Rio): the adjustment is "called" (applied + shown) when
// it's genuinely warm — a dew point of 68°F+. When it's only mildly humid we
// don't change the pace, but we may *mention* the conditions. When it's cool we
// say nothing. Gate primarily on DEW POINT (the runner-relevant moisture
// metric), with a composite-score backstop so a hot, dry day still surfaces.

export const DEW_APPLY_F = 68;    // ≥ this dew point → apply the adjustment
export const DEW_MENTION_F = 60;  // ≥ this dew point → mention conditions only

export type HeatSurfacing = "apply" | "mention" | "none";

/**
 * Whether to apply the heat adjustment, merely mention the conditions, or stay
 * silent. Driven by dew point (Rio's rule), with a composite-score backstop:
 *   • apply   — dew ≥ 68°F, or it's outright hot (composite ≥ 150 / "very hot")
 *   • mention — dew ≥ 60°F (mildly humid), or composite ≥ 130 ("hot")
 *   • none    — cool & dry
 */
export function heatSurfacing(tempF: number, dewPointF: number): HeatSurfacing {
  const score = compositeScore(tempF, dewPointF);
  if (dewPointF >= DEW_APPLY_F || score >= 150) return "apply";
  if (dewPointF >= DEW_MENTION_F || score >= 130) return "mention";
  return "none";
}

// ── Interpolation ──────────────────────────────────────────────

function interpolateAdjustment(score: number): number {
  const table = ADJUSTMENT_TABLE;
  if (score <= table[0].score) return 0;
  if (score >= table[table.length - 1].score) return table[table.length - 1].pct;

  for (let i = 0; i < table.length - 1; i++) {
    const lo = table[i];
    const hi = table[i + 1];
    if (score >= lo.score && score < hi.score) {
      const frac = (score - lo.score) / (hi.score - lo.score);
      return lo.pct + frac * (hi.pct - lo.pct);
    }
  }
  return table[table.length - 1].pct;
}

// ── Core Adjustment ────────────────────────────────────────────

export interface DewPointAdjustment {
  originalPaceSeconds: number;
  /** Prescriptive: the SLOWER pace to run *today* to hold the same effort. */
  adjustedPaceSeconds: number;
  /**
   * The FASTER cool-weather-equivalent — what a pace run in the heat is worth
   * in neutral conditions (the inverse of `adjustedPaceSeconds`). This is what
   * the completed-workout HEAT-ADJ toggle displays (credit for the conditions).
   */
  neutralEquivalentPaceSeconds: number;
  temperatureF: number;
  dewPointF: number;
  multiplier: number;
  compositeScore: number;
  /** Raw table adjustment (continuous-run basis), before rep-length scaling. */
  adjustmentPercent: number;
  /** Rep-length factor actually applied (0.5–1.0). */
  repLengthFactor: number;
  /** Effective adjustment after scaling = adjustmentPercent × repLengthFactor. */
  effectiveAdjustmentPercent: number;
  adjustmentSecondsPerMile: number;
  heatCategory: HeatCategory;
}

/**
 * Heat-adjust a pace from temperature + dew point. Pass `distanceMiles` for a
 * single bout/rep so the rep-length scaling applies; omit it for a continuous
 * run (defaults to the full adjustment).
 */
export function adjustPace(
  paceSeconds: number,
  tempF: number,
  dewPointF: number,
  distanceMiles?: number | null,
): DewPointAdjustment {
  // 1. Dew Point Multiplier — baseline at 55°F DP
  const dpMultiplier = 1.0 + Math.max(0, (dewPointF - 55) * 0.003495);

  // 2. Composite Score = Temp + (Dew Point × Multiplier)
  const compositeScore = tempF + (dewPointF * dpMultiplier);

  // 3. Interpolate adjustment from composite score table
  const adjustmentPct = interpolateAdjustment(compositeScore);

  // 4. Scale by rep length, then 5. apply to pace
  const factor = repLengthFactor(distanceMiles);
  const effectivePct = adjustmentPct * factor;
  const adjustedSeconds = paceSeconds * (1 + effectivePct);

  return {
    originalPaceSeconds: paceSeconds,
    adjustedPaceSeconds: adjustedSeconds,
    neutralEquivalentPaceSeconds: paceSeconds / (1 + effectivePct),
    temperatureF: tempF,
    dewPointF: dewPointF,
    multiplier: dpMultiplier,
    compositeScore,
    adjustmentPercent: adjustmentPct,
    repLengthFactor: factor,
    effectiveAdjustmentPercent: effectivePct,
    adjustmentSecondsPerMile: adjustedSeconds - paceSeconds,
    heatCategory: heatCategory(compositeScore),
  };
}

/**
 * Apply weather adjustment to a map of named paces (e.g. pace_zones).
 * Returns a new map with adjusted values.
 */
export function adjustAllPaces(
  paces: Record<string, number>,
  tempF: number,
  dewPointF: number
): Record<string, number> {
  const adjusted: Record<string, number> = {};
  for (const [key, pace] of Object.entries(paces)) {
    adjusted[key] = adjustPace(pace, tempF, dewPointF).adjustedPaceSeconds;
  }
  return adjusted;
}

/**
 * Compute the composite score from temp + dew point without adjusting a pace.
 * Useful for weather cards and heat warnings.
 */
export function compositeScore(tempF: number, dewPointF: number): number {
  const dpMultiplier = 1.0 + Math.max(0, (dewPointF - 55) * 0.003495);
  return tempF + (dewPointF * dpMultiplier);
}

/** Continuous-run adjustment fraction for a temp/dew (no rep scaling). Used by
 *  the conditions-adjusted fitness signal. */
export function heatAdjustmentPct(tempF: number, dewPointF: number): number {
  return interpolateAdjustment(compositeScore(tempF, dewPointF));
}

/**
 * Format a pace delta as a human-readable string.
 * e.g. adjustmentSecondsPerMile=12.3 → "+12 sec/mi"
 */
export function formatAdjustment(adjustmentSecondsPerMile: number): string {
  const secs = Math.round(adjustmentSecondsPerMile);
  if (secs === 0) return "No adjustment";
  return `+${secs} sec/mi`;
}

/**
 * Build the weather JSONB shape stored in scheduled_workouts.weather_forecast
 * and training_logs.weather_actual.
 */
export function buildWeatherJson(
  tempF: number,
  dewPointF: number,
  humidity: number | null,
  windMph: number | null,
  condition: string,
  fetchedAt: string,
  weatherCode: number | null = null,
): Record<string, unknown> {
  const score = compositeScore(tempF, dewPointF);
  const adjPct = interpolateAdjustment(score);
  return {
    temp_f: Math.round(tempF * 10) / 10,
    dew_point_f: Math.round(dewPointF * 10) / 10,
    humidity,
    wind_mph: windMph != null ? Math.round(windMph * 10) / 10 : null,
    condition,
    weather_code: weatherCode,
    composite_score: Math.round(score * 10) / 10,
    heat_category: heatCategory(score),
    adjustment_pct: Math.round(adjPct * 10000) / 10000,
    // Whether the UI/coach should apply the adjustment, just mention it, or hide it.
    surfacing: heatSurfacing(tempF, dewPointF),
    fetched_at: fetchedAt,
  };
}
