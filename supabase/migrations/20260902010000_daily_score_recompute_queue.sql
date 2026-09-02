-- ============================================================================
-- Daily scores — recompute-within-minutes queue
--
-- Step 1 of the stress/recovery-scores handoff (drip-scores project).
-- Without this, daily_scores only refreshes at the 03:45 UTC nightly cron,
-- so a morning run doesn't move today's stress number until tomorrow.
--
-- Shape: outbox + cron drain, per the repo convention for training_logs
-- side-effects (see 20260518100000_coachable_moment_outbox_trigger.sql).
-- Two deliberate differences from daily_read_workout_dispatches:
--
--   1. No pg_net, no vault keys. compute_daily_scores() is a Postgres
--      function, so the drain calls it directly. The vault-key-drift class
--      of failure (see RPE dispatcher 401s, cron-read 401s) cannot occur.
--   2. The debounce is PRIMARY KEY (user_id) on the queue, not a
--      once-per-day ledger — we WANT a recompute after every new run;
--      we just don't want 30 of them when a HealthKit/Strava burst lands.
--      A burst collapses to one queued row; the drain clears it within a
--      minute and recomputes the athlete once (~300ms measured live).
--
-- The enqueue trigger must stay dirt-cheap (single upsert) and can never
-- fail the underlying training_logs write (EXCEPTION guard). A failed
-- recompute is NOT re-enqueued — the nightly cron is the backstop, and
-- re-enqueueing would turn one poison-pill athlete into a stuck queue.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Queue. PRIMARY KEY (user_id) is the burst-collapse: any number of
--    writes between drains -> one pending recompute per athlete.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS daily_score_recompute_queue (
    user_id      TEXT PRIMARY KEY,
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    reason       TEXT
);

COMMENT ON TABLE daily_score_recompute_queue IS
    'Pending daily_scores recomputes, drained by the '
    'drain-daily-score-recompute cron every minute. PK(user_id) collapses '
    'sync bursts to one recompute per athlete.';

ALTER TABLE daily_score_recompute_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_daily_score_recompute_queue_service_role"
    ON daily_score_recompute_queue
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- ----------------------------------------------------------------------------
-- 2. Enqueue trigger function.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_enqueue_daily_score_recompute()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
BEGIN
    INSERT INTO daily_score_recompute_queue (user_id, reason)
    VALUES (NEW.user_id, lower(TG_OP) || ':' || TG_TABLE_NAME)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING
        'daily_score enqueue failed for user % (sqlstate %): %',
        NEW.user_id, SQLSTATE, SQLERRM;
    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION fn_enqueue_daily_score_recompute() FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 3. Triggers on training_logs.
--
-- INSERT: any new session with real duration (Strava sync, voice log,
-- manual entry). Zero-duration rows are invisible to the scorer, and the
-- UPDATE trigger catches them if duration is filled in later.
--
-- UPDATE: only transitions the scorer can see —
--   - extract-rpe stamping rpe_extracted_at / writing felt_rpe,
--   - Strava sync updating distance/duration/date/type,
--   - a row entering or leaving the scored set
--     (stats_excluded / superseded_at / duplicate_of),
--   - race_result appearing (flips is_race in the scorer).
-- Every field here is read by compute_daily_scores; widen this list if the
-- scorer grows new training_logs inputs.
-- ----------------------------------------------------------------------------
DROP TRIGGER IF EXISTS auto_enqueue_daily_score_on_insert ON training_logs;
CREATE TRIGGER auto_enqueue_daily_score_on_insert
    AFTER INSERT ON training_logs
    FOR EACH ROW
    WHEN (
        NEW.user_id IS NOT NULL
        AND COALESCE(NEW.workout_duration_minutes, 0) > 0
    )
    EXECUTE FUNCTION fn_enqueue_daily_score_recompute();

DROP TRIGGER IF EXISTS auto_enqueue_daily_score_on_update ON training_logs;
CREATE TRIGGER auto_enqueue_daily_score_on_update
    AFTER UPDATE ON training_logs
    FOR EACH ROW
    WHEN (
        NEW.user_id IS NOT NULL
        AND (
            (OLD.rpe_extracted_at IS NULL AND NEW.rpe_extracted_at IS NOT NULL)
            OR OLD.felt_rpe IS DISTINCT FROM NEW.felt_rpe
            OR OLD.workout_date IS DISTINCT FROM NEW.workout_date
            OR OLD.workout_type IS DISTINCT FROM NEW.workout_type
            OR OLD.workout_distance_miles IS DISTINCT FROM NEW.workout_distance_miles
            OR OLD.workout_duration_minutes IS DISTINCT FROM NEW.workout_duration_minutes
            OR OLD.stats_excluded IS DISTINCT FROM NEW.stats_excluded
            OR OLD.superseded_at IS DISTINCT FROM NEW.superseded_at
            OR OLD.duplicate_of IS DISTINCT FROM NEW.duplicate_of
            OR OLD.race_result IS DISTINCT FROM NEW.race_result
        )
    )
    EXECUTE FUNCTION fn_enqueue_daily_score_recompute();

-- ----------------------------------------------------------------------------
-- 4. Drain. Called by cron every minute; bounded so a run can never
--    outlast its interval (the 2026-08-07 cron-saturation failure mode):
--    p_max_users = 20 at ~300ms per athlete ≈ 6s worst case.
--    pg_try_advisory_xact_lock makes overlapping runs a no-op, and being
--    transaction-scoped it can never leak.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION drain_daily_score_recompute_queue(p_max_users INT DEFAULT 20)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, public, pg_temp
AS $$
DECLARE
    _user TEXT;
    _drained INT := 0;
BEGIN
    IF NOT pg_try_advisory_xact_lock(hashtextextended('daily_score_recompute_drain', 0)) THEN
        RETURN 0;
    END IF;

    WHILE _drained < p_max_users LOOP
        DELETE FROM daily_score_recompute_queue q
         WHERE q.user_id = (
                   SELECT user_id
                     FROM daily_score_recompute_queue
                    ORDER BY requested_at
                    LIMIT 1
                    FOR UPDATE SKIP LOCKED
               )
        RETURNING q.user_id INTO _user;

        EXIT WHEN _user IS NULL;

        BEGIN
            PERFORM compute_daily_scores(_user, current_date - 45, NULL);
        EXCEPTION WHEN OTHERS THEN
            -- Deliberately not re-enqueued; nightly cron is the backstop.
            RAISE WARNING
                'daily_score recompute failed for user % (sqlstate %): %',
                _user, SQLSTATE, SQLERRM;
        END;

        _drained := _drained + 1;
    END LOOP;

    RETURN _drained;
END;
$$;

REVOKE ALL ON FUNCTION drain_daily_score_recompute_queue(INT) FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 5. Cron. Every minute; a run with an empty queue is a single indexed
--    SELECT + advisory lock, effectively free.
-- ----------------------------------------------------------------------------
SELECT cron.schedule(
    'drain-daily-score-recompute',
    '* * * * *',
    'SELECT drain_daily_score_recompute_queue()'
);

COMMIT;

-- ============================================================================
-- Verification (run after applying):
--
-- 1. Triggers attached:
--      SELECT trigger_name FROM information_schema.triggers
--       WHERE event_object_table = 'training_logs'
--         AND trigger_name LIKE 'auto_enqueue_daily_score%';
--    Expected: 2 rows.
--
-- 2. Cron scheduled:
--      SELECT jobname, schedule, active FROM cron.job
--       WHERE jobname = 'drain-daily-score-recompute';
--
-- 3. Smoke test:
--      INSERT INTO daily_score_recompute_queue (user_id, reason)
--      VALUES ('<athlete>', 'smoke');
--    Within a minute the row is gone and
--      SELECT computed_at FROM daily_scores
--       WHERE user_id = '<athlete>' ORDER BY score_date DESC LIMIT 1;
--    shows a fresh timestamp.
-- ============================================================================
