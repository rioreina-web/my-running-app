-- ============================================================================
-- Coachable-moment evaluation outbox + enqueue trigger.
--
-- Why this replaces the pg_net-direct approach in
-- 20260515120000_trigger_evaluate_coachable_moment.sql (which was authored
-- but never applied): the workout-insight path moved May 8 to an outbox
-- pattern because direct pg_net firing under HealthKit-sync bursts
-- overwhelmed edge-fn concurrency. evaluate-coachable-moment is
-- vulnerable to the same pattern (30+ inserts in seconds → 30 evaluator
-- calls in seconds), so it gets the same treatment.
--
-- Design choices:
--
-- 1. ONE ROW PER ATHLETE (`PRIMARY KEY (athlete_user_id)`). Coalesces
--    bursts naturally — repeated trigger events for the same athlete
--    just re-arm the existing row to "queued". A 30-event HealthKit
--    sync produces one evaluator call, not 30.
--
-- 2. Trigger does INSERT…ON CONFLICT DO UPDATE, unconditionally setting
--    status='queued', last_enqueued_at=NOW(). If the worker is mid-
--    flight when a new event arrives, the trigger flips the row back to
--    queued; the worker's CAS completion (status='completed' WHERE
--    last_enqueued_at=:claimed_version) will fail, leaving the row
--    queued for the next drain tick. See `claim_coachable_moment_jobs`
--    for the version semantics.
--
-- 3. Two triggers: AFTER INSERT (HealthKit/direct logs) and AFTER UPDATE
--    when `cleaned_notes` transitions NULL→non-NULL (voice processing
--    just finished — mood and niggles available, rules need to re-eval).
--    Identical guards: must have a non-null user_id and an active coach.
--
-- 4. Atomic claim via SKIP LOCKED RPC, same shape as
--    `claim_coach_insight_jobs`. Returns enough context for the worker
--    to call evaluate-coachable-moment and to do the CAS completion.
--
-- 5. RLS: service-role only. No user surfaces read/write the queue;
--    coachable_moments is the user-visible artifact.
--
-- AI-advises-never-acts compliance:
--   This trigger only ENQUEUES evaluation work. The evaluator itself is
--   advisory — it writes rows into coachable_moments for the coach to
--   review. Nothing here modifies training_logs, plans, or paces.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. Outbox table.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS coachable_moment_jobs (
    athlete_user_id   TEXT PRIMARY KEY,
    status            TEXT NOT NULL DEFAULT 'queued'
        CHECK (status IN ('queued', 'in_progress', 'completed', 'failed')),
    attempts          INT  NOT NULL DEFAULT 0,
    max_attempts      INT  NOT NULL DEFAULT 3,
    last_error        TEXT,
    last_attempted_at TIMESTAMPTZ,
    -- Earliest time a worker can claim this row.
    next_retry_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Version flag: bumped by every trigger fire. Worker's CAS
    -- completion uses this to detect "trigger fired during processing
    -- → don't mark completed".
    last_enqueued_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at      TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_coachable_moment_jobs_drain
    ON coachable_moment_jobs (next_retry_at)
    WHERE status = 'queued';

CREATE INDEX IF NOT EXISTS idx_coachable_moment_jobs_failed
    ON coachable_moment_jobs (last_attempted_at DESC)
    WHERE status = 'failed';

-- ---------------------------------------------------------------------------
-- 2. RLS — service role only.
-- ---------------------------------------------------------------------------
ALTER TABLE coachable_moment_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role full access to coachable_moment_jobs"
    ON coachable_moment_jobs;
CREATE POLICY "Service role full access to coachable_moment_jobs"
    ON coachable_moment_jobs FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- ---------------------------------------------------------------------------
-- 3. Atomic claim RPC.
--
-- Returns last_enqueued_at as `version` so the worker can do a CAS
-- completion. The worker calls `UPDATE … SET status='completed' WHERE
-- last_enqueued_at = :version`; if the trigger fired during processing
-- it bumped last_enqueued_at, the CAS misses, and the row stays in
-- 'in_progress' for the next drain tick (which treats stale in_progress
-- rows as recoverable — see the drainer).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION claim_coachable_moment_jobs(batch_size INT DEFAULT 20)
RETURNS TABLE (
    athlete_user_id  TEXT,
    attempts         INT,
    max_attempts     INT,
    version          TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    RETURN QUERY
    WITH next_batch AS (
        SELECT j.athlete_user_id
          FROM coachable_moment_jobs j
         WHERE j.status = 'queued'
           AND j.next_retry_at <= NOW()
         ORDER BY j.next_retry_at, j.athlete_user_id
         LIMIT GREATEST(1, LEAST(100, COALESCE(batch_size, 20)))
        FOR UPDATE SKIP LOCKED
    )
    UPDATE coachable_moment_jobs j
       SET status = 'in_progress',
           attempts = j.attempts + 1,
           last_attempted_at = NOW()
      FROM next_batch nb
     WHERE j.athlete_user_id = nb.athlete_user_id
    RETURNING j.athlete_user_id, j.attempts, j.max_attempts, j.last_enqueued_at;
END;
$$;

REVOKE ALL ON FUNCTION claim_coachable_moment_jobs(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION claim_coachable_moment_jobs(INT) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. Enqueue function — used by both triggers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_enqueue_coachable_moment_evaluation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    -- Cheap guards.
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Skip if the athlete has no active coach. The evaluator would
    -- return `{ moments: [] }` anyway. Saves edge-fn invocations at
    -- scale: at 1k users with ~10% coached, this is ~700 skips/day.
    IF NOT EXISTS (
        SELECT 1
          FROM coach_athlete_relationships
         WHERE athlete_user_id = NEW.user_id
           AND status = 'active'
    ) THEN
        RETURN NEW;
    END IF;

    -- Upsert: re-arms the row regardless of prior status. The version
    -- bump (last_enqueued_at) tells a mid-flight worker that the row
    -- changed and to leave it queued.
    INSERT INTO coachable_moment_jobs (
        athlete_user_id,
        status,
        attempts,
        next_retry_at,
        last_enqueued_at,
        last_error
    )
    VALUES (NEW.user_id, 'queued', 0, NOW(), NOW(), NULL)
    ON CONFLICT (athlete_user_id) DO UPDATE
        SET status           = 'queued',
            attempts         = 0,
            next_retry_at    = NOW(),
            last_enqueued_at = NOW(),
            last_error       = NULL;

    RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5. Trigger 1: AFTER INSERT on training_logs.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS auto_enqueue_coachable_moment_on_insert ON training_logs;
CREATE TRIGGER auto_enqueue_coachable_moment_on_insert
    AFTER INSERT ON training_logs
    FOR EACH ROW
    EXECUTE FUNCTION fn_enqueue_coachable_moment_evaluation();

-- ---------------------------------------------------------------------------
-- 6. Trigger 2: AFTER UPDATE on training_logs, only on the
--    "voice processing just finished" signal — cleaned_notes goes from
--    NULL to non-NULL. Mood and niggles got extracted; rules depending
--    on them (low_mood_streak, future niggles rules) need a re-run.
-- ---------------------------------------------------------------------------
DROP TRIGGER IF EXISTS auto_enqueue_coachable_moment_on_voice_complete ON training_logs;
CREATE TRIGGER auto_enqueue_coachable_moment_on_voice_complete
    AFTER UPDATE ON training_logs
    FOR EACH ROW
    WHEN (
        OLD.cleaned_notes IS NULL
        AND NEW.cleaned_notes IS NOT NULL
        AND length(trim(NEW.cleaned_notes)) > 0
    )
    EXECUTE FUNCTION fn_enqueue_coachable_moment_evaluation();

COMMIT;

-- ============================================================================
-- Verification (run after applying):
--
-- 1. Confirm the outbox table exists:
--      SELECT count(*) FROM coachable_moment_jobs;
--
-- 2. Confirm both triggers attached:
--      SELECT trigger_name, event_manipulation
--      FROM information_schema.triggers
--      WHERE event_object_table = 'training_logs'
--        AND trigger_name LIKE 'auto_enqueue_coachable_moment%';
--    Expected: 2 rows.
--
-- 3. Smoke test (against a coached athlete):
--    (a) INSERT a row in training_logs.
--    (b) SELECT * FROM coachable_moment_jobs WHERE athlete_user_id = '<id>';
--        Expected: one row, status='queued'.
--    (c) After the next drainer tick (~60s), status flips to 'completed'
--        and any rule firings appear in coachable_moments.
-- ============================================================================
