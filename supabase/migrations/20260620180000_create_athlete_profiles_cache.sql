-- Create the athlete_profiles cache table that build-athlete-profile expects.
--
-- The build-athlete-profile edge function reads/writes a 24h profile cache from
-- `athlete_profiles` (SELECT profile_data,updated_at WHERE user_id; UPSERT ON
-- CONFLICT user_id). The table was never created, so BOTH the cache read and the
-- cache write have always failed silently — every call (including the iOS launch
-- `fetchProfile()`) does the full 1.6–2.6s rebuild and returns `cached:false`,
-- forever. Creating the table makes the cache work: one rebuild per 24h, fast
-- cache hits otherwise.
--
-- Schema mirrors the function exactly: user_id (text, conflict key), profile_data
-- (jsonb blob), updated_at (freshness check). Service-role writes (the edge fn)
-- bypass RLS; users may read their own row.

CREATE TABLE IF NOT EXISTS public.athlete_profiles (
    user_id      text PRIMARY KEY,
    profile_data jsonb       NOT NULL,
    updated_at   timestamptz NOT NULL DEFAULT now(),
    created_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.athlete_profiles ENABLE ROW LEVEL SECURITY;

-- Users may read their own cached profile (the edge fn uses the service role and
-- bypasses RLS for writes). No user INSERT/UPDATE policy — writes are server-only.
CREATE POLICY "Users read own athlete profile"
    ON public.athlete_profiles
    FOR SELECT
    USING (user_id = auth.uid()::text);
