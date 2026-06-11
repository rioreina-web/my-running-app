-- ============================================================================
-- Coach notes: the smallest version of a coach→athlete channel.
--
-- A coach reading their roster (or a single athlete's deep-dive) can
-- leave a one-paragraph note that lands on the athlete's iOS home as a
-- "From your coach" card. The athlete taps to mark read.
--
-- Why this exists:
--   The athlete app has the Today home + analytics + AI insights.
--   The coach has the roster + athlete deep-dive (with full pace /
--   mood / injury data). Until now there's been no actual link from
--   "coach decision" back to "athlete sees it." This table is that
--   link, in its simplest form. Plan diffing, auto-flagged messaging,
--   and threading are deliberate follow-ups.
--
-- Schema notes:
--   - athlete_user_id is TEXT to match auth.users.id and the rest of
--     the codebase's per-athlete keying.
--   - coach_id references coach_profiles (UUID).
--   - read_at lets the iOS home filter to unread; null = unread.
--   - body is NOT NULL — empty notes are nonsense; the composer
--     should disable submit when empty.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS coach_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID NOT NULL REFERENCES coach_profiles(id) ON DELETE CASCADE,
    athlete_user_id TEXT NOT NULL,
    body TEXT NOT NULL CHECK (length(trim(body)) > 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    read_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_coach_notes_athlete_unread
    ON coach_notes (athlete_user_id, created_at DESC)
    WHERE read_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_coach_notes_coach_recent
    ON coach_notes (coach_id, created_at DESC);

ALTER TABLE coach_notes ENABLE ROW LEVEL SECURITY;

-- Coaches: full read/write on notes they authored.
CREATE POLICY "Coaches manage own notes"
    ON coach_notes FOR ALL
    USING (coach_id = current_coach_id())
    WITH CHECK (coach_id = current_coach_id());

-- Athletes: read every note addressed to them.
CREATE POLICY "Athletes read their own notes"
    ON coach_notes FOR SELECT
    USING (athlete_user_id = auth.uid()::text);

-- Athletes: update only the read_at field on their own notes
-- (so they can mark read from the iOS home). The CHECK clause is
-- liberal — Postgres doesn't let us scope updates to a column list
-- in a policy, so we lean on the iOS service to send only the
-- read_at field, and we trust RLS to scope row access.
CREATE POLICY "Athletes mark their notes read"
    ON coach_notes FOR UPDATE
    USING (athlete_user_id = auth.uid()::text)
    WITH CHECK (athlete_user_id = auth.uid()::text);

COMMIT;
