-- ============================================================================
-- Weekly plan rebalance — Sunday 8pm UTC.
--
-- For each user with an active training plan, fires adapt-plan with
-- trigger=weekly_rebalance. Relies on pg_cron + pg_net (already enabled
-- by earlier migrations). Timezone-aware per-user scheduling is not yet
-- feasible in pg_cron — we approximate at 20:00 UTC and let adapt-plan's
-- rules be idempotent across re-runs.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
    PERFORM cron.unschedule('weekly-plan-rebalance');
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — weekly-plan-rebalance not scheduled.';
END;
$$;

DO $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
BEGIN
    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE NOTICE 'app.settings missing — weekly-plan-rebalance cron skipped';
        RETURN;
    END IF;

    -- Sunday 20:00 UTC. For each user with an active plan, POST to
    -- adapt-plan. The query inside the cron body expands at run time.
    PERFORM cron.schedule(
        'weekly-plan-rebalance',
        '0 20 * * 0',
        format(
            $job$
            DO $do$
            DECLARE r RECORD;
            BEGIN
                FOR r IN
                    SELECT DISTINCT user_id
                      FROM training_plans
                     WHERE status = 'active'
                LOOP
                    PERFORM net.http_post(
                        url := '%s/functions/v1/adapt-plan',
                        headers := jsonb_build_object(
                            'Content-Type', 'application/json',
                            'Authorization', 'Bearer %s',
                            'apikey', '%s'
                        ),
                        body := jsonb_build_object(
                            'user_id', r.user_id::text,
                            'trigger', 'weekly_rebalance'
                        )
                    );
                END LOOP;
            END
            $do$;
            $job$,
            _supabase_url,
            _service_key,
            _service_key
        )
    );
END;
$$;

COMMIT;
