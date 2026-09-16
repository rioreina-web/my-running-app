-- Voice-memo latency, Phase 1.2 (see outputs/voice-memo-latency-plan-2026-08-04):
-- drop the drain cadence from every minute to every 15 seconds.
--
-- Context: the every-minute cron was the PRIMARY trigger for voice processing,
-- which put a uniform 0-60s (measured mean 25.6s) of pure dead time in front
-- of every memo. As of this change the iOS client direct-invokes
-- process-training-memo right after the training_logs insert (the same call
-- the attach path already made), demoting the outbox to the retry net it was
-- designed to be. This migration is the belt-and-braces half: if the direct
-- invoke is lost (dropped connection, app killed mid-flight), the drain picks
-- the job up within ~15s instead of a full minute.
--
-- Idempotency is already in place end to end: voice_processing_jobs has
-- UNIQUE (training_log_id) ON CONFLICT DO NOTHING, process-training-memo has
-- the completed short-circuit + 2-minute processing concurrency guard, and
-- the drain treats a 409 processing-race as retryable.
--
-- pg_cron >= 1.5 accepts the 'N seconds' interval syntax. If this instance
-- can't schedule it, we keep the every-minute schedule rather than leaving
-- the drain unscheduled — the EXCEPTION fallback below.

DO $$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
    _command      TEXT;
BEGIN
    BEGIN
        CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA extensions;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — drain-voice-processing-jobs reschedule skipped';
        RETURN;
    END;

    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE NOTICE 'vault secrets missing — drain-voice-processing-jobs reschedule skipped';
        RETURN;
    END IF;

    _command := format(
        $job$
        SELECT net.http_post(
            url := %L,
            headers := jsonb_build_object(
                'Content-Type', 'application/json',
                'Authorization', 'Bearer ' || %L,
                'apikey', %L
            ),
            body := jsonb_build_object('batch', 10)
        );
        $job$,
        _supabase_url || '/functions/v1/drain-voice-processing-jobs',
        _service_key,
        _service_key
    );

    BEGIN
        PERFORM cron.unschedule('drain-voice-processing-jobs');
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
        PERFORM cron.schedule('drain-voice-processing-jobs', '15 seconds', _command);
    EXCEPTION WHEN OTHERS THEN
        -- Older pg_cron without seconds-interval support: fall back to the
        -- previous every-minute cadence rather than leaving the drain dark.
        RAISE NOTICE 'seconds-interval schedule rejected (%) — falling back to every-minute', SQLERRM;
        PERFORM cron.schedule('drain-voice-processing-jobs', '* * * * *', _command);
    END;
END;
$$;

-- Verification (SQL editor):
--   SELECT jobname, schedule FROM cron.job WHERE jobname = 'drain-voice-processing-jobs';
--   -- expect schedule = '15 seconds'
