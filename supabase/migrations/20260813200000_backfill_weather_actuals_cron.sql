-- Hourly retry for runs that never got their actual conditions.
--
-- WHY THIS EXISTS
--
-- `strava-sync` fires fetch-workout-weather once per freshly-ingested run,
-- fire-and-forget ("a miss is harmless (weather_actual just stays null)").
-- But Open-Meteo's ARCHIVE endpoint — the one the `actual` path uses — does
-- not publish the current hour immediately. A run synced the same morning it
-- happened asks for an hour the archive hasn't got yet, misses, and NOTHING
-- EVER COMES BACK FOR IT. `weather_actual` stays null permanently.
--
-- That is not hypothetical: 2026-08-13's 11.01 mi run sat weather-less with
-- HEAT-ADJ greyed out on a 74.3°F dew-point morning, while the archive had
-- published its hour (77.6°F / 74.3°F, composite 161.1, ~5.2%) by midday.
--
-- fetch-workout-weather has had the repair mode this whole time
-- (`kind: "backfill_actuals"`); it was simply scheduled nowhere. This is that
-- schedule. Nothing new is computed here — the cron only re-asks.
--
-- SHAPE
--
-- Hourly at :20, one http_post per athlete who actually has a gap, so a quiet
-- hour costs nothing. `net.http_post` is async, so the DO block returns
-- immediately and hourly firings cannot pile up in Postgres. The function's
-- own write is idempotent (it sets weather_actual and stamps the lap heat
-- columns), so an overlapping retry is harmless.
--
-- WINDOW: 7 days. This job exists to lose the race with the archive, not to
-- backfill history — a one-off `{kind:"backfill_actuals", days:N}` call covers
-- older gaps if you ever want them.
--
-- The gap test requires a LOCATABLE run: the function needs either the run's
-- own GPS or the athlete's home_lat/home_lon, and without that check a single
-- permanently-unlocatable run (a manual entry, a voice log) would hold the
-- guard open and buy an edge-function invocation every hour, forever.
--
-- AI-advises-never-acts compliance: this writes weather observations only. It
-- touches no pace, no plan, no target.

DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    -- Idempotent re-runs: drop any previous incarnation first.
    BEGIN
        PERFORM cron.unschedule('backfill-weather-actuals');
    EXCEPTION WHEN OTHERS THEN
        NULL;  -- Job didn't exist; fine.
    END;

    SELECT cron.schedule(
        'backfill-weather-actuals',
        '20 * * * *',  -- hourly, off the top-of-hour crowd
        $cron$
        DO $inner$
        DECLARE
            _supabase_url TEXT;
            _service_key  TEXT;
            _athlete      RECORD;
            _dispatched   INTEGER := 0;
        BEGIN
            _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
            _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

            IF _supabase_url IS NULL OR _supabase_url = ''
               OR _service_key IS NULL OR _service_key = '' THEN
                RAISE NOTICE 'backfill-weather-actuals skipped — vault secrets missing';
                RETURN;
            END IF;

            -- Only athletes with a REPAIRABLE gap: a recent run, with real
            -- distance, no weather_actual, and somewhere on earth to ask about.
            FOR _athlete IN
                SELECT DISTINCT t.user_id
                  FROM training_logs t
                 WHERE t.user_id IS NOT NULL
                   AND btrim(t.user_id) <> ''
                   AND t.workout_date IS NOT NULL
                   AND t.workout_date >= (now() - INTERVAL '7 days')
                   AND t.workout_distance_miles > 0
                   AND t.weather_actual IS NULL
                   AND (
                        jsonb_typeof(t.external_streams -> 'streams' -> 'latlng') = 'array'
                     OR EXISTS (
                            SELECT 1
                              FROM athlete_settings s
                             WHERE s.user_id = t.user_id
                               AND s.home_lat IS NOT NULL
                               AND s.home_lon IS NOT NULL
                        )
                   )
            LOOP
                PERFORM net.http_post(
                    url := _supabase_url || '/functions/v1/fetch-workout-weather',
                    headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'Authorization', 'Bearer ' || _service_key,
                        'apikey', _service_key
                    ),
                    body := jsonb_build_object(
                        'kind', 'backfill_actuals',
                        'user_id', _athlete.user_id,
                        'days', 7
                    )
                );
                _dispatched := _dispatched + 1;
            END LOOP;

            IF _dispatched > 0 THEN
                RAISE NOTICE 'backfill-weather-actuals dispatched for % athlete(s)', _dispatched;
            END IF;
        END
        $inner$;
        $cron$
    ) INTO _job_id;

    RAISE NOTICE 'backfill-weather-actuals cron scheduled (job id %)', _job_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — backfill-weather-actuals not scheduled';
END;
$$;
