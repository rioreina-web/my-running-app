-- User Profile for storing runner data gathered through conversations
-- This builds over time as the AI asks questions and learns about the runner

CREATE TABLE user_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL UNIQUE,  -- Device ID or auth user ID

    -- Personal running stats
    current_weekly_mileage DECIMAL(5,1),  -- e.g., 35.5
    peak_weekly_mileage DECIMAL(5,1),     -- highest they've run
    years_running INTEGER,

    -- PRs (stored in seconds for easy comparison)
    pr_5k_seconds INTEGER,
    pr_10k_seconds INTEGER,
    pr_half_seconds INTEGER,
    pr_marathon_seconds INTEGER,

    -- Current fitness indicators
    easy_pace_per_mile TEXT,      -- e.g., "9:30"
    tempo_pace_per_mile TEXT,     -- e.g., "7:45"

    -- Health & injury history
    injury_history JSONB DEFAULT '[]',  -- [{area: "calf", side: "left", status: "resolved", notes: "tightness"}]
    current_injuries JSONB DEFAULT '[]',

    -- Training preferences
    preferred_run_days TEXT[],    -- ['monday', 'wednesday', 'friday', 'saturday']
    long_run_day TEXT,            -- 'saturday'
    cross_training TEXT[],        -- ['cycling', 'swimming']

    -- Metadata
    data_completeness INTEGER DEFAULT 0,  -- 0-100 score of how complete the profile is
    last_updated TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for quick lookups
CREATE INDEX idx_user_profiles_user_id ON user_profiles(user_id);

-- Function to calculate profile completeness
CREATE OR REPLACE FUNCTION calculate_profile_completeness(profile user_profiles)
RETURNS INTEGER AS $$
DECLARE
    score INTEGER := 0;
    total_fields INTEGER := 10;
BEGIN
    IF profile.current_weekly_mileage IS NOT NULL THEN score := score + 1; END IF;
    IF profile.years_running IS NOT NULL THEN score := score + 1; END IF;
    IF profile.pr_5k_seconds IS NOT NULL OR profile.pr_10k_seconds IS NOT NULL
       OR profile.pr_half_seconds IS NOT NULL OR profile.pr_marathon_seconds IS NOT NULL THEN
        score := score + 2;
    END IF;
    IF profile.easy_pace_per_mile IS NOT NULL THEN score := score + 1; END IF;
    IF profile.injury_history != '[]'::jsonb OR profile.current_injuries != '[]'::jsonb THEN
        score := score + 1;
    END IF;
    IF profile.preferred_run_days IS NOT NULL AND array_length(profile.preferred_run_days, 1) > 0 THEN
        score := score + 1;
    END IF;
    IF profile.long_run_day IS NOT NULL THEN score := score + 1; END IF;
    IF profile.cross_training IS NOT NULL THEN score := score + 1; END IF;
    IF profile.peak_weekly_mileage IS NOT NULL THEN score := score + 1; END IF;

    RETURN (score * 100) / total_fields;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update completeness and timestamp on changes
CREATE OR REPLACE FUNCTION update_profile_metadata()
RETURNS TRIGGER AS $$
BEGIN
    NEW.data_completeness := calculate_profile_completeness(NEW);
    NEW.last_updated := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER profile_metadata_trigger
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_profile_metadata();
