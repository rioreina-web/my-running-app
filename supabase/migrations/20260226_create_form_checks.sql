-- ============================================================================
-- Form Checks Table
-- Stores qualitative running form analysis results. Pose data is extracted
-- on-device and sent to an AI edge function for narrative assessment of
-- imbalances, posture, foot strike, and compensation patterns.
-- ============================================================================

CREATE TABLE IF NOT EXISTS form_checks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,

    -- Video reference (local only, no cloud upload)
    local_video_filename TEXT,

    -- Recording metadata
    recorded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    duration_seconds NUMERIC(6,2),
    frame_count INTEGER,
    fps NUMERIC(5,2),

    -- Processing status
    status TEXT NOT NULL DEFAULT 'processing'
        CHECK (status IN ('processing', 'completed', 'failed')),

    -- On-device pose data summary (flat metrics for AI input)
    pose_data_summary JSONB,

    -- AI qualitative analysis
    ai_analysis JSONB,
    ai_analysis_at TIMESTAMPTZ,

    -- Metadata
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_form_checks_user_id ON form_checks(user_id);
CREATE INDEX idx_form_checks_user_date ON form_checks(user_id, recorded_at DESC);

-- Auto-update updated_at trigger
CREATE OR REPLACE FUNCTION update_form_checks_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER form_checks_updated_at_trigger
    BEFORE UPDATE ON form_checks
    FOR EACH ROW
    EXECUTE FUNCTION update_form_checks_timestamp();

-- RLS policies (with auth.uid() IS NULL fallback for dev)
ALTER TABLE form_checks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own form checks" ON form_checks
    FOR SELECT USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can insert their own form checks" ON form_checks
    FOR INSERT WITH CHECK (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can update their own form checks" ON form_checks
    FOR UPDATE USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can delete their own form checks" ON form_checks
    FOR DELETE USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

-- Service role bypass for edge functions
CREATE POLICY "Service role full access to form checks" ON form_checks
    FOR ALL USING (auth.role() = 'service_role');
