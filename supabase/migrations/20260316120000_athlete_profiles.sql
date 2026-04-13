-- Athlete Profiles: comprehensive recency-weighted profile cache
-- Built by the build-athlete-profile edge function, refreshed every 24 hours.

CREATE TABLE IF NOT EXISTS athlete_profiles (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  profile_data JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE athlete_profiles ENABLE ROW LEVEL SECURITY;

-- Users can read their own profile
CREATE POLICY "Users can read own athlete profile"
  ON athlete_profiles FOR SELECT
  USING (auth.uid() = user_id);

-- Service role inserts/updates via edge function (no user-facing write policy needed)
-- The edge function uses the service role key which bypasses RLS.

-- Index for quick lookups
CREATE INDEX IF NOT EXISTS idx_athlete_profiles_updated_at
  ON athlete_profiles (updated_at DESC);
