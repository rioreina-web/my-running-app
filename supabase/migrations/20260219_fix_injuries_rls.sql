-- Fix injuries RLS policies to allow pre-auth access
-- Matches the pattern used by training_logs and other tables
-- When auth is fully enabled, auth.uid() IS NULL check becomes irrelevant

DROP POLICY IF EXISTS "Users can view their own injuries" ON injuries;
DROP POLICY IF EXISTS "Users can insert their own injuries" ON injuries;
DROP POLICY IF EXISTS "Users can update their own injuries" ON injuries;
DROP POLICY IF EXISTS "Users can delete their own injuries" ON injuries;

CREATE POLICY "Users can view their own injuries" ON injuries
    FOR SELECT USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can insert their own injuries" ON injuries
    FOR INSERT WITH CHECK (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can update their own injuries" ON injuries
    FOR UPDATE USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can delete their own injuries" ON injuries
    FOR DELETE USING (auth.uid()::text = user_id OR auth.uid() IS NULL);
