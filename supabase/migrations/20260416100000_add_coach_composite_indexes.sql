-- ============================================================================
-- Add composite indexes for coach-related queries
-- ============================================================================
-- These tables are queried by (user_id) with ORDER BY on a timestamp column.
-- Single-column indexes force a filter-then-sort; composites let Postgres
-- satisfy both the filter and the sort from one index scan.
-- ============================================================================

-- coaching_feedback: queried by user_id ordered by created_at DESC
-- (replaces separate idx_coaching_feedback_user and idx_coaching_feedback_created)
DROP INDEX IF EXISTS idx_coaching_feedback_user;
DROP INDEX IF EXISTS idx_coaching_feedback_created;
CREATE INDEX idx_coaching_feedback_user_created
  ON coaching_feedback(user_id, created_at DESC);

-- goal_outcomes: queried by user_id ordered by created_at DESC
-- (replaces single-column idx_goal_outcomes_user; distance composite kept)
DROP INDEX IF EXISTS idx_goal_outcomes_user;
CREATE INDEX idx_goal_outcomes_user_created
  ON goal_outcomes(user_id, created_at DESC);

-- injuries: weekly report filters by user_id + created_at range
DROP INDEX IF EXISTS idx_injuries_user_id;
CREATE INDEX idx_injuries_user_created
  ON injuries(user_id, created_at DESC);

-- training_plans: queried by user_id + status (e.g. active plan lookup)
DROP INDEX IF EXISTS idx_training_plans_user_id;
CREATE INDEX idx_training_plans_user_status
  ON training_plans(user_id, status);

-- race_intel: coaching-agent fetches by user_id ordered by fetched_at DESC
DROP INDEX IF EXISTS idx_race_intel_user;
CREATE INDEX idx_race_intel_user_fetched
  ON race_intel(user_id, fetched_at DESC);
