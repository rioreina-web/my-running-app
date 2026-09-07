-- ============================================================================
-- athlete_settings — add profile fields (display_name + bio)
--
-- Gives every athlete a human name and a short free-text profile note,
-- stored on the canonical per-athlete SETTINGS surface (one row per athlete,
-- keyed by user_id = auth.uid()::text). Before this, the coach portal had
-- nowhere to store a name, so every athlete rendered as "Athlete <id>".
--
-- Why here (not a new table): athlete_settings is already the dedicated
-- per-athlete settings surface (20260615210000) with owner + service-role
-- RLS in place. Display name + bio are settings, so they belong on this row.
-- Reusing the table means:
--   * no new RLS to write — the existing owner policies already let an
--     athlete edit their own name/bio; the existing service-role policy
--     already lets a gated coach-portal server action write it.
--   * the future athlete-facing "My account" settings screen reads/writes
--     the same row the coach portal does — one source of truth.
--
-- Read path (who sees the name):
--   * the athlete themselves (owner SELECT policy), and
--   * their coach, server-side via the service-role client after the coach
--     page has gated access (coach owns the plan the athlete is subscribed
--     to) — mirrors how athlete_state / body_mentions are read on the
--     athlete detail dashboard.
--
-- Append-only (hard rule #5): new migration, never edits 20260615210000.
-- Ships to prod via `supabase db push` only (hard rule #9).
-- ============================================================================

-- Display name shown across the coach portal (roster card, athlete detail
-- header, plan-builder preview rail). NULL = fall back to email prefix, then
-- to the "Athlete <id>" placeholder, so existing rows keep working untouched.
ALTER TABLE athlete_settings
    ADD COLUMN IF NOT EXISTS display_name TEXT
        CHECK (display_name IS NULL OR char_length(display_name) <= 80);

-- Short free-text profile note the coach (or athlete) can jot: goals, context,
-- anything useful at a glance ("BQ hopeful, hates hills, races every fall").
-- Capped so it stays a *brief* profile, not a journal. Plain text — no markup
-- is rendered from it.
ALTER TABLE athlete_settings
    ADD COLUMN IF NOT EXISTS bio TEXT
        CHECK (bio IS NULL OR char_length(bio) <= 600);

COMMENT ON COLUMN athlete_settings.display_name IS
    'Human display name for the athlete, shown across the coach portal. '
    'NULL falls back to email prefix then the "Athlete <id>" placeholder. '
    'Editable by the athlete (owner RLS) or their coach (gated service-role '
    'write). Max 80 chars.';
COMMENT ON COLUMN athlete_settings.bio IS
    'Short free-text profile note (goals / context) shown on the athlete '
    'detail page. Plain text, max 600 chars. Optional.';
