-- Enable the pg_net extension for HTTP calls
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Create the trigger function
CREATE OR REPLACE FUNCTION trigger_process_training_memo()
RETURNS TRIGGER AS $$
BEGIN
  PERFORM net.http_post(
    url := 'http://host.docker.internal:54321/functions/v1/process-training-memo',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU"}'::jsonb,
    body := jsonb_build_object('type', 'INSERT', 'table', 'training_logs', 'schema', 'public', 'record', row_to_json(NEW))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create the trigger
DROP TRIGGER IF EXISTS on_training_log_insert ON training_logs;
CREATE TRIGGER on_training_log_insert
AFTER INSERT ON training_logs
FOR EACH ROW
EXECUTE FUNCTION trigger_process_training_memo();
