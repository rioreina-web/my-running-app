-- ============================================================================
-- Workout Reconciliations
--
-- Closes the loop on every training_log: target (from the matching
-- scheduled_workouts row) vs. actual (from the log) vs. weather (from
-- Open-Meteo), producing a weather-adjusted delta and a hit/miss verdict.
--
-- One row per training_log (unique FK). Unplanned runs still get a row so
-- the weather stays on record — scheduled_workout_id is nullable.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS workout_reconciliations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,

    training_log_id UUID NOT NULL UNIQUE
        REFERENCES training_logs(id) ON DELETE CASCADE,
    scheduled_workout_id UUID
        REFERENCES scheduled_workouts(id) ON DELETE SET NULL,

    -- Paces (seconds per mile). Nullable when the log was unplanned.
    target_pace_seconds_per_mile NUMERIC,
    actual_pace_seconds_per_mile NUMERIC,

    -- Raw weather inputs + the heat-adjusted target.
    weather_forecast_jsonb JSONB,
    weather_actual_jsonb JSONB,
    adjusted_target_pace_seconds NUMERIC,
    adjusted_pace_delta_seconds NUMERIC,

    -- Verdict
    hit_target BOOLEAN,
    tolerance_applied_seconds NUMERIC NOT NULL DEFAULT 5,

    -- Free-form notes bag for follow-up analytics
    notes_json JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_workout_reconciliations_user_created
    ON workout_reconciliations(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_workout_reconciliations_scheduled
    ON workout_reconciliations(scheduled_workout_id);

ALTER TABLE workout_reconciliations ENABLE ROW LEVEL SECURITY;

-- Users read their own reconciliations.
CREATE POLICY "Users read own reconciliations"
    ON workout_reconciliations FOR SELECT
    USING (auth.uid() = user_id);

-- Service role writes (reconcile-log edge function is the only writer).
CREATE POLICY "Service role full access to reconciliations"
    ON workout_reconciliations FOR ALL
    USING (auth.role() = 'service_role');

COMMIT;
