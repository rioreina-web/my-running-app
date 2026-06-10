-- ============================================================================
-- Adaptive Training Triggers
--
-- 1. post-run-reconciliation: fires after training_log insert when there's
--    a workout_date and distance > 0 (skips voice-only logs).
-- 2. weekly-plan-review: cron job, Sunday 8pm UTC.
-- ============================================================================

-- Requires pg_net (already enabled from 20260410)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- ============================================================================
-- 1. POST-RUN RECONCILIATION TRIGGER
-- Fires after a training_log is inserted with actual workout data.
-- Calls post-run-reconciliation edge function via pg_net.
-- ============================================================================

CREATE OR REPLACE FUNCTION trigger_post_run_reconciliation()
RETURNS TRIGGER AS $$
DECLARE
  _supabase_url TEXT;
  _service_key TEXT;
  _payload JSONB;
BEGIN
  -- Only fire for rows with actual workout data (not voice-only logs)
  IF NEW.workout_date IS NULL THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.workout_distance_miles, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Build payload
  _payload := jsonb_build_object(
    'training_log_id', NEW.id::text,
    'user_id', NEW.user_id
  );

  _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
  _service_key := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    RAISE WARNING 'app.settings.supabase_url not configured — skipping post-run reconciliation';
    RETURN NEW;
  END IF;

  IF _service_key IS NOT NULL AND _service_key != '' THEN
    PERFORM net.http_post(
      url := _supabase_url || '/functions/v1/post-run-reconciliation',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || _service_key,
        'apikey', _service_key
      ),
      body := _payload
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS auto_post_run_reconciliation ON training_logs;
CREATE TRIGGER auto_post_run_reconciliation
  AFTER INSERT ON training_logs
  FOR EACH ROW
  EXECUTE FUNCTION trigger_post_run_reconciliation();


-- ============================================================================
-- 2. WEEKLY PLAN REVIEW CRON
-- Runs Sunday 8pm UTC. Calls weekly-plan-review in batch mode.
--
-- Requires pg_cron extension. On Supabase this needs to be enabled in the
-- dashboard (Database > Extensions > pg_cron). The schedule below is
-- idempotent — it drops any existing job with this name first.
-- ============================================================================

-- NOTE: pg_cron may not be enabled in all environments. Wrap in a DO block
-- that gracefully skips if the extension isn't available.
DO $$
BEGIN
  -- Try to enable pg_cron
  CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;

  -- Remove existing job if any
  PERFORM cron.unschedule('weekly-plan-review');
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available — weekly-plan-review cron not scheduled. Set up manually or use an external scheduler.';
END;
$$;

-- Schedule the cron job (separate block so it runs even if unschedule had nothing to remove)
DO $$
DECLARE
  _supabase_url TEXT;
  _service_key TEXT;
BEGIN
  _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
  _service_key := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    RAISE NOTICE 'app.settings.supabase_url not configured — weekly-plan-review cron not scheduled';
    RETURN;
  END IF;

  -- Sunday 8pm UTC = "0 20 * * 0"
  PERFORM cron.schedule(
    'weekly-plan-review',
    '0 20 * * 0',
    format(
      $$SELECT net.http_post(
        url := '%s/functions/v1/weekly-plan-review',
        headers := '{"Content-Type": "application/json", "Authorization": "Bearer %s", "apikey": "%s"}'::jsonb,
        body := '{"batch": true}'::jsonb
      )$$,
      _supabase_url,
      _service_key,
      _service_key
    )
  );

  RAISE NOTICE 'weekly-plan-review cron scheduled: Sunday 8pm UTC';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Could not schedule weekly-plan-review cron: %', SQLERRM;
END;
$$;
