-- ============================================================================
-- Trigger: generate a coaching insight on every training_logs INSERT that
-- isn't already going through the voice pipeline.
--
-- Rationale:
--   - Voice logs (audio_url IS NOT NULL) flow through process-training-memo,
--     which already populates coach_insight as part of its analysis.
--   - HealthKit-imported runs and direct API inserts skip that pipeline,
--     so they never get an insight. Sprint 2 of the athlete-first redesign
--     surfaces coach_insight on the home screen and per-workout detail —
--     having it null on most rows defeats the point.
--
-- This trigger fires AFTER INSERT, guards against:
--   1. Missing user_id / trivially-short workouts
--   2. Voice logs (will be populated by process-training-memo instead)
--   3. Rows already carrying coach_insight (manual coach note or backfill)
-- and invokes generate-workout-insight via pg_net with the service-role JWT.
--
-- Settings required (set via SELECT set_config or Supabase secret vault):
--   app.settings.supabase_url       → e.g. https://xxx.supabase.co
--   app.settings.service_role_key   → service-role JWT
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION fn_trigger_workout_insight()
RETURNS TRIGGER AS $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
BEGIN
    -- Guards
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.workout_duration_minutes IS NULL
       OR NEW.workout_duration_minutes <= 0 THEN
        RETURN NEW;
    END IF;

    -- Skip voice logs — process-training-memo handles those.
    IF NEW.audio_url IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Skip rows that already have an insight (e.g. coach manually wrote one).
    IF NEW.coach_insight IS NOT NULL AND length(trim(NEW.coach_insight)) > 0 THEN
        RETURN NEW;
    END IF;

    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE WARNING
            'app.settings.supabase_url / service_role_key not configured — '
            'skipping generate-workout-insight';
        RETURN NEW;
    END IF;

    PERFORM net.http_post(
        url := _supabase_url || '/functions/v1/generate-workout-insight',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || _service_key,
            'apikey', _service_key
        ),
        body := jsonb_build_object('training_log_id', NEW.id::text)
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS auto_generate_workout_insight ON training_logs;
CREATE TRIGGER auto_generate_workout_insight
    AFTER INSERT ON training_logs
    FOR EACH ROW
    EXECUTE FUNCTION fn_trigger_workout_insight();

COMMIT;
