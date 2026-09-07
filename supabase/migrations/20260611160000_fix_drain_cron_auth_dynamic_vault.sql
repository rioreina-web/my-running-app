-- ============================================================================
-- Fix the drain-cron 403 storm by reading Vault credentials at RUN TIME.
--
-- ROOT CAUSE (verified in prod 2026-06-11): every drain cron
-- (drain-coachable-moment-jobs, drain-voice-processing-jobs,
-- drain-coach-insight-jobs) was returning 403 on every minute tick.
-- The original cron migrations baked the Vault `service_role_key` LITERALLY
-- into the scheduled command via format(%L) at apply time. Each drain function
-- authenticates by constant-time STRING EQUALITY of the incoming Bearer token
-- against its own SUPABASE_SERVICE_ROLE_KEY env var
-- (see drain-coachable-moment-jobs/index.ts: constantTimeEq(token, supabaseServiceKey)).
-- Once the service-role key (or the Vault copy of it) drifted from the value
-- baked into the cron command, the token no longer matched -> 403 every tick,
-- and the entire async pipeline (coachable moments, voice processing,
-- coach insights) silently stopped producing results.
--
-- FIX: reschedule each drain so the cron COMMAND reads supabase_url +
-- service_role_key from Vault on every run (subselects), instead of a value
-- baked once at apply time. pg_cron jobs execute as the `postgres` superuser,
-- which can read vault.decrypted_secrets. Consequences:
--   * The next tick after this lands uses the LIVE Vault value.
--   * A future service-role-key rotation only needs the Vault secret updated
--     -- no reschedule, no re-baking, no recurrence of this exact bug.
--
-- PREREQUISITE: this is only effective once the Vault `service_role_key`
-- secret actually equals the functions' SUPABASE_SERVICE_ROLE_KEY env value.
-- If the drains still 403 after this lands, the Vault value itself is stale --
-- update it (Dashboard -> Settings -> API -> service_role key, then
-- vault.update_secret/create_secret), and the next tick recovers automatically.
--
-- cron.schedule() upserts by job name, so re-running these replaces the
-- existing (baked) schedules in place.
-- ============================================================================

BEGIN;

DO $$
BEGIN
  -- coachable-moment drain — every minute, batch 40
  PERFORM cron.schedule(
    'drain-coachable-moment-jobs',
    '* * * * *',
    $job$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1)
               || '/functions/v1/drain-coachable-moment-jobs',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1),
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object('batch', 40)
      );
    $job$
  );

  -- voice-processing drain — every minute, batch 10
  PERFORM cron.schedule(
    'drain-voice-processing-jobs',
    '* * * * *',
    $job$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1)
               || '/functions/v1/drain-voice-processing-jobs',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1),
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object('batch', 10)
      );
    $job$
  );

  -- coach-insight drain — every minute, batch 40
  PERFORM cron.schedule(
    'drain-coach-insight-jobs',
    '* * * * *',
    $job$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1)
               || '/functions/v1/drain-coach-insight-jobs',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1),
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object('batch', 40)
      );
    $job$
  );
END;
$$;

COMMIT;
