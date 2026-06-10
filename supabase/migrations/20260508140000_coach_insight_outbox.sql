-- ============================================================================
-- Coach-insight outbox + status column.
--
-- The Sprint 2 design fired generate-workout-insight directly from a
-- training_logs INSERT trigger via pg_net. That works at small scale but
-- breaks predictably at ~1k DAU:
--   - HealthKit auto-sync bursts (~30 inserts in seconds at app launch)
--     fan out 30k pg_net calls in minutes during a Monday-morning peak.
--   - Edge function concurrency caps at 200; Gemini at 1k RPM; excess
--     calls are silently dropped, leaving rows with NULL coach_insight
--     forever.
--   - No retry, no DLQ, no operator visibility.
--
-- Outbox pattern: trigger writes a row to coach_insight_jobs; a cron-
-- driven worker drains it at a steady rate with retries. Decouples
-- ingest spikes from LLM dispatch.
--
-- Also adds coach_insight_status on training_logs to disambiguate NULL
-- (today: "no insight yet" / "tried, failed" / "skipped because voice
-- handles it" all collapse to NULL). Operators couldn't tell those apart.
-- ============================================================================

BEGIN;

-- 1. Status column on training_logs.
-- pending   = enqueued but not yet processed
-- generated = coach_insight populated successfully
-- failed    = exhausted retries; coach_insight stays NULL
-- skipped   = voice path owns this row (audio_url IS NOT NULL)
ALTER TABLE training_logs
    ADD COLUMN IF NOT EXISTS coach_insight_status TEXT
        DEFAULT 'pending'
        CHECK (coach_insight_status IN ('pending', 'generated', 'failed', 'skipped'));

-- Backfill existing data.
UPDATE training_logs
   SET coach_insight_status = 'generated'
 WHERE coach_insight IS NOT NULL
   AND length(trim(coach_insight)) > 0
   AND coach_insight_status = 'pending';

UPDATE training_logs
   SET coach_insight_status = 'skipped'
 WHERE audio_url IS NOT NULL
   AND coach_insight IS NULL
   AND coach_insight_status = 'pending';

-- 2. Outbox table.
CREATE TABLE IF NOT EXISTS coach_insight_jobs (
    id BIGSERIAL PRIMARY KEY,
    training_log_id UUID NOT NULL REFERENCES training_logs(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued', 'in_progress', 'completed', 'failed')),
    attempts INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 3,
    last_error TEXT,
    last_attempted_at TIMESTAMPTZ,
    -- Earliest time the worker is allowed to pick this up. Defaults to
    -- "now" so newly-enqueued jobs are immediately drainable.
    next_retry_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    -- Idempotency: enqueueing the same training_log twice is a no-op.
    UNIQUE (training_log_id)
);

-- Drain index — partial so it stays small even at 10M+ historical jobs.
CREATE INDEX IF NOT EXISTS idx_coach_insight_jobs_drain
    ON coach_insight_jobs (next_retry_at)
    WHERE status = 'queued';

-- Diagnostic index for "show me failed jobs" queries.
CREATE INDEX IF NOT EXISTS idx_coach_insight_jobs_failed
    ON coach_insight_jobs (last_attempted_at DESC)
    WHERE status = 'failed';

-- 3. RLS — service role only. No user paths read/write the queue;
-- training_logs.coach_insight_status is the user-visible surface.
ALTER TABLE coach_insight_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access to coach_insight_jobs"
    ON coach_insight_jobs FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

COMMIT;
