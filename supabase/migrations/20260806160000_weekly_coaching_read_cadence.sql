-- ============================================================================
-- Coaching Read — daily → weekly cadence
--
-- Supersedes the dispatch half of `20260615220000_daily_coaching_reads_cron.sql`.
--
-- ── Why ────────────────────────────────────────────────────────────────
-- The 2026-06-15 cron fired `coaching-daily-read` for EVERY row in
-- athlete_state whose local hour was 06, every day, with no activity
-- filter. Two problems:
--
--   1. COST. The Read runs gemini-3.1-pro-preview with up to 3 attempts.
--      A daily per-athlete dispatch makes that a fixed monthly cost per
--      signup, paid forever, including for accounts that never come back.
--      The frontier-model choice in coaching-daily-read/index.ts is
--      justified in-file by the comment "runs on a WEEKLY cadence, so
--      per-call cost is small" — a cadence that was never actually
--      implemented. This migration makes that comment true.
--
--   2. IT NEVER WORKED. 104 dispatches between 2026-06-16 and 2026-08-06
--      produced ZERO rows with triggered_by = 'cron' (all 47 reads on
--      file are 'manual'). The function returns 429 from
--      enforceFeatureRateLimit(userId, 'daily_read') before reaching
--      Gemini, so the daily dispatch has been a no-op the whole time.
--      Product decision 2026-08-06: rather than fix the daily cadence,
--      drop to weekly, which is what CLAUDE.md's "on demand, not
--      auto-daily" posture wanted anyway.
--
-- ── What changes ───────────────────────────────────────────────────────
--   * Cadence:     daily 06:00 local  →  Sunday 18:00 local
--   * Eligibility: every athlete_state row  →  only athletes with a
--                  training_log in the trailing 7 days. Dormant accounts
--                  cost nothing.
--
-- ── What does NOT change ───────────────────────────────────────────────
--   * daily_coaching_reads schema. The table stays keyed on
--     (user_id, read_date); a weekly read is simply one row on the
--     Sunday date. No schema rework, no iOS change required.
--   * The manual / on-demand path. Athletes can still generate a Read
--     whenever they want — that is the path that actually gets used.
--   * The workout_trigger re-render path (20260615230000).
--   * enqueue_daily_reads() is left defined but unscheduled, so this is
--     reversible by re-scheduling it. Migrations are append-only
--     (hard rule #5); nothing is dropped.
--
-- Follows the house pattern from 20260615220000: vault-secret lookup,
-- idempotent unschedule-then-schedule, graceful skip when pg_cron is
-- unavailable locally.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. enqueue_weekly_reads()
--
-- Still invoked hourly. The hourly tick is how we catch "it is now
-- 18:00 on Sunday" across every timezone — each athlete matches exactly
-- one of the 168 weekly ticks.
--
-- Two gates, both required:
--   a. local day-of-week = 0 (Sunday) AND local hour = 18
--   b. at least one training_log in the trailing 7 days
--
-- Gate (b) is the cost lever. Without it, every account that ever signed
-- up is a recurring line item.
-- ----------------------------------------------------------------------------
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
    _local            TIMESTAMP;
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

    -- Athletes with any training_log in the trailing 7 days. Timezone is
    -- LEFT JOINed from athlete_settings and defaults to UTC for athletes
    -- who have not set one (same convention as enqueue_daily_reads).
    --
    -- NOTE: the 7-day window is evaluated in UTC rather than per-athlete
    -- local time. At a weekly cadence a few hours of boundary slop cannot
    -- change the answer for anyone who actually trained this week, and it
    -- keeps the eligibility check to a single indexed scan.
    FOR _candidate IN
        SELECT st.user_id AS user_id,
               COALESCE(s.timezone, 'UTC') AS tz
          FROM athlete_state st
          LEFT JOIN athlete_settings s ON s.user_id = st.user_id
         WHERE st.user_id IS NOT NULL
           AND EXISTS (
                 SELECT 1
                   FROM training_logs tl
                  WHERE tl.user_id = st.user_id
                    AND tl.workout_date > now() - INTERVAL '7 days'
               )
    LOOP
        BEGIN
            -- Per-user timezone evaluation in its own block so one bad
            -- IANA string cannot break the loop.
            _local := now() AT TIME ZONE _candidate.tz;

            IF EXTRACT(DOW  FROM _local) = 0     -- Sunday
               AND EXTRACT(HOUR FROM _local) = 18 -- 18:00–18:59 local
            THEN
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
            _notes := COALESCE(_notes || '; ', '')
                   || 'user ' || _candidate.user_id || ': ' || SQLERRM;
        END;
    END LOOP;

    -- Only log ticks that did something, plus any error notes. The daily
    -- version logged all 168 weekly ticks; at a weekly cadence that is
    -- 167 rows of noise for every 1 row of signal.
    IF _candidate_count > 0 OR _notes IS NOT NULL THEN
        INSERT INTO daily_read_dispatch_log (candidate_count, dispatched_count, notes)
        VALUES (_candidate_count, _dispatched_count, COALESCE('weekly: ' || _notes, 'weekly'));
    END IF;
END;
$function$;

COMMENT ON FUNCTION public.enqueue_weekly_reads() IS
    'Hourly tick that dispatches coaching-daily-read at 18:00 local on Sundays, '
    'for athletes with a training_log in the trailing 7 days. Replaces '
    'enqueue_daily_reads() (2026-08-06). Eligibility gate is the per-athlete '
    'cost lever — do not remove it without pricing the change.';

-- ----------------------------------------------------------------------------
-- 2. Swap the schedule
--
-- Unschedule the daily job, schedule the weekly one. Both are hourly
-- pg_cron entries; the cadence lives in the function body, not the cron
-- expression, because "Sunday 18:00 LOCAL" is per-athlete.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    -- Retire the daily dispatch. enqueue_daily_reads() itself is left in
    -- place; re-scheduling it is the rollback.
    BEGIN
        PERFORM cron.unschedule('enqueue-daily-coaching-reads');
        RAISE NOTICE 'enqueue-daily-coaching-reads unscheduled';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'enqueue-daily-coaching-reads was not scheduled — nothing to unschedule';
    END;

    -- Idempotent: unschedule first so re-running this migration is safe.
    BEGIN
        PERFORM cron.unschedule('enqueue-weekly-coaching-reads');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    SELECT cron.schedule(
        'enqueue-weekly-coaching-reads',
        '0 * * * *',
        $cron$ SELECT enqueue_weekly_reads(); $cron$
    ) INTO _job_id;

    RAISE NOTICE 'enqueue-weekly-coaching-reads cron scheduled (job id %)', _job_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — enqueue-weekly-coaching-reads not scheduled';
END;
$$;

COMMIT;
