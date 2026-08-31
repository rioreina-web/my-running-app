-- Voice outbox becomes a SAFETY NET, not a second processor (2026-08-31).
--
-- Since 2026-08-04 the app direct-invokes process-training-memo on insert;
-- the outbox row exists so a memo recorded into a dead network / crashed app
-- still gets processed. But the trigger enqueued with next_retry_at = NOW(),
-- so the every-minute drain routinely raced the healthy in-flight run:
-- 2026-08-31's memo hit a 409 at 14:45:05, backed off 30s, and the job showed
-- "in flight" until 14:46:02 — for a memo whose row completed at 14:45:09.
-- Every cron tick that lands inside the ~15s processing window wastes an
-- invocation and stretches the job's apparent latency to 60-90s.
--
-- Two changes, one invariant — job state DERIVES from row state:
--
--   1. Enqueue with a 90s grace period. The healthy direct path finishes in
--      ~6-15s; the drain only ever claims jobs whose memo is genuinely
--      stranded (no direct invocation completed inside the grace window).
--
--   2. When the training_logs row reaches processing_status = 'completed'
--      (written by process-training-memo AND process-check-in), complete the
--      outbox job in the same transaction. The drain's claim query
--      (status = 'queued') then never sees finished work at all.
--
-- Worst-case rescue for a genuinely stranded memo moves from ~60s to ~90-150s
-- (grace + next cron tick) — acceptable for the failure path; the healthy
-- path no longer touches the drain at all.

-- ── 1. Grace period on enqueue ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.trigger_voice_log_processing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
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

    -- next_retry_at = +90s: the app direct-invokes the processor the moment
    -- it inserts the row, and the healthy run completes well inside 90s (at
    -- which point the completion trigger below closes this job before the
    -- drain ever sees it). The drain claiming this row means the direct
    -- invocation died — exactly what the outbox exists for.
    INSERT INTO public.voice_processing_jobs
        (training_log_id, user_id, kind, audio_url, next_retry_at)
    VALUES (
        NEW.id,
        NEW.user_id,
        CASE
            WHEN NEW.source = 'check_in' THEN 'check_in'
            WHEN NEW.audio_url IS NULL OR NEW.audio_url = '' THEN 'note'
            ELSE 'memo'
        END,
        NEW.audio_url,
        NOW() + INTERVAL '90 seconds'
    )
    ON CONFLICT (training_log_id) DO UPDATE
        SET audio_url     = EXCLUDED.audio_url,
            kind          = EXCLUDED.kind,
            status        = 'queued',
            attempts      = 0,
            last_error    = NULL,
            next_retry_at = NOW() + INTERVAL '90 seconds',
            completed_at  = NULL
      WHERE public.voice_processing_jobs.audio_url
            IS DISTINCT FROM EXCLUDED.audio_url;

    RETURN NEW;
END;
$function$;

-- ── 2. Row completion completes the job ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_complete_voice_job_on_row_complete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
    UPDATE public.voice_processing_jobs
       SET status       = 'completed',
           completed_at = NOW()
     WHERE training_log_id = NEW.id
       AND status IN ('queued', 'in_progress');
    RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_complete_voice_job_on_row_complete ON public.training_logs;
CREATE TRIGGER trg_complete_voice_job_on_row_complete
AFTER UPDATE OF processing_status ON public.training_logs
FOR EACH ROW
WHEN (NEW.processing_status = 'completed'
      AND OLD.processing_status IS DISTINCT FROM 'completed')
EXECUTE FUNCTION public.fn_complete_voice_job_on_row_complete();

-- Rows deleted by the late-sibling collapse (merge_voice_orphan_into_run)
-- need no handling here: voice_processing_jobs.training_log_id is
-- ON DELETE CASCADE, so the job row goes with the memo row.
