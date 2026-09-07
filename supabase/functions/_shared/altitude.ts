/**
 * Altitude pace adjustment — the thin-air counterpart of the heat model.
 *
 * Same philosophy as pace-heat-adjustment.ts: CREDIT-ONLY and conservative.
 * A run at elevation is credited an effort-equivalent faster pace; nothing is
 * ever penalized. The published literature spans roughly 1.5–2.5% per 1,000ft
 * for sustained aerobic efforts depending on acclimatization; we take the
 * conservative (acclimatized) end, mirroring the heat model's lesson that
 * over-crediting is the failure mode that actually ships
 * (project_heat_intensity_scaling: the heat model over-credited hot laps).
 *
 * The adjustment applies only ABOVE a floor: below ~3,000ft the physiological
 * effect on aerobic performance is within measurement noise for our purposes.
 * Capped at 12% to match MAX_HEAT_NORMALIZATION — past that we'd be
 * extrapolating (and an athlete racing above ~10,000ft has bigger questions
 * than a conversion factor).
 *
 * Elevation is a property of the run's location (Open-Meteo elevation API,
 * fetched alongside weather in fetch-workout-weather) and rides in
 * `weather_actual` as `elevation_ft` + `altitude_adjustment_pct`. Consumers
 * (the Ask/Read training context) combine it multiplicatively with the heat
 * `adjustment_pct` — both are computed IN CODE; the model narrates, never
 * derives.
 */

/** Below this elevation the adjustment is zero. */
export const ALTITUDE_FLOOR_FT = 3000;

/** Credit fraction per 1,000ft above the floor (conservative end). */
export const ALTITUDE_PCT_PER_1000FT = 0.015;

/** Never credit altitude for more than 12% — matches MAX_HEAT_NORMALIZATION. */
export const MAX_ALTITUDE_ADJUSTMENT = 0.12;

export function metersToFeet(m: number): number {
  return m * 3.28084;
}

/**
 * Credit fraction for a run at `elevationFt` above sea level.
 * 0 at/below the floor; linear above it; capped.
 */
export function altitudeAdjustmentPct(
  elevationFt: number | null | undefined,
): number {
  if (elevationFt == null || !Number.isFinite(elevationFt)) return 0;
  if (elevationFt <= ALTITUDE_FLOOR_FT) return 0;
  const pct = ((elevationFt - ALTITUDE_FLOOR_FT) / 1000) * ALTITUDE_PCT_PER_1000FT;
  return Math.round(Math.min(pct, MAX_ALTITUDE_ADJUSTMENT) * 10000) / 10000;
}

/**
 * The two altitude fields merged into a weather JSON blob, or {} when
 * elevation is unknown. Elevation is stored even below the floor (a 500ft
 * Austin run records elevation_ft: 500, altitude_adjustment_pct: 0) so
 * "altitude didn't matter here" is a stated fact, not missing data.
 */
export function altitudeFields(
  elevationM: number | null | undefined,
): Record<string, number> {
  if (elevationM == null || !Number.isFinite(elevationM)) return {};
  const ft = Math.round(metersToFeet(elevationM));
  return {
    elevation_ft: ft,
    altitude_adjustment_pct: altitudeAdjustmentPct(ft),
  };
}
