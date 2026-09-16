-- ============================================================================
-- Make user-data storage buckets PRIVATE (beta blocker C1, 2026-07-15).
--
-- `training-memos` (athletes' raw voice memos — health data) and
-- `plan-attachments` (uploaded plan files) were created with public = true
-- (20260126_storage_policies.sql, 20260227_plan_builder_setup.sql). Public
-- buckets serve objects at /storage/v1/object/public/... which BYPASSES RLS:
-- anyone holding a URL could download any athlete's memo with no login.
--
-- Consumer inventory (verified 2026-07-15) — why this breaks nothing:
--   * upload-voice-memo (edge fn)   — uploads with SERVICE ROLE; bypasses RLS.
--   * process-training-memo:470-485 — parses the storage path OUT of the
--     stored audio_url string, then service-role .download(path). Never
--     fetches the public URL. Unaffected.
--   * process-check-in:64-86        — same parse-then-service-role-download.
--   * iOS (VoiceLogViewModel, OfflineQueue, all views) — uses audio_url /
--     transcript_url ONLY as presence flags / passthrough strings. There is
--     no client-side playback or download anywhere. getPublicURL is pure
--     string construction and still works on a private bucket.
--   * plan-attachments — no active read/write code paths in iOS, web, or
--     edge functions (custom plan builder was cut).
--
-- The URL-shaped strings persisted in training_logs.audio_url /
-- transcript_url stay as-is: they are canonical identifiers that carry the
-- bucket + path (process-* functions depend on the
-- "/storage/v1/object/public/training-memos/" prefix to extract the path).
-- After this migration those URLs simply stop being fetchable without auth.
-- If client playback is ever built, use createSignedURL() — the owner-scoped
-- SELECT policies below let each user sign only their own files.
--
-- Policy cleanup: the four generations of training-memos policies
-- (20260126 public / 20260216 auth-scoped / 20260222 public regression /
-- 20260316 owner-scoped) each dropped their predecessor by name, but the
-- prod ledger has diverged before (see
-- docs/migration-ledger-reconciliation-2026-06-11.md) and the 2026-06-09
-- advisor still found policies that a clean replay says were dropped. So
-- this migration drops EVERY historical name and recreates the canonical
-- owner-scoped set, making the final state deterministic regardless of
-- which history actually ran.
-- ============================================================================

BEGIN;

-- ── 1. Flip the buckets private ─────────────────────────────────────────────
-- (One single-id statement per bucket; the guardrail contract test's replay
-- parser matches this exact form.)

UPDATE storage.buckets SET public = false WHERE id = 'training-memos';
UPDATE storage.buckets SET public = false WHERE id = 'plan-attachments';

-- ── 2. Drop every historical policy name for these buckets ─────────────────

-- Gen 1 (20260126): public role, bucket-only — the worst offenders. The
-- 2026-05 audit found the UPDATE/DELETE pair still live in prod.
DROP POLICY IF EXISTS "Allow public uploads" ON storage.objects;
DROP POLICY IF EXISTS "Allow public reads" ON storage.objects;
DROP POLICY IF EXISTS "Allow public updates" ON storage.objects;
DROP POLICY IF EXISTS "Allow public deletes" ON storage.objects;

-- Gen 2 (20260216): authenticated + owner-scoped.
DROP POLICY IF EXISTS "Auth users upload to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Auth users read own files" ON storage.objects;
DROP POLICY IF EXISTS "Auth users update own files" ON storage.objects;
DROP POLICY IF EXISTS "Auth users delete own files" ON storage.objects;

-- Gen 3 (20260222): public role, bucket-only regression.
DROP POLICY IF EXISTS "Allow training memo uploads" ON storage.objects;
DROP POLICY IF EXISTS "Allow training memo reads" ON storage.objects;
DROP POLICY IF EXISTS "Allow training memo updates" ON storage.objects;
DROP POLICY IF EXISTS "Allow training memo deletes" ON storage.objects;

-- Gen 4 (20260316): canonical owner-scoped set — dropped here and recreated
-- below (with a WITH CHECK added on UPDATE) so this migration is idempotent
-- and self-contained.
DROP POLICY IF EXISTS "Users upload to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Users read own files" ON storage.objects;
DROP POLICY IF EXISTS "Users update own files" ON storage.objects;
DROP POLICY IF EXISTS "Users delete own files" ON storage.objects;

-- plan-attachments (20260227): public-role INSERT (any anon could upload);
-- the public SELECT was already dropped by 20260609233540.
DROP POLICY IF EXISTS "Allow authenticated uploads to plan-attachments" ON storage.objects;
DROP POLICY IF EXISTS "Allow public reads from plan-attachments" ON storage.objects;

-- ── 3. Canonical owner-scoped policies: training-memos ─────────────────────
-- Paths are {user_id}/{uuid}.m4a (+ _transcript.txt). Service-role writers
-- (upload-voice-memo, process-training-memo) bypass RLS; these policies
-- govern direct client access (iOS check-in upload path, future signed-URL
-- playback).

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

-- ── 4. Canonical owner-scoped policies: plan-attachments ───────────────────
-- No active code writes here today; these define the contract for when plan
-- uploads return ({user_id}/... paths, owner-only access).
-- These three already exist in prod (created by an earlier plan-attachments
-- setup), so drop-then-recreate keeps the migration idempotent and re-runnable.
DROP POLICY IF EXISTS "Plan files: users upload to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Plan files: users read own files" ON storage.objects;
DROP POLICY IF EXISTS "Plan files: users delete own files" ON storage.objects;

CREATE POLICY "Plan files: users upload to own folder" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'plan-attachments'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Plan files: users read own files" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'plan-attachments'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Plan files: users delete own files" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'plan-attachments'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

COMMIT;
