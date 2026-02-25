-- ============================================================================
-- Injury Tracking Table
-- Dedicated table for tracking running injuries with severity, status,
-- AI analysis, and source provenance.
-- ============================================================================

CREATE TABLE IF NOT EXISTS injuries (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,

    -- Core injury data
    body_area TEXT NOT NULL,
    side TEXT DEFAULT 'unknown',
    description TEXT,
    severity INTEGER DEFAULT 5 CHECK (severity >= 1 AND severity <= 10),

    -- Status tracking
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'monitoring', 'resolved')),
    first_reported_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,

    -- Source tracking
    source TEXT NOT NULL DEFAULT 'manual'
        CHECK (source IN ('voice_memo', 'coaching_chat', 'manual')),
    source_reference_id UUID,

    -- AI analysis (stored result from injury-analysis edge function)
    ai_analysis JSONB,
    ai_analysis_at TIMESTAMPTZ,

    -- Metadata
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_injuries_user_id ON injuries(user_id);
CREATE INDEX idx_injuries_user_active ON injuries(user_id, status) WHERE status = 'active';
CREATE INDEX idx_injuries_body_area ON injuries(user_id, body_area);

-- Auto-update updated_at trigger
CREATE OR REPLACE FUNCTION update_injuries_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER injuries_updated_at_trigger
    BEFORE UPDATE ON injuries
    FOR EACH ROW
    EXECUTE FUNCTION update_injuries_timestamp();

-- RLS policies
ALTER TABLE injuries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own injuries"
    ON injuries FOR SELECT
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can insert their own injuries"
    ON injuries FOR INSERT
    WITH CHECK (auth.uid()::text = user_id);

CREATE POLICY "Users can update their own injuries"
    ON injuries FOR UPDATE
    USING (auth.uid()::text = user_id);

CREATE POLICY "Users can delete their own injuries"
    ON injuries FOR DELETE
    USING (auth.uid()::text = user_id);

-- Service role bypass for edge functions
CREATE POLICY "Service role full access to injuries"
    ON injuries FOR ALL
    USING (auth.role() = 'service_role');
