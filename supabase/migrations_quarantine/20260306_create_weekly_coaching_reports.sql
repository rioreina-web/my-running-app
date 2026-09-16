-- ============================================================================
-- Weekly Coaching Reports Table
-- Stores AI-generated weekly coaching analysis per user per training week.
-- One report per user per week. Includes narrative review, structured alerts,
-- training adjustment recommendations, and computed analytics metrics.
-- ============================================================================

CREATE TABLE IF NOT EXISTS weekly_coaching_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,

    -- Week identification
    week_start DATE NOT NULL,
    week_end DATE NOT NULL,
    plan_id UUID REFERENCES training_plans(id) ON DELETE SET NULL,
    plan_week_number INTEGER,

    -- Computed metrics (JSONB for flexibility)
    metrics JSONB NOT NULL DEFAULT '{}',

    -- AI-generated coaching narrative (3-5 paragraphs, plain text)
    coaching_narrative TEXT,

    -- Structured trend alerts
    alerts JSONB NOT NULL DEFAULT '[]',

    -- Training adjustments for next week
    adjustments JSONB NOT NULL DEFAULT '[]',

    -- Focus areas for next week (1-3 short phrases)
    focus_areas JSONB NOT NULL DEFAULT '[]',

    -- Processing metadata
    ai_model TEXT NOT NULL DEFAULT 'claude-3-5-haiku',
    input_tokens INTEGER,
    output_tokens INTEGER,
    processing_time_ms INTEGER,
    status TEXT NOT NULL DEFAULT 'completed'
        CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
    error_message TEXT,

    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- One report per user per week
CREATE UNIQUE INDEX IF NOT EXISTS idx_weekly_reports_user_week
    ON weekly_coaching_reports(user_id, week_start);

-- Fast lookups by user (most recent first)
CREATE INDEX IF NOT EXISTS idx_weekly_reports_user_date
    ON weekly_coaching_reports(user_id, week_start DESC);

-- Lookup by plan
CREATE INDEX IF NOT EXISTS idx_weekly_reports_plan
    ON weekly_coaching_reports(plan_id, plan_week_number)
    WHERE plan_id IS NOT NULL;

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_weekly_coaching_reports_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER weekly_coaching_reports_updated_at_trigger
    BEFORE UPDATE ON weekly_coaching_reports
    FOR EACH ROW
    EXECUTE FUNCTION update_weekly_coaching_reports_timestamp();

-- RLS (matching fitness_snapshots pattern with auth.uid() IS NULL fallback for dev)
ALTER TABLE weekly_coaching_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own weekly reports" ON weekly_coaching_reports
    FOR SELECT USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can insert their own weekly reports" ON weekly_coaching_reports
    FOR INSERT WITH CHECK (auth.uid()::text = user_id OR auth.uid() IS NULL);

CREATE POLICY "Users can update their own weekly reports" ON weekly_coaching_reports
    FOR UPDATE USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

-- Service role bypass for edge functions
CREATE POLICY "Service role full access to weekly reports" ON weekly_coaching_reports
    FOR ALL USING (auth.role() = 'service_role');
