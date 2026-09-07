-- Route typed manual notes through the same analysis pipeline as voice memos
-- (mood + niggle/injury-mention extraction), per the 2026-07-18 "build out
-- typed-note parsing" decision.
--
-- Before this, trigger_voice_log_processing only enqueued rows with an
-- audio_url, so a typed note (audio_url NULL) was stored verbatim and never
-- analyzed. This migration:
--   1. Allows the outbox to carry an audio-less job (voice_processing_jobs
--      .audio_url NULL) and a new kind 'note'.
--   2. Broadens the enqueue trigger to also fire for typed notes: any pending
--      row with notes but no audio → a 'note' job. The audio-memo and check-in
--      paths are byte-for-byte unchanged.
--
-- Downstream: drain-voice-processing-jobs routes 'note' to process-training-memo
-- (only 'check_in' diverges), and process-training-memo takes its text branch
-- (transcription = the row's `notes`, skipping audio transcription). Cost is
-- capped under the shared `voice_memo` monthly ceiling.

-- 1. Outbox can hold an audio-less job.
ALTER TABLE public.voice_processing_jobs
    ALTER COLUMN audio_url DROP NOT NULL;

-- 2. Allow the 'note' kind (auto-named inline CHECK from the create migration).
ALTER TABLE public.voice_processing_jobs
    DROP CONSTRAINT IF EXISTS voice_processing_jobs_kind_check;
ALTER TABLE public.voice_processing_jobs
    ADD CONSTRAINT voice_processing_jobs_kind_check
    CHECK (kind IN ('memo', 'check_in', 'note'));

-- 3. Enqueue typed notes too. Audio path unchanged; adds the text path.
CREATE OR REPLACE FUNCTION public.trigger_voice_log_processing()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
    -- Only enqueue rows explicitly awaiting processing.
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
    ON CONFLICT (training_log_id) DO NOTHING;

    RETURN NEW;
END;
$function$;
