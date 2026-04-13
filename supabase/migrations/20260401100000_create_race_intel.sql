-- Race intelligence: course data, elevation, weather, and logistics for upcoming races
CREATE TABLE IF NOT EXISTS race_intel (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL,
    race_name TEXT NOT NULL,
    race_date DATE,
    location TEXT,

    -- Course data (from Gemini search grounding)
    course_data JSONB DEFAULT '{}'::jsonb,
    -- Expected keys: elevation_gain_ft, elevation_loss_ft, net_elevation_ft,
    -- key_hills (array of {mile, description, elevation_change_ft}),
    -- surface, aid_station_count, course_description, course_map_url,
    -- start_time, start_location, notable_features, out_and_backs

    -- Weather data (from Open-Meteo historical API)
    weather_data JSONB DEFAULT '{}'::jsonb,
    -- Expected keys: avg_temp_f, avg_low_f, avg_high_f, avg_humidity_pct,
    -- avg_wind_mph, precipitation_chance_pct, sunrise, conditions_summary

    -- Confidence & sources
    confidence TEXT DEFAULT 'low' CHECK (confidence IN ('high', 'medium', 'low')),
    sources TEXT[] DEFAULT '{}',
    verification_notes TEXT,

    -- Raw response for debugging
    raw_llm_response TEXT,

    -- Linked to user_goals if applicable
    goal_id UUID REFERENCES user_goals(id) ON DELETE SET NULL,

    fetched_at TIMESTAMPTZ DEFAULT now(),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Index for quick lookup by user
CREATE INDEX IF NOT EXISTS idx_race_intel_user ON race_intel(user_id);
CREATE INDEX IF NOT EXISTS idx_race_intel_race ON race_intel(race_name, race_date);

-- RLS
ALTER TABLE race_intel ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own race intel"
    ON race_intel FOR SELECT
    USING (auth.uid()::text = user_id OR auth.role() = 'anon');

CREATE POLICY "Anon can insert race intel"
    ON race_intel FOR INSERT
    WITH CHECK (auth.role() = 'anon' AND user_id IS NOT NULL);

CREATE POLICY "Service role full access on race_intel"
    ON race_intel FOR ALL
    USING (auth.role() = 'service_role');
