-- Layer 1 of the Aug-11 cost-runaway fix: stop a write that changes nothing
-- from queuing an LLM call.
--
-- WHAT HAPPENED. On 2026-08-11 `parse-workout-structure` made 1,269 Gemini
-- calls (normal is single digits) and only stopped when the Gemini prepaid
-- balance hit zero. Reproduced in a rolled-back transaction: stamping
-- `structure_parsed_at` on a training_logs row creates a NEW workout_parse_jobs
-- row for that same log. Completion manufactured its own next assignment.
--
-- THE MECHANISM, AND WHY IT IS NOT OBVIOUS. Postgres fires `AFTER UPDATE OF
-- <cols>` when a column appears in the SET list -- when it is ASSIGNED -- not
-- when its value CHANGES. Writing 'felt good' on top of 'felt good' counts.
--
-- So the cycle was:
--   1. parse-workout-structure writes parsed_structure + structure_parsed_at
--   2. trg_mirror_training_log_to_notes is registered on EVERY training_logs
--      update, so that stamp wakes it
--   3. the mirror re-writes workout_notes with cleaned_text / raw_transcript in
--      the SET list -- unchanged, COALESCEd on purpose so a partial write can
--      never blank the athlete's words, but ASSIGNED
--   4. trg_enqueue_workout_parse_from_note reads that as "notes changed",
--      queues a parse, and resets `attempts` to 0
--   5. dispatch_workout_parse retires a job only when
--      structure_parsed_at >= job.created_at -- and the new created_at is
--      always microseconds LATER than the stamp that caused it, so the job is
--      permanently un-retireable
--   6. one minute later, back to step 1
--
-- The `attempts < 3` cap never engaged because step 4 zeroed the counter every
-- cycle. The only brake that worked was the 10-minute per-job backoff, which is
-- why this cost ~$5/day instead of ~$300/day.
--
-- THE FIX HERE is the value-change guard: these triggers now compare OLD to NEW
-- and return early when nothing actually moved. That alone breaks the loop.
-- Narrowing the mirror trigger's column list (bottom of this file) is the
-- belt-and-braces half -- it stops the mirror being woken by writes it does not
-- mirror, which is cheaper and easier to reason about, but the guard is the
-- load-bearing change.
--
-- The same no-op-write bug exists on the training_logs side of the queue
-- (`stream_arrived` fired on any assignment to external_streams, changed or
-- not), so it is fixed in the same pass.
--
-- Fully reversible: re-run 20260810165403 and 20260810170000 to restore the
-- previous definitions. No data is modified.

-- ── 1. workout_notes → parse queue ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enqueue_workout_parse_from_note()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
BEGIN
    -- THE GUARD. `UPDATE OF cleaned_text, raw_transcript, run_id` fires on
    -- assignment, not on change. mirror_training_log_to_workout_notes()
    -- re-assigns all three on every pass, so without this an unrelated write to
    -- the parent training_logs row queued an LLM call. See header.
    IF TG_OP = 'UPDATE'
       AND NEW.cleaned_text   IS NOT DISTINCT FROM OLD.cleaned_text
       AND NEW.raw_transcript IS NOT DISTINCT FROM OLD.raw_transcript
       AND NEW.run_id         IS NOT DISTINCT FROM OLD.run_id THEN
        RETURN NEW;
    END IF;

    -- An unlinked note has no run to reshape. Not an error -- the spec calls
    -- this "a valid, complete, displayable journal entry" -- just nothing owed.
    IF NEW.run_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF COALESCE(btrim(NEW.cleaned_text), '') = ''
       AND COALESCE(btrim(NEW.raw_transcript), '') = '' THEN
        RETURN NEW;
    END IF;

    IF NEW.user_id IS NULL OR NEW.user_id = '' THEN
        RAISE WARNING 'workout_note % has no user_id -- structure parse not enqueued', NEW.id;
        RETURN NEW;
    END IF;

    -- force = true: these are the athlete's own words, which the parser already
    -- ranks above the GPS guess. Same rule as the notes branch on training_logs.
    INSERT INTO public.workout_parse_jobs
        (training_log_id, user_id, reason, force, priority, created_at)
    VALUES (NEW.run_id, NEW.user_id, 'notes_edited', true, 0, now())
    ON CONFLICT (training_log_id) DO UPDATE
        SET reason          = 'notes_edited',
            force           = true,
            attempts        = 0,
            last_error      = NULL,
            last_attempt_at = NULL,
            priority        = 0,
            created_at      = now();

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enqueue_workout_parse_from_note() IS
  'Queues a structure re-parse when an athlete''s note text actually changes. '
  'The OLD/NEW guard is load-bearing: UPDATE OF fires on assignment, not on '
  'change, and the workout_notes mirror re-assigns these columns on every pass. '
  'Without the guard, each completed parse queued the next one (2026-08-11).';

-- ── 2. training_logs → parse queue ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enqueue_workout_parse()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
    _notes_changed  BOOLEAN := false;
    _has_material   BOOLEAN;
    _reason         TEXT;
    _force          BOOLEAN;
BEGIN
    -- Same guard, same reason. The old code had no early return here: when none
    -- of the watched columns had changed it fell through to the
    -- 'stream_arrived' branch and queued a parse anyway.
    IF TG_OP = 'UPDATE'
       AND NEW.workout_notes    IS NOT DISTINCT FROM OLD.workout_notes
       AND NEW.cleaned_notes    IS NOT DISTINCT FROM OLD.cleaned_notes
       AND NEW.notes            IS NOT DISTINCT FROM OLD.notes
       AND NEW.external_streams IS NOT DISTINCT FROM OLD.external_streams THEN
        RETURN NEW;
    END IF;

    IF NEW.user_id IS NULL OR NEW.user_id = '' THEN
        RAISE WARNING 'training log % has no user_id -- structure parse not enqueued', NEW.id;
        RETURN NEW;
    END IF;

    -- Nothing to read from. The parser needs either words or a GPS stream;
    -- with neither it would return "no sources" and we would have paid a round
    -- trip to learn that.
    _has_material :=
        COALESCE(btrim(NEW.workout_notes), '') <> ''
        OR COALESCE(btrim(NEW.cleaned_notes), '') <> ''
        OR COALESCE(btrim(NEW.notes), '') <> ''
        OR NEW.external_streams IS NOT NULL;

    IF NOT _has_material THEN
        RETURN NEW;
    END IF;

    IF TG_OP = 'UPDATE' THEN
        _notes_changed :=
            NEW.workout_notes IS DISTINCT FROM OLD.workout_notes
            OR NEW.cleaned_notes IS DISTINCT FROM OLD.cleaned_notes
            OR NEW.notes IS DISTINCT FROM OLD.notes;
    END IF;

    IF TG_OP = 'INSERT' THEN
        _reason := 'created';
        _force  := false;
    ELSIF _notes_changed THEN
        _reason := 'notes_edited';
        _force  := true;
    ELSE
        _reason := 'stream_arrived';
        _force  := false;
    END IF;

    -- DO UPDATE, not DO NOTHING: a row already queued but not yet drained must
    -- pick up the newer reason, and a row that previously exhausted its retries
    -- deserves a fresh three attempts now that its inputs have changed. `force`
    -- latches true -- if any enqueue since the last parse came from the athlete
    -- typing, their words win when the job finally runs.
    INSERT INTO public.workout_parse_jobs
        (training_log_id, user_id, reason, force, priority, created_at)
    VALUES (NEW.id, NEW.user_id, _reason, _force, 0, now())
    ON CONFLICT (training_log_id) DO UPDATE
        SET reason          = EXCLUDED.reason,
            force           = public.workout_parse_jobs.force OR EXCLUDED.force,
            attempts        = 0,
            last_error      = NULL,
            last_attempt_at = NULL,
            priority        = 0,
            created_at      = now();

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enqueue_workout_parse() IS
  'Queues a structure parse when a run''s words or GPS stream actually change. '
  'The OLD/NEW guard prevents no-op writes from queuing an LLM call.';

-- ── 3. Narrow the mirror trigger to the columns it actually mirrors ─────────
-- Belt and braces. mirror_training_log_to_workout_notes() reads exactly the
-- columns below; being registered on every training_logs update meant a
-- structure_parsed_at stamp, a stress_load recompute, or a pace_segments
-- rewrite all woke it to copy data that had not moved. The function body is
-- unchanged -- this only narrows when it runs.
--
-- If a future column needs mirroring, ADD IT HERE. A missing column here means
-- that field silently stops mirroring on update (it still mirrors on insert).
DROP TRIGGER IF EXISTS trg_mirror_training_log_to_notes ON public.training_logs;
CREATE TRIGGER trg_mirror_training_log_to_notes
    AFTER INSERT OR UPDATE OF
        user_id, source, workout_date,
        audio_url, transcript_url,
        notes, cleaned_notes,
        mood, felt_rpe, rpe_tags,
        extracted_data, processing_status
    ON public.training_logs
    FOR EACH ROW EXECUTE FUNCTION public.mirror_training_log_to_workout_notes();
