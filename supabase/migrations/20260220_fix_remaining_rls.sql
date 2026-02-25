-- Fix RLS policies for tables missing the auth.uid() IS NULL fallback.
-- Needed because auth is currently disabled (Apple Developer Program pending).
-- Matches the pattern used by training_logs, user_goals, and injuries.

-- training_plans
DROP POLICY IF EXISTS "Users can manage own plans" ON training_plans;
CREATE POLICY "Users can manage own plans" ON training_plans
    FOR ALL USING (user_id = auth.uid()::text OR auth.uid() IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);

-- user_profiles
DO $$ BEGIN
    DROP POLICY IF EXISTS "Users can manage own profile" ON user_profiles;
    CREATE POLICY "Users can manage own profile" ON user_profiles
        FOR ALL USING (user_id = auth.uid()::text OR auth.uid() IS NULL)
        WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- user_memories
DO $$ BEGIN
    DROP POLICY IF EXISTS "Users can manage own memories" ON user_memories;
    CREATE POLICY "Users can manage own memories" ON user_memories
        FOR ALL USING (user_id = auth.uid()::text OR auth.uid() IS NULL)
        WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- usage_tracking
DROP POLICY IF EXISTS "Users can view own usage" ON usage_tracking;
DROP POLICY IF EXISTS "Users can insert own usage" ON usage_tracking;
CREATE POLICY "Users can view own usage" ON usage_tracking
    FOR SELECT USING (user_id = auth.uid() OR auth.uid() IS NULL);
CREATE POLICY "Users can insert own usage" ON usage_tracking
    FOR INSERT WITH CHECK (user_id = auth.uid() OR auth.uid() IS NULL);
