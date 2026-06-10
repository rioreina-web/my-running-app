-- Daily weather forecast fetch for upcoming workouts.
--
-- Calls fetch-workout-weather in batch mode for every active training_plan,
-- pre-populating weather_forecast on scheduled_workouts for the next 7 days.
-- The athlete sees forecast-aware pace suggestions when they open the app
-- — the data is already there, no on-demand fetch latency.
--
-- Prerequisite migration: 20260416500000_weather_infrastructure.sql must
-- have been applied first (adds scheduled_workouts.weather_forecast column,
-- weather_cache table, and home_lat/home_lon on user_profiles).
--
-- Cron firing: 5am UTC daily. Forecast horizon: 7 days. Cache TTL is 6h on
-- forecast entries (per weather_cache schema), so a daily cron with on-demand
-- refreshes from iOS covers the day.
--
-- AI-advises-never-acts compliance: this migration ONLY fetches and writes
-- weather data to scheduled_workouts.weather_forecast. It does NOT modify
-- target paces. The iOS workout card consumes weather_forecast at render
-- time and shows a pace suggestion the athlete may accept or override.

DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    -- Unschedule any existing job with this name (idempotent re-runs)
    BEGIN
        PERFORM cron.unschedule('daily-weather-forecast');
    EXCEPTION WHEN OTHERS THEN
        -- Job didn't exist; fine.
        NULL;
    END;

    -- Schedule the daily fetch. Calls fetch-workout-weather with the
    -- plan_id + kind=forecast_week shape it already supports.
    SELECT cron.schedule(
        'daily-weather-forecast',
        '0 5 * * *',  -- 5am UTC daily
        $cron$
        DO $inner$
        DECLARE
            _supabase_url TEXT;
            _service_key  TEXT;
            _plan_row     RECORD;
        BEGIN
            _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
            _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

            IF _supabase_url IS NULL OR _supabase_url = ''
               OR _service_key IS NULL OR _service_key = '' THEN
                RAISE NOTICE 'daily-weather-forecast skipped — app.settings not configured';
                RETURN;
            END IF;

            -- One HTTP call per active plan. fetch-workout-weather handles
            -- the batch internally (walks scheduled_workouts for the next 7d).
            FOR _plan_row IN
                SELECT id FROM training_plans WHERE status = 'active'
            LOOP
                PERFORM net.http_post(
                    url := _supabase_url || '/functions/v1/fetch-workout-weather',
                    headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'Authorization', 'Bearer ' || _service_key,
                        'apikey', _service_key
                    ),
                    body := jsonb_build_object(
                        'plan_id', _plan_row.id::text,
                        'kind', 'forecast_week'
                    )
                );
            END LOOP;

            RAISE NOTICE 'daily-weather-forecast complete';
        END
        $inner$;
        $cron$
    ) INTO _job_id;

    RAISE NOTICE 'daily-weather-forecast cron scheduled (job id %)', _job_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — daily-weather-forecast not scheduled';
END;
$$;
