-- Add coach_insight column to training_logs for persisting AI coaching feedback
ALTER TABLE training_logs
ADD COLUMN IF NOT EXISTS coach_insight TEXT;

-- Add index for quick lookups of entries with/without coach insights
CREATE INDEX IF NOT EXISTS idx_training_logs_coach_insight
ON training_logs(id)
WHERE coach_insight IS NOT NULL;
