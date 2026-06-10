-- ============================================================================
-- Strava credentials
--
-- Per-user Strava OAuth tokens. The `strava-test-pull` edge function reads
-- from this table on every invocation rather than relying on hardcoded
-- constants in source. The whole reason this table exists: Strava rotates
-- the refresh token on every successful refresh, and the previous design
-- (in-memory `let stravaAccessToken`) lost the rotated value on every cold
-- start, so after one refresh round the chain broke permanently.
--
-- user_id is text to match auth.uid()::text — the convention used elsewhere
-- in this schema.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS strava_credentials (
    user_id TEXT PRIMARY KEY,
    strava_athlete_id BIGINT,
    access_token TEXT NOT NULL,
    refresh_token TEXT NOT NULL,
    expires_at TIMESTAMPTZ,
    scope TEXT,
    last_refreshed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE strava_credentials IS
    'Per-user Strava OAuth tokens. The edge function reads on each call '
    'rather than relying on hardcoded constants, so refresh-token rotation '
    'persists across cold starts. user_id matches auth.users.id (text).';

COMMENT ON COLUMN strava_credentials.access_token IS
    'Short-lived (~6h). Refreshed on demand when expires_at passes.';

COMMENT ON COLUMN strava_credentials.refresh_token IS
    'Long-lived but Strava rotates it on every refresh — must be persisted '
    'on every refresh response or the next cold start breaks.';

COMMENT ON COLUMN strava_credentials.expires_at IS
    'When access_token expires. Edge function pre-emptively refreshes when '
    'within 5 minutes.';

ALTER TABLE strava_credentials ENABLE ROW LEVEL SECURITY;

CREATE POLICY "athletes manage own strava credentials"
    ON strava_credentials
    FOR ALL
    USING (user_id = (auth.uid())::text)
    WITH CHECK (user_id = (auth.uid())::text);

COMMIT;
