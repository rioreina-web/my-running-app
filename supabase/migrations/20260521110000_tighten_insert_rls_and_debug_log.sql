-- ============================================================================
-- Tighten over-permissive INSERT policies + enable RLS on debug_coach_log.
--
-- Findings (Supabase advisors 0013_rls_disabled_in_public,
-- 0024_permissive_rls_policy):
--   * public.debug_coach_log has RLS disabled entirely (ERROR) — anyone with
--     the anon key can read/write it. Violates the project's hard rule #1.
--   * Several tables ship an INSERT policy with `WITH CHECK (true)`, so an
--     authenticated user can insert rows attributed to OTHER users
--     (forge fitness history, usage records, race intel, weekly reports).
--
-- Service-role edge functions are unaffected: the service_role bypasses RLS,
-- so the real insert paths (race-intel, weekly-coaching-report, usage
-- tracking in transcribe/training-analysis/fitness-predictor) keep working.
-- The only insert path these scoped checks govern is direct client inserts —
-- e.g. iOS backup-restore into fitness_snapshots, which restores the user's
-- OWN rows and therefore still passes (user_id = auth.uid()).
--
-- NOT fully addressed (flagged for product decision):
--   * blog_posts still lets ANY authenticated user author a post; we only
--     stop them forging someone else's author_id. Admin-gating is a separate
--     call.
-- ============================================================================

BEGIN;

-- ── debug_coach_log: enable RLS (service-role writer bypasses; deny public) ──
ALTER TABLE public.debug_coach_log ENABLE ROW LEVEL SECURITY;

-- ── fitness_snapshots: owner-scoped INSERT ───────────────────────────────────
DROP POLICY IF EXISTS "auth_insert_own_snapshots" ON public.fitness_snapshots;
CREATE POLICY "auth_insert_own_snapshots" ON public.fitness_snapshots
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid()::text);

-- ── race_intel: owner-scoped INSERT ──────────────────────────────────────────
DROP POLICY IF EXISTS "auth_insert_own_intel" ON public.race_intel;
CREATE POLICY "auth_insert_own_intel" ON public.race_intel
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid()::text);

-- ── weekly_coaching_reports: owner-scoped INSERT ─────────────────────────────
DROP POLICY IF EXISTS "auth_insert_own_reports" ON public.weekly_coaching_reports;
CREATE POLICY "auth_insert_own_reports" ON public.weekly_coaching_reports
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid()::text);

-- ── usage_tracking: drop redundant always-true policy. The existing
--    "Users can insert own usage" already enforces ownership (and allows the
--    auth.uid() IS NULL service path), so this one only weakened it. ─────────
DROP POLICY IF EXISTS "auth_insert_usage" ON public.usage_tracking;

-- ── content_library: RAG/content table with no owner column and no client
--    insert path. Make it service-role-only by removing the open policy
--    (service_role bypasses RLS, so admin/edge inserts continue). ───────────
DROP POLICY IF EXISTS "Allow content inserts" ON public.content_library;

-- ── blog_posts: stop authors forging another user's author_id. Does NOT
--    restrict who may author — see header note. ─────────────────────────────
DROP POLICY IF EXISTS "Authenticated users can insert posts" ON public.blog_posts;
CREATE POLICY "Authenticated users can insert posts" ON public.blog_posts
    FOR INSERT TO authenticated
    WITH CHECK (author_id = auth.uid()::text);

COMMIT;
