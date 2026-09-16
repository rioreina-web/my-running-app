-- ============================================================================
-- Coach SELECT policy for athlete_plan_subscriptions.
--
-- FOUND: `athlete_plan_subscriptions` has no read policy for coaches at all —
-- only the athlete's own row ("auth_athlete_view_subs") and service-role. The
-- coach portal's edit-plan gate (src/app/(app)/coach-portal/athletes/[id]/
-- edit-plan/page.tsx) runs this exact join, under the COACH's own session
-- (not service-role):
--
--   from("athlete_plan_subscriptions")
--     .select("id, plan_template:plan_templates!inner(coach_id)")
--     .eq("athlete_user_id", id).eq("status", "active")
--     .eq("plan_template.coach_id", coachProfile.id)
--
-- For a PostgREST embed to return a row, the BASE table (here,
-- athlete_plan_subscriptions) must itself be readable under RLS first —
-- readability of the joined table alone is not enough. With no coach policy
-- on the base table, this query returns [] for every coach, every time, and
-- the page 404s via notFound(). This predates plan-edit; found while wiring
-- plan-edit's own (working, tested) coach-ownership check into a live
-- browser session against this page and reproducing a 200-with-empty-array
-- response from the coach's real, RLS-scoped session.
--
-- FIX: mirror plan_templates' own policy shape (coach_id = current_coach_id(),
-- the SECURITY DEFINER helper from 20260311120000_fix_coach_rls_recursion.sql
-- — never a raw subquery against coach_profiles, which is what caused the
-- original recursion). This subqueries plan_templates, a different table in
-- a single direction (athlete_plan_subscriptions -> plan_templates), so it
-- does not reintroduce the A<->B cycle that migration fixed.
-- ============================================================================

CREATE POLICY "auth_coach_view_subs" ON public.athlete_plan_subscriptions
    FOR SELECT
    USING (
        plan_template_id IN (
            SELECT id FROM public.plan_templates WHERE coach_id = current_coach_id()
        )
    );
