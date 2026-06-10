-- ============================================================================
-- Daily Coaching Reads — cron dispatch
--
-- Phase 1, Prompt 1.4 of coach-the-read-prompts.md.
--
-- An hourly pg_cron job fires `coaching-daily-read` for every athlete
-- whose local time is in the 06:00-06:59 window. Each athlete therefore
-- gets exactly one dispatch per day (one of the 24 hourly ticks hits
-- their morning hour). The edge function is idempotent via the
-- daily_coaching_reads unique (user_id, read_date) constraint, so any
-- double-fires from DST transitions or manual triggers collapse cleanly.
--
-- Three pieces:
--   1. ALTER TABLE user_profiles ADD COLUMN timezone (additive — the
--      column doesn't exist yet; the cron filter and the edge function
--      both need it).
--   2. daily_read_dispatch_log — append-only log of every cron tick:
--      when it fired, how many candidates matched, how many we actually
--      dispatched. Service-role only.
--   3. enqueue_daily_reads() — SECURITY DEFINER function that does the
--      candidate scan + per-user net.http_post + log insert. Cron calls
--      this once per hour.
--
-- Modeled after `20260423100000_daily_weather_forecast_cron.sql` and
-- `20260508170000_drain_coach_insight_jobs_cron.sql` — same vault-secret
-- lookup pattern, same idempotent unschedule-then-schedule shape, same
-- graceful skip when pg_cron isn't available locally.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

DO $$
BEGIN
    CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — daily-coaching-reads cron skipped';
END;
$$;

-- ----------------------------------------------------------------------------
-- 1. Add `timezone` to user_profiles
--
-- IANA timezone name (e.g. "America/Los_Angeles"). Default 'UTC' so
-- existing rows fire at 06:00 UTC until the iOS client backfills the
-- real timezone from the device. The edge function's date-resolution
-- helper (resolveAthleteLocalDate) also defaults to UTC, so the column
-- and the helper agree.
-- ----------------------------------------------------------------------------
ALTER TABLE user_profiles
    ADD COLUMN IF NOT EXISTS timezone TEXT NOT NULL DEFAULT 'UTC';

COMMENT ON COLUMN user_profiles.timezone IS
    'IANA timezone name (e.g. "America/Los_Angeles"). Used by the daily '
    'Coach Read cron to fire at the athlete''s local 6 AM. Default ''UTC''.';

-- ----------------------------------------------------------------------------
-- 2. Dispatch log
--
-- Append-only audit of every hourly cron tick. Lets us spot-check
-- "did the cron run at 06:00 PT yesterday?" without grepping cron logs,
-- and lets us alert on candidate_count = 0 if dispatching breaks.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_read_dispatch_log (
    id BIGSERIAL PRIMARY KEY,
    fired_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    candidate_count INTEGER NOT NULL,
    dispatched_count INTEGER NOT NULL,
    notes TEXT
);

CREATE INDEX IF NOT EXISTS idx_daily_read_dispatch_log_fired_at
    ON daily_read_dispatch_log(fired_at DESC);

COMMENT ON TABLE daily_read_dispatch_log IS
    'Append-only audit of every hourly Daily Read cron tick. '
    'candidate_count: athletes whose local hour was 6. '
    'dispatched_count: athletes for whom net.http_post fired successfully.';

-- RLS — service-role only. No user-facing read path.
ALTER TABLE daily_read_dispatch_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_daily_read_dispatch_log_service_role"
    ON daily_read_dispatch_log
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- ----------------------------------------------------------------------------
-- 3. enqueue_daily_reads()
--
-- SECURITY DEFINER so the cron context (which runs as the cron user)
-- can read vault.decrypted_secrets without being granted blanket vault
-- access. Pinned search_path keeps the function safe under search-path
-- manipulation.
--
-- Iteration is per-row with a BEGIN/EXCEPTION wrapper so a single bad
-- timezone string can't kill the whole batch — that user is skipped,
-- the rest still fire.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION enqueue_daily_reads()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, pg_temp
AS $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
    _candidate    RECORD;
    _candidate_count INTEGER := 0;
    _dispatched_count INTEGER := 0;
    _notes TEXT := NULL;
BEGIN
    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        -- Log the skip so we can see it in the audit table without
        -- hunting through Postgres logs.
        INSERT INTO daily_read_dispatch_log (candidate_count, dispatched_count, notes)
        VALUES (0, 0, 'skipped: vault secrets missing');
        RAISE NOTICE 'enqueue_daily_reads skipped — vault secrets missing';
        RETURN;
    END IF;

    -- One row per athlete whose local hour right now is 6.
    -- COALESCE protects against NULL timezone (the column has a NOT NULL
    -- default so this is belt-and-braces).
    FOR _candidate IN
        SELECT user_id, COALESCE(timezone, 'UTC') AS tz
          FROM user_profiles
         WHERE user_id IS NOT NULL
    LOOP
        BEGIN
            -- Per-user timezone evaluation in its own block so a bad
            -- IANA string can't break the loop.
            IF EXTRACT(HOUR FROM (now() AT TIME ZONE _candidate.tz)) = 6 THEN
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
            END IF;
        EXCEPTION WHEN OTHERS THEN
            -- Bad timezone or http_post failure — note it and move on.
            _notes := COALESCE(_notes || '; ', '')
                   || 'user ' || _candidate.user_id || ': ' || SQLERRM;
        END;
    END LOOP;

    INSERT INTO daily_read_dispatch_log (candidate_count, dispatched_count, notes)
    VALUES (_candidate_count, _dispatched_count, _notes);
END;
$$;

REVOKE ALL ON FUNCTION enqueue_daily_reads() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION enqueue_daily_reads() TO service_role;

COMMENT ON FUNCTION enqueue_daily_reads() IS
    'Hourly cron entry point for daily Coach Reads. Selects user_profiles '
    'rows whose local hour is 6, fires net.http_post to coaching-daily-read '
    'for each, and writes a row to daily_read_dispatch_log. Idempotency: '
    'the edge function short-circuits if a completed read already exists '
    'for (user_id, today).';

-- ----------------------------------------------------------------------------
-- 4. Hourly cron schedule
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    -- Idempotent: unschedule first so re-running this migration is safe.
    BEGIN
        PERFORM cron.unschedule('enqueue-daily-coaching-reads');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- '0 * * * *' — top of every hour. Each user fires on whichever
    -- tick lands inside their 06:00 local hour.
    SELECT cron.schedule(
        'enqueue-daily-coaching-reads',
        '0 * * * *',
        $cron$ SELECT enqueue_daily_reads(); $cron$
    ) INTO _job_id;

    RAISE NOTICE 'enqueue-daily-coaching-reads cron scheduled (job id %)', _job_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — enqueue-daily-coaching-reads not scheduled';
END;
$$;

COMMIT;
