-- ============================================================================
-- Automatic Strava sync: incremental watermark column + pg_cron schedule.
--
-- Pairs with the `strava-sync` edge function (service-role auth, multi-user,
-- incremental). The cron reads supabase_url + service_role_key from Vault AT
-- RUN TIME (same pattern as the drain-cron auth fix in
-- 20260611160000_fix_drain_cron_auth_dynamic_vault.sql) so it never bakes a
-- stale key and survives future rotations without a reschedule.
--
-- PREREQUISITE: Vault `service_role_key` must equal the functions'
-- SUPABASE_SERVICE_ROLE_KEY env (same requirement as the drains). If the drains
-- are returning 200, this will authenticate too.
-- ============================================================================

BEGIN;

-- High-water mark for incremental sync. strava-sync lists
-- /athlete/activities?after=<last_synced_at>; NULL => first sync (looks back
-- ~60 days). Dedup on vital_workout_id = strava_<id> keeps overlaps harmless.
ALTER TABLE strava_credentials
  ADD COLUMN IF NOT EXISTS last_synced_at TIMESTAMPTZ;

COMMENT ON COLUMN strava_credentials.last_synced_at IS
  'High-water mark for incremental Strava sync (strava-sync edge function). '
  'NULL means never synced -> first run looks back ~60 days.';

DO $$
BEGIN
  -- every 15 minutes; cron.schedule upserts by job name
  PERFORM cron.schedule(
    'strava-sync',
    '*/15 * * * *',
    $job$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1)
               || '/functions/v1/strava-sync',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1),
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1)
        ),
        body := jsonb_build_object('source', 'cron')
      );
    $job$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'strava-sync cron not scheduled (pg_cron unavailable): %', SQLERRM;
END;
$$;

COMMIT;
