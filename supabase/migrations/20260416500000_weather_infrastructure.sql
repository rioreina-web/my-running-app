-- ============================================================================
-- Weather Infrastructure
--
-- 1. weather_forecast JSONB on scheduled_workouts (forecast for planned day)
-- 2. weather_actual JSONB + weather_adjusted_pace_delta on training_logs
-- 3. weather_cache table (deduplicate Open-Meteo calls)
-- 4. home_lat/home_lon on user_profiles (backend location source)
--
-- Weather shape (matches WorkoutWeather in WeatherService.swift):
-- {
--   "temp_f": 82.4,
--   "dew_point_f": 68.0,
--   "humidity": 65,
--   "wind_mph": 8.2,
--   "condition": "partly_cloudy",
--   "composite_score": 152.3,
--   "heat_category": "very_hot",
--   "adjustment_pct": 0.031,
--   "fetched_at": "2026-04-16T14:00:00Z"
-- }
-- ============================================================================

-- ── 1. scheduled_workouts: forecast weather ──────────────────────

ALTER TABLE scheduled_workouts
    ADD COLUMN IF NOT EXISTS weather_forecast JSONB;

COMMENT ON COLUMN scheduled_workouts.weather_forecast IS
    'Open-Meteo forecast for the planned workout day. Populated by fetch-workout-weather trigger on insert/update.';


-- ── 2. training_logs: actual weather + adjusted pace delta ──────

ALTER TABLE training_logs
    ADD COLUMN IF NOT EXISTS weather_actual JSONB;

ALTER TABLE training_logs
    ADD COLUMN IF NOT EXISTS weather_adjusted_pace_delta_seconds_per_mile REAL;

COMMENT ON COLUMN training_logs.weather_actual IS
    'Actual weather conditions at workout time. Populated by post-run-reconciliation.';
COMMENT ON COLUMN training_logs.weather_adjusted_pace_delta_seconds_per_mile IS
    'Seconds per mile slower the target should be due to heat. Positive = slower target is expected.';


-- ── 3. weather_cache ────────────────────────────────────────────
-- Already created and deployed in 20260417400000_weather_cache.sql with the
-- simple-column schema (lat_key, lon_key, hour_key + raw observation columns).
-- The originally planned rich-JSON schema was never adopted; fetch-workout-weather
-- and _shared/weather.ts both use the simple shape, reconstructing the rich JSON
-- via buildWeatherJson() on read. Intentionally a no-op here.


-- ── 4. user_profiles: home location ─────────────────────────────

ALTER TABLE user_profiles
    ADD COLUMN IF NOT EXISTS home_lat REAL,
    ADD COLUMN IF NOT EXISTS home_lon REAL,
    ADD COLUMN IF NOT EXISTS preferred_run_time TEXT
        CHECK (preferred_run_time IS NULL OR preferred_run_time IN ('morning', 'afternoon', 'evening'));

COMMENT ON COLUMN user_profiles.home_lat IS 'Home latitude for backend weather fetches when GPS unavailable.';
COMMENT ON COLUMN user_profiles.home_lon IS 'Home longitude for backend weather fetches when GPS unavailable.';
COMMENT ON COLUMN user_profiles.preferred_run_time IS 'morning (6am), afternoon (5pm), or evening (7pm) — used for forecast hour selection.';


-- ── 5. Cleanup: skipped ──────────────────────────────────────────
-- The original plan scheduled a daily DELETE WHERE expires_at < now(), but the
-- deployed weather_cache schema has no expires_at column. Cache freshness is
-- handled application-side; rows are upserted on (lat_key, lon_key, hour_key)
-- so each location-hour holds at most one row.
