-- Heat adjustment: intensity scaling for the credit, and a rep-length fix
--
-- TWO CHANGES, READ BOTH.
--
-- ── 1. BUG FIX: rep-length scaling was applied to continuous runs ────────────
-- `20260805180000_recalibrate_heat_to_emy_v2.sql` backfilled every lap with
--     heat_effective_pct(temp_f, dew_point_f, lap.distance_meters)
-- which runs `heat_rep_length_factor` over the length of each individual lap.
-- For a rep session that is correct. For a CONTINUOUS run whose laps are the
-- watch's mile splits it is not: a 1.0 mi split lands mid-ramp at 0.67x, so a
-- plain 6-mile run had its heat adjustment cut by a third for no stated reason.
-- On the reference run (78F / 75F dew, 7:44/mi) that is the difference between
-- 25 s/mi and 17 s/mi. The module's own rule has always been "an easy run /
-- tempo (>=1.5 mi) gets the full adjustment" -- a continuous run is ONE bout,
-- not N reps, and the recovery that justifies the discount never happened.
--
-- Fix: rep-length scaling applies only to laps in a workout that actually has
-- rest laps. Continuous geometry -> factor 1.0. As of this migration that is
-- 68 interval workouts (scaled) vs 102 continuous ones (no longer scaled).
--
-- ── 2. NEW: intensity scaling of the CREDIT ─────────────────────────────────
-- The adjustment table is a QUALITY-WORK chart. Hadley published it to answer
-- "how much slower should I run my tempo today," and the Emy sheet's own
-- out-of-range string names marathon-pace work specifically. Applying it at
-- full strength as retroactive credit on a recovery jog is off-label: metabolic
-- heat production scales with running speed, so an easy run makes less heat,
-- sheds a larger share of it, and gives up less pace.
--
-- Scaled on fraction-of-threshold-SPEED (LT pace / actual pace):
--   <= 0.78 -> 0.75x    0.78-0.95 -> linear ramp    >= 0.95 -> 1.0x
-- Mirrors intensityFactor() in _shared/pace-heat-adjustment.ts and
-- heatIntensityFactor() in PaceCalculator.swift. Keep all three in lockstep.
--
-- CREDIT ONLY. `heat_adjusted_pace_sec_per_mile` is the backward-looking
-- neutral equivalent and IS intensity-scaled. Any prescriptive surface ("what
-- should I run today") must keep using the unscaled `heat_effective_pct` --
-- holding effort constant, the full slowdown is correct at every intensity.
-- The two are deliberately no longer exact inverses of each other.
--
-- CALIBRATION HONESTY: the 0.75 floor is a coaching judgment, not a fitted
-- parameter. Regressed against 1191 real laps (Jan-Aug 2026, dew 43-78F),
-- controlling for the season fitness trend: at HR 145-152 (n=220) the observed
-- sensitivity was 0.077-0.097 %/composite-pt, i.e. 4.8-6.1% at composite 163 --
-- the table's 5.6% sits inside that, so the chart is right where the data can
-- see it and the factor stays 1.0 there. The easy bands (HR 128-143, n=183)
-- returned 1.0% / 7.6% / 4.5% across 5bpm bins with SEs of +/-3.2-4.4pp: noise,
-- not signal. The easy end is UNRESOLVED by this dataset and 0.75 is the
-- smallest departure consistent with the mechanism. Retune from conviction.

-- ── Intensity factor ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION heat_intensity_factor(
    pace_sec_per_mile NUMERIC, threshold_pace_sec_per_mile NUMERIC
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    -- Unknown threshold -> 1.0. An athlete with no anchor gets the chart as
    -- published; we never invent a discount we cannot justify.
    SELECT CASE
        WHEN threshold_pace_sec_per_mile IS NULL
          OR threshold_pace_sec_per_mile <= 0
          OR pace_sec_per_mile IS NULL
          OR pace_sec_per_mile <= 0                                  THEN 1.0
        WHEN threshold_pace_sec_per_mile / pace_sec_per_mile >= 0.95 THEN 1.0
        WHEN threshold_pace_sec_per_mile / pace_sec_per_mile <= 0.78 THEN 0.75
        ELSE 0.75 + ((threshold_pace_sec_per_mile / pace_sec_per_mile) - 0.78)
                    / (0.95 - 0.78) * 0.25
    END;
$$;

COMMENT ON FUNCTION heat_intensity_factor(NUMERIC, NUMERIC) IS
    'Fraction of the heat adjustment a bout at this intensity earns, from '
    'fraction-of-threshold-speed. 0.75 at recovery, 1.0 at LT and faster. '
    'Applies to the CREDIT only, never to a prescriptive target. Mirrors '
    'intensityFactor() in _shared/pace-heat-adjustment.ts.';

-- ── Rep-length factor, gated on the workout actually being intervals ────────

CREATE OR REPLACE FUNCTION heat_rep_length_factor_for_lap(
    distance_meters NUMERIC, workout_has_rest BOOLEAN
)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    -- A continuous run is one bout. Only a session the athlete actually stood
    -- still inside earns the short-rep discount.
    SELECT CASE
        WHEN workout_has_rest IS NOT TRUE THEN 1.0
        ELSE heat_rep_length_factor(distance_meters)
    END;
$$;

COMMENT ON FUNCTION heat_rep_length_factor_for_lap(NUMERIC, BOOLEAN) IS
    'Rep-length factor for one lap, 1.0 unless the parent workout contains rest '
    'laps. Guards against treating the mile splits of a continuous run as reps.';

-- ── Column for the intensity factor actually applied ────────────────────────

ALTER TABLE running_workout_laps
    ADD COLUMN IF NOT EXISTS heat_intensity_factor NUMERIC;

COMMENT ON COLUMN running_workout_laps.heat_intensity_factor IS
    'Intensity factor applied to the CREDIT (0.75-1.0). 1.0 when the athlete '
    'had no threshold anchor at backfill time, or the bout was at LT+.';

-- ── Recompute ───────────────────────────────────────────────────────────────
-- Threshold pace comes from athlete_state.pace_zones->>''threshold'' (written
-- by _shared/paces.ts:oneHourPaceSecPerMile). Older blobs predate that key, so
-- fall back to ''hm''. HM is slower than LT for every runner whose half takes
-- under an hour and much slower for everyone else, which makes the ratio LOWER
-- and the discount SMALLER -- the fallback errs toward the status quo rather
-- than inventing a large new discount on rows we cannot classify confidently.
-- We deliberately do NOT reimplement oneHourPaceSecPerMile in SQL: it already
-- has three must-mirror copies (TS/web/Swift) and a fourth is a drift liability.

WITH lap_ctx AS (
    SELECT lap.id,
           bool_or(sib.is_rest IS TRUE) OVER (PARTITION BY lap.workout_id) AS has_rest,
           COALESCE(
               (ast.pace_zones ->> 'threshold')::numeric,
               (ast.pace_zones ->> 'hm')::numeric
           ) AS threshold_pace
    FROM running_workout_laps lap
    JOIN running_workout_laps sib ON sib.workout_id = lap.workout_id
    JOIN training_logs tl         ON tl.id = lap.workout_id
    LEFT JOIN athlete_state ast   ON ast.user_id = tl.user_id
    WHERE lap.temp_f IS NOT NULL AND lap.dew_point_f IS NOT NULL
)
UPDATE running_workout_laps lap
SET heat_intensity_factor = heat_intensity_factor(
        lap.avg_pace_sec_per_mile, ctx.threshold_pace),
    heat_adjustment_pct = heat_adjustment_pct(lap.temp_f, lap.dew_point_f)
        * heat_rep_length_factor_for_lap(lap.distance_meters, ctx.has_rest)
        * heat_intensity_factor(lap.avg_pace_sec_per_mile, ctx.threshold_pace),
    heat_adjusted_pace_sec_per_mile = CASE
        WHEN lap.is_rest IS TRUE               THEN NULL
        WHEN lap.avg_pace_sec_per_mile IS NULL THEN NULL
        WHEN lap.avg_pace_sec_per_mile <= 0    THEN NULL
        ELSE ROUND(
            lap.avg_pace_sec_per_mile
            / (1 + heat_adjustment_pct(lap.temp_f, lap.dew_point_f)
                   * heat_rep_length_factor_for_lap(lap.distance_meters, ctx.has_rest)
                   * heat_intensity_factor(lap.avg_pace_sec_per_mile, ctx.threshold_pace))
        )
    END
FROM (SELECT DISTINCT id, has_rest, threshold_pace FROM lap_ctx) ctx
WHERE ctx.id = lap.id;

COMMENT ON COLUMN running_workout_laps.heat_adjustment_pct IS
    'EFFECTIVE CREDIT adjustment as a FRACTION (0.042 == 4.2%), after both '
    'rep-length and intensity scaling. Reconciles with '
    'heat_adjusted_pace_sec_per_mile. NOT the prescriptive figure -- a target '
    'to run today uses heat_effective_pct(), which omits intensity scaling.';
