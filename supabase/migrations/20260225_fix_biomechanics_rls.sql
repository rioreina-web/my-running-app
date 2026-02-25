-- Fix biomechanics_analyses RLS policies to include auth.uid() IS NULL fallback
-- matching the pattern used by all other tables (see 20260221_fix_all_rls_fallbacks.sql)

DROP POLICY IF EXISTS "Users can view their own analyses" ON biomechanics_analyses;
DROP POLICY IF EXISTS "Users can insert their own analyses" ON biomechanics_analyses;
DROP POLICY IF EXISTS "Users can update their own analyses" ON biomechanics_analyses;
DROP POLICY IF EXISTS "Users can delete their own analyses" ON biomechanics_analyses;

CREATE POLICY "Users can view their own analyses" ON biomechanics_analyses
    FOR SELECT USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can insert their own analyses" ON biomechanics_analyses
    FOR INSERT WITH CHECK (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can update their own analyses" ON biomechanics_analyses
    FOR UPDATE USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can delete their own analyses" ON biomechanics_analyses
    FOR DELETE USING (auth.uid()::text = user_id OR auth.uid() IS NULL);
