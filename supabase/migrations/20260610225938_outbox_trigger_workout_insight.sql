-- ============================================================================
-- Replace the pg_net-firing trigger with an outbox-writing trigger.
--
-- Old behavior (20260428110000_trigger_workout_insight.sql):
--   AFTER INSERT → vault read → pg_net.http_post → generate-workout-insight
--
-- Why the change:
--   1. Bursts (HealthKit sync at app launch) overwhelmed edge function
--      concurrency / Gemini rate limits, and pg_net has no backpressure.
--   2. Two vault decryptions per INSERT are wasteful at scale.
--   3. No retry path — failures were silent, permanent.
--
-- New behavior:
--   AFTER INSERT → INSERT into coach_insight_jobs (cheap, transactional).
--   A cron-driven worker (drain-coach-insight-jobs) drains the queue at
--   a steady rate, with retries + exponential backoff.
--
-- Hardening:
--   - SET search_path on the SECURITY DEFINER function (footgun fix).
--   - Status column on training_logs disambiguates NULL.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION fn_enqueue_workout_insight()
RETURNS TRIGGER AS $$
BEGIN
    -- Cheap guards first — most rejections happen here.
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.workout_duration_minutes IS NULL
       OR NEW.workout_duration_minutes <= 0 THEN
        RETURN NEW;
    END IF;

    -- Voice path: process-training-memo will populate coach_insight.
    -- Mark the row so operators can tell "skipped intentionally" from
    -- "not yet processed".
    IF NEW.audio_url IS NOT NULL THEN
        UPDATE training_logs
           SET coach_insight_status = 'skipped'
         WHERE id = NEW.id
           AND coach_insight_status = 'pending';
        RETURN NEW;
    END IF;

    -- Manual coach note already present — same story.
    IF NEW.coach_insight IS NOT NULL
       AND length(trim(NEW.coach_insight)) > 0 THEN
        UPDATE training_logs
           SET coach_insight_status = 'generated'
         WHERE id = NEW.id
           AND coach_insight_status = 'pending';
        RETURN NEW;
    END IF;

    -- Enqueue. UNIQUE(training_log_id) makes this idempotent across
    -- re-fires (e.g. if the row is reinserted after delete-by-cascade).
    INSERT INTO coach_insight_jobs (training_log_id, user_id)
    VALUES (NEW.id, NEW.user_id)
    ON CONFLICT (training_log_id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql
   SECURITY DEFINER
   SET search_path = pg_catalog, pg_temp;

-- Detach the legacy trigger and drop its function.
DROP TRIGGER IF EXISTS auto_generate_workout_insight ON training_logs;
DROP FUNCTION IF EXISTS fn_trigger_workout_insight();

DROP TRIGGER IF EXISTS auto_enqueue_workout_insight ON training_logs;
CREATE TRIGGER auto_enqueue_workout_insight
    AFTER INSERT ON training_logs
    FOR EACH ROW
    EXECUTE FUNCTION fn_enqueue_workout_insight();

COMMIT;
