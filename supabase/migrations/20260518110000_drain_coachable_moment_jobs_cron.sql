-- ============================================================================
-- Cron schedule for the coachable-moment outbox drainer.
--
-- Mirrors 20260508170000_drain_coach_insight_jobs_cron.sql for the
-- coachable-moment side: pg_cron job fires every minute, hits
-- drain-coachable-moment-jobs with batch=40, which atomically claims
-- queued rows from coachable_moment_jobs and calls evaluate-coachable-
-- moment per athlete.
--
-- Idempotent — re-running this migration unschedules the existing job
-- first.
--
-- Settings required:
--   supabase_url       → from vault
--   service_role_key   → from vault
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net  WITH SCHEMA extensions;

DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — drain-coachable-moment-jobs cron skipped';
END;
$$;

DO $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
BEGIN
    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url'      LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE NOTICE 'vault secrets missing — drain-coachable-moment-jobs cron skipped';
        RETURN;
    END IF;

    -- Idempotent: unschedule first so re-running this migration is safe.
    BEGIN
        PERFORM cron.unschedule('drain-coachable-moment-jobs');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- One drain per minute. With ~10% of training_log inserts touching
    -- coached athletes, batch=40 covers a healthy spike. The drainer
    -- itself uses 10-wide parallelism inside the call.
    PERFORM cron.schedule(
        'drain-coachable-moment-jobs',
        '* * * * *',
        format(
            $job$
            SELECT net.http_post(
                url := %L,
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || %L,
                    'apikey', %L
                ),
                body := jsonb_build_object('batch', 40)
            );
            $job$,
            _supabase_url || '/functions/v1/drain-coachable-moment-jobs',
            _service_key,
            _service_key
        )
    );
END;
$$;

COMMIT;

-- ============================================================================
-- Verification:
--
-- 1. Confirm the cron job is registered:
--      SELECT jobname, schedule, command
--      FROM cron.job
--      WHERE jobname = 'drain-coachable-moment-jobs';
--
-- 2. After insert a training_log for a coached athlete, watch the queue:
--      SELECT * FROM coachable_moment_jobs ORDER BY created_at DESC LIMIT 5;
--    Status should go queued → in_progress → completed within ~60s.
--
-- 3. Diagnostic — recent cron runs:
--      SELECT * FROM cron.job_run_details
--      WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'drain-coachable-moment-jobs')
--      ORDER BY start_time DESC LIMIT 10;
-- ============================================================================
