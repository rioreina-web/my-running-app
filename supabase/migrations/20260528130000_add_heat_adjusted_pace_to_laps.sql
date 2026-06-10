-- ============================================================================
-- 20260528130000_add_heat_adjusted_pace_to_laps.sql
--
-- Adds heat-adjusted pace + conditions snapshot to running_workout_laps so
-- the UI can display "actual pace" alongside "adjusted pace" whenever it
-- mattered. Both numbers are stored, never one replacing the other — heat
-- adjustment is a model, not a measurement, and the athlete owns the
-- interpretation.
--
-- Formula is ported from supabase/functions/_shared/pace-heat-adjustment.ts
-- (Emy's Calculator). Single source of truth for SQL-side computation lives
-- in the heat_adjustment_pct() function created below — keep the TS and SQL
-- versions in sync.
--
-- Scope note: for now, every lap on a given workout uses the workout-level
-- weather snapshot from training_logs.weather_actual. Per-lap weather
-- interpolation across long workouts (where conditions shift between the
-- first and last rep) is a follow-up migration once we wire weather samples
-- to lap timestamps.
-- ============================================================================

-- ── New columns on running_workout_laps ────────────────────────────────────

ALTER TABLE running_workout_laps
    ADD COLUMN temp_f                       NUMERIC(5, 2),
    ADD COLUMN dew_point_f                  NUMERIC(5, 2),
    ADD COLUMN heat_composite_score         NUMERIC(6, 2),
    ADD COLUMN heat_category                TEXT
        CHECK (heat_category IN ('ideal', 'warm', 'hot', 'very_hot', 'dangerous')),
    ADD COLUMN heat_adjustment_pct          NUMERIC(5, 4),
    ADD COLUMN heat_adjusted_pace_sec_per_mile NUMERIC(8, 2);

COMMENT ON COLUMN running_workout_laps.heat_adjusted_pace_sec_per_mile IS
    'avg_pace_sec_per_mile after Emy''s Calculator adjustment. Lower = the '
    'equivalent neutral-conditions pace. Stored beside the raw pace, never '
    'in place of it. UI shows both when heat_category != ''ideal''.';

-- ── Reusable adjustment function (SQL port of pace-heat-adjustment.ts) ─────
-- Composite score = temp_f + (dew_point_f × multiplier),
-- where multiplier ramps once dew point clears 55°F.
-- Adjustment table interpolated linearly between anchor scores.

CREATE OR REPLACE FUNCTION heat_adjustment_pct(temp_f NUMERIC, dew_point_f NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    dp_mult NUMERIC;
    score   NUMERIC;
BEGIN
    IF temp_f IS NULL OR dew_point_f IS NULL THEN
        RETURN NULL;
    END IF;

    dp_mult := 1.0 + GREATEST(0, (dew_point_f - 55) * 0.003495);
    score   := temp_f + (dew_point_f * dp_mult);

    -- Linear interpolation across the adjustment table.
    -- (100, 0.000) → (110, 0.004) → (120, 0.010) → (130, 0.015) →
    -- (140, 0.021) → (150, 0.030) → (160, 0.045) → (170, 0.065) →
    -- (180, 0.090) → (190, 0.120). Clamp at endpoints.
    RETURN CASE
        WHEN score <= 100 THEN 0.000
        WHEN score <  110 THEN 0.000 + (score - 100) / 10.0 * (0.004 - 0.000)
        WHEN score <  120 THEN 0.004 + (score - 110) / 10.0 * (0.010 - 0.004)
        WHEN score <  130 THEN 0.010 + (score - 120) / 10.0 * (0.015 - 0.010)
        WHEN score <  140 THEN 0.015 + (score - 130) / 10.0 * (0.021 - 0.015)
        WHEN score <  150 THEN 0.021 + (score - 140) / 10.0 * (0.030 - 0.021)
        WHEN score <  160 THEN 0.030 + (score - 150) / 10.0 * (0.045 - 0.030)
        WHEN score <  170 THEN 0.045 + (score - 160) / 10.0 * (0.065 - 0.045)
        WHEN score <  180 THEN 0.065 + (score - 170) / 10.0 * (0.090 - 0.065)
        WHEN score <  190 THEN 0.090 + (score - 180) / 10.0 * (0.120 - 0.090)
        ELSE                    0.120
    END;
END;
$$;

CREATE OR REPLACE FUNCTION heat_composite_score(temp_f NUMERIC, dew_point_f NUMERIC)
RETURNS NUMERIC
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN temp_f IS NULL OR dew_point_f IS NULL THEN NULL
        ELSE temp_f + (dew_point_f * (1.0 + GREATEST(0, (dew_point_f - 55) * 0.003495)))
    END;
$$;

CREATE OR REPLACE FUNCTION heat_category_for(score NUMERIC)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN score IS NULL THEN NULL
        WHEN score <  100 THEN 'ideal'
        WHEN score <  130 THEN 'warm'
        WHEN score <  150 THEN 'hot'
        WHEN score <  170 THEN 'very_hot'
        ELSE                   'dangerous'
    END;
$$;

-- ── Backfill from existing training_logs.weather_actual ─────────────────────

UPDATE running_workout_laps lap
SET
    temp_f      = (tl.weather_actual ->> 'temp_f')::numeric,
    dew_point_f = (tl.weather_actual ->> 'dew_point_f')::numeric,
    heat_composite_score = heat_composite_score(
        (tl.weather_actual ->> 'temp_f')::numeric,
        (tl.weather_actual ->> 'dew_point_f')::numeric
    ),
    heat_category = heat_category_for(heat_composite_score(
        (tl.weather_actual ->> 'temp_f')::numeric,
        (tl.weather_actual ->> 'dew_point_f')::numeric
    )),
    heat_adjustment_pct = heat_adjustment_pct(
        (tl.weather_actual ->> 'temp_f')::numeric,
        (tl.weather_actual ->> 'dew_point_f')::numeric
    ),
    heat_adjusted_pace_sec_per_mile = CASE
        WHEN lap.avg_pace_sec_per_mile IS NULL THEN NULL
        WHEN (tl.weather_actual ->> 'temp_f') IS NULL THEN NULL
        WHEN (tl.weather_actual ->> 'dew_point_f') IS NULL THEN NULL
        ELSE lap.avg_pace_sec_per_mile / (1 + heat_adjustment_pct(
            (tl.weather_actual ->> 'temp_f')::numeric,
            (tl.weather_actual ->> 'dew_point_f')::numeric
        ))
    END
FROM training_logs tl
WHERE lap.workout_id = tl.id
  AND tl.weather_actual IS NOT NULL
  AND tl.weather_actual ? 'temp_f'
  AND tl.weather_actual ? 'dew_point_f';

-- Note on the math: heat_adjusted_pace = actual_pace / (1 + adjustment_pct).
-- That gives us "what would this pace have been in neutral conditions" —
-- a faster (lower seconds-per-mile) number than the raw pace. The TS port
-- does the opposite (adjusts target paces UP for hot weather); here we
-- adjust observed paces DOWN to a neutral equivalent. Both are correct;
-- they're answering different questions. Document this clearly in the UI.

-- ── Index for fast "show me hot workouts" queries ──────────────────────────

CREATE INDEX idx_workout_laps_heat_cat
    ON running_workout_laps (user_id, heat_category, lap_start_at DESC)
    WHERE heat_category IS NOT NULL AND heat_category != 'ideal';

-- ── Verification (commented for re-run safety) ──────────────────────────────
-- SELECT heat_category, COUNT(*) FROM running_workout_laps GROUP BY 1;
-- SELECT workout_id, lap_index, avg_pace_sec_per_mile,
--        heat_adjusted_pace_sec_per_mile, temp_f, dew_point_f, heat_category
--   FROM running_workout_laps
--   WHERE heat_category IN ('hot','very_hot','dangerous')
--   ORDER BY lap_start_at DESC LIMIT 20;
