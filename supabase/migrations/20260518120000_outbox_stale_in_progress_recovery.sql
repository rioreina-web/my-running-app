-- ============================================================================
-- Stale `in_progress` recovery sweep for the outbox queues.
--
-- Both outbox queues (coach_insight_jobs, coachable_moment_jobs) can
-- strand rows in `in_progress` when a worker crashes mid-batch — edge-fn
-- timeout, Deno OOM, pod recycle. The drainer's claim RPC only picks
-- `status='queued'`, so a stranded row blocks all future events for the
-- same key (training_log_id for coach_insight, athlete_user_id for
-- coachable_moment) and never recovers without intervention.
--
-- This sweep runs every 5 minutes and resets any `in_progress` row
-- whose `last_attempted_at` is older than 5 minutes (well past the 30s
-- edge-fn budget) back to `queued`. The drainer then picks it up on
-- the next tick.
--
-- Why 5 minutes:
--   - Edge fn timeout caps at 150s (Supabase platform limit).
--   - Adding margin for "function is in the middle of a legitimate slow
--     call" (Gemini upstream latency spike, etc.) lands around 5 min.
--   - Shorter (e.g. 2 min) risks double-processing during legitimate
--     long jobs. Longer (e.g. 30 min) delays recovery too much.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

DO $$
BEGIN
    -- Idempotent: unschedule first so re-running this migration is safe.
    BEGIN
        PERFORM cron.unschedule('outbox-stale-in-progress-recovery');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    PERFORM cron.schedule(
        'outbox-stale-in-progress-recovery',
        '*/5 * * * *',
        $job$
        WITH coach_insight_reset AS (
            UPDATE coach_insight_jobs
               SET status = 'queued',
                   next_retry_at = NOW()
             WHERE status = 'in_progress'
               AND last_attempted_at < NOW() - INTERVAL '5 minutes'
            RETURNING 1
        ),
        coachable_moment_reset AS (
            UPDATE coachable_moment_jobs
               SET status = 'queued',
                   next_retry_at = NOW()
             WHERE status = 'in_progress'
               AND last_attempted_at < NOW() - INTERVAL '5 minutes'
            RETURNING 1
        )
        SELECT
            (SELECT count(*) FROM coach_insight_reset)   AS coach_insight_reset,
            (SELECT count(*) FROM coachable_moment_reset) AS coachable_moment_reset;
        $job$
    );
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'outbox-stale-in-progress-recovery cron not scheduled (pg_cron unavailable)';
END;
$$;

COMMIT;

-- ============================================================================
-- Verification:
--
-- 1. Confirm cron registered:
--      SELECT jobname, schedule FROM cron.job
--      WHERE jobname = 'outbox-stale-in-progress-recovery';
--    Expected: 1 row, schedule '*/5 * * * *'.
--
-- 2. Manual smoke (force a stale row, then trigger the sweep):
--      UPDATE coachable_moment_jobs
--         SET status='in_progress', last_attempted_at = NOW() - INTERVAL '10 min'
--       WHERE athlete_user_id = '<test-athlete>';
--    Wait up to 5 min OR run the sweep manually:
--      SELECT cron.schedule('manual-sweep-test', '* * * * *', 'SELECT 1');
--      (Easier: just run the inner UPDATE manually to confirm it works.)
--
-- 3. Diagnostic — recent sweep runs:
--      SELECT * FROM cron.job_run_details
--      WHERE jobid = (
--          SELECT jobid FROM cron.job
--          WHERE jobname = 'outbox-stale-in-progress-recovery'
--      )
--      ORDER BY start_time DESC LIMIT 10;
-- ============================================================================
