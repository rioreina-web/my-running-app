-- ============================================================================
-- Backfill helper: populate coach_insight on pre-existing training_logs rows
-- that were imported before the auto-trigger landed.
--
-- Adds a function (does NOT auto-invoke). The deploy is safe — no LLM calls
-- happen until you manually run:
--
--   SELECT backfill_workout_insights(25);   -- top 25 oldest missing rows
--   SELECT backfill_workout_insights(NULL); -- all of them (use with care)
--
-- The function POSTs each qualifying row's id to generate-workout-insight via
-- pg_net. Calls are async — pg_net buffers and dispatches in the background,
-- so the SELECT returns immediately. Watch coach_insight populate over the
-- next minute or two via:
--
--   SELECT count(*) FILTER (WHERE coach_insight IS NULL) AS pending,
--          count(*) AS total
--   FROM training_logs
--   WHERE audio_url IS NULL AND workout_duration_minutes > 0;
--
-- Re-runs cleanly: rows that already have coach_insight are skipped both
-- here and inside the edge function (idempotent on both sides).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION backfill_workout_insights(batch_limit INT DEFAULT 25)
RETURNS INT AS $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
    _row          RECORD;
    _queued       INT := 0;
BEGIN
    _supabase_url := current_setting('app.settings.supabase_url', true);
    _service_key  := current_setting('app.settings.service_role_key', true);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE EXCEPTION
            'app.settings.supabase_url / service_role_key not configured — '
            'set them before running the backfill';
    END IF;

    FOR _row IN
        SELECT id
        FROM training_logs
        WHERE coach_insight IS NULL
          AND audio_url IS NULL
          AND user_id IS NOT NULL
          AND workout_duration_minutes IS NOT NULL
          AND workout_duration_minutes > 0
        ORDER BY workout_date DESC
        LIMIT COALESCE(batch_limit, 10000)
    LOOP
        PERFORM net.http_post(
            url := _supabase_url || '/functions/v1/generate-workout-insight',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || _service_key,
                'apikey', _service_key
            ),
            body := jsonb_build_object('training_log_id', _row.id::text)
        );
        _queued := _queued + 1;
    END LOOP;

    RETURN _queued;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION backfill_workout_insights(INT) IS
    'Run once per environment after the trigger ships. Returns the number '
    'of rows queued for insight generation. pg_net dispatches asynchronously.';

COMMIT;
