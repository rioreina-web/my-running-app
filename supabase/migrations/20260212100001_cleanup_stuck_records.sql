-- Function to reset stuck "processing" records older than 5 minutes
CREATE OR REPLACE FUNCTION public.cleanup_stuck_processing()
RETURNS INTEGER AS $$
DECLARE
  affected INTEGER;
BEGIN
  UPDATE public.training_logs
  SET processing_status = 'failed',
      processing_error = 'Processing timed out after 5 minutes'
  WHERE processing_status = 'processing'
    AND last_processing_attempt < NOW() - INTERVAL '5 minutes';
  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END;
$$ LANGUAGE plpgsql;

-- Also reset any ancient "pending" records (older than 30 minutes)
-- These likely lost their edge function call
CREATE OR REPLACE FUNCTION public.cleanup_stale_pending()
RETURNS INTEGER AS $$
DECLARE
  affected INTEGER;
BEGIN
  UPDATE public.training_logs
  SET processing_status = 'failed',
      processing_error = 'Record was pending for over 30 minutes without processing'
  WHERE processing_status = 'pending'
    AND audio_url IS NOT NULL
    AND created_at < NOW() - INTERVAL '30 minutes'
    AND cleaned_notes IS NULL;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END;
$$ LANGUAGE plpgsql;

-- Schedule cleanup every 10 minutes if pg_cron is available
-- Run this manually if pg_cron is not enabled:
--   SELECT cron.schedule('cleanup-stuck-records', '*/10 * * * *', 'SELECT public.cleanup_stuck_processing(); SELECT public.cleanup_stale_pending();');
