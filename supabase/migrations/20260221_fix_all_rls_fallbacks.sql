-- Fix all RLS policies to use auth.uid() IS NULL fallback instead of user_id IS NULL.
-- The old pattern (user_id IS NULL) only works when inserting rows without a user_id.
-- The correct pattern (auth.uid() IS NULL) allows access when there's no auth session,
-- regardless of whether the row has a user_id.

-- ==============================
-- training_logs
-- ==============================
DROP POLICY IF EXISTS "Users can view own training logs" ON training_logs;
DROP POLICY IF EXISTS "Users can insert own training logs" ON training_logs;
DROP POLICY IF EXISTS "Users can update own training logs" ON training_logs;
DROP POLICY IF EXISTS "Users can delete own training logs" ON training_logs;

CREATE POLICY "Users can view own training logs" ON training_logs
    FOR SELECT USING (user_id = auth.uid()::text OR auth.uid() IS NULL);

CREATE POLICY "Users can insert own training logs" ON training_logs
    FOR INSERT WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);

CREATE POLICY "Users can update own training logs" ON training_logs
    FOR UPDATE USING (user_id = auth.uid()::text OR auth.uid() IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);

CREATE POLICY "Users can delete own training logs" ON training_logs
    FOR DELETE USING (user_id = auth.uid()::text OR auth.uid() IS NULL);

-- ==============================
-- conversations
-- ==============================
DROP POLICY IF EXISTS "Users can view own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can insert own conversations" ON conversations;
DROP POLICY IF EXISTS "Users can update own conversations" ON conversations;

CREATE POLICY "Users can view own conversations" ON conversations
    FOR SELECT USING (user_id = auth.uid()::text OR auth.uid() IS NULL);

CREATE POLICY "Users can insert own conversations" ON conversations
    FOR INSERT WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);

CREATE POLICY "Users can update own conversations" ON conversations
    FOR UPDATE USING (user_id = auth.uid()::text OR auth.uid() IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);

-- ==============================
-- user_goals
-- ==============================
DROP POLICY IF EXISTS "Users can manage own goals" ON user_goals;

CREATE POLICY "Users can manage own goals" ON user_goals
    FOR ALL USING (user_id = auth.uid()::text OR auth.uid() IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);

-- ==============================
-- scheduled_workouts
-- ==============================
DROP POLICY IF EXISTS "Users can manage own scheduled workouts" ON scheduled_workouts;

CREATE POLICY "Users can manage own scheduled workouts" ON scheduled_workouts
    FOR ALL USING (user_id = auth.uid()::text OR auth.uid() IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);
