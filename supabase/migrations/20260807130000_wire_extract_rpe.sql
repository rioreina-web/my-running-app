-- ============================================================================
-- wire extract-rpe
--
-- `extract-rpe` has been deployed since 2026-06-11. The columns exist
-- (20260611180000_add_rpe_to_training_logs.sql), the Train tab renders
-- "Effort · Felt vs Planned" off them, and the view model already guards with
-- `guard let felt = rpe?.feltRpe` so it draws nothing rather than a fabricated
-- number. That guard is why nobody noticed: the section has been silently
-- empty for two months because **nothing has ever called the function**.
-- 268 logs carry a transcript; 0 carry a felt RPE.
--
-- This migration is the missing wire, in the shape the repo already uses three
-- times over (voice_processing_jobs, coach_insight_jobs, coachable moments):
-- row changes → enqueue → a cron drains the queue.
--
--   1. `rpe_extraction_jobs` — the outbox. One row per log awaiting extraction.
--   2. `enqueue_rpe_extraction()` — trigger on training_logs. Fires when a
--      transcript lands (INSERT, or UPDATE OF cleaned_notes/notes — which is
--      exactly what the voice pipeline writes when a memo finishes cleaning).
--   3. `dispatch_rpe_extraction()` — claims a bounded batch and fires one
--      net.http_post per job at extract-rpe.
--   4. A per-minute cron calling (3) with a batch of 8.
--   5. A seed of the 268 existing logs, which drains through the same path.
--
-- WHY A QUEUE AND NOT A TRIGGER THAT POSTS DIRECTLY. A trigger calling
-- net.http_post is two fewer objects, and it would have fired 268 concurrent
-- Gemini calls the moment this migration applied. The queue exists to make the
-- backfill boring: 8/minute, ~34 minutes, nothing else notices.
--
-- WHY `rpe_extracted_at IS NOT NULL` IS THE COMPLETION SIGNAL. extract-rpe
-- stamps it on every successful write — including when the model correctly
-- returns felt_rpe = null because the memo never said how hard it felt. So
-- "done" and "found a number" are different states, and a memo that genuinely
-- conveys no effort is retired rather than retried forever.
--
-- NO FEEDBACK LOOP. The trigger is scoped `UPDATE OF cleaned_notes, notes`, so
-- extract-rpe's own write-back (felt_rpe, rpe_pull_quote, rpe_tags,
-- rpe_extracted_at) cannot re-enqueue the row it just finished.
--
-- Auth: vault secrets are read at RUN TIME inside the function, per the
-- 2026-06-11 dynamic-vault fix. Never baked in at apply time.
-- ============================================================================

-- ── 1. The outbox ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.rpe_extraction_jobs (
    training_log_id  UUID PRIMARY KEY REFERENCES training_logs(id) ON DELETE CASCADE,
    user_id          TEXT NOT NULL,
    -- Bounded retry. A log the model fails on three times stops costing money;
    -- it stays in the table as the record of that, and the Train tab keeps
    -- rendering nothing for it, which is the honest outcome.
    attempts         SMALLINT NOT NULL DEFAULT 0,
    last_attempt_at  TIMESTAMPTZ,
    -- 0 = a memo that just landed, 1 = a row from the historical backfill.
    -- The dispatcher orders by this FIRST, so a run logged today is never stuck
    -- behind two months of history — not on the first minute of the drain and
    -- not on the last. (An earlier draft encoded the same intent by stamping
    -- backfill rows a few minutes into the future; that only held while the
    -- backlog was younger than its own offset window, which is a trap.)
    priority         SMALLINT NOT NULL DEFAULT 0,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.rpe_extraction_jobs IS
    'Outbox for extract-rpe. A row means "this log has a transcript and no RPE '
    'yet". Rows are deleted once training_logs.rpe_extracted_at is stamped; '
    'rows at attempts = 3 are exhausted and stay as a record of the failure.';

-- Mirrors the dispatcher's predicate, so the claim stays an index scan as the
-- table grows.
CREATE INDEX IF NOT EXISTS rpe_extraction_jobs_claimable_idx
    ON public.rpe_extraction_jobs (priority, created_at)
    WHERE attempts < 3;

ALTER TABLE public.rpe_extraction_jobs ENABLE ROW LEVEL SECURITY;

-- Internal queue: no athlete ever reads it. Service role only, matching
-- voice_processing_jobs.
DROP POLICY IF EXISTS "Service role full access to rpe_extraction_jobs"
    ON public.rpe_extraction_jobs;
CREATE POLICY "Service role full access to rpe_extraction_jobs"
    ON public.rpe_extraction_jobs FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- ── 2. Enqueue on transcript ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.enqueue_rpe_extraction()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_catalog', 'pg_temp'
AS $fn$
BEGIN
    -- Already extracted (or re-extracted by hand) — nothing owed.
    IF NEW.rpe_extracted_at IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- No transcript, nothing to read. extract-rpe would return
    -- {skipped: "no transcript"} and we would have paid a round trip for it.
    IF COALESCE(btrim(NEW.cleaned_notes), '') = ''
       AND COALESCE(btrim(NEW.notes), '') = '' THEN
        RETURN NEW;
    END IF;

    IF NEW.user_id IS NULL OR NEW.user_id = '' THEN
        RAISE WARNING 'training log % has no user_id — RPE not enqueued', NEW.id;
        RETURN NEW;
    END IF;

    INSERT INTO public.rpe_extraction_jobs (training_log_id, user_id)
    VALUES (NEW.id, NEW.user_id)
    ON CONFLICT (training_log_id) DO NOTHING;

    RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_enqueue_rpe_extraction ON public.training_logs;
CREATE TRIGGER trg_enqueue_rpe_extraction
    AFTER INSERT OR UPDATE OF cleaned_notes, notes
    ON public.training_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.enqueue_rpe_extraction();

-- ── 3. The dispatcher ───────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_rpe_extraction(_batch INT DEFAULT 8)
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
    -- Retire finished work first. extract-rpe stamps rpe_extracted_at on write,
    -- so the log row itself is the completion record — the queue never has to
    -- be told, and a job can never be marked done while the write failed.
    DELETE FROM public.rpe_extraction_jobs j
     USING public.training_logs t
     WHERE t.id = j.training_log_id
       AND t.rpe_extracted_at IS NOT NULL;

    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets
                       WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets
                       WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE NOTICE 'dispatch_rpe_extraction skipped — vault secrets missing';
        RETURN 0;
    END IF;

    -- Claim and dispatch in one statement: the UPDATE ... RETURNING is what the
    -- loop reads, so a row cannot be handed out twice even if two dispatchers
    -- overlap. `FOR UPDATE SKIP LOCKED` is the same guard
    -- claim_voice_processing_jobs uses. The 10-minute floor is the retry
    -- backoff: net.http_post is fire-and-forget, so a job that got no
    -- write-back is simply due again.
    FOR _job IN
        UPDATE public.rpe_extraction_jobs j
           SET attempts        = j.attempts + 1,
               last_attempt_at = now()
         WHERE j.training_log_id IN (
                   SELECT c.training_log_id
                     FROM public.rpe_extraction_jobs c
                    WHERE c.attempts < 3
                      AND (c.last_attempt_at IS NULL
                           OR c.last_attempt_at < now() - INTERVAL '10 minutes')
                    ORDER BY c.priority, c.created_at
                    LIMIT GREATEST(_batch, 1)
                    FOR UPDATE SKIP LOCKED
               )
        RETURNING j.training_log_id, j.user_id
    LOOP
        PERFORM net.http_post(
            url := _supabase_url || '/functions/v1/extract-rpe',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || _service_key,
                'apikey', _service_key
            ),
            body := jsonb_build_object(
                'log_id',  _job.training_log_id,
                'user_id', _job.user_id
            )
        );
        _sent := _sent + 1;
    END LOOP;

    RETURN _sent;
END;
$fn$;

COMMENT ON FUNCTION public.dispatch_rpe_extraction(INT) IS
    'Drains rpe_extraction_jobs: retires completed logs, then fires one '
    'extract-rpe invocation per claimed job. Returns the number dispatched.';

REVOKE ALL ON FUNCTION public.dispatch_rpe_extraction(INT) FROM PUBLIC, anon, authenticated;

-- ── 4. The cron ─────────────────────────────────────────────────────────────
DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    BEGIN
        PERFORM cron.unschedule('dispatch-rpe-extraction');
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    SELECT cron.schedule(
        'dispatch-rpe-extraction',
        '* * * * *',
        $cron$ SELECT public.dispatch_rpe_extraction(8); $cron$
    ) INTO _job_id;

    RAISE NOTICE 'dispatch-rpe-extraction cron scheduled (job id %)', _job_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — dispatch-rpe-extraction not scheduled';
END;
$$;

-- ── 5. Seed the backlog ─────────────────────────────────────────────────────
-- Every log that already has a transcript and no RPE. As of 2026-08-07 that is
-- 268 rows, which the per-minute cron drains in ~34 minutes.
--
-- `priority = 1` puts every one of them behind any memo recorded from here on,
-- permanently — see the column comment. Within the backlog the drain order is
-- `created_at`, stamped from row_number over workout_date DESC so the most
-- recent run goes first: those are the ones the athlete scrolls to, and they
-- are the ones the Ask analyzers and the Train tab read from.
INSERT INTO public.rpe_extraction_jobs (training_log_id, user_id, priority, created_at)
SELECT t.id,
       t.user_id,
       1,
       now() + (row_number() OVER (ORDER BY t.workout_date DESC) * INTERVAL '1 second')
  FROM public.training_logs t
 WHERE t.rpe_extracted_at IS NULL
   AND t.user_id IS NOT NULL
   AND t.user_id <> ''
   AND (COALESCE(btrim(t.cleaned_notes), '') <> ''
        OR COALESCE(btrim(t.notes), '') <> '')
ON CONFLICT (training_log_id) DO NOTHING;
