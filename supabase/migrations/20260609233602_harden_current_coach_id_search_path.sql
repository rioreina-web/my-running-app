-- ============================================================================
-- Harden current_coach_id(): pin search_path + schema-qualify table ref.
--
-- Background: current_coach_id() (from 20260311120000_fix_coach_rls_recursion)
-- is a SECURITY DEFINER helper used in coach-scoped RLS policies (hard rule
-- #6). It runs as its owner and bypasses RLS on coach_profiles — so an
-- unpinned search_path is a privilege-escalation surface: a caller who can
-- create an object earlier in the resolution path could shadow `coach_profiles`
-- and have the definer-privileged function read the wrong relation.
--
-- Fix: mirror the hardening convention already standardized in this repo
-- (cf. fn_enqueue_coachable_moment_evaluation, claim_coachable_moment_jobs):
--   * SET search_path = pg_catalog, pg_temp  — lock resolution down
--   * schema-qualify the table ref as public.coach_profiles
--
-- The pairing is mandatory: pinning search_path WITHOUT qualifying the table
-- is what broke fn_enqueue on 2026-05-15 (relation "..." does not exist,
-- aborting the parent INSERT — see
-- 20260520130000_fix_coachable_moment_enqueue_schema_qualification.sql).
-- auth.uid() is already schema-qualified, so it is unaffected.
--
-- Append-only (hard rule #5): this is a CREATE OR REPLACE, which preserves
-- the function's existing owner and all dependent RLS policies. Ownership
-- (should be postgres, not authenticator) is verified out-of-band against
-- the live DB, not altered here — an ALTER FUNCTION ... OWNER TO can fail
-- depending on the migration role's memberships.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION current_coach_id()
RETURNS UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = pg_catalog, pg_temp
AS $$
    SELECT id FROM public.coach_profiles WHERE user_id = auth.uid()::text LIMIT 1;
$$;

COMMIT;
