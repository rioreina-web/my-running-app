-- ============================================================================
-- Biomechanics Analysis Table
-- Stores video-based running form analysis results including 3D joint angles,
-- foot strike patterns, shank angles, and gait metrics.
-- ============================================================================

CREATE TABLE IF NOT EXISTS biomechanics_analyses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,

    -- Video reference
    video_storage_path TEXT,
    local_video_filename TEXT,

    -- Recording metadata
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    duration_seconds NUMERIC(6,2),
    frame_count INTEGER,
    fps NUMERIC(5,2),
    view_angle TEXT DEFAULT 'sagittal_left'
        CHECK (view_angle IN ('sagittal_left', 'sagittal_right', 'frontal', 'posterior')),

    -- Processing status
    status TEXT NOT NULL DEFAULT 'processing'
        CHECK (status IN ('processing', 'completed', 'failed')),

    -- Results (JSONB for flexibility)
    joint_angles JSONB,
    foot_strike JSONB,
    gait_metrics JSONB,
    pose_frames_summary JSONB,

    -- AI analysis (Phase 3)
    ai_analysis JSONB,
    ai_analysis_at TIMESTAMPTZ,

    -- Link to injury for correlation
    linked_injury_id UUID REFERENCES injuries(id) ON DELETE SET NULL,

    -- Metadata
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_biomechanics_user_id ON biomechanics_analyses(user_id);
CREATE INDEX idx_biomechanics_user_date ON biomechanics_analyses(user_id, recorded_at DESC);
CREATE INDEX idx_biomechanics_linked_injury ON biomechanics_analyses(linked_injury_id)
    WHERE linked_injury_id IS NOT NULL;

-- Auto-update updated_at trigger
CREATE OR REPLACE FUNCTION update_biomechanics_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER biomechanics_updated_at_trigger
    BEFORE UPDATE ON biomechanics_analyses
    FOR EACH ROW
    EXECUTE FUNCTION update_biomechanics_timestamp();

-- RLS policies
ALTER TABLE biomechanics_analyses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own analyses"
    ON biomechanics_analyses FOR SELECT
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert their own analyses"
    ON biomechanics_analyses FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can update their own analyses"
    ON biomechanics_analyses FOR UPDATE
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can delete their own analyses"
    ON biomechanics_analyses FOR DELETE
    USING (auth.uid()::text = user_id);

-- Service role bypass for edge functions
CREATE POLICY "Service role full access to biomechanics"
    ON biomechanics_analyses FOR ALL
    USING (auth.role() = 'service_role');
