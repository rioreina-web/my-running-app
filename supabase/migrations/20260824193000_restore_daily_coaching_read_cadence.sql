-- ============================================================================
-- Coaching Read — restore the daily cadence alongside the weekly one
--
-- Supersedes the dispatch half of `20260806160000_weekly_coaching_read_cadence.sql`.
--
-- ── Why now ────────────────────────────────────────────────────────────
-- The 2026-08-06 migration dropped daily → weekly for two stated reasons.
-- BOTH have since been fixed, independently, and neither fix revisited the
-- cadence decision:
--
--   1. "COST. The Read runs gemini-3.1-pro-preview with up to 3 attempts."
--      Fixed 2026-08-13 in coaching-daily-read/index.ts:241 — the model was
--      downgraded to gemini-2.5-flash. The in-file comment justifying a
--      frontier model by "runs on a WEEKLY cadence" no longer describes the
--      code it sits next to.
--
--   2. "IT NEVER WORKED. 104 dispatches ... produced ZERO rows with
--      triggered_by = 'cron'. The function returns 429 from
--      enforceFeatureRateLimit(userId, 'daily_read')."
--      Fixed by the isServiceRole short-circuit in _shared/rateLimit.ts
--      (documented at rateLimit.ts:335: "service-role callers (cron,
--      triggers, other edge functions) bypass user-keyed limits"), which
--      coaching-daily-read now passes at index.ts:169. Cron dispatches
--      reach Gemini.
--
-- The product reason for a daily read is the habit loop: it is the only
-- athlete touch that fires on days they do not run. A post-run insight
-- reaches an athlete 4-5x/week; a morning read reaches them 7x/week,
-- because rest days still have a body to report on.
--
-- ── What changes ───────────────────────────────────────────────────────
--   * enqueue_daily_reads() gains the ACTIVITY GATE that the weekly
--     version already has (a training_log in the trailing 7 days). This is
--     the cost lever the 2026-06-15 original lacked and the 2026-08-06
--     rewrite correctly identified: without it, every account that ever
--     signed up is a recurring line item forever. Dormant accounts now
--     cost nothing on either cadence.
--   * enqueue_daily_reads() skips Sunday. See the collision note below.
--   * `enqueue-daily-coaching-reads` is scheduled again (hourly tick).
--
-- ── What does NOT change ───────────────────────────────────────────────
--   * enqueue_weekly_reads() and its cron are untouched. Sunday 18:00
--     local still produces the weekly Read.
--   * daily_coaching_reads schema. No iOS change required.
--   * The manual / on-demand path and the workout_trigger re-render path.
--
-- ── The Sunday collision ───────────────────────────────────────────────
-- daily_coaching_reads is UNIQUE (user_id, read_date). A Sunday-morning
-- daily read and a Sunday-evening weekly read are the same (user, date),
-- so one would silently no-op against the other and which one won would
-- depend on dispatch order. Rather than leave that nondeterministic, the
-- daily job skips Sunday outright (DOW 0) and Sunday belongs to the
-- weekly Read.
--
-- This is a stopgap, not the intended end state. The daily brief and the
-- weekly Read want to be different products — the brief is ~60-100 words
-- of text leading with what CHANGED overnight (glanceable, every day);
-- the weekly Read is long-form retrospective and the natural home for
-- voice. Splitting them onto separate surfaces (or a `cadence` column) is
-- the follow-up that lets both exist on a Sunday. Until then, six daily
-- reads plus one weekly beats one weekly.
--
-- Follows the house pattern from 20260615220000 / 20260806160000:
-- vault-secret lookup, idempotent unschedule-then-schedule, graceful skip
-- when pg_cron is unavailable locally. Append-only; nothing is dropped.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. enqueue_daily_reads() — activity-gated, Sunday-skipping
--
-- Still invoked hourly. The hourly tick is how we catch "it is now 06:00
-- local" across every timezone — each athlete matches exactly one of the
-- 24 daily ticks.
--
-- Three gates, all required:
--   a. local hour = 6
--   b. local day-of-week <> 0 (Sunday belongs to the weekly Read)
--   c. at least one training_log in the trailing 7 days
--
-- Gate (c) is the cost lever. Do not remove it without pricing the change.
-- ----------------------------------------------------------------------------
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
        VALUES (0, 0, 'daily: skipped — vault secrets missing');
        RAISE NOTICE 'enqueue_daily_reads skipped — vault secrets missing';
        RETURN;
    END IF;

    -- Athletes with any training_log in the trailing 7 days. Timezone is
    -- LEFT JOINed from athlete_settings and defaults to UTC for athletes
    -- who have not set one (same convention as enqueue_weekly_reads).
    --
    -- NOTE: as in the weekly version, the 7-day window is evaluated in UTC
    -- rather than per-athlete local time. A few hours of boundary slop at
    -- the edge of a 7-day window cannot change the answer for anyone who
    -- actually trained this week, and it keeps eligibility to a single
    -- indexed scan.
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

            IF EXTRACT(HOUR FROM _local) = 6      -- 06:00–06:59 local
               AND EXTRACT(DOW FROM _local) <> 0  -- not Sunday (weekly Read owns it)
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

    -- Only log ticks that did something, plus any error notes. The
    -- 2026-06-15 version logged all 24 daily ticks, which buried the one
    -- row that mattered under 23 rows of zeros.
    IF _candidate_count > 0 OR _notes IS NOT NULL THEN
        INSERT INTO daily_read_dispatch_log (candidate_count, dispatched_count, notes)
        VALUES (_candidate_count, _dispatched_count, COALESCE('daily: ' || _notes, 'daily'));
    END IF;
END;
$function$;

COMMENT ON FUNCTION public.enqueue_daily_reads() IS
    'Hourly tick that dispatches coaching-daily-read at 06:00 local Mon-Sat, '
    'for athletes with a training_log in the trailing 7 days. Restored '
    '2026-08-24 after both blockers cited in 20260806160000 were fixed '
    '(model downgraded to flash 2026-08-13; isServiceRole rate-limit bypass). '
    'Sunday is skipped so it cannot collide with enqueue_weekly_reads() on the '
    'daily_coaching_reads (user_id, read_date) unique constraint. Eligibility '
    'gate is the per-athlete cost lever — do not remove it without pricing it.';

-- ----------------------------------------------------------------------------
-- 2. Schedule the daily job again
--
-- The weekly job is deliberately left alone. Both are hourly pg_cron
-- entries; the cadence lives in the function body, not the cron
-- expression, because "06:00 LOCAL" is per-athlete.
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
