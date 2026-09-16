-- ============================================================================
-- Assertions for 20260807130000_wire_extract_rpe.sql.
--
-- 28 assertions, run against a throwaway Postgres 16 — NOT against prod. They
-- caught one real bug before this shipped: the first draft gave backfilled rows
-- a near-future created_at to keep live memos ahead of the backlog, which only
-- works while the backlog is younger than its own offset window. Hence the
-- explicit `priority` column.
--
-- Recipe (from the repo root):
--   initdb -D /tmp/rpe/data -U postgres --auth=trust
--   pg_ctl -D /tmp/rpe/data -o "-p 5433 -k /tmp/rpe" -l /tmp/rpe/log start
--   psql -h /tmp/rpe -p 5433 -U postgres -v ON_ERROR_STOP=1 \
--        -f supabase/tests/wire_extract_rpe_stub_env.sql \
--        -f supabase/migrations/20260807130000_wire_extract_rpe.sql \
--        -f supabase/tests/wire_extract_rpe_assert.sql
-- ============================================================================
\set ON_ERROR_STOP on
\pset pager off

CREATE OR REPLACE FUNCTION assert(_cond BOOLEAN, _msg TEXT) RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  IF _cond THEN RAISE NOTICE 'PASS  %', _msg;
  ELSE RAISE EXCEPTION 'FAIL  %', _msg; END IF;
END; $$;

-- ── seed correctness ────────────────────────────────────────────────────────
SELECT assert((SELECT count(*) FROM rpe_extraction_jobs) = 4,
  'seed took exactly the 4 logs with a transcript, a user, and no RPE');
SELECT assert(NOT EXISTS (SELECT 1 FROM rpe_extraction_jobs WHERE training_log_id = '55555555-5555-5555-5555-555555555555'),
  'blank-transcript log was not seeded');
SELECT assert(NOT EXISTS (SELECT 1 FROM rpe_extraction_jobs WHERE training_log_id = '66666666-6666-6666-6666-666666666666'),
  'already-extracted log was not seeded');
SELECT assert(NOT EXISTS (SELECT 1 FROM rpe_extraction_jobs WHERE training_log_id = '77777777-7777-7777-7777-777777777777'),
  'log with NULL user_id was not seeded');
SELECT assert(
  (SELECT training_log_id FROM rpe_extraction_jobs ORDER BY priority, created_at LIMIT 1) = '11111111-1111-1111-1111-111111111111',
  'backlog drains newest workout first');
SELECT assert((SELECT count(*) FROM rpe_extraction_jobs WHERE priority = 1) = 4,
  'every backfilled row is marked backfill priority');

-- ── trigger: a live memo lands ──────────────────────────────────────────────
INSERT INTO training_logs (id, user_id, workout_date, cleaned_notes)
VALUES ('aaaaaaaa-0000-0000-0000-000000000001','u1','2026-08-07','brutal session');
SELECT assert(EXISTS (SELECT 1 FROM rpe_extraction_jobs WHERE training_log_id='aaaaaaaa-0000-0000-0000-000000000001'),
  'INSERT with a transcript enqueues');
SELECT assert(
  (SELECT training_log_id FROM rpe_extraction_jobs ORDER BY priority, created_at LIMIT 1) = 'aaaaaaaa-0000-0000-0000-000000000001',
  'a live memo jumps the whole backfilled backlog');
-- and it still jumps it once the backlog is older than any offset window.
UPDATE rpe_extraction_jobs SET created_at = created_at - INTERVAL '3 days' WHERE priority = 1;
SELECT assert(
  (SELECT training_log_id FROM rpe_extraction_jobs ORDER BY priority, created_at LIMIT 1) = 'aaaaaaaa-0000-0000-0000-000000000001',
  'a live memo jumps a THREE-DAY-OLD backlog too — priority, not timestamp luck');

-- Strava-style: row lands empty, transcript arrives later.
INSERT INTO training_logs (id, user_id, workout_date) VALUES ('aaaaaaaa-0000-0000-0000-000000000002','u1','2026-08-07');
SELECT assert(NOT EXISTS (SELECT 1 FROM rpe_extraction_jobs WHERE training_log_id='aaaaaaaa-0000-0000-0000-000000000002'),
  'INSERT with no transcript does not enqueue');
UPDATE training_logs SET cleaned_notes = 'easy shakeout, felt fine' WHERE id='aaaaaaaa-0000-0000-0000-000000000002';
SELECT assert(EXISTS (SELECT 1 FROM rpe_extraction_jobs WHERE training_log_id='aaaaaaaa-0000-0000-0000-000000000002'),
  'the voice pipeline writing cleaned_notes later enqueues');

-- ── dispatch ────────────────────────────────────────────────────────────────
SELECT assert(dispatch_rpe_extraction(4) = 4, 'dispatch honours the batch size');
SELECT assert((SELECT count(*) FROM net.sent) = 4, 'one http_post per claimed job');
SELECT assert((SELECT count(DISTINCT url) FROM net.sent) = 1
          AND (SELECT url FROM net.sent LIMIT 1) = 'https://example.supabase.co/functions/v1/extract-rpe',
  'posts go to extract-rpe at the vault-resolved URL');
SELECT assert((SELECT body->>'log_id' FROM net.sent ORDER BY id LIMIT 1) = 'aaaaaaaa-0000-0000-0000-000000000001'
          AND (SELECT body->>'user_id' FROM net.sent ORDER BY id LIMIT 1) = 'u1',
  'payload carries log_id + user_id, the service-role shape extract-rpe accepts');
SELECT assert((SELECT headers->>'Authorization' FROM net.sent LIMIT 1) = 'Bearer SERVICE_KEY'
          AND (SELECT headers->>'apikey' FROM net.sent LIMIT 1) = 'SERVICE_KEY',
  'service-role auth headers are read from the vault at run time');
SELECT assert((SELECT count(*) FROM rpe_extraction_jobs WHERE attempts = 1) = 4, 'claimed jobs record the attempt');

-- ── no double-dispatch inside the backoff window ────────────────────────────
SELECT assert(dispatch_rpe_extraction(8) = 2,
  'a second run inside the 10-minute backoff only picks up the 2 untouched jobs');
SELECT assert((SELECT count(*) FROM net.sent) = 6, 'no job was posted twice');

-- ── completion retires the job ──────────────────────────────────────────────
-- extract-rpe writing its result back, including the honest null case.
UPDATE training_logs SET felt_rpe = 8, rpe_pull_quote = 'legs were done', rpe_tags = ARRAY['tired'],
       rpe_extracted_at = now() WHERE id = 'aaaaaaaa-0000-0000-0000-000000000001';
UPDATE training_logs SET felt_rpe = NULL, rpe_extracted_at = now()
 WHERE id = '11111111-1111-1111-1111-111111111111';
SELECT assert(EXISTS (SELECT 1 FROM rpe_extraction_jobs WHERE training_log_id='aaaaaaaa-0000-0000-0000-000000000001'),
  'the write-back does not itself retire the job (the dispatcher does)');
SELECT dispatch_rpe_extraction(8);
SELECT assert(NOT EXISTS (SELECT 1 FROM rpe_extraction_jobs WHERE training_log_id='aaaaaaaa-0000-0000-0000-000000000001'),
  'a log with a felt RPE is retired');
SELECT assert(NOT EXISTS (SELECT 1 FROM rpe_extraction_jobs WHERE training_log_id='11111111-1111-1111-1111-111111111111'),
  'a log the model honestly found no RPE in is retired too, not retried forever');

-- ── no feedback loop ────────────────────────────────────────────────────────
SELECT assert((SELECT count(*) FROM rpe_extraction_jobs WHERE training_log_id IN
   ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111')) = 0,
  'extract-rpe write-back never re-enqueued the row it just finished');

-- ── bounded retry ───────────────────────────────────────────────────────────
UPDATE rpe_extraction_jobs SET attempts = 3, last_attempt_at = now() - INTERVAL '1 day';
SELECT assert(dispatch_rpe_extraction(8) = 0, 'exhausted jobs are never dispatched again');

-- ── cron ────────────────────────────────────────────────────────────────────
SELECT assert((SELECT count(*) FROM cron.job WHERE jobname='dispatch-rpe-extraction') = 1,
  'exactly one cron job registered');
SELECT assert((SELECT schedule FROM cron.job WHERE jobname='dispatch-rpe-extraction') = '* * * * *',
  'cron runs every minute');

-- ── idempotency: re-applying the migration changes nothing ──────────────────
\i supabase/migrations/20260807130000_wire_extract_rpe.sql
SELECT assert((SELECT count(*) FROM cron.job WHERE jobname='dispatch-rpe-extraction') = 1,
  're-apply does not duplicate the cron job');
SELECT assert((SELECT count(*) FROM rpe_extraction_jobs) = 4,
  're-apply does not duplicate queue rows (2 exhausted + 2 still owed = 4)');

SELECT 'ALL ASSERTIONS PASSED' AS result;
