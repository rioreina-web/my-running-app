-- Allow anonymous uploads to training-memos bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('training-memos', 'training-memos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- Allow anyone to upload files
CREATE POLICY "Allow public uploads" ON storage.objects
FOR INSERT TO anon, authenticated
WITH CHECK (bucket_id = 'training-memos');

-- Allow anyone to read files (public bucket)
CREATE POLICY "Allow public reads" ON storage.objects
FOR SELECT TO anon, authenticated
USING (bucket_id = 'training-memos');

-- Allow anyone to update their files
CREATE POLICY "Allow public updates" ON storage.objects
FOR UPDATE TO anon, authenticated
USING (bucket_id = 'training-memos');

-- Allow anyone to delete files
CREATE POLICY "Allow public deletes" ON storage.objects
FOR DELETE TO anon, authenticated
USING (bucket_id = 'training-memos');
