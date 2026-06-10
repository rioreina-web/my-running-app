-- ============================================================================
-- Drain worker: cron schedule + atomic claim RPC + pg_net cleanup.
--
-- 1. claim_coach_insight_jobs(batch_size) — atomic SKIP LOCKED claim.
--    Marks the next batch of queued jobs as in_progress and returns
--    enough context for the worker to call generate-workout-insight.
--
-- 2. Cron every minute POSTs to drain-coach-insight-jobs. The worker
--    pulls a batch of 40 and processes 10 in parallel — ~40 insights/min
--    steady-state throughput (~57k/day). Far below Gemini RPM and edge
--    fn concurrency. Burst recovery is hours-scale by design;
--    coach_insight is enrichment, not blocking.
--
-- 3. pg_net response-cache cleanup — the legacy pg_net trigger wrote
--    response rows that grow unbounded. Daily delete of >7-day-old rows
--    keeps the table off the disk-full path.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — drain-coach-insight-jobs cron skipped';
END;
$$;

-- ----------------------------------------------------------------------------
-- 1. Atomic claim RPC
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION claim_coach_insight_jobs(batch_size INT DEFAULT 20)
RETURNS TABLE (
    id BIGINT,
    training_log_id UUID,
    user_id TEXT,
    attempts INT,
    max_attempts INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH next_batch AS (
        SELECT j.id
          FROM coach_insight_jobs j
         WHERE j.status = 'queued'
           AND j.next_retry_at <= NOW()
         ORDER BY j.next_retry_at, j.id
         LIMIT GREATEST(1, LEAST(100, COALESCE(batch_size, 20)))
        FOR UPDATE SKIP LOCKED
    )
    UPDATE coach_insight_jobs j
       SET status = 'in_progress',
           attempts = j.attempts + 1,
           last_attempted_at = NOW()
      FROM next_batch nb
     WHERE j.id = nb.id
    RETURNING j.id, j.training_log_id, j.user_id, j.attempts, j.max_attempts;
END;
$$;

REVOKE ALL ON FUNCTION claim_coach_insight_jobs(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_coach_insight_jobs(INT) TO service_role;

-- ----------------------------------------------------------------------------
-- 2. Cron schedule — drain every 30s
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
BEGIN
    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE NOTICE 'vault secrets missing — drain-coach-insight-jobs cron skipped';
        RETURN;
    END IF;

    -- Idempotent: unschedule first so re-running this migration is safe.
    BEGIN
        PERFORM cron.unschedule('drain-coach-insight-jobs');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- One drain per minute, batch of 40 with 10-wide parallelism inside
    -- the worker. Gives ~40 insights/min and stays well under the 30s
    -- edge-fn budget. We avoided the pg_sleep-staggered pattern — having
    -- two cron jobs racing on the queue is fine (SKIP LOCKED handles it)
    -- but pg_sleep inside cron sessions is fragile.
    PERFORM cron.schedule(
        'drain-coach-insight-jobs',
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
            _supabase_url || '/functions/v1/drain-coach-insight-jobs',
            _service_key,
            _service_key
        )
    );
END;
$$;

-- ----------------------------------------------------------------------------
-- 3. pg_net response-cache cleanup
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    BEGIN
        PERFORM cron.unschedule('pg-net-response-cleanup');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    PERFORM cron.schedule(
        'pg-net-response-cleanup',
        '17 4 * * *',  -- 04:17 UTC daily — off-peak, off the hour to avoid
                       -- piling on top of every other "0 4" job.
        $job$DELETE FROM net._http_response WHERE created < NOW() - INTERVAL '7 days';$job$
    );
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'pg-net-response-cleanup cron not scheduled (pg_cron unavailable)';
END;
$$;

COMMIT;
