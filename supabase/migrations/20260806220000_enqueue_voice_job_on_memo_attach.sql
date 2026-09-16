-- ============================================================================
-- Give the memo-ATTACH path the same retry net the memo-INSERT path has.
--
-- THE BUG (found 2026-08-06): `auto_process_voice_log` is AFTER INSERT only.
-- Attaching a memo to an ALREADY-EXISTING run (`ReceiptMemoService.attach` in
-- RunningLog/Workouts/WorkoutReceiptSignals.swift) is an UPDATE — it points the
-- run's `audio_url` at the new recording and sets `processing_status='pending'`.
-- No INSERT, so no `voice_processing_jobs` row, so no outbox, so no retry.
--
-- That left the iOS direct-invoke of `process-training-memo` as the ONLY path
-- for every attached memo. Any single failure of that one call — a 429 from the
-- per-user `voice_memo` rate limit, a dropped connection, a 5xx — stranded the
-- row at `processing_status='pending'` FOREVER, rendering as a permanent
-- "Processing with AI…" spinner in the journal with a red banner on top. Which
-- is exactly what happened: the athlete's daily `voice_memo` quota was spent by
-- a day of testing, the attach 429'd, and the memo had nowhere to land.
--
-- Why this fix is the important one: the drain worker calls
-- `process-training-memo` with the SERVICE ROLE key, and
-- `enforceFeatureRateLimit` short-circuits on `isServiceRole`. So an enqueued
-- job bypasses the per-user quota entirely. Giving the attach path an outbox row
-- makes this whole class of failure self-healing instead of terminal.
--
-- Append-only per hard rule #5: this supersedes the trigger body from
-- 20260610230012 (and its later notes-aware revision) rather than editing it.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Enqueue function — now shared by both the INSERT and UPDATE triggers.
--
--    Body is the current live logic (audio OR typed notes; check_in / note /
--    memo kinds) with one change: the ON CONFLICT clause re-queues a job when
--    the audio actually changed, so re-attaching a DIFFERENT recording to a run
--    that already carries a completed job reprocesses instead of silently
--    no-oping. Same-audio updates still collapse to nothing, which is what
--    keeps the UPDATE trigger from looping on the processor's own writes.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trigger_voice_log_processing()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    -- Only rows explicitly awaiting processing.
    IF NEW.processing_status IS DISTINCT FROM 'pending' THEN
        RETURN NEW;
    END IF;

    -- Need something to work with: audio to transcribe OR typed notes to
    -- analyze. A row with neither is a no-op (e.g. an auto-synced workout).
    IF (NEW.audio_url IS NULL OR NEW.audio_url = '')
       AND (NEW.notes IS NULL OR btrim(NEW.notes) = '') THEN
        RETURN NEW;
    END IF;

    IF NEW.user_id IS NULL OR NEW.user_id = '' THEN
        RAISE WARNING 'training log % has no user_id — not enqueued', NEW.id;
        RETURN NEW;
    END IF;

    INSERT INTO public.voice_processing_jobs
        (training_log_id, user_id, kind, audio_url)
    VALUES (
        NEW.id,
        NEW.user_id,
        CASE
            WHEN NEW.source = 'check_in' THEN 'check_in'
            WHEN NEW.audio_url IS NULL OR NEW.audio_url = '' THEN 'note'
            ELSE 'memo'
        END,
        NEW.audio_url
    )
    ON CONFLICT (training_log_id) DO UPDATE
        SET audio_url     = EXCLUDED.audio_url,
            kind          = EXCLUDED.kind,
            status        = 'queued',
            attempts      = 0,
            last_error    = NULL,
            next_retry_at = NOW(),
            completed_at  = NULL
      WHERE public.voice_processing_jobs.audio_url
            IS DISTINCT FROM EXCLUDED.audio_url;

    RETURN NEW;
END;
$$;

-- ----------------------------------------------------------------------------
-- 2. The new AFTER UPDATE trigger — the attach path's entry point.
--
--    The WHEN clause is the loop guard. It fires only when the update actually
--    moved `audio_url` or `processing_status`, and only INTO the 'pending'
--    state. The processor's own writes (pending → transcribed → completed) fail
--    the `new.processing_status = 'pending'` test and never re-enter.
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS auto_process_voice_log_on_attach ON public.training_logs;

CREATE TRIGGER auto_process_voice_log_on_attach
    AFTER UPDATE ON public.training_logs
    FOR EACH ROW
    WHEN (
        new.processing_status = 'pending'
        AND (
            old.audio_url IS DISTINCT FROM new.audio_url
            OR old.processing_status IS DISTINCT FROM new.processing_status
        )
    )
    EXECUTE FUNCTION public.trigger_voice_log_processing();

COMMIT;
