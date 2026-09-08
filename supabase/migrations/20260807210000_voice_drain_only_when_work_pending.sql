-- Voice-drain load guard — follow-up to the 2026-08-07 20:23 UTC stall.
--
-- WHAT HAPPENED
-- `drain-voice-processing-jobs` runs every 15 seconds (20260804120000). Each
-- tick unconditionally launched a pg_cron background worker and fired a
-- net.http_post, which booted an edge function that called
-- claim_voice_processing_jobs — whether or not a single job was queued. With
-- an empty queue that is ~5,760 wasted invocations a day.
--
-- On 2026-08-07 one tick ran long. The next fired anyway, then the next.
-- Background-worker slots filled, and Postgres began logging
-- `job startup timeout` for EVERY cron job (2, 3, 6, 19, 21) plus
-- `could not accept SSL connection: EOF detected`. Trivial catalog queries
-- took 12–68 s. GoTrue could not reach the database, so /auth/v1/user
-- returned 504 `context deadline exceeded`, and the iOS client's session
-- refresh 504'd with it — which wedged every request in the app behind a
-- refresh that never completed.
--
-- THE FIX — two guards on the cron command itself, so a tick costs one index
-- probe when there is nothing to do:
--
--   1. EXISTS gate. `SELECT net.http_post(...) WHERE <cond>` does not
--      evaluate the target list when the qualification is false, so no HTTP
--      request is queued and no edge function boots on an idle tick.
--
--   2. pg_try_advisory_xact_lock. If a previous tick's transaction is still
--      running (the database is slow, as it was during the incident), this
--      tick takes no lock and exits immediately instead of stacking on top
--      of it. This is the piece that stops the pile-up from compounding.
--
-- The 15-second cadence is DELIBERATELY KEPT. 15s was never the bug — the
-- bug was that every tick did real work regardless of whether there was any.
-- The voice-memo latency win from 20260804120000 is preserved.
--
-- The EXISTS predicate must match what claim_voice_processing_jobs actually
-- picks up, and that RPC does TWO things: it claims queued rows, and it
-- recovers rows stranded in 'in_progress' past the 10-minute threshold. A
-- gate on queued rows alone would mean stale rows never got recovered,
-- because the recovery only runs when the RPC runs. Both arms are covered
-- below, and the second gets a partial index (the first already has
-- idx_voice_processing_jobs_drain).
--
-- ON THE PLAN: measured against prod at 40 rows / 3 pages, this gate is a
-- Seq Scan taking 0.1 ms, NOT an index scan — the planner correctly declines
-- a BitmapOr across two partial indexes on a table that small. That is fine,
-- and it self-corrects: nothing prunes completed rows from this table, but
-- BOTH partial indexes exclude them (`WHERE status = 'queued'` and
-- `WHERE status = 'in_progress'`), so the indexes stay tiny no matter how far
-- the table grows, and the planner switches to them exactly when the seq scan
-- stops being the cheap option. No retention job is needed for this gate to
-- stay cheap — deliberately so, since an extra cron job is the shape of
-- problem this migration exists to fix.

CREATE INDEX IF NOT EXISTS idx_voice_processing_jobs_stale
    ON public.voice_processing_jobs (last_attempted_at)
    WHERE status = 'in_progress';

COMMENT ON INDEX public.idx_voice_processing_jobs_stale IS
    'Supports the stale-in_progress arm of the drain cron''s work-pending gate. '
    'Partial on in_progress, so it stays small as completed rows accumulate.';

DO $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
    _command      TEXT;
    _schedule     TEXT;
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — drain guard skipped';
        RETURN;
    END;

    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE NOTICE 'vault secrets missing — drain guard skipped';
        RETURN;
    END IF;

    -- Preserve whatever cadence is actually live rather than assuming 15s:
    -- 20260804120000 falls back to '* * * * *' on a pg_cron too old for the
    -- seconds-interval syntax, and this migration must not silently promote
    -- such an instance.
    SELECT schedule INTO _schedule
      FROM cron.job
     WHERE jobname = 'drain-voice-processing-jobs'
     LIMIT 1;

    _schedule := COALESCE(_schedule, '15 seconds');

    _command := format(
        $job$
        SELECT net.http_post(
            url := %L,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || %L,
                'apikey', %L
            ),
            body := jsonb_build_object('batch', 10)
        )
         WHERE pg_try_advisory_xact_lock(hashtext('drain-voice-processing-jobs')::bigint)
           AND EXISTS (
                   SELECT 1
                     FROM public.voice_processing_jobs j
                    WHERE (j.status = 'queued' AND j.next_retry_at <= now())
                       OR (j.status = 'in_progress'
                           AND j.last_attempted_at < now() - INTERVAL '10 minutes')
               );
        $job$,
        _supabase_url || '/functions/v1/drain-voice-processing-jobs',
        _service_key,
        _service_key
    );

    -- cron.schedule() upserts by job name.
    PERFORM cron.schedule('drain-voice-processing-jobs', _schedule, _command);

    RAISE NOTICE 'drain-voice-processing-jobs guarded, schedule preserved as %', _schedule;
END;
$$;

-- Verification (SQL editor, after `supabase db push`):
--
--   -- 1. Command carries both guards, schedule unchanged:
--   SELECT jobname, schedule, command FROM cron.job
--    WHERE jobname = 'drain-voice-processing-jobs';
--
--   -- 2. Idle ticks now no-op — expect `return_message = '0 rows'` on runs
--   --    where the queue was empty, rather than '1 row':
--   SELECT status, return_message, start_time, end_time
--     FROM cron.job_run_details
--    WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'drain-voice-processing-jobs')
--    ORDER BY start_time DESC LIMIT 20;
--
--   -- 3. The gate stays sub-millisecond. Expect a Seq Scan while the table is
--   --    small (see ON THE PLAN above) — check Execution Time, not the node
--   --    type. Investigate only if this climbs into single-digit ms while the
--   --    partial indexes are still being ignored:
--   EXPLAIN (ANALYZE, BUFFERS) SELECT 1 WHERE EXISTS (
--       SELECT 1 FROM public.voice_processing_jobs j
--        WHERE (j.status = 'queued' AND j.next_retry_at <= now())
--           OR (j.status = 'in_progress'
--               AND j.last_attempted_at < now() - INTERVAL '10 minutes'));
