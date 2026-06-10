/**
 * Pace Heat Adjustment — Emy's Calculator (backend single source of truth)
 *
 * Ported verbatim from PaceCalculator.swift lines 296-441.
 * iOS should eventually call this via edge function to prevent drift.
 *
 * Formula:
 *   1. dpMultiplier = 1.0 + max(0, (dewPointF - 55) * 0.003495)
 *   2. compositeScore = tempF + (dewPointF × dpMultiplier)
 *   3. adjustmentPct = interpolate(compositeScore, adjustmentTable)
 *   4. adjustedPace = paceSeconds × (1 + adjustmentPct)
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
  adjustedPaceSeconds: number;
  temperatureF: number;
  dewPointF: number;
  multiplier: number;
  compositeScore: number;
  adjustmentPercent: number;
  adjustmentSecondsPerMile: number;
  heatCategory: HeatCategory;
}

/**
 * Calculate heat-adjusted pace based on temperature and dew point.
 * This is the verbatim port of PaceCalculator.swift:324-350.
 */
export function adjustPace(
  paceSeconds: number,
  tempF: number,
  dewPointF: number
): DewPointAdjustment {
  // 1. Dew Point Multiplier — baseline at 55°F DP
  const dpMultiplier = 1.0 + Math.max(0, (dewPointF - 55) * 0.003495);

  // 2. Composite Score = Temp + (Dew Point × Multiplier)
  const compositeScore = tempF + (dewPointF * dpMultiplier);

  // 3. Interpolate adjustment from composite score table
  const adjustmentPct = interpolateAdjustment(compositeScore);

  // 4. Adjusted Pace
  const adjustedSeconds = paceSeconds * (1 + adjustmentPct);

  return {
    originalPaceSeconds: paceSeconds,
    adjustedPaceSeconds: adjustedSeconds,
    temperatureF: tempF,
    dewPointF: dewPointF,
    multiplier: dpMultiplier,
    compositeScore,
    adjustmentPercent: adjustmentPct,
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
    fetched_at: fetchedAt,
  };
}
