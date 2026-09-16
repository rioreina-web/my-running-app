-- 2026-09-03 security audit — database follow-ups.
--
-- Everything here was verified against the LIVE project (aqdijapxmjqaetursrde)
-- with pg_policies / pg_proc queries and the Supabase security advisor on
-- 2026-09-03. It is idempotent and skips objects that don't exist, so it is
-- safe on a fresh local stack as well as on prod.
--
-- 1. current_coach_id() is SECURITY DEFINER and callable by `anon` via
--    /rest/v1/rpc. It only ever returns the caller's own coach id (null for
--    anon), so this is hygiene rather than a leak — but anon can never be a
--    coach and the advisor flags it on every run.
-- 2. Ten SECURITY DEFINER *trigger* functions still carry the default PUBLIC
--    EXECUTE grant. PostgREST does not expose trigger-returning functions, so
--    they are not reachable today; revoking closes the door if that ever
--    changes and clears ten advisor warnings.
-- 3. Eighteen functions run with a role-mutable search_path (advisor lint
--    0011). Pin them to `public, pg_temp` — their bodies reference public
--    tables unqualified, so the pg_catalog-only pin used elsewhere would
--    break them. This is the same treatment 20260824185452 gave the
--    timestamp triggers.
--
-- Not done here, on purpose (needs a product/ops decision — see
-- docs/security-audit-2026-09-03.md):
--   * ALTER DEFAULT PRIVILEGES ... REVOKE EXECUTE ON FUNCTIONS — would make
--     every future RPC opt-in. Right call long-term, but it changes the
--     developer workflow, so it is documented rather than applied.
--   * Leaked-password protection, password length/complexity — Auth
--     dashboard settings, not SQL.

BEGIN;

-- ── 1 + 2. EXECUTE grants on SECURITY DEFINER functions ─────────────────────
DO $$
DECLARE
    fn text;
BEGIN
    -- current_coach_id(): drop for anon, keep for authenticated.
    --
    -- The revoke must name PUBLIC, not just anon. Postgres grants function
    -- EXECUTE to PUBLIC by default, so `REVOKE ... FROM anon` leaves anon
    -- holding the privilege *through PUBLIC* and changes nothing — which is
    -- what the advisor's "Public Can Execute SECURITY DEFINER Function" lint
    -- is actually reporting. (Verified by executing this migration against a
    -- real PostgreSQL 16: the anon-only revoke asserted FAIL.)
    --
    -- authenticated and service_role are then re-granted explicitly, because
    -- revoking PUBLIC would otherwise take the privilege from them too. That
    -- matters here in a way it does not for the trigger functions below:
    -- current_coach_id() is called inside the USING clauses of every
    -- coach-scoped RLS policy, and policy expressions are evaluated as the
    -- querying role. Without EXECUTE, `authenticated` would get "permission
    -- denied for function current_coach_id" on every coach query.
    IF to_regprocedure('public.current_coach_id()') IS NOT NULL THEN
        EXECUTE 'REVOKE EXECUTE ON FUNCTION public.current_coach_id() FROM PUBLIC, anon';
        EXECUTE 'GRANT EXECUTE ON FUNCTION public.current_coach_id() TO authenticated, service_role';
    END IF;

    -- All twelve below are trigger functions (RETURNS trigger), so they are
    -- not callable through PostgREST anyway, and revoking EXECUTE does not
    -- stop their triggers firing: PostgreSQL checks EXECUTE on a trigger
    -- function at CREATE TRIGGER time, not on each fire. Verified against a
    -- real PostgreSQL 16 — an INSERT as `authenticated`, with EXECUTE revoked
    -- from PUBLIC/anon/authenticated, still fired the trigger.
    FOREACH fn IN ARRAY ARRAY[
        'public.enforce_watch_athlete_columns()',
        'public.enqueue_rpe_extraction()',
        'public.enqueue_workout_parse()',
        'public.enqueue_workout_parse_from_note()',
        'public.fn_complete_voice_job_on_row_complete()',
        'public.fn_enqueue_coachable_moment_evaluation()',
        'public.fn_enqueue_daily_read_workout_rerender()',
        'public.fn_enqueue_workout_insight()',
        'public.fn_trigger_reconcile_log()',
        'public.mirror_training_log_to_workout_notes()',
        'public.sync_workout_laps_from_streams()',
        'public.trigger_voice_log_processing()'
    ] LOOP
        IF to_regprocedure(fn) IS NOT NULL THEN
            EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
        END IF;
    END LOOP;
END $$;

-- ── 3. Pin role-mutable search_path ─────────────────────────────────────────
DO $$
DECLARE
    fn text;
BEGIN
    FOREACH fn IN ARRAY ARRAY[
        'public.cleanup_stuck_processing()',
        'public.cleanup_expired_memories()',
        'public.cleanup_stale_pending()',
        'public.match_coaching_documents(text, integer, text)',
        'public.claim_athlete_state_rebuild(text, integer, integer)',
        'public.effective_pace_view(text)',
        'public.set_pace_view_default(text)',
        'public.increment_subscriber_count(uuid)',
        'public.training_logs_ensure_external_id()',
        'public.pace_segments_from_laps(jsonb, numeric, numeric)',
        'public.heat_composite_score(numeric, numeric)',
        'public.heat_adjustment_pct(numeric, numeric)',
        'public.heat_category_for(numeric)',
        'public.heat_dew_multiplier(numeric)',
        'public.heat_rep_length_factor(numeric)',
        'public.heat_rep_length_factor_for_lap(numeric, boolean)',
        'public.heat_effective_pct(numeric, numeric, numeric)',
        'public.heat_intensity_factor(numeric, numeric)'
    ] LOOP
        IF to_regprocedure(fn) IS NOT NULL THEN
            EXECUTE format('ALTER FUNCTION %s SET search_path = public, pg_temp', fn);
        END IF;
    END LOOP;
END $$;

COMMIT;
