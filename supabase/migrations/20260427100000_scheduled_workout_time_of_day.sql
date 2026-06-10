-- ============================================================================
-- Per-workout scheduled time
--
-- Adds an optional `scheduled_hour` smallint column to scheduled_workouts so
-- the athlete can specify when (within the day) a workout is going to happen.
-- Drives the heat-adjustment forecast: today the cron uses a single
-- profile-level preferred_run_time for every workout, which is wrong for
-- athletes whose Saturday LR is at 6am but whose weekday tempo is at 5pm.
--
-- Resolution order, lowest precedence first:
--   1. 7am default (hardcoded fallback in fetch-workout-weather)
--   2. user_profiles.preferred_run_time (athlete's general preference)
--   3. scheduled_workouts.scheduled_hour (per-workout override) — wins
--
-- Backwards-compatible: column is nullable, no default. Existing workouts
-- continue to use the profile-level preference until the athlete sets a
-- per-workout time.
-- ============================================================================

BEGIN;

-- Store the local hour as a SMALLINT (0-23), not a timestamptz. Why:
-- Open-Meteo's hourly forecast (with timezone=auto) is indexed by the
-- LOCATION'S LOCAL hour. A timestamptz forces us to convert UTC ↔ local
-- on the fly, which requires knowing the athlete's timezone — which we
-- don't store. Storing the local hour as an integer dodges the conversion
-- entirely: "7" means hour 7 of the workout's local date, period.
--
-- Hour-level precision is all weather forecasting offers anyway (Open-
-- Meteo gives one sample per HH:00). If we need 5:30am display fidelity
-- later, we can add a separate `scheduled_local_minute` column without
-- changing the forecast plumbing.
ALTER TABLE scheduled_workouts
    ADD COLUMN IF NOT EXISTS scheduled_hour SMALLINT
        CHECK (scheduled_hour IS NULL OR scheduled_hour BETWEEN 0 AND 23);

COMMENT ON COLUMN scheduled_workouts.scheduled_hour IS
    'Optional per-workout local hour (0-23). When set, fetch-workout-weather '
    'pulls Open-Meteo''s hourly forecast for THIS hour (athlete''s local time, '
    'matched against Open-Meteo''s timezone=auto hourly array) instead of the '
    'profile-level preferred_run_time default. Athlete sets this from the '
    'workout detail sheet by tapping the time pill. Null = inherit from '
    'user_profiles.preferred_run_time.';

CREATE INDEX IF NOT EXISTS idx_scheduled_workouts_scheduled_hour
    ON scheduled_workouts (scheduled_hour)
    WHERE scheduled_hour IS NOT NULL;

COMMIT;
