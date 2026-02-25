-- ============================================================================
-- PRODUCTION AUTH SECURITY MIGRATION
-- ============================================================================
-- Adds user_id columns to tables missing them (nullable for existing data)
-- Replaces USING(true) RLS with auth.uid()-based policies
-- Restricts storage bucket access to authenticated users
-- ============================================================================


-- 1. ADD user_id TO TABLES MISSING IT
-- ====================================

ALTER TABLE training_logs ADD COLUMN IF NOT EXISTS user_id TEXT;
CREATE INDEX IF NOT EXISTS idx_training_logs_user_id ON training_logs(user_id);

ALTER TABLE conversations ADD COLUMN IF NOT EXISTS user_id TEXT;
CREATE INDEX IF NOT EXISTS idx_conversations_user_id ON conversations(user_id);

ALTER TABLE user_goals ADD COLUMN IF NOT EXISTS user_id TEXT;
CREATE INDEX IF NOT EXISTS idx_user_goals_user_id ON user_goals(user_id);

ALTER TABLE scheduled_workouts ADD COLUMN IF NOT EXISTS user_id TEXT;
CREATE INDEX IF NOT EXISTS idx_scheduled_workouts_user_id ON scheduled_workouts(user_id);


-- 2. ENABLE RLS ON TABLES THAT WERE MISSING IT
-- ===============================================

DO $$ BEGIN
    ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

DO $$ BEGIN
    ALTER TABLE user_memories ENABLE ROW LEVEL SECURITY;
EXCEPTION WHEN undefined_table THEN NULL;
END $$;


-- 3. DROP OLD PERMISSIVE POLICIES
-- =================================

DROP POLICY IF EXISTS "Allow all access" ON training_logs;
DROP POLICY IF EXISTS "Allow all access to conversations" ON conversations;
DROP POLICY IF EXISTS "Allow all operations on user_goals" ON user_goals;
DROP POLICY IF EXISTS "Allow all operations on training_plans" ON training_plans;
DROP POLICY IF EXISTS "Allow all operations on scheduled_workouts" ON scheduled_workouts;
DROP POLICY IF EXISTS "Allow all operations on usage_tracking" ON usage_tracking;
DROP POLICY IF EXISTS "Allow all operations on user_tiers" ON user_tiers;


-- 4. CREATE NEW auth.uid() BASED POLICIES
-- ==========================================

-- training_logs (user_id TEXT)
CREATE POLICY "Users can view own training logs" ON training_logs
    FOR SELECT USING (user_id = auth.uid()::text OR user_id IS NULL);

CREATE POLICY "Users can insert own training logs" ON training_logs
    FOR INSERT WITH CHECK (user_id = auth.uid()::text OR user_id IS NULL);

CREATE POLICY "Users can update own training logs" ON training_logs
    FOR UPDATE USING (user_id = auth.uid()::text OR user_id IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR user_id IS NULL);

CREATE POLICY "Users can delete own training logs" ON training_logs
    FOR DELETE USING (user_id = auth.uid()::text OR user_id IS NULL);

-- conversations (user_id TEXT)
CREATE POLICY "Users can view own conversations" ON conversations
    FOR SELECT USING (user_id = auth.uid()::text OR user_id IS NULL);

CREATE POLICY "Users can insert own conversations" ON conversations
    FOR INSERT WITH CHECK (user_id = auth.uid()::text OR user_id IS NULL);

CREATE POLICY "Users can update own conversations" ON conversations
    FOR UPDATE USING (user_id = auth.uid()::text OR user_id IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR user_id IS NULL);

-- user_goals (user_id TEXT)
CREATE POLICY "Users can manage own goals" ON user_goals
    FOR ALL USING (user_id = auth.uid()::text OR user_id IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR user_id IS NULL);

-- training_plans (user_id TEXT, already exists)
CREATE POLICY "Users can manage own plans" ON training_plans
    FOR ALL USING (user_id = auth.uid()::text)
    WITH CHECK (user_id = auth.uid()::text);

-- scheduled_workouts (user_id TEXT, newly added)
CREATE POLICY "Users can manage own scheduled workouts" ON scheduled_workouts
    FOR ALL USING (user_id = auth.uid()::text OR user_id IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR user_id IS NULL);

-- user_profiles (user_id TEXT, already exists)
DO $$ BEGIN
    CREATE POLICY "Users can manage own profile" ON user_profiles
        FOR ALL USING (user_id = auth.uid()::text)
        WITH CHECK (user_id = auth.uid()::text);
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- user_memories (user_id TEXT, already exists)
DO $$ BEGIN
    CREATE POLICY "Users can manage own memories" ON user_memories
        FOR ALL USING (user_id = auth.uid()::text)
        WITH CHECK (user_id = auth.uid()::text);
EXCEPTION WHEN undefined_table THEN NULL;
END $$;

-- usage_tracking (user_id UUID)
CREATE POLICY "Users can view own usage" ON usage_tracking
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can insert own usage" ON usage_tracking
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- user_tiers (user_id UUID, primary key)
CREATE POLICY "Users can view own tier" ON user_tiers
    FOR SELECT USING (user_id = auth.uid());

-- coaching_documents: keep existing "Allow all access" (shared reference data)
-- content_library: keep existing policies (shared admin content)


-- 5. RESTRICT STORAGE POLICIES
-- ==============================

-- Drop existing overly permissive training-memos policies
DROP POLICY IF EXISTS "Allow public uploads" ON storage.objects;
DROP POLICY IF EXISTS "Allow public reads" ON storage.objects;
DROP POLICY IF EXISTS "Allow public updates" ON storage.objects;
DROP POLICY IF EXISTS "Allow public deletes" ON storage.objects;

-- Authenticated users can only access files in their own folder
-- Folder structure: training-memos/{user_id}/{filename}
CREATE POLICY "Auth users upload to own folder" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'training-memos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Auth users read own files" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'training-memos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Auth users update own files" ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'training-memos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

CREATE POLICY "Auth users delete own files" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'training-memos'
        AND (storage.foldername(name))[1] = auth.uid()::text
    );

-- Service role (used by process-training-memo webhook) bypasses RLS automatically
-- Content-videos bucket: keep existing public read + admin write policies
