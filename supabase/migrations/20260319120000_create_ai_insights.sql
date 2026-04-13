-- AI Insights table — unified output store for all agentic AI features
CREATE TABLE IF NOT EXISTS ai_insights (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    insight_type TEXT NOT NULL,  -- 'post_run_analysis', 'injury_warning', 'adaptive_workout', 'race_readiness', 'block_review', 'voice_debrief'
    trigger_source TEXT,         -- 'workout_sync', 'cron', 'on_demand', 'voice_memo'
    status TEXT DEFAULT 'unread', -- 'unread', 'read', 'dismissed', 'acted_on'
    title TEXT,
    summary TEXT,                -- 1-2 sentence preview
    full_analysis JSONB,         -- structured AI output
    reference_id UUID,           -- optional FK to training_log, etc.
    priority TEXT DEFAULT 'normal', -- 'high', 'normal', 'low'
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_ai_insights_user_type ON ai_insights(user_id, insight_type);
CREATE INDEX IF NOT EXISTS idx_ai_insights_user_status ON ai_insights(user_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_insights_reference ON ai_insights(reference_id);
CREATE INDEX IF NOT EXISTS idx_ai_insights_expires ON ai_insights(expires_at) WHERE expires_at IS NOT NULL;

-- RLS
ALTER TABLE ai_insights ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rls_ai_insights_select" ON ai_insights;
CREATE POLICY "rls_ai_insights_select" ON ai_insights FOR SELECT USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "rls_ai_insights_update" ON ai_insights;
CREATE POLICY "rls_ai_insights_update" ON ai_insights FOR UPDATE USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "rls_ai_insights_delete" ON ai_insights;
CREATE POLICY "rls_ai_insights_delete" ON ai_insights FOR DELETE USING (user_id = auth.uid()::text);

DROP POLICY IF EXISTS "Service role full access to ai_insights" ON ai_insights;
CREATE POLICY "Service role full access to ai_insights" ON ai_insights FOR ALL USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

-- Anon insert for iOS client fallback
DROP POLICY IF EXISTS "Anon insert ai_insights" ON ai_insights;
CREATE POLICY "Anon insert ai_insights" ON ai_insights FOR INSERT WITH CHECK (auth.role() = 'anon' AND user_id IS NOT NULL);

-- Anon select for iOS client fallback
DROP POLICY IF EXISTS "Anon select ai_insights" ON ai_insights;
CREATE POLICY "Anon select ai_insights" ON ai_insights FOR SELECT USING (auth.role() = 'anon');
