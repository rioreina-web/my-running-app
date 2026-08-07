-- ============================================================================
-- Stand-in for the prod extensions `20260807130000_wire_extract_rpe.sql` leans
-- on, so the migration can be run and asserted against a throwaway Postgres 16
-- before it ever touches prod. net.http_post records instead of posting, which
-- is what lets the assertions check the URL, headers and payload.
--
-- Run from the repo root (see wire_extract_rpe_assert.sql for the full recipe).
-- ============================================================================
CREATE ROLE anon;
CREATE ROLE authenticated;
CREATE ROLE service_role;

CREATE SCHEMA vault;
CREATE TABLE vault.decrypted_secrets (name TEXT PRIMARY KEY, decrypted_secret TEXT);
INSERT INTO vault.decrypted_secrets VALUES
  ('supabase_url', 'https://example.supabase.co'),
  ('service_role_key', 'SERVICE_KEY');

CREATE SCHEMA net;
CREATE TABLE net.sent (
  id BIGSERIAL PRIMARY KEY, url TEXT, headers JSONB, body JSONB, at TIMESTAMPTZ DEFAULT now()
);
CREATE FUNCTION net.http_post(
  url TEXT, body JSONB DEFAULT '{}', params JSONB DEFAULT '{}',
  headers JSONB DEFAULT '{}', timeout_milliseconds INT DEFAULT 5000
) RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE _id BIGINT;
BEGIN
  INSERT INTO net.sent (url, headers, body) VALUES (url, headers, body) RETURNING id INTO _id;
  RETURN _id;
END; $$;

CREATE SCHEMA cron;
CREATE TABLE cron.job (jobid BIGSERIAL PRIMARY KEY, jobname TEXT, schedule TEXT, command TEXT);
CREATE FUNCTION cron.schedule(job_name TEXT, schedule TEXT, command TEXT)
RETURNS BIGINT LANGUAGE plpgsql AS $$
DECLARE _id BIGINT;
BEGIN
  INSERT INTO cron.job (jobname, schedule, command) VALUES (job_name, schedule, command) RETURNING jobid INTO _id;
  RETURN _id;
END; $$;
CREATE FUNCTION cron.unschedule(job_name TEXT) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
BEGIN
  DELETE FROM cron.job WHERE jobname = job_name;
  RETURN TRUE;
END; $$;

CREATE SCHEMA auth;
CREATE FUNCTION auth.role() RETURNS TEXT LANGUAGE sql STABLE AS $$ SELECT current_setting('request.jwt.role', true) $$;

-- The columns of training_logs this migration reads, with prod's types.
CREATE TABLE public.training_logs (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          TEXT,
  workout_date     TIMESTAMPTZ,
  notes            TEXT,
  cleaned_notes    TEXT,
  felt_rpe         SMALLINT,
  planned_rpe      SMALLINT,
  rpe_pull_quote   TEXT,
  rpe_tags         TEXT[],
  rpe_extracted_at TIMESTAMPTZ
);

-- Pre-existing rows, standing in for the 268-log backlog:
--   1..3  transcript, no RPE            -> should be seeded
--   4     notes only, no cleaned_notes  -> should be seeded (fallback path)
--   5     no transcript at all          -> must NOT be seeded
--   6     already extracted             -> must NOT be seeded
--   7     transcript but NULL user_id   -> must NOT be seeded
INSERT INTO public.training_logs (id, user_id, workout_date, cleaned_notes, notes, rpe_extracted_at) VALUES
 ('11111111-1111-1111-1111-111111111111','u1','2026-08-06','felt strong today', NULL, NULL),
 ('22222222-2222-2222-2222-222222222222','u1','2026-08-04','legs were heavy',    NULL, NULL),
 ('33333333-3333-3333-3333-333333333333','u1','2026-07-30','cruised it',         NULL, NULL),
 ('44444444-4444-4444-4444-444444444444','u1','2026-07-28', NULL, 'typed note only', NULL),
 ('55555555-5555-5555-5555-555555555555','u1','2026-07-27', '   ', '',           NULL),
 ('66666666-6666-6666-6666-666666666666','u1','2026-07-26','already done',       NULL, now()),
 ('77777777-7777-7777-7777-777777777777', NULL,'2026-07-25','orphan log',        NULL, NULL);
