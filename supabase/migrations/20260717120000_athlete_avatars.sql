-- ============================================================================
-- Athlete profile photos — private `avatars` bucket + athlete_settings.avatar_path
--
-- Adds an optional profile photo to the athlete profile (display_name + bio
-- shipped in 20260716140000). The image lives in Supabase Storage; the row
-- only holds the object path.
--
-- Security posture mirrors the 2026-07-15 buckets-private work: the bucket is
-- PRIVATE and access is owner-scoped by the first path segment
-- ({user_id}/avatar.jpg), exactly like `training-memos`. Display uses signed
-- URLs — the athlete signs their own file (owner SELECT policy); the coach
-- portal signs via the service-role admin client (already how it reads
-- athlete_state / body_mentions), so no coach SELECT policy on storage is
-- needed.
--
-- Append-only (hard rule #5); ships via `supabase db push` only (rule #9).
-- ============================================================================

-- ── 1. Path to the athlete's avatar object (NULL = no photo, show monogram) ──
ALTER TABLE athlete_settings
    ADD COLUMN IF NOT EXISTS avatar_path TEXT
        CHECK (avatar_path IS NULL OR char_length(avatar_path) <= 300);

COMMENT ON COLUMN athlete_settings.avatar_path IS
    'Storage object path of the athlete''s profile photo in the private '
    '`avatars` bucket, e.g. "<user_id>/avatar.jpg". NULL means no photo — '
    'surfaces fall back to the initials monogram. Display via signed URL.';

-- ── 2. Private avatars bucket ───────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', false)
ON CONFLICT (id) DO NOTHING;

-- ── 3. Owner-scoped RLS on the bucket (path = {user_id}/...) ────────────────
-- Mirrors the canonical training-memos policy set. Service-role writers/readers
-- (e.g. the coach portal signing a URL) bypass RLS; these govern the athlete's
-- own direct client access.
DROP POLICY IF EXISTS "Avatars: users upload to own folder" ON storage.objects;
DROP POLICY IF EXISTS "Avatars: users read own files" ON storage.objects;
DROP POLICY IF EXISTS "Avatars: users update own files" ON storage.objects;
DROP POLICY IF EXISTS "Avatars: users delete own files" ON storage.objects;

CREATE POLICY "Avatars: users upload to own folder" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Avatars: users read own files" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Avatars: users update own files" ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    )
    WITH CHECK (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );

CREATE POLICY "Avatars: users delete own files" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'avatars'
        AND auth.uid()::text = (storage.foldername(name))[1]
    );
