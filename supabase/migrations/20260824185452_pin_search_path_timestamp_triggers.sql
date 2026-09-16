-- ============================================================================
-- Pin search_path on the trivial timestamp-trigger functions.
--
-- Supabase advisor `function_search_path_mutable` flags 32 functions in
-- public. A function without a pinned search_path resolves unqualified names
-- through whatever the caller's path happens to be; combined with SECURITY
-- DEFINER that is a privilege-escalation shape, and it is untidy even without.
--
-- This migration handles ONLY the 14 that are provably trivial: every one of
-- them is exactly `NEW.<col> := now(); RETURN NEW;` (set_coachable_moment_
-- handled_at also branches on NEW/OLD.status). They reference no table, no
-- type, and no extension — just `now()`, which lives in pg_catalog and is
-- always implicitly on the path. Pinning to '' therefore cannot change their
-- behaviour, and it makes any future edit that DOES reference a table fail
-- loudly rather than resolve through a caller-controlled path.
--
-- The remaining ~18 flagged functions are deliberately NOT touched here.
-- `match_coaching_documents` (pgvector operators), the `heat_*` family,
-- `pace_segments_from_laps`, `effective_pace_view`, `claim_athlete_state_
-- rebuild` and the `cleanup_*` jobs all resolve real tables or extension
-- functions, so each needs its own schema-qualification pass and its own
-- verification. Doing them blind in a batch is how you break a cron job.
-- ============================================================================

BEGIN;

ALTER FUNCTION public.set_coachable_moment_handled_at()          SET search_path = '';
ALTER FUNCTION public.touch_athlete_signature_observations()     SET search_path = '';
ALTER FUNCTION public.update_athlete_settings_timestamp()        SET search_path = '';
ALTER FUNCTION public.update_biomechanics_timestamp()            SET search_path = '';
ALTER FUNCTION public.update_daily_coaching_reads_timestamp()    SET search_path = '';
ALTER FUNCTION public.update_form_checks_timestamp()             SET search_path = '';
ALTER FUNCTION public.update_injuries_timestamp()                SET search_path = '';
ALTER FUNCTION public.update_plan_templates_timestamp()          SET search_path = '';
ALTER FUNCTION public.update_scheduled_workouts_updated_at()     SET search_path = '';
ALTER FUNCTION public.update_training_plans_updated_at()         SET search_path = '';
ALTER FUNCTION public.update_user_goals_updated_at()             SET search_path = '';
ALTER FUNCTION public.update_user_tiers_updated_at()             SET search_path = '';
ALTER FUNCTION public.update_weekly_coaching_reports_timestamp() SET search_path = '';
ALTER FUNCTION public.update_workout_templates_timestamp()       SET search_path = '';

COMMIT;
