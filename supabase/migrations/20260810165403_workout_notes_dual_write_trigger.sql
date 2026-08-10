-- Phase 2b — dual-write into `workout_notes`, in the database rather than the
-- client.
--
-- WHY A TRIGGER AND NOT SWIFT. The spec says "voice upload writes to
-- workout_notes and the old columns". There are five writers that can put a
-- note on a training_logs row — the iOS recorder, the attach-to-this-run sheet,
-- the check-in flow, process-training-memo, and dedupe_recent_training_logs()
-- — and a dual-write added at each call site is five chances to forget one.
-- The whole reason this bug has been re-fixed five times is that the rule lived
-- in call sites instead of in the schema. So it goes in the schema.
--
-- THE IDENTITY OF A NOTE IS ITS RECORDING. A memo can move between
-- training_logs rows (the cron merges it onto a run, then deletes the row it
-- came from), so `legacy_log_id` alone is not a stable key — keying on it would
-- mint a SECOND note every time the cron photocopied one. `audio_url` is the
-- thing that does not move: one uploaded recording, one note. Hence the partial
-- unique index below, verified against 0 existing collisions.
--
-- The happy consequence: when the cron merges a memo onto a run, this trigger
-- sees a run row carrying a known recording and sets that note's `run_id` to
-- the run. The cron's photocopy becomes a real link, which is exactly what the
-- athlete meant by "the voice log should attach itself to the workout".
--
-- run_id is only ever FILLED IN, never cleared and never repointed once set —
-- linkNoteToRun and this trigger may add a link; nothing here may take one away.
-- Nothing reads this table yet. Fully reversible: DROP TRIGGER.

CREATE UNIQUE INDEX IF NOT EXISTS workout_notes_user_audio_uniq
    ON public.workout_notes(user_id, audio_url)
    WHERE audio_url IS NOT NULL;

CREATE OR REPLACE FUNCTION public.mirror_training_log_to_workout_notes()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_is_note   boolean;
  v_is_run    boolean;
  v_clean     text;
  v_raw       text;
  v_existing  uuid;
BEGIN
  IF NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_is_note := NEW.source IN ('voice_log', 'check_in') OR NEW.audio_url IS NOT NULL;
  IF NOT v_is_note THEN
    RETURN NEW;
  END IF;

  v_is_run := NEW.source IN ('strava', 'auto_sync', 'strava_backfill');

  -- Same two judgement calls as the backfill: a Strava auto-title is not the
  -- athlete's words, and the Strava import blob in `notes` is not a transcript.
  v_clean := CASE WHEN public.is_strava_placeholder_note(NEW.cleaned_notes)
                  THEN NULL ELSE NEW.cleaned_notes END;
  v_raw   := CASE WHEN NEW.source IN ('voice_log', 'check_in')
                  THEN NEW.notes END;

  -- Find this recording's existing note: by recording first, then by the row
  -- it was mirrored from (covers typed notes, which have no audio).
  SELECT id INTO v_existing FROM public.workout_notes
   WHERE user_id = NEW.user_id
     AND NEW.audio_url IS NOT NULL
     AND audio_url = NEW.audio_url
   LIMIT 1;

  IF v_existing IS NULL THEN
    SELECT id INTO v_existing FROM public.workout_notes
     WHERE legacy_log_id = NEW.id LIMIT 1;
  END IF;

  IF v_existing IS NULL THEN
    INSERT INTO public.workout_notes (
      user_id, run_id, recorded_at, audio_url, transcript_url,
      raw_transcript, cleaned_text, mood, felt_rpe, rpe_tags,
      extracted_data, processing_status, legacy_log_id
    ) VALUES (
      NEW.user_id,
      CASE WHEN v_is_run THEN NEW.id END,
      COALESCE(NEW.workout_date, NEW.created_at, now()),
      NEW.audio_url, NEW.transcript_url,
      v_raw, v_clean, NEW.mood, NEW.felt_rpe, NEW.rpe_tags,
      NEW.extracted_data, NEW.processing_status, NEW.id
    );
  ELSE
    UPDATE public.workout_notes n SET
      -- COALESCE on the way in: a later partial update (e.g. the memo pipeline
      -- writing only processing_status) must never blank words already stored.
      run_id            = COALESCE(n.run_id, CASE WHEN v_is_run THEN NEW.id END),
      audio_url         = COALESCE(NEW.audio_url, n.audio_url),
      transcript_url    = COALESCE(NEW.transcript_url, n.transcript_url),
      raw_transcript    = COALESCE(v_raw, n.raw_transcript),
      cleaned_text      = COALESCE(v_clean, n.cleaned_text),
      mood              = COALESCE(NEW.mood, n.mood),
      felt_rpe          = COALESCE(NEW.felt_rpe, n.felt_rpe),
      rpe_tags          = COALESCE(NEW.rpe_tags, n.rpe_tags),
      extracted_data    = COALESCE(NEW.extracted_data, n.extracted_data),
      processing_status = COALESCE(NEW.processing_status, n.processing_status),
      legacy_log_id     = COALESCE(n.legacy_log_id, NEW.id)
    WHERE n.id = v_existing;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.mirror_training_log_to_workout_notes() IS
  'Phase 2 dual-write: mirrors any training_logs row that IS or CARRIES a note '
  'into workout_notes, keyed on the recording (user_id, audio_url). Only ever '
  'fills run_id in, never clears it. Nothing reads workout_notes yet.';

DROP TRIGGER IF EXISTS trg_mirror_training_log_to_notes ON public.training_logs;
CREATE TRIGGER trg_mirror_training_log_to_notes
    AFTER INSERT OR UPDATE ON public.training_logs
    FOR EACH ROW EXECUTE FUNCTION public.mirror_training_log_to_workout_notes();