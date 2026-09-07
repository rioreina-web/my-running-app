-- ============================================================================
-- Close unauthenticated INSERT into the public `content-videos` bucket.
--
-- Finding (live audit 2026-08-24): storage.objects carries
--
--     "Allow video uploads"  PERMISSIVE  INSERT  TO public
--     WITH CHECK (bucket_id = 'content-videos')
--
-- `public` includes `anon`, and `anon` holds INSERT on storage.objects. The
-- bucket is public:true with file_size_limit NULL and allowed_mime_types NULL.
-- Net effect: anyone holding the anon key -- it ships inside the iOS binary
-- and in the web bundle as NEXT_PUBLIC_SUPABASE_ANON_KEY, so treat it as
-- published -- could write unlimited files of any type and receive a public
-- *.supabase.co URL. That is storage/egress spend plus arbitrary content
-- (malware, phishing) served from the project domain. It is NOT a cross-user
-- data read: no SELECT is granted here.
--
-- THIS IS THE SECOND TIME. `20260313100000_lock_down_rls.sql` already dropped
-- this policy and IS recorded in supabase_migrations.schema_migrations, yet
-- the policy was live again on 2026-08-24 -- so it was re-created outside the
-- migration files (Storage policy UI is the likely path). A file-replay
-- contract test would have reported this bucket clean the whole time. If this
-- comes back a third time, the check has to run against pg_policies on the
-- live database, not against this directory.
--
-- Why service-role-only rather than an owner-folder check: `content-videos`
-- is the curated content library, not user data. Its objects live at
-- `strength/...` and `thumbnails/...` with owner NULL (service-role/dashboard
-- uploads). There is no per-user folder to scope to, unlike `training-memos`
-- / `plan-attachments` / `avatars`. Dropping every write policy leaves the
-- bucket writable only by service role, which bypasses RLS -- so dashboard
-- and admin uploads are unaffected.
--
-- Reads are unaffected: `rls_content_videos_read` (20260313100000) stays, and
-- public object URLs bypass RLS regardless.
-- ============================================================================

BEGIN;

DROP POLICY IF EXISTS "Allow video uploads" ON storage.objects;

-- Any other name the same permission could be hiding under.
DROP POLICY IF EXISTS "Videos are publicly writable" ON storage.objects;
DROP POLICY IF EXISTS "Allow content video uploads" ON storage.objects;

-- Backstop, independent of RLS: cap object size on the bucket. 200 MB clears
-- the largest object present (15.9 MB) with room for real content.
-- allowed_mime_types is deliberately left NULL -- the existing .mov is stored
-- as application/octet-stream, so any allowlist permissive enough to keep
-- current content working would not actually restrict anything.
UPDATE storage.buckets
   SET file_size_limit = 209715200
 WHERE id = 'content-videos';

COMMIT;
