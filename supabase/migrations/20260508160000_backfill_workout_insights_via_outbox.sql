-- ============================================================================
-- Rewrite backfill_workout_insights to enqueue into the outbox instead of
-- firing pg_net directly.
--
-- Old behavior fanned out N pg_net calls in a tight loop, which
-- overwhelms edge function concurrency on a 10k-user base. New behavior
-- inserts N rows into coach_insight_jobs and lets the cron worker drain
-- at its configured rate.
--
-- Returns the number of rows enqueued (not the number of historical
-- rows missing — that count is queryable directly via SELECT count(*)
-- FROM coach_insight_jobs WHERE status = 'queued').
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION backfill_workout_insights(batch_limit INT DEFAULT 100)
RETURNS INT AS $$
DECLARE
    _queued INT;
BEGIN
    INSERT INTO coach_insight_jobs (training_log_id, user_id)
    SELECT id, user_id
      FROM training_logs
     WHERE coach_insight IS NULL
       AND audio_url IS NULL
       AND user_id IS NOT NULL
       AND workout_duration_minutes IS NOT NULL
       AND workout_duration_minutes > 0
       AND coach_insight_status IN ('pending', 'failed')
     ORDER BY workout_date DESC
     LIMIT COALESCE(batch_limit, 1000000)
    ON CONFLICT (training_log_id) DO NOTHING;

    GET DIAGNOSTICS _queued = ROW_COUNT;

    -- Reset failed rows so the worker reattempts them.
    UPDATE coach_insight_jobs
       SET status = 'queued',
           attempts = 0,
           next_retry_at = NOW(),
           last_error = NULL
     WHERE training_log_id IN (
        SELECT id FROM training_logs
         WHERE coach_insight_status = 'failed'
         ORDER BY workout_date DESC
         LIMIT COALESCE(batch_limit, 1000000)
     )
       AND status = 'failed';

    RETURN _queued;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = pg_catalog, pg_temp;

COMMENT ON FUNCTION backfill_workout_insights(INT) IS
    'Enqueue rows missing coach_insight into coach_insight_jobs. The '
    'cron worker drain-coach-insight-jobs picks them up at its configured '
    'rate. Returns the number of rows enqueued. Safe to re-run — the '
    'UNIQUE(training_log_id) constraint keeps the queue clean.';

COMMIT;
