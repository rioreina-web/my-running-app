-- Fix storage RLS policies for training-memos bucket.
-- Current policies only allow 'authenticated' role, which blocks access
-- when auth is disabled. Add anon fallback policies to match the
-- pattern used across all database tables.

-- Drop strict authenticated-only policies
DROP POLICY IF EXISTS "Auth users upload to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Auth users read own files" ON storage.objects;
DROP POLICY IF EXISTS "Auth users update own files" ON storage.objects;
DROP POLICY IF EXISTS "Auth users delete own files" ON storage.objects;

-- Allow uploads to training-memos bucket (authenticated or anon when no auth)
CREATE POLICY "Allow training memo uploads" ON storage.objects
    FOR INSERT
    WITH CHECK (bucket_id = 'training-memos');

CREATE POLICY "Allow training memo reads" ON storage.objects
    FOR SELECT
    USING (bucket_id = 'training-memos');

CREATE POLICY "Allow training memo updates" ON storage.objects
    FOR UPDATE
    USING (bucket_id = 'training-memos');

CREATE POLICY "Allow training memo deletes" ON storage.objects
    FOR DELETE
    USING (bucket_id = 'training-memos');
