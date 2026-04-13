-- ============================================================================
-- Migration: Lock Down RLS Policies
-- Date: 2026-03-13
--
-- Replaces all USING(true), WITH CHECK(true), and auth.uid() IS NULL
-- fallback policies with strict user_id = auth.uid()::text enforcement.
--
-- PREREQUISITE: All existing rows must have user_id populated.
-- Run backfill before applying this migration.
-- ============================================================================

-- ============================================================================
-- STEP 1: Drop all permissive USING(true) policies
-- ============================================================================

-- training_logs
DROP POLICY IF EXISTS "Allow all access" ON training_logs;

-- user_goals
DROP POLICY IF EXISTS "Allow all operations on user_goals" ON user_goals;

-- usage_tracking / user_tiers
DROP POLICY IF EXISTS "Allow all operations on usage_tracking" ON usage_tracking;
DROP POLICY IF EXISTS "Allow all operations on user_tiers" ON user_tiers;

-- content_library
DROP POLICY IF EXISTS "Allow content inserts" ON content_library;
DROP POLICY IF EXISTS "Allow content updates" ON content_library;

-- training_plans
DROP POLICY IF EXISTS "Allow all operations on training_plans" ON training_plans;

-- scheduled_workouts
DROP POLICY IF EXISTS "Allow all operations on scheduled_workouts" ON scheduled_workouts;

-- blog_posts
DROP POLICY IF EXISTS "Authenticated users can insert posts" ON blog_posts;
DROP POLICY IF EXISTS "Authenticated users can update posts" ON blog_posts;

-- coaching_documents
DROP POLICY IF EXISTS "Allow all access to coaching_documents" ON coaching_documents;

-- conversations
DROP POLICY IF EXISTS "Allow all access to conversations" ON conversations;

-- ============================================================================
-- STEP 2: Drop all auth.uid() IS NULL fallback policies
-- ============================================================================

-- training_logs (from 20260221_fix_all_rls_fallbacks.sql)
DROP POLICY IF EXISTS "Users can view own training logs" ON training_logs;
DROP POLICY IF EXISTS "Users can insert own training logs" ON training_logs;
DROP POLICY IF EXISTS "Users can update own training logs" ON training_logs;
DROP POLICY IF EXISTS "Users can delete own training logs" ON training_logs;

-- conversations (from 20260221)
DROP POLICY IF EXISTS "Users can view own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can insert own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can update own conversations" ON conversations;

-- user_goals (from 20260221)
DROP POLICY IF EXISTS "Users can manage own goals" ON user_goals;

-- scheduled_workouts (from 20260221)
DROP POLICY IF EXISTS "Users can view own scheduled workouts" ON scheduled_workouts;
DROP POLICY IF EXISTS "Users can insert own scheduled workouts" ON scheduled_workouts;
DROP POLICY IF EXISTS "Users can update own scheduled workouts" ON scheduled_workouts;
DROP POLICY IF EXISTS "Users can delete own scheduled workouts" ON scheduled_workouts;

-- training_plans (from 20260220)
DROP POLICY IF EXISTS "Users can view own training plans" ON training_plans;
DROP POLICY IF EXISTS "Users can insert own training plans" ON training_plans;
DROP POLICY IF EXISTS "Users can update own training plans" ON training_plans;
DROP POLICY IF EXISTS "Users can delete own training plans" ON training_plans;

-- user_profiles (from 20260220)
DROP POLICY IF EXISTS "Users can manage own profile" ON user_profiles;

-- user_memories (from 20260220)
DROP POLICY IF EXISTS "Users can manage own memories" ON user_memories;

-- usage_tracking (from 20260220)
DROP POLICY IF EXISTS "Users can view own usage" ON usage_tracking;
DROP POLICY IF EXISTS "Users can insert own usage" ON usage_tracking;

-- injuries (from 20260219)
DROP POLICY IF EXISTS "Users can view their own injuries" ON injuries;
DROP POLICY IF EXISTS "Users can insert their own injuries" ON injuries;
DROP POLICY IF EXISTS "Users can update their own injuries" ON injuries;
DROP POLICY IF EXISTS "Users can delete their own injuries" ON injuries;

-- biomechanics_analyses (from 20260225)
DROP POLICY IF EXISTS "Users can view their own analyses" ON biomechanics_analyses;
DROP POLICY IF EXISTS "Users can insert their own analyses" ON biomechanics_analyses;
DROP POLICY IF EXISTS "Users can update their own analyses" ON biomechanics_analyses;
DROP POLICY IF EXISTS "Users can delete their own analyses" ON biomechanics_analyses;

-- form_checks (from 20260226)
DROP POLICY IF EXISTS "Users can view their own form checks" ON form_checks;
DROP POLICY IF EXISTS "Users can insert their own form checks" ON form_checks;
DROP POLICY IF EXISTS "Users can update their own form checks" ON form_checks;
DROP POLICY IF EXISTS "Users can delete their own form checks" ON form_checks;

-- fitness_snapshots (from 20260228)
DROP POLICY IF EXISTS "Users can view their own fitness snapshots" ON fitness_snapshots;
DROP POLICY IF EXISTS "Users can insert their own fitness snapshots" ON fitness_snapshots;
DROP POLICY IF EXISTS "Users can update their own fitness snapshots" ON fitness_snapshots;

-- weekly_coaching_reports (from 20260306)
DROP POLICY IF EXISTS "Users can view their own weekly reports" ON weekly_coaching_reports;
DROP POLICY IF EXISTS "Users can insert their own weekly reports" ON weekly_coaching_reports;
DROP POLICY IF EXISTS "Users can update their own weekly reports" ON weekly_coaching_reports;
DROP POLICY IF EXISTS "Users can delete their own weekly reports" ON weekly_coaching_reports;

-- coach tables (from 20260312 and 20260311)
DROP POLICY IF EXISTS "Users can view own coach profile" ON coach_profiles;
DROP POLICY IF EXISTS "Users can insert own coach profile" ON coach_profiles;
DROP POLICY IF EXISTS "Users can update own coach profile" ON coach_profiles;
DROP POLICY IF EXISTS "coach_profiles_select" ON coach_profiles;
DROP POLICY IF EXISTS "coach_profiles_insert" ON coach_profiles;
DROP POLICY IF EXISTS "coach_profiles_update" ON coach_profiles;

DROP POLICY IF EXISTS "Coaches can view their relationships" ON coach_athlete_relationships;
DROP POLICY IF EXISTS "Athletes can view their relationships" ON coach_athlete_relationships;
DROP POLICY IF EXISTS "Coaches can insert relationships" ON coach_athlete_relationships;
DROP POLICY IF EXISTS "Coaches can update relationships" ON coach_athlete_relationships;
DROP POLICY IF EXISTS "coach_relationships_select" ON coach_athlete_relationships;
DROP POLICY IF EXISTS "coach_relationships_insert" ON coach_athlete_relationships;
DROP POLICY IF EXISTS "coach_relationships_update" ON coach_athlete_relationships;

DROP POLICY IF EXISTS "Coaches can manage their templates" ON workout_templates;
DROP POLICY IF EXISTS "workout_templates_select" ON workout_templates;
DROP POLICY IF EXISTS "workout_templates_insert" ON workout_templates;
DROP POLICY IF EXISTS "workout_templates_update" ON workout_templates;
DROP POLICY IF EXISTS "workout_templates_delete" ON workout_templates;

DROP POLICY IF EXISTS "Coaches can manage their plan templates" ON plan_templates;
DROP POLICY IF EXISTS "plan_templates_select" ON plan_templates;
DROP POLICY IF EXISTS "plan_templates_insert" ON plan_templates;
DROP POLICY IF EXISTS "plan_templates_update" ON plan_templates;
DROP POLICY IF EXISTS "plan_templates_delete" ON plan_templates;

DROP POLICY IF EXISTS "Athletes can view their subscriptions" ON athlete_plan_subscriptions;
DROP POLICY IF EXISTS "athlete_subscriptions_select" ON athlete_plan_subscriptions;
DROP POLICY IF EXISTS "athlete_subscriptions_insert" ON athlete_plan_subscriptions;

-- ============================================================================
-- STEP 3: Ensure RLS is enabled on all tables
-- ============================================================================

ALTER TABLE training_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE usage_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_tiers ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE scheduled_workouts ENABLE ROW LEVEL SECURITY;
ALTER TABLE coaching_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE content_library ENABLE ROW LEVEL SECURITY;
ALTER TABLE blog_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_memories ENABLE ROW LEVEL SECURITY;
ALTER TABLE injuries ENABLE ROW LEVEL SECURITY;
ALTER TABLE biomechanics_analyses ENABLE ROW LEVEL SECURITY;
ALTER TABLE form_checks ENABLE ROW LEVEL SECURITY;
ALTER TABLE fitness_snapshots ENABLE ROW LEVEL SECURITY;
ALTER TABLE weekly_coaching_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE coach_athlete_relationships ENABLE ROW LEVEL SECURITY;
ALTER TABLE workout_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE athlete_plan_subscriptions ENABLE ROW LEVEL SECURITY;

-- ============================================================================
-- STEP 4: Create strict user-scoped policies (NO fallbacks)
-- ============================================================================

-- Helper: reusable function to get current coach_id without RLS recursion
-- (already exists from 20260311120000_fix_coach_rls_recursion.sql)

-- ── training_logs ──
CREATE POLICY "rls_training_logs_select" ON training_logs
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_training_logs_insert" ON training_logs
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_training_logs_update" ON training_logs
    FOR UPDATE USING (user_id = auth.uid()::text);
CREATE POLICY "rls_training_logs_delete" ON training_logs
    FOR DELETE USING (user_id = auth.uid()::text);

-- ── conversations ──
CREATE POLICY "rls_conversations_select" ON conversations
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_conversations_insert" ON conversations
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_conversations_update" ON conversations
    FOR UPDATE USING (user_id = auth.uid()::text);

-- ── user_goals ──
CREATE POLICY "rls_user_goals_all" ON user_goals
    FOR ALL USING (user_id = auth.uid()::text)
    WITH CHECK (user_id = auth.uid()::text);

-- ── usage_tracking ──
CREATE POLICY "rls_usage_tracking_select" ON usage_tracking
    FOR SELECT USING (user_id = auth.uid());
CREATE POLICY "rls_usage_tracking_insert" ON usage_tracking
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- ── user_tiers ──
CREATE POLICY "rls_user_tiers_select" ON user_tiers
    FOR SELECT USING (user_id = auth.uid());

-- ── training_plans ──
CREATE POLICY "rls_training_plans_select" ON training_plans
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_training_plans_insert" ON training_plans
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_training_plans_update" ON training_plans
    FOR UPDATE USING (user_id = auth.uid()::text);
CREATE POLICY "rls_training_plans_delete" ON training_plans
    FOR DELETE USING (user_id = auth.uid()::text);

-- ── scheduled_workouts ──
CREATE POLICY "rls_scheduled_workouts_select" ON scheduled_workouts
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_scheduled_workouts_insert" ON scheduled_workouts
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_scheduled_workouts_update" ON scheduled_workouts
    FOR UPDATE USING (user_id = auth.uid()::text);
CREATE POLICY "rls_scheduled_workouts_delete" ON scheduled_workouts
    FOR DELETE USING (user_id = auth.uid()::text);

-- ── user_profiles ──
CREATE POLICY "rls_user_profiles_all" ON user_profiles
    FOR ALL USING (user_id = auth.uid()::text)
    WITH CHECK (user_id = auth.uid()::text);

-- ── user_memories ──
CREATE POLICY "rls_user_memories_all" ON user_memories
    FOR ALL USING (user_id = auth.uid()::text)
    WITH CHECK (user_id = auth.uid()::text);

-- ── injuries ──
CREATE POLICY "rls_injuries_select" ON injuries
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_injuries_insert" ON injuries
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_injuries_update" ON injuries
    FOR UPDATE USING (user_id = auth.uid()::text);
CREATE POLICY "rls_injuries_delete" ON injuries
    FOR DELETE USING (user_id = auth.uid()::text);

-- ── biomechanics_analyses ──
CREATE POLICY "rls_biomechanics_select" ON biomechanics_analyses
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_biomechanics_insert" ON biomechanics_analyses
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_biomechanics_update" ON biomechanics_analyses
    FOR UPDATE USING (user_id = auth.uid()::text);
CREATE POLICY "rls_biomechanics_delete" ON biomechanics_analyses
    FOR DELETE USING (user_id = auth.uid()::text);

-- ── form_checks ──
CREATE POLICY "rls_form_checks_select" ON form_checks
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_form_checks_insert" ON form_checks
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_form_checks_update" ON form_checks
    FOR UPDATE USING (user_id = auth.uid()::text);
CREATE POLICY "rls_form_checks_delete" ON form_checks
    FOR DELETE USING (user_id = auth.uid()::text);

-- ── fitness_snapshots ──
CREATE POLICY "rls_fitness_snapshots_select" ON fitness_snapshots
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_fitness_snapshots_insert" ON fitness_snapshots
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_fitness_snapshots_update" ON fitness_snapshots
    FOR UPDATE USING (user_id = auth.uid()::text);

-- ── weekly_coaching_reports ──
CREATE POLICY "rls_weekly_reports_select" ON weekly_coaching_reports
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_weekly_reports_insert" ON weekly_coaching_reports
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_weekly_reports_update" ON weekly_coaching_reports
    FOR UPDATE USING (user_id = auth.uid()::text);
CREATE POLICY "rls_weekly_reports_delete" ON weekly_coaching_reports
    FOR DELETE USING (user_id = auth.uid()::text);

-- ── coaching_documents (read-only for authenticated users, admin writes via service role) ──
CREATE POLICY "rls_coaching_docs_select" ON coaching_documents
    FOR SELECT USING (auth.uid() IS NOT NULL);

-- ── content_library (public read for active content, admin writes via service role) ──
CREATE POLICY "rls_content_library_select" ON content_library
    FOR SELECT USING (is_active = true);

-- ── blog_posts (public read, admin writes via service role) ──
CREATE POLICY "rls_blog_posts_select" ON blog_posts
    FOR SELECT USING (true);

-- ── coach_profiles ──
CREATE POLICY "rls_coach_profiles_select" ON coach_profiles
    FOR SELECT USING (user_id = auth.uid()::text);
CREATE POLICY "rls_coach_profiles_insert" ON coach_profiles
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);
CREATE POLICY "rls_coach_profiles_update" ON coach_profiles
    FOR UPDATE USING (user_id = auth.uid()::text);

-- ── coach_athlete_relationships ──
-- Coaches can see their athletes, athletes can see their coaches
CREATE POLICY "rls_coach_rel_select" ON coach_athlete_relationships
    FOR SELECT USING (
        coach_user_id = auth.uid()::text OR athlete_user_id = auth.uid()::text
    );
CREATE POLICY "rls_coach_rel_insert" ON coach_athlete_relationships
    FOR INSERT WITH CHECK (coach_user_id = auth.uid()::text);
CREATE POLICY "rls_coach_rel_update" ON coach_athlete_relationships
    FOR UPDATE USING (coach_user_id = auth.uid()::text);

-- ── workout_templates (coach-owned via coach_profiles) ──
CREATE POLICY "rls_workout_templates_select" ON workout_templates
    FOR SELECT USING (
        coach_profile_id IN (
            SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text
        )
    );
CREATE POLICY "rls_workout_templates_insert" ON workout_templates
    FOR INSERT WITH CHECK (
        coach_profile_id IN (
            SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text
        )
    );
CREATE POLICY "rls_workout_templates_update" ON workout_templates
    FOR UPDATE USING (
        coach_profile_id IN (
            SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text
        )
    );
CREATE POLICY "rls_workout_templates_delete" ON workout_templates
    FOR DELETE USING (
        coach_profile_id IN (
            SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text
        )
    );

-- ── plan_templates (coach-owned via coach_profiles) ──
CREATE POLICY "rls_plan_templates_select" ON plan_templates
    FOR SELECT USING (
        coach_profile_id IN (
            SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text
        )
    );
CREATE POLICY "rls_plan_templates_insert" ON plan_templates
    FOR INSERT WITH CHECK (
        coach_profile_id IN (
            SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text
        )
    );
CREATE POLICY "rls_plan_templates_update" ON plan_templates
    FOR UPDATE USING (
        coach_profile_id IN (
            SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text
        )
    );
CREATE POLICY "rls_plan_templates_delete" ON plan_templates
    FOR DELETE USING (
        coach_profile_id IN (
            SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text
        )
    );

-- ── athlete_plan_subscriptions ──
CREATE POLICY "rls_athlete_subs_select" ON athlete_plan_subscriptions
    FOR SELECT USING (athlete_user_id = auth.uid()::text);
CREATE POLICY "rls_athlete_subs_insert" ON athlete_plan_subscriptions
    FOR INSERT WITH CHECK (athlete_user_id = auth.uid()::text);

-- ── Storage: restrict content-videos to admin only (service role writes) ──
DROP POLICY IF EXISTS "Allow video uploads" ON storage.objects;
DROP POLICY IF EXISTS "Videos are publicly viewable" ON storage.objects;

CREATE POLICY "rls_content_videos_read" ON storage.objects
    FOR SELECT USING (bucket_id = 'content-videos');
