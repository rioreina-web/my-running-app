-- ════════════════════════════════════════════════════════════════════════════
-- Recalibrate the lap heat adjustment to "Dew Point Calculator Emy" v2,
-- and give the SQL path the rep-length scaling it never had.
--
-- TWO BUGS ARE BEING FIXED HERE.
--
-- 1. WRONG CURVE. The functions created in 20260528222217 used a LINEAR dew
--    multiplier — 1 + (dew - 55) × 0.003495 — against an adjustment table whose
--    breakpoints sit ~10 composite points right of Coach Mark Hadley's published
--    "temperature + dew point" chart. That right-shift is deliberate: the dew
--    multiplier is supposed to inflate the score enough to absorb it. But at the
--    72–75°F dew points this athlete actually trains in, the linear form only
--    added ~5 points where the table wanted ~10. Net effect: the model
--    under-corrected by roughly half a table row.
--
--    Measured over 590 real laps (May 10 – Aug 4 2026), the old model returned a
--    time-weighted mean adjustment of 3.60%, where the source spreadsheet (4.37%)
--    and Hadley's chart (4.34%) independently agree. The exponential multiplier
--    below contributes ~+10 points at 75°F dew, which is exactly the shift the
--    table expects, and reproduces the spreadsheet cell-for-cell.
--
--    It also weights dew point above air temperature, which is the
--    physiologically correct bias — dew point, not temperature, decides whether
--    sweat can evaporate. Hadley's plain temp+dew sum treats the two as
--    interchangeable and therefore rates a 78°F/75°dew morning (RH ~90%) as
--    easier than a 96°F/67°dew afternoon.
--
-- 2. MISSING REP SCALING. Hadley's chart explicitly says short repeats get HALF
--    the continuous-run adjustment, because the athlete sheds heat during the
--    recovery. `repLengthFactor()` in pace-heat-adjustment.ts implements this and
--    `applyHeatToLaps()` passes lap distance in. The SQL function never took a
--    distance argument at all, so every lap it touched — including 400m and 1k
--    reps — got the full continuous penalty. The two writers disagreed:
--
--      writer            short reps ≤0.75mi   continuous ≥1.5mi
--      SQL backfill      3.71%                3.22%     ← reps penalised MORE
--      applyHeatToLaps   1.95%                4.37%     ← correct
--
--    That affected 492 laps spanning April 1 through August 1 — not a clean
--    historical cutover, so recent workouts were mixed. Intervals are exactly
--    where the adjustment decides pace-band membership, so this mattered.
--
-- SEMANTIC CHANGE, READ THIS: `heat_adjustment_pct` now stores the EFFECTIVE
-- fraction — after rep-length scaling — so it always reconciles with
-- `heat_adjusted_pace_sec_per_mile`. It previously stored the raw table value
-- while the pace column had (sometimes) been scaled, which is what made the
-- inconsistency invisible. Still a FRACTION, not a percent: 0.056 == 5.6%.
-- See pace-heat.contract.test.ts before changing that.
--
-- Keep in lockstep with:
--   supabase/functions/_shared/pace-heat-adjustment.ts
--   supabase/functions/_shared/pace-heat.ts
--   RunningLog/RunningLog/Workouts/PaceCalculator.swift
-- Reference point pinned in all four: 5:15/mi at 78°F / 75°dew → 5:33/mi.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Dew point multiplier ────────────────────────────────────────────────────
-- Flat 1.01 up to the 65°F pivot, exponential above it. Constants are the
-- spreadsheet's own; do not round them.

CREATE OR REPLACE FUNCTION heat_dew_multiplier(dew_point_f NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN dew_point_f IS NULL THEN NULL
        WHEN dew_point_f <= 65   THEN 1.01
        ELSE 1.01 * POWER(1.011557695, dew_point_f - 65)
    END;
$$;

COMMENT ON FUNCTION heat_dew_multiplier(NUMERIC) IS
    'Dew-point multiplier for the composite heat score. Flat 1.01 to 65F, '
    'exponential above. Mirrors dewPointMultiplier() in pace-heat-adjustment.ts.';

-- ── Composite score ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION heat_composite_score(temp_f NUMERIC, dew_point_f NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN temp_f IS NULL OR dew_point_f IS NULL THEN NULL
        ELSE temp_f + (dew_point_f * heat_dew_multiplier(dew_point_f))
    END;
$$;

-- ── Rep-length factor ───────────────────────────────────────────────────────
-- 0.5 for reps ≤0.75mi, ramping linearly to 1.0 at 1.5mi, full above that.
-- Unknown distance → full adjustment (treat as continuous). Mirrors
-- repLengthFactor() in pace-heat-adjustment.ts.

CREATE OR REPLACE FUNCTION heat_rep_length_factor(distance_meters NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN distance_meters IS NULL THEN 1.0
        WHEN distance_meters / 1609.344 >= 1.5  THEN 1.0
        WHEN distance_meters / 1609.344 <= 0.75 THEN 0.5
        ELSE 0.5 + ((distance_meters / 1609.344) - 0.75) / 0.75 * 0.5
    END;
$$;

-- ── Adjustment percentage (continuous-run basis, before rep scaling) ────────
-- Table matches "Dew Point Calculator Emy" v2 cell B10 exactly:
--   (100, 0.000) (110, 0.005) (120, 0.008) (130, 0.012) (140, 0.020)
--   (150, 0.034) (160, 0.050) (170, 0.070) (185, 0.100)
-- The sheet returns NA() above 185 and prints "Very tough conditions to run
-- marathon pace work". SQL has no good way to carry that, so we clamp at 0.100;
-- callers should check heat_composite_score(...) > 185 and refuse instead.

CREATE OR REPLACE FUNCTION heat_adjustment_pct(temp_f NUMERIC, dew_point_f NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    score NUMERIC;
BEGIN
    IF temp_f IS NULL OR dew_point_f IS NULL THEN
        RETURN NULL;
    END IF;

    score := heat_composite_score(temp_f, dew_point_f);

    RETURN CASE
        WHEN score <= 100 THEN 0.000
        WHEN score <  110 THEN 0.000 + (score - 100) / 10.0 * (0.005 - 0.000)
        WHEN score <  120 THEN 0.005 + (score - 110) / 10.0 * (0.008 - 0.005)
        WHEN score <  130 THEN 0.008 + (score - 120) / 10.0 * (0.012 - 0.008)
        WHEN score <  140 THEN 0.012 + (score - 130) / 10.0 * (0.020 - 0.012)
        WHEN score <  150 THEN 0.020 + (score - 140) / 10.0 * (0.034 - 0.020)
        WHEN score <  160 THEN 0.034 + (score - 150) / 10.0 * (0.050 - 0.034)
        WHEN score <  170 THEN 0.050 + (score - 160) / 10.0 * (0.070 - 0.050)
        WHEN score <  185 THEN 0.070 + (score - 170) / 15.0 * (0.100 - 0.070)
        ELSE                    0.100
    END;
END;
$$;

-- ── Effective (rep-scaled) adjustment for one lap ───────────────────────────

CREATE OR REPLACE FUNCTION heat_effective_pct(
    temp_f NUMERIC, dew_point_f NUMERIC, distance_meters NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN temp_f IS NULL OR dew_point_f IS NULL THEN NULL
        ELSE heat_adjustment_pct(temp_f, dew_point_f)
             * heat_rep_length_factor(distance_meters)
    END;
$$;

-- ── Fill any missing lap weather from the parent log ────────────────────────
-- Some laps were stamped by applyHeatToLaps (temp/dew present) and some only by
-- the original backfill. Level the ground before recomputing.

UPDATE running_workout_laps lap
SET temp_f      = (tl.weather_actual ->> 'temp_f')::numeric,
    dew_point_f = (tl.weather_actual ->> 'dew_point_f')::numeric
FROM training_logs tl
WHERE lap.workout_id = tl.id
  AND (lap.temp_f IS NULL OR lap.dew_point_f IS NULL)
  AND tl.weather_actual IS NOT NULL
  AND tl.weather_actual ? 'temp_f'
  AND tl.weather_actual ? 'dew_point_f';

-- ── Recompute every lap under the new model ─────────────────────────────────
-- heat_adjusted_pace is the NEUTRAL EQUIVALENT: what the effort was worth in
-- neutral conditions, so it is FASTER (fewer seconds) than the raw pace.
-- Rounded to whole seconds to match applyHeatToLaps()'s Math.round.

UPDATE running_workout_laps lap
SET heat_composite_score = heat_composite_score(lap.temp_f, lap.dew_point_f),
    heat_category        = heat_category_for(
                               heat_composite_score(lap.temp_f, lap.dew_point_f)),
    heat_adjustment_pct  = heat_effective_pct(
                               lap.temp_f, lap.dew_point_f, lap.distance_meters),
    heat_adjusted_pace_sec_per_mile = CASE
        WHEN lap.is_rest IS TRUE                THEN NULL
        WHEN lap.avg_pace_sec_per_mile IS NULL  THEN NULL
        WHEN lap.avg_pace_sec_per_mile <= 0     THEN NULL
        ELSE ROUND(
            lap.avg_pace_sec_per_mile
            / (1 + heat_effective_pct(lap.temp_f, lap.dew_point_f, lap.distance_meters))
        )
    END
WHERE lap.temp_f IS NOT NULL
  AND lap.dew_point_f IS NOT NULL;

COMMENT ON COLUMN running_workout_laps.heat_adjustment_pct IS
    'EFFECTIVE heat adjustment as a FRACTION (0.056 == 5.6%), after rep-length '
    'scaling. Reconciles with heat_adjusted_pace_sec_per_mile. Emy v2 calibration.';
