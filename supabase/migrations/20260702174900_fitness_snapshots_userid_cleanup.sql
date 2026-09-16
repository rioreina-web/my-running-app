-- Data-integrity cleanup for fitness_snapshots.user_id.
--
-- Two historical bugs (see outputs/fitness-snapshot-writer-diagnosis-2026-07-02.md):
--   1. Empty-string user_id — the iOS app read AuthManager.userId before auth
--      resolved and wrote snapshots with user_id = '' (guarded going forward in
--      the app + rejected by compute-fitness-snapshot, but existing orphan rows
--      remain here). These rows are invisible to every user and to server reads.
--   2. Uppercase UUID user_id — builds before the AuthManager `.lowercased()`
--      fix wrote UUID().uuidString (uppercase in Swift). Server reads key on the
--      lowercase auth uid, so these rows are invisible to server-side reads.
--
-- This migration is idempotent and general (also corrects any future casing
-- drift). fitness_snapshots has no unique (user_id, created_at) constraint, so
-- lowercasing cannot violate a constraint.
--
-- Append-only per CLAUDE.md hard rule #5; reaches prod only via `supabase db
-- push` from a committed SHA per hard rule #9.

BEGIN;

-- 1. Drop orphaned rows with no owner.
DELETE FROM public.fitness_snapshots
WHERE user_id IS NULL OR btrim(user_id) = '';

-- 2. Normalize any non-lowercase user_id to match the canonical auth uid casing.
UPDATE public.fitness_snapshots
SET user_id = lower(user_id)
WHERE user_id <> lower(user_id);

COMMIT;
