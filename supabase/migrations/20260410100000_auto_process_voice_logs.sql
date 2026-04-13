-- Auto-trigger processing for voice logs and check-ins.
--
-- When a new training_logs row is inserted with an audio_url and
-- processing_status = 'pending', this trigger calls the appropriate edge
-- function (process-check-in or process-training-memo) server-side via
-- pg_net. This removes the dependency on the iOS app's background Task
-- calling the edge function — which was silently failing due to auth
-- session hangs and Task cancellation.
--
-- Requires the pg_net extension (already enabled on Supabase by default).

-- Enable pg_net if not already enabled
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- The trigger function
CREATE OR REPLACE FUNCTION trigger_voice_log_processing()
RETURNS TRIGGER AS $$
DECLARE
  _function_name TEXT;
  _supabase_url TEXT;
  _service_key TEXT;
  _payload JSONB;
BEGIN
  -- Only fire for new rows with audio that need processing
  IF NEW.audio_url IS NULL OR NEW.processing_status != 'pending' THEN
    RETURN NEW;
  END IF;

  -- Pick the right edge function based on source
  IF NEW.source = 'check_in' THEN
    _function_name := 'process-check-in';
  ELSE
    _function_name := 'process-training-memo';
  END IF;

  -- Build the payload the edge functions expect
  _payload := jsonb_build_object(
    'record', jsonb_build_object(
      'id', NEW.id::text,
      'audio_url', NEW.audio_url
    )
  );

  -- Get Supabase URL and service role key from vault (or hardcode for now)
  _supabase_url := current_setting('app.settings.supabase_url', true);
  _service_key := current_setting('app.settings.service_role_key', true);

  -- Require app.settings to be configured — no hardcoded fallback
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    RAISE WARNING 'app.settings.supabase_url is not configured — skipping voice log auto-processing';
    RETURN NEW;
  END IF;

  -- Use pg_net to make an async HTTP POST to the edge function.
  -- This runs outside the transaction so it doesn't block the INSERT.
  IF _service_key IS NOT NULL AND _service_key != '' THEN
    PERFORM net.http_post(
      url := _supabase_url || '/functions/v1/' || _function_name,
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

-- Attach the trigger (AFTER INSERT so the row is committed first)
DROP TRIGGER IF EXISTS auto_process_voice_log ON training_logs;
CREATE TRIGGER auto_process_voice_log
  AFTER INSERT ON training_logs
  FOR EACH ROW
  EXECUTE FUNCTION trigger_voice_log_processing();
