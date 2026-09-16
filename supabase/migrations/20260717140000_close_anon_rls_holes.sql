-- Close the anon-key RLS holes surfaced by the 2026-07-17 beta risk sweep.
--
-- The Supabase anon key ships inside the iOS app, so any policy that grants
-- access to role `anon` (either an explicit `auth.role() = 'anon'` clause or
-- the `OR auth.uid() IS NULL` fallback) is reachable by anyone who extracts
-- that key. The app requires an authenticated session everywhere, so the
-- `auth.uid() IS NULL` branch never serves a legitimate caller — it only
-- serves the attacker. service_role bypasses RLS (BYPASSRLS), so the
-- edge-function write paths are unaffected by tightening these.
--
-- This is the same fix the March lockdown (20260313100000_lock_down_rls.sql)
-- applied to the tables that existed then; these five were created afterward
-- and re-introduced the pattern by copy-paste. Verified against live
-- pg_policies before authoring (not against the CREATE migrations, which in
-- several cases were later superseded).
--
-- Policies are recreated `TO authenticated` so the anon role is excluded
-- explicitly, not just by predicate. Append-only per hard rule #5; reaches
-- prod only via `supabase db push` per hard rule #9.

-- ─────────────────────────────────────────────────────────────────────────
-- 1. athlete_settings — home_lat / home_lon / timezone (the known #11)
-- ─────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Athletes read own settings"   ON athlete_settings;
CREATE POLICY "Athletes read own settings" ON athlete_settings
    FOR SELECT TO authenticated
    USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "Athletes insert own settings" ON athlete_settings;
CREATE POLICY "Athletes insert own settings" ON athlete_settings
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "Athletes update own settings" ON athlete_settings;
CREATE POLICY "Athletes update own settings" ON athlete_settings
    FOR UPDATE TO authenticated
    USING (user_id = auth.uid()::text)
    WITH CHECK (user_id = auth.uid()::text);

-- ─────────────────────────────────────────────────────────────────────────
-- 2. coachable_moments — synthesized injury/mood/load observations
--    (anon could read ALL rows and flip their status)
-- ─────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Coaches view own coachable_moments"   ON coachable_moments;
CREATE POLICY "Coaches view own coachable_moments" ON coachable_moments
    FOR SELECT TO authenticated
    USING (coach_id = current_coach_id());

DROP POLICY IF EXISTS "Coaches update own coachable_moments" ON coachable_moments;
CREATE POLICY "Coaches update own coachable_moments" ON coachable_moments
    FOR UPDATE TO authenticated
    USING (coach_id = current_coach_id());

-- ─────────────────────────────────────────────────────────────────────────
-- 3. coach_athlete_relationships — self-enroll onto an arbitrary athlete
--    (removing the anon branch; the no-athlete-consent gap is tracked
--     separately and left as-is here to avoid changing the coach flow)
-- ─────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Coaches invite athletes" ON coach_athlete_relationships;
CREATE POLICY "Coaches invite athletes" ON coach_athlete_relationships
    FOR INSERT TO authenticated
    WITH CHECK (coach_id = current_coach_id());

-- ─────────────────────────────────────────────────────────────────────────
-- 4. athlete_plan_subscriptions — anon could forge a subscription naming
--    any athlete_user_id
-- ─────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Athletes subscribe to plans" ON athlete_plan_subscriptions;
CREATE POLICY "Athletes subscribe to plans" ON athlete_plan_subscriptions
    FOR INSERT TO authenticated
    WITH CHECK (athlete_user_id = auth.uid()::text);

-- ─────────────────────────────────────────────────────────────────────────
-- 5. usage_tracking — anon could inject usage/billing rows (user_id is uuid)
-- ─────────────────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Users can insert own usage" ON usage_tracking;
CREATE POLICY "Users can insert own usage" ON usage_tracking
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.uid());

-- Note: coach_workout_reads (20260717130000, still unpushed) carried the same
-- hole; it was fixed in place in its own migration since it is untracked and
-- has never reached prod — no separate block needed here.

-- ─────────────────────────────────────────────────────────────────────────
-- 6. SECURITY DEFINER dedup/merge RPCs — Postgres defaults EXECUTE to
--    PUBLIC, so both are callable via PostgREST by anyone holding the anon
--    key. dedupe_recent_training_logs is NOT user-scoped and bypasses RLS
--    (SECURITY DEFINER) — an anon caller can trigger a global delete sweep.
--    Revoke from anon + authenticated; service_role (cron / edge fns) keeps
--    access. Matches the 20260610230628 hardening pattern.
-- ─────────────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.dedupe_recent_training_logs(integer)  FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.merge_voice_orphan_into_run(uuid, uuid) FROM anon, authenticated;

-- Broader sweep (2026-07-17): other SECURITY DEFINER functions that PostgREST
-- exposes as anon-callable RPCs (non-trigger return types) and that enqueue
-- LLM work or mutate shared counters. Their real callers are pg_cron (runs as
-- postgres) or service-role edge functions (increment_subscriber_count ←
-- subscribe-to-plan, which uses the service-role key and so keeps EXECUTE).
-- Trigger functions (return type `trigger`) and the RLS helper current_coach_id()
-- are intentionally left executable by anon/authenticated — the former aren't
-- RPC-exposable, the latter only ever returns the caller's own coach_id.
REVOKE EXECUTE ON FUNCTION public.backfill_workout_insights(integer) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.enqueue_daily_reads()             FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.increment_subscriber_count(uuid)  FROM anon, authenticated;
