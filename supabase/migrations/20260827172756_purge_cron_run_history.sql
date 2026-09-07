-- Purge and bound cron.job_run_details.
--
-- ROOT CAUSE: five per-minute cron jobs write ~7,200 rows/day into
-- cron.job_run_details and nothing has ever deleted them. Audited 2026-08-27:
-- 470,755 rows / 734 MB, oldest row 2026-04-19 — 94% of the entire 781 MB
-- database. last_vacuum and last_autovacuum are both NULL. A trivial
-- aggregate over the table measured 18.9s.
--
-- We already do exactly this for pg_net via the pg-net-response-cleanup job
-- (_http_response sits at a healthy 1 MB). Cron history never got the same
-- treatment.
--
-- NOTE: this reclaims space for reuse but does NOT return it to the OS.
-- VACUUM FULL cannot run inside a migration transaction — see the runbook
-- comment at the bottom of this file.

DELETE FROM cron.job_run_details
WHERE end_time < now() - INTERVAL '7 days';

-- Recurring purge. 04:40 UTC sits between pg-net-response-cleanup (04:17)
-- and weekly-consolidate-memories (04:30 Sun) so the nightly maintenance
-- jobs stay serialized rather than piling onto the same minute.
SELECT cron.unschedule('purge-cron-history')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'purge-cron-history');

SELECT cron.schedule(
  'purge-cron-history',
  '40 4 * * *',
  $job$ DELETE FROM cron.job_run_details WHERE end_time < now() - INTERVAL '7 days' $job$
);

-- Runbook — run manually, off-peak, NOT part of this migration.
-- Takes an ACCESS EXCLUSIVE lock on a 734 MB table; expect it to block cron
-- writes for the duration.
--
--   VACUUM (FULL, ANALYZE) cron.job_run_details;
--
-- Verify afterwards:
--   SELECT pg_size_pretty(pg_total_relation_size('cron.job_run_details'));
