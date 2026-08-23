-- ============================================================================
-- Close the `training-memos` bucket.
--
-- Voice memos are the most sensitive data the product holds — injuries,
-- mental state, work stress, life context. The bucket has been `public = true`
-- since 20260126_storage_policies.sql, and iOS wrote `getPublicURL` results
-- into `training_logs.audio_url`.
--
-- A public bucket's `/storage/v1/object/public/...` route bypasses RLS
-- entirely, so the owner-scoped policies added in 20260316130000 never applied
-- to reads at all. Object paths are `{user_id}/training_memo_{unix_seconds}.m4a`
-- — a guessable path, not a capability URL.
--
-- Three things here:
--   1. Flip the bucket to private, so the public route stops serving objects
--      and the storage policies below actually govern access.
--   2. Replace the remaining unscoped `public`-role policies from
--      20260222_fix_storage_rls.sql. 20260609233540 dropped only the SELECT
--      one and explicitly deferred UPDATE/DELETE, which have been letting
--      anyone overwrite or delete any athlete's memo.
--   3. Normalize `audio_url` to a bare storage path. Once the bucket is
--      private those stored public URLs are dead links, and the path is what
--      every server-side reader actually wants.
--
-- Server-side readers (process-training-memo, process-check-in) download with
-- the service-role client, which bypasses bucket privacy — they keep working.
-- iOS never plays memos back; every `audioUrl` use is a `!= nil` check driving
-- a mic icon, so there is no client read path to migrate.
-- ============================================================================

BEGIN;

-- ── 1. Bucket becomes private ───────────────────────────────────────────────
UPDATE storage.buckets
SET public = false
WHERE id = 'training-memos';

-- ── 2. Owner-scoped object policies ─────────────────────────────────────────
-- Unscoped `public`-role policies from 20260222_fix_storage_rls.sql.
-- "Allow training memo reads" was already dropped by 20260609233540; the
-- others are dropped here. IF EXISTS keeps this idempotent either way.
DROP POLICY IF EXISTS "Allow training memo uploads" ON storage.objects;
DROP POLICY IF EXISTS "Allow training memo reads"   ON storage.objects;
DROP POLICY IF EXISTS "Allow training memo updates" ON storage.objects;
DROP POLICY IF EXISTS "Allow training memo deletes" ON storage.objects;

-- Recreate the owner-scoped set from 20260316130000. Dropping first makes this
-- migration safe to apply whether or not that one reached this environment —
-- the ledger has diverged before (docs/migration-ledger-reconciliation-2026-06-11.md).
DROP POLICY IF EXISTS "Users upload to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Users read own files"       ON storage.objects;
DROP POLICY IF EXISTS "Users update own files"     ON storage.objects;
DROP POLICY IF EXISTS "Users delete own files"     ON storage.objects;

CREATE POLICY "Users upload to own folder" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'training-memos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users read own files" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'training-memos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users update own files" ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'training-memos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    )
    WITH CHECK (
        bucket_id = 'training-memos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Users delete own files" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'training-memos'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

-- ── 3. Normalize audio_url to a bare storage path ───────────────────────────
-- `https://<proj>.supabase.co/storage/v1/object/public/training-memos/<path>`
-- becomes `<path>`. Guarded so it only touches rows in exactly that shape, and
-- re-running is a no-op (rewritten rows no longer match the WHERE clause).
--
-- `_shared/storage.ts` still parses the old shape, so a row restored from a
-- backup — or written by an app build older than this migration — keeps
-- resolving correctly.
UPDATE public.training_logs
SET audio_url = regexp_replace(
        split_part(audio_url, '/storage/v1/object/public/training-memos/', 2),
        '[?#].*$',
        ''
    )
WHERE audio_url IS NOT NULL
  AND position('/storage/v1/object/public/training-memos/' IN audio_url) > 0;

-- ── Verification ────────────────────────────────────────────────────────────
DO $$
DECLARE
    still_public   BOOLEAN;
    unscoped_count INT;
    bad_rows       INT;
BEGIN
    SELECT public INTO still_public
    FROM storage.buckets WHERE id = 'training-memos';

    IF still_public IS TRUE THEN
        RAISE EXCEPTION 'training-memos is still public after this migration';
    END IF;

    -- No policy on this bucket may remain that lacks an owner check.
    SELECT count(*) INTO unscoped_count
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename  = 'objects'
      AND policyname IN (
          'Allow training memo uploads',
          'Allow training memo reads',
          'Allow training memo updates',
          'Allow training memo deletes'
      );

    IF unscoped_count > 0 THEN
        RAISE EXCEPTION
            'Unscoped training-memos storage policies still present (% found)',
            unscoped_count;
    END IF;

    SELECT count(*) INTO bad_rows
    FROM public.training_logs
    WHERE audio_url IS NOT NULL
      AND position('/storage/v1/object/public/training-memos/' IN audio_url) > 0;

    IF bad_rows > 0 THEN
        RAISE EXCEPTION
            'audio_url normalization missed % row(s)', bad_rows;
    END IF;
END $$;

COMMIT;
