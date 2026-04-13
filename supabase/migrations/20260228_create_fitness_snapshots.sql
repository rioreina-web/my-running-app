-- ============================================================================
-- Fitness Snapshots Table
-- Stores point-in-time race prediction snapshots so users can track fitness
-- trends over time. One snapshot per prediction run, rate-limited to 1/day
-- on the client side. Snapshots are immutable (no UPDATE policy).
-- ============================================================================

CREATE TABLE IF NOT EXISTS fitness_snapshots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,

    -- Predicted race times (total seconds for official distance)
    predicted_mile_seconds INTEGER NOT NULL,
    predicted_5k_seconds INTEGER NOT NULL,
    predicted_10k_seconds INTEGER NOT NULL,
    predicted_half_seconds INTEGER NOT NULL,
    predicted_marathon_seconds INTEGER NOT NULL,

    -- Baseline pace used for VDOT calculation (seconds per mile)
    estimated_10k_pace_seconds DOUBLE PRECISION NOT NULL,

    -- Prediction metadata
    confidence TEXT NOT NULL DEFAULT 'Low'
        CHECK (confidence IN ('High', 'Medium', 'Low')),
    data_source TEXT NOT NULL DEFAULT 'default',
    workout_count INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fetching user's recent history (sorted by date)
CREATE INDEX idx_fitness_snapshots_user_date ON fitness_snapshots(user_id, created_at DESC);

-- RLS policies (with auth.uid() IS NULL fallback for dev)
ALTER TABLE fitness_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own fitness snapshots" ON fitness_snapshots
    FOR SELECT USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can insert their own fitness snapshots" ON fitness_snapshots
    FOR INSERT WITH CHECK (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can delete their own fitness snapshots" ON fitness_snapshots
    FOR DELETE USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

-- Service role bypass for edge functions
CREATE POLICY "Service role full access to fitness snapshots" ON fitness_snapshots
    FOR ALL USING (auth.role() = 'service_role');
