-- Remove the per-iteration subtransaction from the coaching-read dispatchers.
--
-- ROOT CAUSE: both enqueue_daily_reads() and enqueue_weekly_reads() wrap the
-- ENTIRE loop body in a BEGIN ... EXCEPTION block:
--
--     FOR _candidate IN (every athlete with a log in 7 days) LOOP
--         BEGIN  ... EXCEPTION WHEN OTHERS THEN ... END;
--     END LOOP;
--
-- In PL/pgSQL, entering a block with an EXCEPTION handler opens a
-- subtransaction. So the subxid count equals the number of ELIGIBLE athletes,
-- not the ~4% whose local clock is actually in the dispatch hour.
--
-- Postgres caches 64 subtransaction IDs per backend (PGPROC_MAX_CACHED_SUBXIDS).
-- Past 64 the backend is flagged "subxid overflowed" and EVERY other backend in
-- the database falls back to pg_subtrans lookups for visibility checks. That
-- makes an hourly background job degrade unrelated user-facing queries at
-- roughly 64 active athletes — the same shape as the 2026-08-07 cron
-- saturation outage.
--
-- FIX, three parts:
--   1. Push the timezone predicate into SQL so the loop body runs only for
--      athletes actually being dispatched (~40 of 1000 rather than all 1000).
--      NOTE: this does not shrink the candidate SCAN — that is unchanged. The
--      win is subtransactions and wasted iterations, not I/O.
--   2. Replace the per-iteration exception block with ONE block around the
--      whole loop. Still cannot crash the cron tick; costs 1 subxid per call
--      instead of N. Trade-off: an error now ends that tick's dispatching
--      rather than skipping one athlete. Acceptable because (3) removes the
--      only per-athlete failure mode.
--   3. Bad IANA strings were the reason for the per-athlete handler. Resolve
--      them with a JOIN instead of an exception. pg_timezone_names is a
--      function-backed view measured at 791ms mean, so materialize it once.

CREATE TABLE IF NOT EXISTS public.valid_timezones (name text PRIMARY KEY);

INSERT INTO public.valid_timezones (name)
SELECT name FROM pg_timezone_names
ON CONFLICT (name) DO NOTHING;

REVOKE ALL ON public.valid_timezones FROM anon, authenticated;

-- No policies: nothing reachable over PostgREST. The SECURITY DEFINER
-- dispatchers run as the table owner and bypass RLS, so the join still works.
ALTER TABLE public.valid_timezones ENABLE ROW LEVEL SECURITY;

-- The eligibility EXISTS() probes (user_id, workout_date). Today it can only
-- use idx_training_logs_user_id (user_id alone) and then filter. At 1000
-- athletes / ~150k logs this composite turns it into a single index probe.
CREATE INDEX IF NOT EXISTS idx_training_logs_user_workout_date
  ON public.training_logs USING btree (user_id, workout_date DESC);


CREATE OR REPLACE FUNCTION public.enqueue_daily_reads()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
    _supabase_url     TEXT;
    _service_key      TEXT;
    _candidate        RECORD;
    _candidate_count  INTEGER := 0;
    _dispatched_count INTEGER := 0;
    _notes            TEXT := NULL;
BEGIN
    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        INSERT INTO daily_read_dispatch_log (candidate_count, dispatched_count, notes)
        VALUES (0, 0, 'daily: skipped — vault secrets missing');
        RAISE NOTICE 'enqueue_daily_reads skipped — vault secrets missing';
        RETURN;
    END IF;

    -- One subtransaction for the whole tick, not one per athlete.
    BEGIN
        FOR _candidate IN
            SELECT st.user_id AS user_id
              FROM athlete_state st
              LEFT JOIN athlete_settings s  ON s.user_id = st.user_id
              LEFT JOIN public.valid_timezones vt ON vt.name = s.timezone
             WHERE st.user_id IS NOT NULL
               AND EXISTS (
                     SELECT 1
                       FROM training_logs tl
                      WHERE tl.user_id = st.user_id
                        AND tl.workout_date > now() - INTERVAL '7 days'
                   )
               -- 06:00–06:59 local, not Sunday (the weekly Read owns Sunday).
               -- Unknown / unset / invalid timezone falls back to UTC, matching
               -- the previous COALESCE(s.timezone,'UTC') behaviour.
               AND EXTRACT(HOUR FROM now() AT TIME ZONE COALESCE(vt.name, 'UTC')) = 6
               AND EXTRACT(DOW  FROM now() AT TIME ZONE COALESCE(vt.name, 'UTC')) <> 0
        LOOP
            _candidate_count := _candidate_count + 1;

            PERFORM net.http_post(
                url := _supabase_url || '/functions/v1/coaching-daily-read',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || _service_key,
                    'apikey', _service_key
                ),
                body := jsonb_build_object(
                    'user_id', _candidate.user_id,
                    'triggered_by', 'cron'
                )
            );

            _dispatched_count := _dispatched_count + 1;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        _notes := 'aborted after ' || _dispatched_count || ' dispatches: ' || SQLERRM;
    END;

    IF _candidate_count > 0 OR _notes IS NOT NULL THEN
        INSERT INTO daily_read_dispatch_log (candidate_count, dispatched_count, notes)
        VALUES (_candidate_count, _dispatched_count, COALESCE('daily: ' || _notes, 'daily'));
    END IF;
END;
$function$;


CREATE OR REPLACE FUNCTION public.enqueue_weekly_reads()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
    _supabase_url     TEXT;
    _service_key      TEXT;
    _candidate        RECORD;
    _candidate_count  INTEGER := 0;
    _dispatched_count INTEGER := 0;
    _notes            TEXT := NULL;
BEGIN
    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        INSERT INTO daily_read_dispatch_log (candidate_count, dispatched_count, notes)
        VALUES (0, 0, 'weekly: skipped — vault secrets missing');
        RAISE NOTICE 'enqueue_weekly_reads skipped — vault secrets missing';
        RETURN;
    END IF;

    BEGIN
        FOR _candidate IN
            SELECT st.user_id AS user_id
              FROM athlete_state st
              LEFT JOIN athlete_settings s  ON s.user_id = st.user_id
              LEFT JOIN public.valid_timezones vt ON vt.name = s.timezone
             WHERE st.user_id IS NOT NULL
               AND EXISTS (
                     SELECT 1
                       FROM training_logs tl
                      WHERE tl.user_id = st.user_id
                        AND tl.workout_date > now() - INTERVAL '7 days'
                   )
               -- Sunday 18:00–18:59 local.
               AND EXTRACT(DOW  FROM now() AT TIME ZONE COALESCE(vt.name, 'UTC')) = 0
               AND EXTRACT(HOUR FROM now() AT TIME ZONE COALESCE(vt.name, 'UTC')) = 18
        LOOP
            _candidate_count := _candidate_count + 1;

            PERFORM net.http_post(
                url := _supabase_url || '/functions/v1/coaching-daily-read',
                headers := jsonb_build_object(
                    'Content-Type', 'application/json',
                    'Authorization', 'Bearer ' || _service_key,
                    'apikey', _service_key
                ),
                body := jsonb_build_object(
                    'user_id', _candidate.user_id,
                    'triggered_by', 'cron'
                )
            );

            _dispatched_count := _dispatched_count + 1;
        END LOOP;
    EXCEPTION WHEN OTHERS THEN
        _notes := 'aborted after ' || _dispatched_count || ' dispatches: ' || SQLERRM;
    END;

    IF _candidate_count > 0 OR _notes IS NOT NULL THEN
        INSERT INTO daily_read_dispatch_log (candidate_count, dispatched_count, notes)
        VALUES (_candidate_count, _dispatched_count, COALESCE('weekly: ' || _notes, 'weekly'));
    END IF;
END;
$function$;

-- Preserve the existing lockdown posture on both functions.
REVOKE EXECUTE ON FUNCTION public.enqueue_daily_reads()  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_weekly_reads() FROM anon, authenticated;
