-- Voice Processing Pipeline Overhaul
-- Adds structured data columns and formalizes processing status tracking

-- Formalize processing columns (may already exist in live DB but lack migration files)
ALTER TABLE public.training_logs ADD COLUMN IF NOT EXISTS processing_status TEXT DEFAULT 'pending';
ALTER TABLE public.training_logs ADD COLUMN IF NOT EXISTS processing_error TEXT;
ALTER TABLE public.training_logs ADD COLUMN IF NOT EXISTS processing_attempts INTEGER DEFAULT 0;
ALTER TABLE public.training_logs ADD COLUMN IF NOT EXISTS last_processing_attempt TIMESTAMPTZ;

-- New structured data columns from voice processing
ALTER TABLE public.training_logs ADD COLUMN IF NOT EXISTS workout_pace_per_mile TEXT;
ALTER TABLE public.training_logs ADD COLUMN IF NOT EXISTS workout_type TEXT;
ALTER TABLE public.training_logs ADD COLUMN IF NOT EXISTS extracted_data JSONB;

-- Index for stuck-record cleanup queries
CREATE INDEX IF NOT EXISTS idx_training_logs_processing_status
ON public.training_logs(processing_status)
WHERE processing_status IN ('pending', 'processing');

-- Comments
COMMENT ON COLUMN public.training_logs.workout_pace_per_mile IS 'AI-extracted pace from voice memo (e.g. 7:30/mi)';
COMMENT ON COLUMN public.training_logs.workout_type IS 'AI-extracted workout type: easy, tempo, interval, long_run, recovery, race, other';
COMMENT ON COLUMN public.training_logs.extracted_data IS 'JSONB of structured workout data: distance_miles, pace_per_mile, duration_minutes, workout_type, intervals, splits, warmup, cooldown, effort_level';
COMMENT ON COLUMN public.training_logs.coach_insight IS 'Auto-populated coaching insight from voice processing or on-demand coaching agent';
