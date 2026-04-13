-- Composite indexes for scale (20k+ users)
-- Covers the most common query patterns that were missing targeted indexes.

-- training_logs: user_id + workout_date (calendar view, mood data loading)
CREATE INDEX IF NOT EXISTS idx_training_logs_user_workout_date
    ON training_logs (user_id, workout_date DESC);

-- training_logs: user_id + created_at (export, fitness predictor)
CREATE INDEX IF NOT EXISTS idx_training_logs_user_created
    ON training_logs (user_id, created_at DESC);

-- scheduled_workouts: plan_id + date + session (daily workout lookup)
-- Note: idx_scheduled_workouts_date_session exists but only covers (plan_id, date, session)
-- Adding user_id for RLS-filtered queries
CREATE INDEX IF NOT EXISTS idx_scheduled_workouts_user_date
    ON scheduled_workouts (user_id, date);

-- conversations: user_id + updated_at (chat history, sorted by recency)
CREATE INDEX IF NOT EXISTS idx_conversations_user_updated
    ON conversations (user_id, updated_at DESC);

-- user_memories: user_id + updated_at (memory retrieval for coaching)
CREATE INDEX IF NOT EXISTS idx_user_memories_user_updated
    ON user_memories (user_id, updated_at DESC);

-- fitness_snapshots: user_id + created_at already exists as idx_fitness_snapshots_user_date

-- biomechanics_analyses: user_id + recorded_at already exists as idx_biomechanics_user_date

-- form_checks: user_id + recorded_at already exists as idx_form_checks_user_date
