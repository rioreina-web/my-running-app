-- Wire the budget guard into the two SQL dispatchers that spend money.
--
-- Both functions are otherwise unchanged -- same claim-and-dispatch statement,
-- same retire rule, same backoff. The only difference is that the http_post is
-- now conditional on public.llm_budget_allows().
--
-- TWO PLACES THE CHECK HAPPENS, ON PURPOSE:
--
--   1. BEFORE the claim. If the global ceiling is already spent, return 0
--      immediately without touching the queue. This matters because the claim
--      statement increments `attempts` -- checking after it would burn a retry
--      on every job, every minute, and quietly exhaust jobs that were never
--      dispatched. The queue must be untouched when we are not spending.
--
--   2. INSIDE the loop, per job. This is where the per-subject loop detector
--      lands, and it is deliberately AFTER the claim: a job that keeps tripping
--      the loop detector SHOULD burn its attempts and fall out of the rotation.
--      Its last_error records why, so it is visible rather than mute.
--
-- WHAT IS NOT COVERED YET. The other LLM surfaces -- coaching-daily-read,
-- drain-coach-insight-jobs, drain-coachable-moment-jobs, ask, and the rest --
-- call Gemini from inside the edge function, not through a SQL dispatcher, so
-- they are not behind this ceiling. They need an RPC call to
-- llm_budget_allows() at the top of the handler. Tracked in
-- LLM-COST-GUARDS-APPLY.md; until then the ceiling covers the two paths that
-- have run away through SQL.
--
-- Note that a SQL-side ceiling structurally cannot govern a client-driven
-- runaway -- the 2026-08-12 incident (COST-AUDIT-2026-08-13.md) was the iOS app
-- calling an edge function on every foreground, which never touches a
-- dispatcher. That half needs the in-handler check above plus the provider-side
-- billing cap in docs/deploy/llm-cost-controls.md.
--
-- Reversible: re-run 20260810170000 and 20260807130000 for the prior bodies.

-- ── parse-workout-structure ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_workout_parse(_batch integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
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
        RAISE NOTICE 'dispatch_workout_parse skipped -- vault secrets missing';
        RETURN 0;
    END IF;

    -- Ceiling pre-check, read-only. Nothing is claimed and nothing is recorded
    -- when the budget is spent, so the queue is left exactly as we found it and
    -- no job burns a retry it never got to use.
    IF public.llm_budget_headroom() <= 0 THEN
        PERFORM public.llm_budget_note_trip('workout_parse');
        RAISE NOTICE 'dispatch_workout_parse skipped -- LLM daily ceiling reached';
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
        IF NOT public.llm_budget_allows('workout_parse', _job.training_log_id, _job.user_id) THEN
            UPDATE public.workout_parse_jobs
               SET last_error = 'blocked by LLM budget guard at ' || now()::text
             WHERE training_log_id = _job.training_log_id;
            CONTINUE;
        END IF;

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
$$;

-- ── extract-rpe ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_rpe_extraction(_batch integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
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
        RAISE NOTICE 'dispatch_rpe_extraction skipped -- vault secrets missing';
        RETURN 0;
    END IF;

    IF public.llm_budget_headroom() <= 0 THEN
        PERFORM public.llm_budget_note_trip('rpe_extract');
        RAISE NOTICE 'dispatch_rpe_extraction skipped -- LLM daily ceiling reached';
        RETURN 0;
    END IF;

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
        IF NOT public.llm_budget_allows('rpe_extract', _job.training_log_id, _job.user_id) THEN
            UPDATE public.rpe_extraction_jobs
               SET last_error = 'blocked by LLM budget guard at ' || now()::text
             WHERE training_log_id = _job.training_log_id;
            CONTINUE;
        END IF;

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
$$;

COMMENT ON FUNCTION public.dispatch_workout_parse(integer) IS
  'Drains workout_parse_jobs behind public.llm_budget_allows(). Pre-checks the '
  'global ceiling before claiming so a spent budget never burns retries.';
COMMENT ON FUNCTION public.dispatch_rpe_extraction(integer) IS
  'Drains rpe_extraction_jobs behind public.llm_budget_allows(). Same shape as '
  'dispatch_workout_parse.';
