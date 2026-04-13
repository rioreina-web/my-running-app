-- Fix CRITICAL security issue: storage RLS policies for training-memos bucket
-- were wide open — any authenticated user could read/write ANY user's audio files.
-- Now scoped so users can only access files in their own folder ({user_id}/...).

-- Drop the overly permissive policies
DROP POLICY IF EXISTS "Allow training memo uploads" ON storage.objects;
DROP POLICY IF EXISTS "Allow training memo reads" ON storage.objects;
DROP POLICY IF EXISTS "Allow training memo updates" ON storage.objects;
DROP POLICY IF EXISTS "Allow training memo deletes" ON storage.objects;

-- INSERT: user can only upload to their own folder
CREATE POLICY "Users upload to own folder" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'training-memos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- SELECT: user can only read their own files
CREATE POLICY "Users read own files" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'training-memos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- UPDATE: user can only update their own files
CREATE POLICY "Users update own files" ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'training-memos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- DELETE: user can only delete their own files
CREATE POLICY "Users delete own files" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'training-memos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );
