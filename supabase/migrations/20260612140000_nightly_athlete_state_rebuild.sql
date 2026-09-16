-- Nightly athlete_state keep-warm (v2 Phase E).
--
-- athlete_state was built lazily on read with a 60-minute TTL, so prod had
-- only 2 rows and the Read could see a stale (or missing) athlete. This cron
-- rebuilds the state nightly for every active athlete — one http_post per
-- athlete into rebuild-athlete-state, mirroring daily-weather-forecast's
-- per-plan fan-out.
--
-- "Active athlete" = any user_id with a logged workout in the last 45 days.
--
-- Auth: reads supabase_url + service_role_key from Vault at RUN TIME
-- (subselects), per the 2026-06-11 dynamic-vault fix — never bake the key in.
--
-- AI-advises-never-acts: this only recomputes the read-model snapshot from
-- existing data. It writes no plans, no targets, no decisions.
--
-- Firing: 4am UTC daily (before the 6am-local Read cron in most US zones, so
-- the morning Read reads a fresh state). Edge budget: each invocation rebuilds
-- ONE athlete (~14 source queries), well within the 150s limit.
--
-- Prerequisites: rebuild-athlete-state edge function deployed; Vault secrets
-- supabase_url + service_role_key present (same ones the drain crons use).

DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    BEGIN
        PERFORM cron.unschedule('nightly-athlete-state-rebuild');
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    SELECT cron.schedule(
        'nightly-athlete-state-rebuild',
        '0 4 * * *',  -- 4am UTC daily
        $cron$
        DO $inner$
        DECLARE
            _supabase_url TEXT;
            _service_key  TEXT;
            _athlete      RECORD;
        BEGIN
            _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
            _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

            IF _supabase_url IS NULL OR _supabase_url = ''
               OR _service_key IS NULL OR _service_key = '' THEN
                RAISE NOTICE 'nightly-athlete-state-rebuild skipped — vault secrets missing';
                RETURN;
            END IF;

            -- One fire-and-forget http_post per active athlete. net.http_post
            -- is async, so the loop returns immediately and the edge function
            -- invocations run in parallel.
            FOR _athlete IN
                SELECT DISTINCT user_id
                FROM training_logs
                WHERE user_id IS NOT NULL
                  AND workout_date >= (now() - INTERVAL '45 days')::date
            LOOP
                PERFORM net.http_post(
                    url := _supabase_url || '/functions/v1/rebuild-athlete-state',
                    headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'Authorization', 'Bearer ' || _service_key,
                        'apikey', _service_key
                    ),
                    body := jsonb_build_object('user_id', _athlete.user_id)
                );
            END LOOP;

            RAISE NOTICE 'nightly-athlete-state-rebuild dispatched';
        END
        $inner$;
        $cron$
    ) INTO _job_id;

    RAISE NOTICE 'nightly-athlete-state-rebuild cron scheduled (job id %)', _job_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — nightly-athlete-state-rebuild not scheduled';
END;
$$;
