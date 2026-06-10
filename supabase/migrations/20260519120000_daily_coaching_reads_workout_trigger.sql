-- ============================================================================
-- Daily Coaching Reads — workout-trigger re-render
--
-- Phase 1, Prompt 1.5 of coach-the-read-prompts.md.
--
-- When an athlete logs a quality workout (long, tempo, threshold,
-- interval, progression, race) for today, re-render today's Coach Read
-- so it can reflect the new session. Without this, the morning Read
-- stays frozen — a 14mi long run logged at 11am is invisible until the
-- next morning's cron.
--
-- WHY DIRECT pg_net IS SAFE HERE (READ BEFORE EDITING):
-- The codebase has elsewhere replaced direct `pg_net` triggers on
-- `training_logs` with outbox + cron-drainer patterns (see
-- 20260508150000_outbox_trigger_workout_insight.sql and
-- 20260518100000_coachable_moment_outbox_trigger.sql). The motivating
-- problem was HealthKit-sync bursts: N inserts in seconds → N edge-fn
-- invocations in seconds → overwhelmed Gemini rate limits.
--
-- This trigger is structurally immune to that bug because of the
-- daily_read_workout_dispatches uniqueness constraint below. The
-- constraint caps invocations at one per (athlete, day) — a 30-workout
-- HealthKit sync produces at most ONE Daily Read call, not 30. The
-- thundering-herd condition can't exist.
--
-- If you find yourself reading this and thinking "this should be on
-- the outbox like the others" — the answer is no, because the
-- once-per-day cap is the same backpressure mechanism the outbox
-- provides, but cheaper and stronger (it's a database constraint, not
-- a worker rate-limit).
--
-- Three pieces:
--   1. daily_read_workout_dispatches — once-per-day-per-athlete ledger.
--   2. fn_enqueue_daily_read_workout_rerender() — the trigger function.
--   3. AFTER INSERT and AFTER UPDATE triggers on training_logs.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ----------------------------------------------------------------------------
-- 1. Dispatch ledger
--
-- One row per (athlete, athlete-local date) we've fired a workout-
-- triggered re-render for. The UNIQUE constraint is what enforces the
-- "at most one trigger per athlete per day" guarantee from the spec.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_read_workout_dispatches (
    id BIGSERIAL PRIMARY KEY,
    user_id TEXT NOT NULL,
    dispatch_date DATE NOT NULL,
    triggering_log_id UUID,
    dispatched_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT daily_read_workout_dispatches_user_date_uniq
        UNIQUE (user_id, dispatch_date)
);

COMMENT ON TABLE daily_read_workout_dispatches IS
    'One row per (athlete, local date) for which the training_logs '
    'trigger has fired a Daily Read re-render. The UNIQUE constraint '
    'is the once-per-day cap.';

CREATE INDEX IF NOT EXISTS idx_daily_read_workout_dispatches_dispatched_at
    ON daily_read_workout_dispatches(dispatched_at DESC);

-- RLS — service-role only. Same pattern as daily_read_dispatch_log.
ALTER TABLE daily_read_workout_dispatches ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_daily_read_workout_dispatches_service_role"
    ON daily_read_workout_dispatches
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- ----------------------------------------------------------------------------
-- 2. Trigger function
--
-- Quality workout types treated as "changes the picture":
--   long, long_run, tempo, threshold, interval, intervals, progression, race
--
-- Gate sequence, in order of cheapness:
--   (a) user_id non-null
--   (b) workout_type matches a quality session
--   (c) workout's date == athlete-local today
--   (d) pg_try_advisory_xact_lock — concurrent-fire debounce
--   (e) INSERT … ON CONFLICT DO NOTHING — daily uniqueness check
--   (f) vault secrets present — bail in local dev
--   (g) PERFORM net.http_post
--
-- The function never RAISEs. Any failure inside the body is captured
-- via the EXCEPTION block so the underlying training_logs insert/
-- update is never affected.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_enqueue_daily_read_workout_rerender()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, extensions, pg_temp
AS $$
DECLARE
    _quality_types TEXT[] := ARRAY[
        'long', 'long_run',
        'tempo', 'threshold',
        'interval', 'intervals',
        'progression', 'race'
    ];
    _athlete_tz TEXT;
    _athlete_today DATE;
    _supabase_url TEXT;
    _service_key TEXT;
    _lock_key BIGINT;
BEGIN
    -- (a) user_id required.
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- (b) Quality workout types only. A 4mi easy run shouldn't
    --     re-render the morning's Read.
    IF NEW.workout_type IS NULL
       OR NOT (lower(NEW.workout_type) = ANY(_quality_types)) THEN
        RETURN NEW;
    END IF;

    -- Resolve athlete-local "today". Defaults to UTC if the column
    -- (added in 20260519110000) is missing or the timezone string is
    -- bad. Wrap in a nested block so a bad IANA string falls back
    -- cleanly instead of failing the trigger.
    BEGIN
        SELECT COALESCE(timezone, 'UTC') INTO _athlete_tz
          FROM user_profiles
         WHERE user_id = NEW.user_id
         LIMIT 1;
        _athlete_tz := COALESCE(_athlete_tz, 'UTC');
        _athlete_today := (now() AT TIME ZONE _athlete_tz)::DATE;
    EXCEPTION WHEN OTHERS THEN
        _athlete_today := (now() AT TIME ZONE 'UTC')::DATE;
    END;

    -- (c) Only re-render for workouts the athlete did TODAY (their
    --     local time). Backfills, future-scheduled entries, and
    --     stale edits to old workouts shouldn't disturb today's Read.
    IF NEW.workout_date IS NOT NULL AND NEW.workout_date <> _athlete_today THEN
        RETURN NEW;
    END IF;

    -- (d) Concurrent-fire debounce. Transaction-scoped so it
    --     auto-releases when the underlying INSERT commits. Two
    --     parallel HealthKit-sync transactions hitting the same
    --     athlete on the same day → only one proceeds past here.
    --     This is belt-and-braces; the UNIQUE constraint below is
    --     the real once-per-day cap.
    _lock_key := hashtextextended(NEW.user_id || ':' || _athlete_today::TEXT, 0);
    IF NOT pg_try_advisory_xact_lock(_lock_key) THEN
        RETURN NEW;
    END IF;

    -- (e) Once-per-day uniqueness. The constraint is the real cap;
    --     if a row already exists for (user_id, today), this is a
    --     no-op and the function returns without firing http_post.
    INSERT INTO daily_read_workout_dispatches (
        user_id, dispatch_date, triggering_log_id
    )
    VALUES (NEW.user_id, _athlete_today, NEW.id)
    ON CONFLICT (user_id, dispatch_date) DO NOTHING;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- (f) Vault secrets — bail in local-dev environments where the
    --     service-role key isn't seeded.
    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        -- Mark the dispatch row so operators can see "skipped: vault
        -- missing" without grepping logs.
        UPDATE daily_read_workout_dispatches
           SET triggering_log_id = NULL
         WHERE user_id = NEW.user_id
           AND dispatch_date = _athlete_today;
        RETURN NEW;
    END IF;

    -- (g) Fire-and-forget post. The edge function (Phase 1.3) has
    --     dedicated handling for triggered_by = 'workout_trigger':
    --     it bypasses the completed-row short-circuit and regenerates.
    PERFORM net.http_post(
        url := _supabase_url || '/functions/v1/coaching-daily-read',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || _service_key,
            'apikey', _service_key
        ),
        body := jsonb_build_object(
            'user_id', NEW.user_id,
            'triggered_by', 'workout_trigger'
        )
    );

    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    -- Last-resort guard: never propagate trigger errors back into the
    -- INSERT/UPDATE that triggered us.
    RAISE WARNING
        'daily-read workout trigger failed for user % (sqlstate %): %',
        NEW.user_id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_enqueue_daily_read_workout_rerender() FROM PUBLIC;

COMMENT ON FUNCTION fn_enqueue_daily_read_workout_rerender() IS
    'training_logs trigger function — fires coaching-daily-read with '
    'triggered_by=workout_trigger after a quality session, at most once '
    'per athlete per local day. See migration header for the direct-'
    'pg_net design rationale.';

-- ----------------------------------------------------------------------------
-- 3. Triggers
--
-- INSERT path: a new quality workout was logged. Most common case.
--
-- UPDATE path: only on the "voice processing just finished" signal
-- (cleaned_notes goes NULL → non-NULL). This catches the case where
-- a voice memo logged this morning got transcribed by midday and now
-- the model has the athlete's own words to ground the Read in. Same
-- discrimination pattern as the coachable_moment_jobs UPDATE trigger
-- (20260518100000) — we only want the meaningful transition, not
-- every metadata edit.
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS auto_enqueue_daily_read_on_quality_insert ON training_logs;
CREATE TRIGGER auto_enqueue_daily_read_on_quality_insert
    AFTER INSERT ON training_logs
    FOR EACH ROW
    EXECUTE FUNCTION fn_enqueue_daily_read_workout_rerender();

DROP TRIGGER IF EXISTS auto_enqueue_daily_read_on_voice_complete ON training_logs;
CREATE TRIGGER auto_enqueue_daily_read_on_voice_complete
    AFTER UPDATE ON training_logs
    FOR EACH ROW
    WHEN (
        OLD.cleaned_notes IS NULL
        AND NEW.cleaned_notes IS NOT NULL
        AND length(trim(NEW.cleaned_notes)) > 0
    )
    EXECUTE FUNCTION fn_enqueue_daily_read_workout_rerender();

COMMIT;

-- ============================================================================
-- Verification (run after applying):
--
-- 1. Confirm the ledger exists:
--      SELECT count(*) FROM daily_read_workout_dispatches;
--
-- 2. Confirm both triggers attached:
--      SELECT trigger_name, event_manipulation
--        FROM information_schema.triggers
--       WHERE event_object_table = 'training_logs'
--         AND trigger_name LIKE 'auto_enqueue_daily_read%';
--    Expected: 2 rows.
--
-- 3. Smoke test:
--    (a) INSERT a tempo workout for today against any user.
--    (b) SELECT * FROM daily_read_workout_dispatches WHERE user_id = '<id>';
--        Expected: one row, dispatched_at ≈ now().
--    (c) INSERT a SECOND tempo workout for the same user today.
--        Expected: no new row, no second http_post — once-per-day cap held.
-- ============================================================================
