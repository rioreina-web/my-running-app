-- ============================================================================
-- Drop broad public SELECT (list) policies on storage.objects.
--
-- Finding (Supabase security advisor 0025_public_bucket_allows_listing):
-- `training-memos`, `plan-attachments`, and `content-videos` are public
-- buckets that each carry a SELECT policy of the form
-- `bucket_id = '<bucket>'` for the `public` role. That policy lets any
-- client ENUMERATE every file in the bucket via the storage list API —
-- e.g. list all athletes' voice memos.
--
-- Public buckets do NOT need a SELECT policy for direct object-URL access:
-- the `/storage/v1/object/public/...` download path bypasses RLS. iOS reads
-- memos via getPublicURL (VoiceLogViewModel, OfflineQueue) which uses that
-- public path, and no app/web code calls `.list()` on these buckets, so
-- dropping these policies stops enumeration without breaking playback.
--
-- NOT addressed here (tracked separately): the `public`-role UPDATE and
-- DELETE policies on `training-memos` are unscoped (no owner check), which
-- lets anyone overwrite or delete any user's memo. Scoping those to the
-- object owner can affect the app's own edit/delete path and needs its own
-- verification, so it is intentionally left for a follow-up migration.
-- ============================================================================

BEGIN;

DROP POLICY IF EXISTS "Allow training memo reads" ON storage.objects;
DROP POLICY IF EXISTS "Allow public reads from plan-attachments" ON storage.objects;
DROP POLICY IF EXISTS "Videos are publicly viewable" ON storage.objects;

COMMIT;
