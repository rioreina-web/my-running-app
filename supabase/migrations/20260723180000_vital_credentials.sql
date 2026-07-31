-- ============================================================================
-- Vital / Junction credentials
--
-- Per-athlete Junction user mapping. The `vital-connect` edge function creates
-- a Junction user (client_user_id = our auth user id) and stores the returned
-- vital_user_id here, so all subsequent workout fetches and webhooks resolve to
-- the right athlete. Mirrors `strava_credentials`.
--
-- user_id is TEXT to match auth.uid()::text — the schema-wide convention.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS vital_credentials (
    user_id       TEXT PRIMARY KEY,
    vital_user_id TEXT NOT NULL UNIQUE,
    provider      TEXT,
    connected_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE vital_credentials IS
    'Per-athlete Junction/Vital user mapping. vital_user_id is created by the '
    'vital-connect edge function and used for all Junction API calls + webhook '
    'routing. user_id matches auth.users.id (text).';

ALTER TABLE vital_credentials ENABLE ROW LEVEL SECURITY;

-- Athletes may READ their own mapping. All writes go through the service-role
-- edge function (which bypasses RLS) -- no client insert/update/delete path,
-- consistent with the coachable_moments service-role-write rule (hard rule #4).
CREATE POLICY "athletes read own vital credentials"
    ON vital_credentials
    FOR SELECT
    USING (user_id = (auth.uid())::text);

COMMIT;
