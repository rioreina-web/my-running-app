-- ============================================================================
-- Trigger: reconcile every training_logs insert via the reconcile-log fn.
--
-- Fires AFTER INSERT on training_logs. Pays attention only to rows with
-- enough data to be meaningful (user_id present, workout_duration_minutes
-- set). Calls reconcile-log via pg_net with the service-role JWT.
--
-- Settings required (set via SELECT set_config or Supabase secret vault):
--   app.settings.supabase_url       → e.g. https://xxx.supabase.co
--   app.settings.service_role_key   → service-role JWT
--
-- Coexists with the pre-existing auto_post_run_reconciliation trigger,
-- which calls a different downstream function (post-run-reconciliation)
-- serving a different purpose. Once reconcile-log covers everything the
-- old trigger did, we can drop the old one in a follow-up migration.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION fn_trigger_reconcile_log()
RETURNS TRIGGER AS $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
    _payload      JSONB;
BEGIN
    -- Guards: skip rows that don't represent an actual workout.
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.workout_duration_minutes IS NULL
       OR NEW.workout_duration_minutes <= 0 THEN
        RETURN NEW;
    END IF;

    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE WARNING
            'app.settings.supabase_url / service_role_key not configured — skipping reconcile-log';
        RETURN NEW;
    END IF;

    _payload := jsonb_build_object('training_log_id', NEW.id::text);

    PERFORM net.http_post(
        url := _supabase_url || '/functions/v1/reconcile-log',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || _service_key,
            'apikey', _service_key
        ),
        body := _payload
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS auto_reconcile_log ON training_logs;
CREATE TRIGGER auto_reconcile_log
    AFTER INSERT ON training_logs
    FOR EACH ROW
    EXECUTE FUNCTION fn_trigger_reconcile_log();

-- ── One-time backfill for the last 90 days ─────────────────────────────
--
-- Iterates in batches (200 rows / cycle) and fires a reconcile-log call per
-- row. Failures are logged via RAISE NOTICE but don't abort — the migration
-- can re-run for stragglers via the trigger if needed.

DO $backfill$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
    _log_row      RECORD;
    _since        TIMESTAMPTZ := now() - interval '90 days';
    _count        INTEGER := 0;
    _batch        INTEGER := 0;
BEGIN
    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE NOTICE 'reconcile-log backfill skipped — app.settings not configured';
        RETURN;
    END IF;

    FOR _log_row IN
        SELECT id
          FROM training_logs
         WHERE workout_date >= _since
           AND workout_duration_minutes IS NOT NULL
           AND workout_duration_minutes > 0
         ORDER BY workout_date ASC
    LOOP
        PERFORM net.http_post(
            url := _supabase_url || '/functions/v1/reconcile-log',
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || _service_key,
                'apikey', _service_key
            ),
            body := jsonb_build_object('training_log_id', _log_row.id::text)
        );
        _count := _count + 1;

        IF _count % 200 = 0 THEN
            _batch := _batch + 1;
            RAISE NOTICE 'reconcile-log backfill: fired % calls (batch %)', _count, _batch;
            -- Throttle: 200 calls per second is plenty for Deno cold-start.
            PERFORM pg_sleep(1);
        END IF;
    END LOOP;

    RAISE NOTICE 'reconcile-log backfill complete: % training_logs queued', _count;
END
$backfill$;

COMMIT;
