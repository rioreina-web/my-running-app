-- ============================================================================
-- athlete_settings — the SETTINGS surface
--
-- Resolves the "user_profiles ghost table" P0. user_profiles never existed
-- in prod (a malformed January migration filename collided with
-- fix_vector_search and was silently skipped for 5 months — see
-- docs/migration-ledger-reconciliation-2026-06-11.md and
-- outputs/profile-table-audit-2026-05-22.md). Rather than resurrect the
-- "three-tables-in-one-coat" user_profiles, this creates the dedicated
-- SETTINGS surface the audit recommended (Phase 5f, option 1): device /
-- location / locale config that belongs neither in athlete_state (the DCO)
-- nor in the event log.
--
-- Scope of THIS migration: create the table + RLS only. It carries the four
-- SETTINGS columns the audit catalogued — timezone, home_lat, home_lon,
-- preferred_run_time — typed to match their original user_profiles
-- definitions (weather infra migration 20260416500000) so the SETTINGS
-- edge-function readers (fetch-workout-weather, post-run-reconciliation,
-- reconcile-log) can be repointed later with no further schema change.
--
-- The immediate consumer is the Daily Read automation pair (the next two
-- migrations), which sources athlete timezone from here instead of the
-- ghost user_profiles.timezone column.
--
-- RLS (per docs/conventions/rls-checklist.md, user-owned pattern):
--   SELECT  — owner (user_id = auth.uid()::text), dev/service fallback
--   INSERT  — owner, dev/service fallback
--   UPDATE  — owner, dev/service fallback (USING + WITH CHECK)
--   DELETE  — none (no client delete path)
--   ALL     — service_role (edge-function writes)
-- ============================================================================

CREATE TABLE IF NOT EXISTS athlete_settings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL UNIQUE,   -- matches auth.uid()::text

    -- Locale: IANA timezone name (e.g. "America/Los_Angeles"). Default 'UTC'
    -- so existing athletes resolve cleanly until the iOS client backfills the
    -- real device timezone. The Daily Read cron and the coaching-daily-read
    -- edge function both default to UTC, so column and consumers agree.
    timezone TEXT NOT NULL DEFAULT 'UTC',

    -- Backend location source for weather fetches when GPS is unavailable.
    -- Types mirror the original user_profiles columns (weather infra).
    home_lat REAL,
    home_lon REAL,
    preferred_run_time TEXT
        CHECK (preferred_run_time IS NULL
               OR preferred_run_time IN ('morning', 'afternoon', 'evening')),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_athlete_settings_user_id
    ON athlete_settings(user_id);

COMMENT ON TABLE athlete_settings IS
    'Per-athlete device/location/locale settings (the SETTINGS surface). '
    'Replaces the never-shipped user_profiles for config fields. One row '
    'per athlete, keyed by user_id = auth.uid()::text.';
COMMENT ON COLUMN athlete_settings.timezone IS
    'IANA timezone name. Used by the daily Coach Read cron to fire at the '
    'athlete''s local 6 AM and by coaching-daily-read for local-date '
    'resolution. Default ''UTC''.';
COMMENT ON COLUMN athlete_settings.home_lat IS
    'Home latitude for backend weather fetches when GPS unavailable.';
COMMENT ON COLUMN athlete_settings.home_lon IS
    'Home longitude for backend weather fetches when GPS unavailable.';
COMMENT ON COLUMN athlete_settings.preferred_run_time IS
    'morning (6am), afternoon (5pm), or evening (7pm) — used for forecast '
    'hour selection.';

-- Auto-update updated_at on every mutation.
CREATE OR REPLACE FUNCTION update_athlete_settings_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS athlete_settings_updated_at_trigger ON athlete_settings;
CREATE TRIGGER athlete_settings_updated_at_trigger
    BEFORE UPDATE ON athlete_settings
    FOR EACH ROW
    EXECUTE FUNCTION update_athlete_settings_timestamp();

-- ----------------------------------------------------------------------------
-- RLS
-- ----------------------------------------------------------------------------
ALTER TABLE athlete_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Athletes read own settings" ON athlete_settings
    FOR SELECT
    USING (user_id = auth.uid()::text OR auth.uid() IS NULL);

CREATE POLICY "Athletes insert own settings" ON athlete_settings
    FOR INSERT
    WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);

CREATE POLICY "Athletes update own settings" ON athlete_settings
    FOR UPDATE
    USING (user_id = auth.uid()::text OR auth.uid() IS NULL)
    WITH CHECK (user_id = auth.uid()::text OR auth.uid() IS NULL);

CREATE POLICY "Service role full access to athlete_settings" ON athlete_settings
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');
