-- ============================================================================
-- Athlete Pace Profiles
-- Single source of truth for the six reference paces (easy, marathon, half,
-- 10K, 5K, mile) used at plan-generation time to stamp concrete
-- target_pace_seconds_per_mile values onto scheduled_workouts steps.
-- One row per user, upserted by the build-pace-profile edge function.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS athlete_pace_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Goal context (nullable — a profile can exist without a declared goal)
    goal_race_distance TEXT
        CHECK (goal_race_distance IN ('mile', '5K', '10K', 'half', 'marathon')),
    goal_time_seconds INTEGER,

    -- Six reference paces. Each group has: seconds/mile, confidence, source date.
    -- Confidence is 'high' when derived directly from a snapshot prediction,
    -- 'medium' when cascaded (e.g. marathon inferred from half), 'low' when
    -- only a single source distance was available.
    easy_pace_seconds NUMERIC,
    easy_pace_confidence TEXT CHECK (easy_pace_confidence IN ('high', 'medium', 'low')),
    easy_pace_source_date TIMESTAMPTZ,

    marathon_pace_seconds NUMERIC,
    marathon_pace_confidence TEXT CHECK (marathon_pace_confidence IN ('high', 'medium', 'low')),
    marathon_pace_source_date TIMESTAMPTZ,

    half_pace_seconds NUMERIC,
    half_pace_confidence TEXT CHECK (half_pace_confidence IN ('high', 'medium', 'low')),
    half_pace_source_date TIMESTAMPTZ,

    ten_k_pace_seconds NUMERIC,
    ten_k_pace_confidence TEXT CHECK (ten_k_pace_confidence IN ('high', 'medium', 'low')),
    ten_k_pace_source_date TIMESTAMPTZ,

    five_k_pace_seconds NUMERIC,
    five_k_pace_confidence TEXT CHECK (five_k_pace_confidence IN ('high', 'medium', 'low')),
    five_k_pace_source_date TIMESTAMPTZ,

    mile_pace_seconds NUMERIC,
    mile_pace_confidence TEXT CHECK (mile_pace_confidence IN ('high', 'medium', 'low')),
    mile_pace_source_date TIMESTAMPTZ,

    -- Provenance
    based_on_snapshot_id UUID REFERENCES fitness_snapshots(id),
    generated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (user_id)
);

-- Enable RLS
ALTER TABLE athlete_pace_profiles ENABLE ROW LEVEL SECURITY;

-- Users can read, insert, and update their own row.
CREATE POLICY "Users can read own pace profile"
    ON athlete_pace_profiles FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own pace profile"
    ON athlete_pace_profiles FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own pace profile"
    ON athlete_pace_profiles FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- Service role bypass for edge functions (build-pace-profile upserts here)
CREATE POLICY "Service role full access to pace profiles"
    ON athlete_pace_profiles FOR ALL
    USING (auth.role() = 'service_role');

-- updated_at trigger
CREATE OR REPLACE FUNCTION update_athlete_pace_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER athlete_pace_profiles_updated_at
    BEFORE UPDATE ON athlete_pace_profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_athlete_pace_profiles_updated_at();

COMMIT;
