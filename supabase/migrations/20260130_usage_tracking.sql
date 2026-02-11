-- Usage tracking for rate limiting and cost monitoring
-- Tracks every AI interaction for billing, analytics, and rate limiting

CREATE TABLE usage_tracking (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID,
    feature TEXT NOT NULL CHECK (feature IN ('coaching', 'transcription', 'insight')),
    model_used TEXT,
    input_tokens INT DEFAULT 0,
    output_tokens INT DEFAULT 0,
    cached BOOLEAN DEFAULT false,
    date DATE DEFAULT CURRENT_DATE,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes for efficient querying
CREATE INDEX idx_usage_user_date ON usage_tracking(user_id, date, feature);
CREATE INDEX idx_usage_date_model ON usage_tracking(date, model_used);
CREATE INDEX idx_usage_date ON usage_tracking(date);

-- Daily usage view for rate limiting checks
CREATE VIEW daily_usage AS
SELECT
    user_id,
    feature,
    date,
    COUNT(*) as query_count,
    SUM(input_tokens) as total_input_tokens,
    SUM(output_tokens) as total_output_tokens,
    COUNT(*) FILTER (WHERE cached = true) as cached_count
FROM usage_tracking
WHERE date = CURRENT_DATE
GROUP BY user_id, feature, date;

-- User tiers for rate limits
CREATE TABLE user_tiers (
    user_id UUID PRIMARY KEY,
    tier TEXT DEFAULT 'free' CHECK (tier IN ('free', 'pro', 'unlimited')),
    daily_limit INT DEFAULT 5,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE usage_tracking ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_tiers ENABLE ROW LEVEL SECURITY;

-- Allow all operations for now (no auth - single user app)
CREATE POLICY "Allow all operations on usage_tracking" ON usage_tracking
    FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Allow all operations on user_tiers" ON user_tiers
    FOR ALL USING (true) WITH CHECK (true);

-- Trigger to update user_tiers updated_at timestamp
CREATE OR REPLACE FUNCTION update_user_tiers_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER user_tiers_updated_at
    BEFORE UPDATE ON user_tiers
    FOR EACH ROW
    EXECUTE FUNCTION update_user_tiers_updated_at();

-- Cost monitoring view (for dashboard/analytics)
CREATE VIEW daily_cost_estimate AS
SELECT
    date,
    model_used,
    COUNT(*) as requests,
    SUM(input_tokens) as total_input_tokens,
    SUM(output_tokens) as total_output_tokens,
    CASE
        WHEN model_used LIKE 'simple%' OR model_used = 'groq-llama-8b' THEN COUNT(*) * 0.00031
        WHEN model_used LIKE 'moderate%' OR model_used = 'gemini-flash' THEN COUNT(*) * 0.0006
        WHEN model_used LIKE 'complex%' OR model_used = 'claude-haiku' THEN COUNT(*) * 0.00219
        WHEN model_used = 'cache' THEN 0
        ELSE COUNT(*) * 0.001
    END as estimated_cost_usd
FROM usage_tracking
GROUP BY date, model_used
ORDER BY date DESC, estimated_cost_usd DESC;
