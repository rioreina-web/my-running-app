-- Nightly fitness_snapshots writer.
--
-- fitness_snapshots was only ever written by the iOS app, on-device, when a
-- user opened the predictor screen — so the server-side athlete-state rebuild
-- and Coach Read read stale-or-absent fitness data. This cron regenerates a
-- snapshot for every active athlete using the SAME algorithm the app shows
-- (ported to _shared/fitnessPrediction.ts, invoked via compute-fitness-snapshot).
-- See outputs/fitness-snapshot-writer-diagnosis-2026-07-02.md.
--
-- "Active athlete" = any user_id with a logged workout in the last 45 days.
-- Empty-string user_id (the pre-auth write bug) is excluded here too.
--
-- Auth: reads supabase_url + service_role_key from Vault at RUN TIME
-- (subselects), per the dynamic-vault pattern — never bake the key in.
--
-- AI-advises-never-acts: this only recomputes a read-model prediction from
-- existing data (range + confidence per hard rule #7). It writes no plans, no
-- targets, no decisions.
--
-- Firing: 3:30am UTC daily — BEFORE the 4am nightly-athlete-state-rebuild, so
-- the rebuild (which reads the latest snapshot) sees today's fresh row. Edge
-- budget: each invocation computes ONE athlete, well within the 150s limit.
--
-- Prerequisites: compute-fitness-snapshot edge function deployed; Vault secrets
-- supabase_url + service_role_key present (same ones the drain crons use).

DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    BEGIN
        PERFORM cron.unschedule('nightly-fitness-snapshot');
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    SELECT cron.schedule(
        'nightly-fitness-snapshot',
        '30 3 * * *',  -- 3:30am UTC daily, before the 4am athlete-state rebuild
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
                RAISE NOTICE 'nightly-fitness-snapshot skipped — vault secrets missing';
                RETURN;
            END IF;

            -- One fire-and-forget http_post per active athlete. net.http_post
            -- is async, so the loop returns immediately and the edge function
            -- invocations run in parallel.
            FOR _athlete IN
                SELECT DISTINCT user_id
                FROM training_logs
                WHERE user_id IS NOT NULL
                  AND btrim(user_id) <> ''
                  AND workout_date >= (now() - INTERVAL '45 days')::date
            LOOP
                PERFORM net.http_post(
                    url := _supabase_url || '/functions/v1/compute-fitness-snapshot',
                    headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'Authorization', 'Bearer ' || _service_key,
                        'apikey', _service_key
                    ),
                    body := jsonb_build_object('user_id', _athlete.user_id)
                );
            END LOOP;

            RAISE NOTICE 'nightly-fitness-snapshot dispatched';
        END
        $inner$;
        $cron$
    ) INTO _job_id;

    RAISE NOTICE 'nightly-fitness-snapshot cron scheduled (job id %)', _job_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — nightly-fitness-snapshot not scheduled';
END;
$$;
