-- ============================================================================
-- Workout Features Table
-- Pre-computed training signal features per workout for ML consumption.
-- All features derived from raw data (pace_segments, HR, distance, duration).
-- No workout-type labels — the model decides what patterns matter.
-- ============================================================================

CREATE TABLE IF NOT EXISTS workout_features (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    training_log_id UUID NOT NULL REFERENCES training_logs(id) ON DELETE CASCADE,
    workout_date TIMESTAMPTZ NOT NULL,

    -- Volume signals
    total_distance_miles DOUBLE PRECISION,          -- total workout distance
    total_duration_seconds DOUBLE PRECISION,        -- total elapsed time
    avg_pace_seconds DOUBLE PRECISION,              -- overall pace (sec/mi)

    -- Intensity distribution (seconds spent in each zone, relative to runner's paces)
    easy_seconds DOUBLE PRECISION DEFAULT 0,        -- below 75% MP velocity
    moderate_seconds DOUBLE PRECISION DEFAULT 0,    -- 75-85% MP velocity
    threshold_seconds DOUBLE PRECISION DEFAULT 0,   -- 85-95% MP velocity
    hard_seconds DOUBLE PRECISION DEFAULT 0,        -- above 95% MP velocity (interval/race)

    -- Intensity metrics
    intensity_score DOUBLE PRECISION,               -- time-weighted avg: sum(segment_seconds * zone_weight) / total_seconds
    hard_effort_minutes DOUBLE PRECISION DEFAULT 0, -- threshold + hard combined (minutes)
    peak_pace_seconds DOUBLE PRECISION,             -- fastest segment pace (sec/mi)
    pace_variance DOUBLE PRECISION,                 -- stdev of segment paces (higher = more variable workout)

    -- Workout shape
    segment_count INTEGER DEFAULT 0,                -- number of distinct pace segments
    hard_segment_count INTEGER DEFAULT 0,           -- segments at threshold+ intensity
    avg_hard_segment_duration DOUBLE PRECISION,     -- mean duration of hard segments (seconds)
    effort_distribution TEXT,                        -- 'front_loaded', 'back_loaded', 'even', 'mixed'

    -- Heart rate signals (nullable — not all workouts have HR)
    avg_heart_rate INTEGER,
    hard_effort_avg_hr INTEGER,                     -- avg HR during hard segments only
    easy_effort_avg_hr INTEGER,                     -- avg HR during easy segments only
    hr_pace_efficiency DOUBLE PRECISION,            -- avg_hr / avg_pace — lower = more efficient

    -- Recovery context (computed from neighboring workouts)
    hours_since_last_workout DOUBLE PRECISION,      -- time gap from previous workout
    hours_since_last_hard DOUBLE PRECISION,          -- time gap from previous hard workout

    -- Mood signal (from voice log, nullable)
    mood TEXT,

    -- Rolling aggregates (7/14/28/42 day windows ending at this workout)
    rolling_7d_miles DOUBLE PRECISION,
    rolling_14d_miles DOUBLE PRECISION,
    rolling_28d_miles DOUBLE PRECISION,
    rolling_42d_miles DOUBLE PRECISION,
    rolling_7d_hard_minutes DOUBLE PRECISION,
    rolling_28d_hard_minutes DOUBLE PRECISION,
    monotony_7d DOUBLE PRECISION,                   -- stdev(daily_miles) / mean(daily_miles) over 7d
    strain_7d DOUBLE PRECISION,                     -- rolling_7d_miles * monotony_7d
    acwr DOUBLE PRECISION,                          -- acute:chronic work ratio (7d / 28d)

    -- Metadata
    data_source TEXT,                                -- 'auto_sync', 'voice_log', 'manual'
    has_pace_segments BOOLEAN DEFAULT false,
    has_hr_data BOOLEAN DEFAULT false,
    computed_at TIMESTAMPTZ DEFAULT now(),

    UNIQUE(training_log_id)
);

-- Indexes
CREATE INDEX idx_workout_features_user_date ON workout_features(user_id, workout_date DESC);
CREATE INDEX idx_workout_features_log ON workout_features(training_log_id);

-- RLS
ALTER TABLE workout_features ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own workout features" ON workout_features
    FOR SELECT USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Service role full access to workout features" ON workout_features
    FOR ALL USING (auth.role() = 'service_role');
