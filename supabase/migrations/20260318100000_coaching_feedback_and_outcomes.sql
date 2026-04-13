-- ============================================================================
-- Phase 2: Coaching Feedback & Outcome Tracking
--
-- Creates tables for:
-- 1. coaching_feedback - thumbs up/down on individual coaching messages
-- 2. coaching_adjustments - tracks advice given and whether it was followed
-- 3. goal_outcomes - compares predicted vs actual race results
-- ============================================================================

-- ============================================================================
-- 1. coaching_feedback — user rates individual coaching messages
-- ============================================================================
CREATE TABLE IF NOT EXISTS coaching_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  conversation_id UUID NOT NULL,
  message_id UUID, -- references conversation_messages.id if available
  rating SMALLINT NOT NULL CHECK (rating IN (-1, 1)), -- -1 = thumbs down, 1 = thumbs up
  feedback_text TEXT, -- optional written feedback
  message_content TEXT, -- snapshot of the message being rated (for prompt feedback loop)
  query_complexity TEXT, -- simple/moderate/complex at time of response
  model_used TEXT, -- which model generated the response
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexes for efficient querying
CREATE INDEX idx_coaching_feedback_user ON coaching_feedback(user_id);
CREATE INDEX idx_coaching_feedback_conversation ON coaching_feedback(conversation_id);
CREATE INDEX idx_coaching_feedback_rating ON coaching_feedback(user_id, rating);
CREATE INDEX idx_coaching_feedback_created ON coaching_feedback(created_at DESC);

-- RLS
ALTER TABLE coaching_feedback ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert own feedback"
  ON coaching_feedback FOR INSERT
  WITH CHECK (
    user_id = (SELECT auth.jwt() ->> 'sub')
    OR user_id = coalesce(current_setting('request.jwt.claims', true)::json ->> 'sub', '')
  );

CREATE POLICY "Users can read own feedback"
  ON coaching_feedback FOR SELECT
  USING (
    user_id = (SELECT auth.jwt() ->> 'sub')
    OR user_id = coalesce(current_setting('request.jwt.claims', true)::json ->> 'sub', '')
  );

-- ============================================================================
-- 2. coaching_adjustments — tracks advice → outcome loop
-- ============================================================================
CREATE TABLE IF NOT EXISTS coaching_adjustments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  week_start DATE NOT NULL,
  adjustment_type TEXT NOT NULL, -- 'volume', 'intensity', 'recovery', 'workout_swap', 'pace_target', 'cross_training', 'other'
  target_workout TEXT, -- which workout this adjustment targets (e.g., "Tuesday tempo")
  recommendation TEXT NOT NULL, -- what the coach suggested
  source TEXT DEFAULT 'weekly_report', -- 'weekly_report', 'conversation', 'proactive'
  source_reference_id UUID, -- FK to weekly_coaching_reports.id or conversation_messages.id
  followed BOOLEAN, -- did the athlete follow the advice? (null = unknown)
  outcome_notes TEXT, -- what happened (auto-populated from next week's data or user input)
  outcome_metrics JSONB, -- structured outcome data (pace_change, mood_change, volume_delta)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ -- when the outcome was recorded
);

CREATE INDEX idx_coaching_adjustments_user ON coaching_adjustments(user_id);
CREATE INDEX idx_coaching_adjustments_week ON coaching_adjustments(user_id, week_start DESC);
CREATE INDEX idx_coaching_adjustments_unresolved ON coaching_adjustments(user_id)
  WHERE followed IS NULL;

ALTER TABLE coaching_adjustments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own adjustments"
  ON coaching_adjustments FOR ALL
  USING (
    user_id = (SELECT auth.jwt() ->> 'sub')
    OR user_id = coalesce(current_setting('request.jwt.claims', true)::json ->> 'sub', '')
  );

-- ============================================================================
-- 3. goal_outcomes — predicted vs actual race results
-- ============================================================================
CREATE TABLE IF NOT EXISTS goal_outcomes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  goal_id UUID, -- FK to user_goals.id
  race_distance TEXT NOT NULL, -- '5k', '10k', 'half', 'marathon'
  predicted_time_seconds INTEGER, -- what the coach/predictor estimated
  actual_time_seconds INTEGER, -- what actually happened
  delta_seconds INTEGER GENERATED ALWAYS AS (actual_time_seconds - predicted_time_seconds) STORED,
  delta_percentage FLOAT GENERATED ALWAYS AS (
    CASE WHEN predicted_time_seconds > 0
    THEN ((actual_time_seconds - predicted_time_seconds)::float / predicted_time_seconds) * 100
    ELSE NULL END
  ) STORED,
  race_conditions TEXT, -- 'ideal', 'hot', 'cold', 'windy', 'hilly', 'altitude'
  athlete_notes TEXT, -- how the race felt
  prediction_source TEXT DEFAULT 'fitness_predictor', -- 'fitness_predictor', 'coach_agent', 'manual'
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_goal_outcomes_user ON goal_outcomes(user_id);
CREATE INDEX idx_goal_outcomes_distance ON goal_outcomes(user_id, race_distance);

ALTER TABLE goal_outcomes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can manage own goal outcomes"
  ON goal_outcomes FOR ALL
  USING (
    user_id = (SELECT auth.jwt() ->> 'sub')
    OR user_id = coalesce(current_setting('request.jwt.claims', true)::json ->> 'sub', '')
  );

-- ============================================================================
-- Helper function: Get recent negative feedback for prompt injection
-- Returns the last 5 thumbs-down messages so the agent can learn what didn't work
-- ============================================================================
CREATE OR REPLACE FUNCTION get_negative_feedback(p_user_id TEXT, p_limit INTEGER DEFAULT 5)
RETURNS TABLE (
  message_content TEXT,
  feedback_text TEXT,
  created_at TIMESTAMPTZ
) LANGUAGE sql STABLE AS $$
  SELECT
    cf.message_content,
    cf.feedback_text,
    cf.created_at
  FROM coaching_feedback cf
  WHERE cf.user_id = p_user_id
    AND cf.rating = -1
    AND cf.message_content IS NOT NULL
  ORDER BY cf.created_at DESC
  LIMIT p_limit;
$$;

-- ============================================================================
-- Helper function: Get unresolved adjustments for next coaching session
-- ============================================================================
CREATE OR REPLACE FUNCTION get_pending_adjustments(p_user_id TEXT)
RETURNS TABLE (
  id UUID,
  week_start DATE,
  adjustment_type TEXT,
  recommendation TEXT,
  target_workout TEXT,
  created_at TIMESTAMPTZ
) LANGUAGE sql STABLE AS $$
  SELECT
    ca.id,
    ca.week_start,
    ca.adjustment_type,
    ca.recommendation,
    ca.target_workout,
    ca.created_at
  FROM coaching_adjustments ca
  WHERE ca.user_id = p_user_id
    AND ca.followed IS NULL
    AND ca.week_start >= (CURRENT_DATE - INTERVAL '4 weeks')
  ORDER BY ca.created_at DESC
  LIMIT 10;
$$;
