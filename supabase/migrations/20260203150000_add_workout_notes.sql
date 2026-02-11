-- Add workout_notes column to training_logs for storing splits, paces, and other workout details
ALTER TABLE public.training_logs
ADD COLUMN IF NOT EXISTS workout_notes TEXT;

-- Add comment to document the purpose
COMMENT ON COLUMN public.training_logs.workout_notes IS 'User-entered workout details like splits, paces, intervals, etc.';
