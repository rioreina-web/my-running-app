-- RLS tenant-isolation test (starter)
-- ---------------------------------------------------------------------------
-- PURPOSE: prove that one user cannot read another user's rows, for every
-- user-owned table. This is the single most important test for a 1000-stranger
-- beta. Run it against a LOCAL Supabase (never prod).
--
-- HOW TO RUN (local):
--   1. supabase start                 # boots local Postgres + auth
--   2. supabase db reset              # applies all migrations fresh
--   3. psql "$LOCAL_DB_URL" -f outputs/starter-tests/rls-tenant-isolation.test.sql
--
-- It should print "ISOLATION OK" for every table. Any "LEAK" line is a bug
-- that must block release.
--
-- NOTE FOR YOUR AI ASSISTANT: extend `user_owned_tables` below to cover EVERY
-- table that has a `user_id TEXT` column. Grep migrations for
-- `ENABLE ROW LEVEL SECURITY` to find them, then keep this list in sync.
-- ---------------------------------------------------------------------------

begin;

-- Two fake auth users. In real auth.uid() is a UUID; user_id columns in this
-- repo are TEXT matching auth.uid()::text (see CLAUDE.md conventions).
\set user_a '11111111-1111-1111-1111-111111111111'
\set user_b '22222222-2222-2222-2222-222222222222'

-- Helper: run a SELECT as a given user by setting the JWT claim RLS reads.
-- Supabase RLS reads auth.uid() from request.jwt.claims -> 'sub'.
create or replace function _test_set_user(uid text) returns void as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', uid, 'role','authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end;
$$ language plpgsql;

-- ---- SEED: one row owned by user A in each table under test. -------------
-- Fill in real required columns per table. Keep this minimal — just enough
-- to insert one row owned by user A. Use service role (no RLS) to seed.
set local role postgres;

-- EXAMPLE for the training journal. Replace/extend with your real columns.
-- insert into training_logs (user_id, date, distance_m)
--   values (:'user_a', now(), 5000);

-- ---- CHECK: as user B, every user-owned table must return zero A-rows. ----
-- Add one block per table. The pattern is identical each time.
do $$
declare
  leak_count int;
  tbl text;
  user_b text := '22222222-2222-2222-2222-222222222222';
  -- >>> EXTEND THIS LIST to every user-owned table <<<
  -- These are REAL tables in this repo that carry a user_id TEXT column
  -- (confirmed against supabase/migrations). Keep it in sync as you add tables.
  user_owned_tables text[] := array[
    'training_logs',
    'coachable_moments',
    'athlete_state',
    'athlete_settings',
    'injuries',
    'daily_coaching_reads',
    'fitness_snapshots',
    'strava_credentials',
    'user_memories',
    'user_goals',
    'workout_features'
  ];
begin
  perform _test_set_user(user_b);
  foreach tbl in array user_owned_tables loop
    execute format(
      'select count(*) from %I where user_id = %L', tbl, '11111111-1111-1111-1111-111111111111'
    ) into leak_count;
    if leak_count > 0 then
      raise warning 'LEAK: user B can read % of user A''s rows in table %', leak_count, tbl;
    else
      raise notice 'ISOLATION OK: %', tbl;
    end if;
  end loop;
end $$;

-- ---- CHECK: no user-owned table carries the auth.uid() IS NULL bypass. ----
-- This pattern (a historical repo convention) makes a policy read as "allow"
-- for unauthenticated/service contexts. A later migration dropped many, but
-- verify none remain on user-owned tables.
select
  schemaname, tablename, policyname,
  'REVIEW: policy still uses auth.uid() IS NULL bypass' as flag
from pg_policies
where schemaname = 'public'
  and qual ilike '%auth.uid() is null%';

rollback;  -- never persist test data
