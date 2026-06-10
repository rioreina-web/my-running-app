-- ============================================================================
-- Voice auto-process pipeline → outbox pattern (W3.3 in TASKS.md).
--
-- The 20260410100000 trigger fired process-training-memo / process-check-in
-- directly via pg_net on every training_logs INSERT with audio. Same
-- failure modes the coach-insight pipeline had (no retry, no DLQ, no
-- backpressure, silent drops at burst) — and voice is the higher-stakes
-- path: a dropped memo is athlete-visible data loss, not missing
-- enrichment.
--
-- This migration mirrors the coach-insight outbox (20260508140000/170000):
--   1. voice_processing_jobs table (+ RLS, service-role only — hard rule #1)
--   2. claim_voice_processing_jobs(batch) — atomic SKIP LOCKED claim with
--      built-in stale-in_progress recovery (no separate sweep cron needed)
--   3. trigger_voice_log_processing() rewritten to enqueue instead of
--      firing pg_net directly
--   4. pg_cron: drain-voice-processing-jobs every minute, batch 10
--
-- ALSO FIXES A LATENT AUTH BUG: the old trigger's payload was
-- { record: { id, audio_url } } — no user_id. process-training-memo's
-- W2.3-follow-up auth gate (requireAuthOrServiceRole) rejects service-role
-- calls that don't name a user (400). The moment the hardened function
-- deploys, the old trigger's calls would start failing. The outbox payload
-- carries user_id.
--
-- DEVIATION from the TASKS.md spec: no `voice_processing_status` column is
-- added. training_logs.processing_status (20260212100000) already serves
-- exactly that role (pending/processing/completed/failed, managed by the
-- edge functions + cleanup_stuck_processing cron). A second status column
-- would drift from the first. cleanup_stuck_processing stays as
-- belt-and-suspenders for rows stuck in 'processing'.
--
-- SECURITY DEFINER hygiene per 20260520130000's lesson: search_path pinned
-- AND every relation schema-qualified.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ----------------------------------------------------------------------------
-- 1. Outbox table
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.voice_processing_jobs (
    id BIGSERIAL PRIMARY KEY,
    training_log_id UUID NOT NULL REFERENCES public.training_logs(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL,
    -- Which downstream function processes this row.
    kind TEXT NOT NULL CHECK (kind IN ('memo', 'check_in')),
    audio_url TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued', 'in_progress', 'completed', 'failed')),
    attempts INT NOT NULL DEFAULT 0,
    max_attempts INT NOT NULL DEFAULT 3,
    last_error TEXT,
    last_attempted_at TIMESTAMPTZ,
    next_retry_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    -- Idempotency: enqueueing the same training_log twice is a no-op.
    UNIQUE (training_log_id)
);

CREATE INDEX IF NOT EXISTS idx_voice_processing_jobs_drain
    ON public.voice_processing_jobs (next_retry_at)
    WHERE status = 'queued';

CREATE INDEX IF NOT EXISTS idx_voice_processing_jobs_failed
    ON public.voice_processing_jobs (last_attempted_at DESC)
    WHERE status = 'failed';

ALTER TABLE public.voice_processing_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role full access to voice_processing_jobs"
    ON public.voice_processing_jobs FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- ----------------------------------------------------------------------------
-- 2. Atomic claim RPC (with stale-in_progress recovery built in)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_voice_processing_jobs(batch_size INT DEFAULT 10)
RETURNS TABLE (
    id BIGINT,
    training_log_id UUID,
    user_id TEXT,
    kind TEXT,
    audio_url TEXT,
    attempts INT,
    max_attempts INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    -- Stale recovery first: a drain worker that hit its wall-clock budget
    -- mid-batch strands rows in 'in_progress'. Voice processing
    -- (transcription + LLM) can legitimately take ~60s, so the threshold
    -- is generous. Exhausted rows go to 'failed'; the rest re-queue.
    UPDATE public.voice_processing_jobs j
       SET status = CASE WHEN j.attempts >= j.max_attempts THEN 'failed' ELSE 'queued' END,
           last_error = COALESCE(j.last_error, 'stale in_progress recovered'),
           next_retry_at = NOW()
     WHERE j.status = 'in_progress'
       AND j.last_attempted_at < NOW() - INTERVAL '10 minutes';

    RETURN QUERY
    WITH next_batch AS (
        SELECT j.id
          FROM public.voice_processing_jobs j
         WHERE j.status = 'queued'
           AND j.next_retry_at <= NOW()
         ORDER BY j.next_retry_at, j.id
         LIMIT GREATEST(1, LEAST(50, COALESCE(batch_size, 10)))
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.voice_processing_jobs j
       SET status = 'in_progress',
           attempts = j.attempts + 1,
           last_attempted_at = NOW()
      FROM next_batch nb
     WHERE j.id = nb.id
    RETURNING j.id, j.training_log_id, j.user_id, j.kind, j.audio_url, j.attempts, j.max_attempts;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_voice_processing_jobs(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_voice_processing_jobs(INT) TO service_role;

-- ----------------------------------------------------------------------------
-- 3. Trigger: enqueue instead of direct pg_net fire
--    (CREATE OR REPLACE swaps the function body under the existing
--     auto_process_voice_log trigger — no trigger re-attach needed.)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_voice_log_processing()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    -- Only rows with audio that need processing.
    IF NEW.audio_url IS NULL OR NEW.processing_status IS DISTINCT FROM 'pending' THEN
        RETURN NEW;
    END IF;

    -- No user — nothing downstream can do anything useful, and the
    -- hardened edge functions would reject the call anyway.
    IF NEW.user_id IS NULL OR NEW.user_id = '' THEN
        RAISE WARNING 'voice log % has no user_id — not enqueued', NEW.id;
        RETURN NEW;
    END IF;

    INSERT INTO public.voice_processing_jobs
        (training_log_id, user_id, kind, audio_url)
    VALUES (
        NEW.id,
        NEW.user_id,
        CASE WHEN NEW.source = 'check_in' THEN 'check_in' ELSE 'memo' END,
        NEW.audio_url
    )
    ON CONFLICT (training_log_id) DO NOTHING;

    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 4. Cron: drain every minute
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — drain-voice-processing-jobs cron skipped';
        RETURN;
    END;

    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE NOTICE 'vault secrets missing — drain-voice-processing-jobs cron skipped';
        RETURN;
    END IF;

    BEGIN
        PERFORM cron.unschedule('drain-voice-processing-jobs');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Batch 10, parallelism 3 inside the worker. Voice processing is
    -- slow (transcription + LLM, ~10-60s/job), so the worker is sized to
    -- finish well inside its budget and let the every-minute cadence do
    -- the throughput: ~10 memos/min steady state, which is far above the
    -- expected voice-log rate at 1k users (~700/day ≈ 0.5/min).
    PERFORM cron.schedule(
        'drain-voice-processing-jobs',
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
                body := jsonb_build_object('batch', 10)
            );
            $job$,
            _supabase_url || '/functions/v1/drain-voice-processing-jobs',
            _service_key,
            _service_key
        )
    );
END;
$$;

COMMIT;

-- ============================================================================
-- Verification (run in SQL editor after the drain function is deployed):
--
--   1. Both pieces exist:
--      SELECT proname FROM pg_proc WHERE proname IN
--        ('claim_voice_processing_jobs', 'trigger_voice_log_processing');
--      SELECT jobname FROM cron.job WHERE jobname = 'drain-voice-processing-jobs';
--
--   2. Insert a training_logs row with audio_url + processing_status
--      'pending' → a queued row appears in voice_processing_jobs within
--      the same transaction, and the memo is processed within ~1 minute.
--
--   3. Failure path: point a job at a bogus audio_url → attempts climb,
--      then status='failed' with last_error after 3 tries.
-- ============================================================================
