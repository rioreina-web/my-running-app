/**
 * Pace Heat Adjustment — Emy's Calculator (backend single source of truth)
 *
 * Ported verbatim from PaceCalculator.swift lines 296-441.
 * iOS should eventually call this via edge function to prevent drift.
 *
 * Formula:
 *   1. dpMultiplier  = 1.01                                    (dew ≤ 65°F)
 *                    = 1.01 × 1.011557695^(dewPointF - 65)     (dew > 65°F)
 *   2. compositeScore = tempF + (dewPointF × dpMultiplier)
 *   3. adjustmentPct  = interpolate(compositeScore, adjustmentTable)
 *   4. repFactor      = repLengthFactor(distanceMiles)
 *   5. adjustedPace   = paceSeconds × (1 + adjustmentPct × repFactor)
 *
 * RECALIBRATION (2026-08-05, Rio): this now matches "Dew Point Calculator Emy"
 * v2 EXACTLY — the spreadsheet is the source of truth, this is the port.
 *
 * What changed and why. The previous version used a LINEAR multiplier
 * (1 + (dew-55) × 0.003495) against a table shifted ~10 composite points to the
 * right of Coach Mark Hadley's published "temperature + dew point" chart. The
 * shift is intentional — the multiplier is supposed to inflate the score enough
 * to absorb it. But at 72–75°F dew the linear form only added ~5 points where
 * the table demanded ~10, so the model under-corrected by roughly half a row.
 * Measured against 590 real laps (May–Aug 2026) it returned a mean adjustment
 * of 3.60% where both the sheet (4.37%) and Hadley's chart (4.34%) agree.
 *
 * The exponential multiplier fixes this: it contributes ~+10 points at 75°F dew,
 * exactly the shift the table expects. It also weights dew point more heavily
 * than temperature, which is the physiologically correct bias — dew point, not
 * air temperature, determines whether sweat can evaporate at all. Hadley's plain
 * temp+dew sum treats the two as interchangeable and consequently reads a
 * 78°F/75°F-dew morning (RH ~90%) as easier than a 96°F/67°F-dew afternoon.
 *
 * Reference point, pinned in the tests: 5:15/mi at 78°F / 75°F dew → 5:33/mi.
 *
 * Above a composite of 185 the chart stops. The sheet returns NA() there and
 * shows "Very tough conditions to run marathon pace work"; we surface the same
 * intent via `beyondChart` while still returning the 10% cap so no consumer has
 * to handle a null. Prefer showing the refusal over showing the number.
 *
 * REP-LENGTH SCALING (decision 2026-06-23, Rio): the table is calibrated for
 * CONTINUOUS running of ~1.5 mi or longer. Shorter reps get less of the penalty
 * because the body sheds heat during the recovery between them:
 *   • ≤ 0.75 mi  → 0.5 × adjustment (half)
 *   • 0.75–1.5mi → ramps linearly 0.5 × → 1.0 ×
 *   • ≥ 1.5 mi   → 1.0 × adjustment (full)
 * Apply PER BOUT: an easy run / tempo (≥1.5 mi) gets the full adjustment; 1k /
 * 600m interval reps get the scaled-down amount. Unknown length → full.
 *
 * A continuous run is ONE bout, not N reps. Do not pass the length of an
 * individual mile split of a continuous run — six 1-mile splits of a 6-mile run
 * would each land mid-ramp at 0.67 × and under-credit the whole run by a third.
 * Pass `null` for continuous geometry; pass the rep length only when the athlete
 * actually stood still between bouts.
 *
 * INTENSITY SCALING (decision 2026-08-05, Rio): the table is a QUALITY-WORK
 * chart. Hadley published it to answer "how much slower should I run my tempo
 * today," and the sheet's own out-of-range string is "Very tough conditions to
 * run marathon pace work." Applying it at full strength as retroactive credit on
 * a recovery jog is using it off-label: metabolic heat production scales with
 * running speed, so an easy run generates less heat, sheds a larger fraction of
 * it, and is forced to give up less pace. Périard frames the slowdown itself as
 * behavioral thermoregulation — deliberately cutting heat production — which is
 * a lever the easy run has barely pulled.
 *
 * Scaled on fraction-of-threshold-SPEED (LT pace ÷ actual pace):
 *   • ≤ 0.78 (recovery, ~28% slower than LT) → 0.75 ×
 *   • 0.78–0.95                              → ramps linearly 0.75 × → 1.0 ×
 *   • ≥ 0.95 (LT / MP / race and faster)     → 1.0 × (the chart as published)
 * Threshold pace unknown → 1.0 ×, same convention as rep length: never invent a
 * discount we can't justify.
 *
 * CALIBRATION HONESTY — read before retuning these constants. The 0.75 floor is
 * a COACHING JUDGMENT, not a fitted parameter. Measured against 1191 real laps
 * (Jan–Aug 2026, one athlete, dew 43–78°F), regressing pace on composite score
 * while controlling for the season fitness trend:
 *   • HR 145–152 (n=220): 0.077–0.097 %/composite-pt → 4.8–6.1% at composite
 *     163. The table's 5.6% sits inside that. THE CHART IS RIGHT HERE.
 *   • HR 128–143 (n=183): estimates ranged 1.0% / 7.6% / 4.5% across 5bpm bins
 *     with standard errors of ±3.2–4.4pp. That is noise, not signal — easy pace
 *     is chosen rather than constrained (terrain, company, recovery days), so
 *     the effect never separates from the variance. WE CANNOT SEE THE EASY END.
 *   • HR 153+ : unusable — session prescription (5K reps vs MP work) swamps
 *     conditions entirely.
 *   • Acclimatization (split on prior-14-day heat exposure) came out the wrong
 *     way with SEs of ±0.04–0.10. Inconclusive; deliberately NOT modeled.
 * So: 1.0 × at moderate-and-harder is empirically anchored. The 0.75 floor is
 * the smallest departure consistent with the mechanism, chosen because it lands
 * a HR-142 easy run near the ~20–21 s/mi the neighbouring (weakly-resolved)
 * bands imply, rather than the 25 s/mi the unscaled chart gives. If you retune
 * it, retune it from coaching conviction — this dataset will not adjudicate.
 *
 * CREDIT ONLY (decision 2026-08-05, Rio): the intensity factor scales the
 * BACKWARD-LOOKING credit (`neutralEquivalentPaceSeconds` — "what was this run
 * worth in neutral air") and NOT the prescriptive target
 * (`adjustedPaceSeconds` — "what should I run today"). The two uses genuinely
 * differ: a prescription holds EFFORT constant and asks what pace that buys, so
 * the full slowdown is correct at every intensity — an easy run in soup really
 * should be run slower to stay easy. The credit runs the inference backwards and
 * is where over-application inflates a 7:44 jog into a 7:19 one. Rep-length
 * scaling, by contrast, applies to BOTH — a 600m rep neither earns nor owes the
 * continuous penalty in either direction.
 */

// ── Dew Point Multiplier ───────────────────────────────────────
// Exponential above a 65°F pivot. Flat 1.01 below it — cool air is not free,
// but it doesn't scale either. Constants are the spreadsheet's, not rounded.

export const DEW_MULT_FLOOR = 1.01;
export const DEW_MULT_PIVOT_F = 65;
export const DEW_MULT_BASE = 1.011557695;

/** The multiplier the composite score applies to dew point. */
export function dewPointMultiplier(dewPointF: number): number {
  if (!isFinite(dewPointF) || dewPointF <= DEW_MULT_PIVOT_F) return DEW_MULT_FLOOR;
  return DEW_MULT_FLOOR * Math.pow(DEW_MULT_BASE, dewPointF - DEW_MULT_PIVOT_F);
}

// ── Adjustment Table ───────────────────────────────────────────
// Composite score → adjustment percentage. Matches "Dew Point Calculator Emy"
// v2 cell B10 exactly; each segment's slope is the sheet's own.

const ADJUSTMENT_TABLE: Array<{ score: number; pct: number }> = [
  { score: 100, pct: 0.000 },
  { score: 110, pct: 0.005 }, // slope 0.0005
  { score: 120, pct: 0.008 }, // slope 0.0003
  { score: 130, pct: 0.012 }, // slope 0.0004
  { score: 140, pct: 0.020 }, // slope 0.0008
  { score: 150, pct: 0.034 }, // slope 0.0014
  { score: 160, pct: 0.050 }, // slope 0.0016
  { score: 170, pct: 0.070 }, // slope 0.0020
  { score: 185, pct: 0.100 }, // slope 0.0020 — chart ends here
];

/** Past this composite the chart has nothing to say. The sheet refuses; we flag
 *  it and clamp, so callers can show the refusal without handling a null. */
export const BEYOND_CHART_SCORE = 185;

/** Copy for the refusal, verbatim from the sheet. */
export const BEYOND_CHART_MESSAGE =
  "Very tough conditions to run marathon pace work";

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

// ── Intensity scaling ──────────────────────────────────────────
// Keyed on fraction-of-threshold-SPEED, not on a zone label. Zone classifier
// labels are not trustworthy enough to move a number the athlete sees (see the
// pace_segment-labels decision); a pace ratio against the athlete's own LT is
// derived from PaceEngine and carries no classifier in the path.

export const INTENSITY_FULL_RATIO = 0.95;  // ≥ this × LT speed → full chart
export const INTENSITY_FLOOR_RATIO = 0.78; // ≤ this × LT speed → floor
export const INTENSITY_FLOOR = 0.75;       // the floor itself — coaching judgment

/**
 * Fraction of the heat adjustment a bout at this intensity earns, from the
 * athlete's threshold pace. Both paces in sec/mile; slower pace = bigger number.
 *
 * Returns 1.0 when threshold pace is unknown or nonsense — an athlete with no
 * anchor gets the chart as published rather than an invented discount.
 */
export function intensityFactor(
  paceSeconds: number,
  thresholdPaceSeconds?: number | null,
): number {
  if (
    thresholdPaceSeconds == null || !isFinite(thresholdPaceSeconds) ||
    thresholdPaceSeconds <= 0 || !isFinite(paceSeconds) || paceSeconds <= 0
  ) return 1.0;

  // Fraction of threshold SPEED. LT pace 6:20 run at 7:44 → 380/464 = 0.82.
  const ratio = thresholdPaceSeconds / paceSeconds;

  if (ratio >= INTENSITY_FULL_RATIO) return 1.0;
  if (ratio <= INTENSITY_FLOOR_RATIO) return INTENSITY_FLOOR;
  const frac = (ratio - INTENSITY_FLOOR_RATIO) /
    (INTENSITY_FULL_RATIO - INTENSITY_FLOOR_RATIO);
  return INTENSITY_FLOOR + frac * (1.0 - INTENSITY_FLOOR);
}

// ── Heat Category ──────────────────────────────────────────────
//
// The LABEL boundaries. Deliberately decoupled from the adjustment table's
// zero knot (2026-08-05).
//
// They used to share the number 100, which was a collision, not a decision:
// below the 65°F dew pivot the multiplier is flat, so the composite is
// essentially `temp + dew`, and the ideal/warm line landed on
// `temp + dew ≈ 99`. That put a 55°F morning with a 45°F dew point — composite
// 100.45, a near-perfect day to run — into "Warm", which the iOS pace chart
// renders as a sun icon, the word "Warm", and a warm-tinted card
// (PaceChartView.swift). The time cost it was flagging: 0.02%. A fifth of a
// second per mile. The label was shouting while the model whispered.
//
// The table's zero at 100 is a physical claim — below it, heat costs no time —
// and it stays. The label answers a different question, "did this day feel
// like a factor", so "ideal" now runs to 110, where the cost first reaches
// ~0.5%. A day can cost a rounding error and still be an ideal day.
//
// Mirrored in `pace-heat.ts:heatCategoryFromScore`, the Swift
// `PaceCalculator.heatCategory`, and SQL `heat_category_for()` — four
// implementations, one ladder. Change all four together.

export const HEAT_IDEAL_MAX_SCORE = 110;
export const HEAT_WARM_MAX_SCORE = 130;
export const HEAT_HOT_MAX_SCORE = 150;
export const HEAT_VERY_HOT_MAX_SCORE = 170;

export type HeatCategory = "ideal" | "warm" | "hot" | "very_hot" | "dangerous";

export function heatCategory(compositeScore: number): HeatCategory {
  if (compositeScore < HEAT_IDEAL_MAX_SCORE) return "ideal";
  if (compositeScore < HEAT_WARM_MAX_SCORE) return "warm";
  if (compositeScore < HEAT_HOT_MAX_SCORE) return "hot";
  if (compositeScore < HEAT_VERY_HOT_MAX_SCORE) return "very_hot";
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
  /** Intensity factor applied to the CREDIT only (0.75–1.0). 1.0 when the
   *  athlete has no threshold anchor, or the bout was at LT and faster. */
  intensityFactor: number;
  /** PRESCRIPTIVE adjustment = adjustmentPercent × repLengthFactor. Drives
   *  `adjustedPaceSeconds`. Deliberately NOT intensity-scaled. */
  effectiveAdjustmentPercent: number;
  /** RETROACTIVE adjustment = effectiveAdjustmentPercent × intensityFactor.
   *  Drives `neutralEquivalentPaceSeconds`. Equal to the prescriptive figure at
   *  LT-and-faster, smaller below it. */
  creditAdjustmentPercent: number;
  adjustmentSecondsPerMile: number;
  heatCategory: HeatCategory;
  /** Composite is past the end of the chart (>185). The returned pace is a
   *  clamped extrapolation — show `BEYOND_CHART_MESSAGE` instead of using it. */
  beyondChart: boolean;
}

/**
 * Heat-adjust a pace from temperature + dew point.
 *
 * `distanceMiles` — the length of ONE bout, for rep-length scaling. Omit it for
 * continuous running and for prescriptive targets. Never pass the length of an
 * individual split of a continuous run.
 *
 * `thresholdPaceSeconds` — the athlete's LT pace, for intensity scaling of the
 * CREDIT. Omit it and the credit equals the prescription (full chart).
 */
export function adjustPace(
  paceSeconds: number,
  tempF: number,
  dewPointF: number,
  distanceMiles?: number | null,
  thresholdPaceSeconds?: number | null,
): DewPointAdjustment {
  // 1. Dew Point Multiplier — flat below the 65°F pivot, exponential above
  const dpMultiplier = dewPointMultiplier(dewPointF);

  // 2. Composite Score = Temp + (Dew Point × Multiplier)
  const compositeScore = tempF + (dewPointF * dpMultiplier);

  // 3. Interpolate adjustment from composite score table
  const adjustmentPct = interpolateAdjustment(compositeScore);

  // 4. Rep-length scaling applies to BOTH directions — a 600m rep neither owes
  //    nor earns the continuous-running penalty.
  const factor = repLengthFactor(distanceMiles);
  const effectivePct = adjustmentPct * factor;
  const adjustedSeconds = paceSeconds * (1 + effectivePct);

  // 5. Intensity scaling applies to the CREDIT ONLY. The prescription holds
  //    effort constant and is correct at full strength at any intensity; the
  //    credit runs the inference backwards and over-pays the easy run.
  const intensity = intensityFactor(paceSeconds, thresholdPaceSeconds);
  const creditPct = effectivePct * intensity;

  return {
    originalPaceSeconds: paceSeconds,
    adjustedPaceSeconds: adjustedSeconds,
    neutralEquivalentPaceSeconds: paceSeconds / (1 + creditPct),
    temperatureF: tempF,
    dewPointF: dewPointF,
    multiplier: dpMultiplier,
    compositeScore,
    adjustmentPercent: adjustmentPct,
    repLengthFactor: factor,
    intensityFactor: intensity,
    effectiveAdjustmentPercent: effectivePct,
    creditAdjustmentPercent: creditPct,
    adjustmentSecondsPerMile: adjustedSeconds - paceSeconds,
    heatCategory: heatCategory(compositeScore),
    beyondChart: compositeScore > BEYOND_CHART_SCORE,
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
  return tempF + (dewPointF * dewPointMultiplier(dewPointF));
}

/** True when conditions are past the end of the chart — the caller should show
 *  `BEYOND_CHART_MESSAGE` instead of prescribing a pace. */
export function isBeyondChart(tempF: number, dewPointF: number): boolean {
  return compositeScore(tempF, dewPointF) > BEYOND_CHART_SCORE;
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
    // Past the end of the chart — UI should refuse rather than prescribe.
    beyond_chart: score > BEYOND_CHART_SCORE,
    // Whether the UI/coach should apply the adjustment, just mention it, or hide it.
    surfacing: heatSurfacing(tempF, dewPointF),
    fetched_at: fetchedAt,
  };
}

// ---------------------------------------------------------------------------
// Neutral-day normalization (the inverse of the prescription above).
// ---------------------------------------------------------------------------

/** Never credit heat for more than 12% — beyond that the table extrapolates. */
export const MAX_HEAT_NORMALIZATION = 0.12;

/**
 * Normalize an OBSERVED pace to neutral conditions:
 *   neutralPace = observed / (1 + adjustmentPct × repLengthFactor(distance))
 *
 * The inverse of the prescription direction: prescribing asks "how much slower
 * should I run today?", normalizing asks "what was this effort worth on a
 * neutral day?". The result is FASTER than observed — the heat made the effort
 * cost more, so the same effort buys a quicker pace in neutral air.
 *
 * Lives here rather than in fitnessPrediction.ts (where it was defined until
 * 2026-08-17) so that trainingZoneSignal.ts can normalize without importing the
 * predictor — that would be a cycle, since the predictor consumes the signal.
 */
export function heatNeutralPace(
  paceSeconds: number,
  tempF: number,
  dewPointF: number,
  distanceMiles?: number | null,
): number {
  if (!Number.isFinite(tempF) || !Number.isFinite(dewPointF) || !(paceSeconds > 0)) return paceSeconds;
  const pct = Math.min(
    heatAdjustmentPct(tempF, dewPointF) * repLengthFactor(distanceMiles),
    MAX_HEAT_NORMALIZATION,
  );
  return pct > 0 ? paceSeconds / (1 + pct) : paceSeconds;
}
