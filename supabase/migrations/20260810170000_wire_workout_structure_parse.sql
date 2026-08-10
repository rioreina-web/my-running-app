-- ============================================================================
-- wire parse-workout-structure
--
-- `parse-workout-structure` is the Observer — the one source this repo trusts
-- for workout structure (see feedback: pace_segment classifier labels are not
-- a fitness signal, only parsed_structure is). Eight call sites read it. The
-- chat's `recent_workouts` block leads with "trust user notes + work pace over
-- avg pace" and falls back to average pace only when structure is absent.
--
-- It has never been wired. Today it runs from exactly two fire-and-forget call
-- sites — a `Task { _ = try? await callEdgeFunction(...) }` in
-- EditWorkoutNotesSheet.swift and a bare `fetch()` in process-training-memo —
-- both of which discard the result. Measured 2026-08-10:
--
--     283 logs · 133 parsed (47%) · 150 unparsed — 272 of 283 HAVE notes
--
--     2026-02 100%   2026-03 55%   2026-04 33%   2026-05 0% (44 logs, all
--     with notes)    2026-06 43%   2026-07 91%   2026-08 74% and falling
--
-- A whole month at zero with no alarm, and no month since February at 100%.
-- That is the signature of a discarded error: nothing retries, nothing
-- reports, and the gaps never heal. Downstream, a 6×1mi threshold session with
-- no parsed_structure is narrated to the athlete as a flat 9-miler at average
-- pace, confidently, because the fallback is invisible to the model too.
--
-- This migration is the missing wire, in the shape the repo already uses four
-- times over (voice_processing_jobs, coach_insight_jobs, coachable_moment_jobs,
-- rpe_extraction_jobs): row changes → enqueue → a cron drains the queue.
--
--   1. `training_logs.structure_parsed_at` — the completion stamp, mirroring
--      `rpe_extracted_at`. A top-level column rather than reading
--      `parsed_structure->>'parsed_at'` so the dispatcher's retire predicate is
--      an index scan and cannot fault on a malformed JSON timestamp.
--   2. `workout_parse_jobs` — the outbox.
--   3. `enqueue_workout_parse()` — trigger on training_logs.
--   4. `dispatch_workout_parse()` — claims a bounded batch, one net.http_post
--      per job.
--   5. A per-minute cron with a batch of 6.
--   6. A seed of the 150 unparsed logs, which drains through the same path.
--
-- AUTOMATIC, BUT CORRECTABLE. `parse-workout-structure` treats
-- `parsed_structure.edited_by_user = true` as sacrosanct and skips unless the
-- caller passes `force`. That protects a manual "Fix reps" from being undone by
-- a machine re-derivation — but as a permanent freeze it also means typing the
-- real workout into the notes afterwards does nothing, which is correctable but
-- no longer automatic. So the job carries `force`, and the trigger sets it by
-- what actually changed:
--
--   • notes changed  → force = true.  The athlete just stated intent in words.
--     Typed notes are already the parser's TOP source, ranked above the GPS
--     guess; it would be incoherent for them to outrank the stream but not an
--     older tap-fix. The newest human input wins.
--   • stream arrived → force = false. A machine re-derivation must never
--     silently overwrite a human correction.
--
-- NO FEEDBACK LOOP. The trigger is scoped `UPDATE OF workout_notes,
-- cleaned_notes, notes, external_streams`. parse-workout-structure writes
-- `parsed_structure` and `structure_parsed_at`, neither of which is in that
-- list, so its own write-back cannot re-enqueue the row it just finished.
--
-- WHY A QUEUE AND NOT A TRIGGER THAT POSTS DIRECTLY. Same reason as the RPE
-- wire: a direct net.http_post would have fired 150 concurrent Gemini calls the
-- moment this applied. 6/minute drains the backlog in ~25 minutes and nothing
-- else notices.
--
-- Auth: vault secrets are read at RUN TIME inside the function, per the
-- 2026-06-11 dynamic-vault fix. Never baked in at apply time.
-- ============================================================================

-- ── 1. The completion stamp ─────────────────────────────────────────────────
ALTER TABLE public.training_logs
    ADD COLUMN IF NOT EXISTS structure_parsed_at TIMESTAMPTZ;

COMMENT ON COLUMN public.training_logs.structure_parsed_at IS
    'When parse-workout-structure last wrote parsed_structure for this row. '
    'NULL = never parsed. Set even when the parse correctly finds no structure '
    '(an easy run has none), so "parsed, nothing there" and "never parsed" are '
    'distinguishable — the fallback to average pace must never be silent.';

-- ── 2. The outbox ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.workout_parse_jobs (
    training_log_id  UUID PRIMARY KEY REFERENCES training_logs(id) ON DELETE CASCADE,
    user_id          TEXT NOT NULL,
    -- Bounded retry. A log the parser fails on three times stops costing money;
    -- it stays in the table as the record of that failure, which is the whole
    -- point — today those failures leave no trace at all.
    attempts         SMALLINT NOT NULL DEFAULT 0,
    last_attempt_at  TIMESTAMPTZ,
    last_error       TEXT,
    -- Passed through to the function. See "AUTOMATIC, BUT CORRECTABLE" above.
    force            BOOLEAN NOT NULL DEFAULT false,
    -- Why this row is owed a parse. Diagnostic only; the dispatcher ignores it.
    reason           TEXT NOT NULL DEFAULT 'created'
        CHECK (reason IN ('created', 'notes_edited', 'stream_arrived', 'backfill')),
    -- 0 = a run that just landed, 1 = a row from the historical backfill. The
    -- dispatcher orders by this FIRST so today's run is never stuck behind five
    -- months of history.
    priority         SMALLINT NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.workout_parse_jobs IS
    'Outbox for parse-workout-structure. A row means "this log has notes or a '
    'stream and no current parse". Rows are retired once training_logs.'
    'structure_parsed_at is at or after the job''s created_at; rows at '
    'attempts = 3 are exhausted and stay as the record of the failure.';

CREATE INDEX IF NOT EXISTS workout_parse_jobs_claimable_idx
    ON public.workout_parse_jobs (priority, created_at)
    WHERE attempts < 3;

ALTER TABLE public.workout_parse_jobs ENABLE ROW LEVEL SECURITY;

-- Internal queue: no athlete ever reads it. Service role only, matching
-- rpe_extraction_jobs and voice_processing_jobs.
DROP POLICY IF EXISTS "Service role full access to workout_parse_jobs"
    ON public.workout_parse_jobs;
CREATE POLICY "Service role full access to workout_parse_jobs"
    ON public.workout_parse_jobs FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- ── 3. Enqueue on notes or stream ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enqueue_workout_parse()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $fn$
DECLARE
    _notes_changed  BOOLEAN := false;
    _has_material   BOOLEAN;
    _reason         TEXT;
    _force          BOOLEAN;
BEGIN
    IF NEW.user_id IS NULL OR NEW.user_id = '' THEN
        RAISE WARNING 'training log % has no user_id — structure parse not enqueued', NEW.id;
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
    -- latches true — if any enqueue since the last parse came from the athlete
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
$fn$;

DROP TRIGGER IF EXISTS trg_enqueue_workout_parse ON public.training_logs;
CREATE TRIGGER trg_enqueue_workout_parse
    AFTER INSERT OR UPDATE OF workout_notes, cleaned_notes, notes, external_streams
    ON public.training_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.enqueue_workout_parse();

-- ── 3b. Retire the trigger that was never able to fire ──────────────────────
--
-- `auto_parse_workout_structure` has been on training_logs this whole time,
-- calling `trigger_parse_workout_structure()`. It is the reason this looked
-- wired. It reads its credentials like this:
--
--     _supabase_url := current_setting('app.settings.supabase_url', true);
--     IF _supabase_url IS NULL OR ... THEN
--       RAISE WARNING 'parse-workout-structure trigger: app.settings not configured';
--       RETURN NEW;
--
-- `ALTER DATABASE ... SET app.settings.*` is permission-denied on Supabase, so
-- those settings have never existed. Every write to training_logs took this
-- branch: a warning into the Postgres log, where nobody was looking, and a
-- silent RETURN. It has never once issued an http_post. (Independently, its
-- body omits `user_id`, which parse-workout-structure requires from
-- service-role callers — so it would have 400'd even with the settings set.
-- Two reasons it could not work, and it still read as plumbed-in.)
--
-- That is the whole explanation for 47% coverage: the only parses that ever
-- happened came from the two fire-and-forget client call sites, which is why
-- the rate tracked app usage rather than training.
--
-- Dropped rather than left alongside the queue: two triggers racing to parse
-- the same row would double every Gemini call, and leaving a decoy that looks
-- like wiring is how this went unnoticed for months. The vault-secret read in
-- `dispatch_workout_parse` above is the pattern that actually works here —
-- the same one rpe_extraction_jobs uses, per the 2026-06-11 dynamic-vault fix.
DROP TRIGGER IF EXISTS auto_parse_workout_structure ON public.training_logs;
DROP FUNCTION IF EXISTS public.trigger_parse_workout_structure();

-- ── 3c. The same wire, on the note side ─────────────────────────────────────
--
-- `docs/specs/runs-and-notes-split.md` is moving the qualitative columns off
-- training_logs and into `workout_notes` (Phase 2 landed 2026-08-10; Phase 4
-- drops `cleaned_notes` / `notes` / `workout_notes` from training_logs). A
-- trigger watching only those columns would go quiet the moment Phase 3
-- repoints the writers — silently, which is the exact failure this migration
-- exists to remove. So the note side gets the same wire now.
--
-- `parsed_structure` itself stays on training_logs: structure is a property of
-- the RUN, derived from its stream and named by the athlete's words. So a note
-- change enqueues a parse for the run it belongs to.
--
-- `run_id` is in the trigger's column list on purpose, and it is the most
-- interesting one. A memo recorded before its run has synced is a note with
-- `run_id IS NULL` — nothing to parse yet. When `linkNoteToRun()` later fills
-- it in, THAT is the moment the athlete's words first have a run to reshape,
-- and this fires the parse for it. Before the split, that case produced a
-- GPS-less orphan row instead.
--
-- Double-enqueue during dual-write is a non-issue: workout_parse_jobs is keyed
-- by training_log_id with ON CONFLICT DO UPDATE, so the mirror trigger writing
-- both tables converges on exactly one job.
CREATE OR REPLACE FUNCTION public.enqueue_workout_parse_from_note()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $fn$
BEGIN
    -- An unlinked note has no run to reshape. Not an error — the spec calls
    -- this "a valid, complete, displayable journal entry" — just nothing owed.
    IF NEW.run_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF COALESCE(btrim(NEW.cleaned_text), '') = ''
       AND COALESCE(btrim(NEW.raw_transcript), '') = '' THEN
        RETURN NEW;
    END IF;

    IF NEW.user_id IS NULL OR NEW.user_id = '' THEN
        RAISE WARNING 'workout_note % has no user_id — structure parse not enqueued', NEW.id;
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
$fn$;

DROP TRIGGER IF EXISTS trg_enqueue_workout_parse_from_note ON public.workout_notes;
CREATE TRIGGER trg_enqueue_workout_parse_from_note
    AFTER INSERT OR UPDATE OF cleaned_text, raw_transcript, run_id
    ON public.workout_notes
    FOR EACH ROW
    EXECUTE FUNCTION public.enqueue_workout_parse_from_note();

-- ── 4. The dispatcher ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_workout_parse(_batch INT DEFAULT 6)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $fn$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
    _job          RECORD;
    _sent         INT := 0;
BEGIN
    -- Retire finished work first. The comparison is against the JOB's
    -- created_at, not merely "is structure_parsed_at set" — that is what makes
    -- a RE-parse work. Editing notes on an already-parsed log stamps a new job
    -- at now(); the old parse is older than that, so the job correctly survives
    -- until a parse newer than the edit lands.
    DELETE FROM public.workout_parse_jobs j
     USING public.training_logs t
     WHERE t.id = j.training_log_id
       AND t.structure_parsed_at IS NOT NULL
       AND t.structure_parsed_at >= j.created_at;

    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets
                       WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets
                       WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE NOTICE 'dispatch_workout_parse skipped — vault secrets missing';
        RETURN 0;
    END IF;

    -- Claim and dispatch in one statement: the UPDATE ... RETURNING is what the
    -- loop reads, so a row cannot be handed out twice even if two dispatchers
    -- overlap. The 10-minute floor is the retry backoff — net.http_post is
    -- fire-and-forget, so a job that got no write-back is simply due again.
    FOR _job IN
        UPDATE public.workout_parse_jobs j
           SET attempts        = j.attempts + 1,
               last_attempt_at = now()
         WHERE j.training_log_id IN (
                   SELECT c.training_log_id
                     FROM public.workout_parse_jobs c
                    WHERE c.attempts < 3
                      AND (c.last_attempt_at IS NULL
                           OR c.last_attempt_at < now() - INTERVAL '10 minutes')
                    ORDER BY c.priority, c.created_at
                    LIMIT GREATEST(_batch, 1)
                    FOR UPDATE SKIP LOCKED
               )
        RETURNING j.training_log_id, j.user_id, j.force
    LOOP
        PERFORM net.http_post(
            url := _supabase_url || '/functions/v1/parse-workout-structure',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || _service_key,
                'apikey', _service_key
            ),
            body := jsonb_build_object(
                'training_log_id', _job.training_log_id,
                'user_id',         _job.user_id,
                'force',           _job.force
            )
        );
        _sent := _sent + 1;
    END LOOP;

    RETURN _sent;
END;
$fn$;

COMMENT ON FUNCTION public.dispatch_workout_parse(INT) IS
    'Drains workout_parse_jobs: retires logs parsed at or after their job was '
    'queued, then fires one parse-workout-structure invocation per claimed '
    'job. Returns the number dispatched.';

REVOKE ALL ON FUNCTION public.dispatch_workout_parse(INT) FROM PUBLIC, anon, authenticated;

-- ── 5. The cron ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    BEGIN
        PERFORM cron.unschedule('dispatch-workout-parse');
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    SELECT cron.schedule(
        'dispatch-workout-parse',
        '* * * * *',
        $cron$ SELECT public.dispatch_workout_parse(6); $cron$
    ) INTO _job_id;

    RAISE NOTICE 'scheduled dispatch-workout-parse as cron job %', _job_id;
END;
$$;

-- ── 6. Seed the backlog ─────────────────────────────────────────────────────
-- Every log with material to read and no parse. priority = 1 so the whole
-- backlog sits behind anything logged from here on.
INSERT INTO public.workout_parse_jobs
    (training_log_id, user_id, reason, force, priority)
SELECT t.id, t.user_id, 'backfill', false, 1
  FROM public.training_logs t
 WHERE t.parsed_structure IS NULL
   AND t.user_id IS NOT NULL
   AND t.user_id <> ''
   AND (
        COALESCE(btrim(t.workout_notes), '') <> ''
     OR COALESCE(btrim(t.cleaned_notes), '') <> ''
     OR COALESCE(btrim(t.notes), '') <> ''
     OR t.external_streams IS NOT NULL
   )
ON CONFLICT (training_log_id) DO NOTHING;
