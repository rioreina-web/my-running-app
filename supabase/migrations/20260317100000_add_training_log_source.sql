-- Add source column to distinguish how training logs were created
ALTER TABLE training_logs ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'voice_log';

-- Add vital_workout_id for dedup of auto-synced workouts
ALTER TABLE training_logs ADD COLUMN IF NOT EXISTS vital_workout_id text;

-- Unique index on vital_workout_id to prevent duplicate auto-sync entries
CREATE UNIQUE INDEX IF NOT EXISTS idx_training_logs_vital_workout_id
  ON training_logs (vital_workout_id)
  WHERE vital_workout_id IS NOT NULL;
