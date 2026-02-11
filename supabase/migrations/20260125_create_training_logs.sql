-- Create training_logs table
CREATE TABLE IF NOT EXISTS public.training_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_at TIMESTAMPTZ DEFAULT now(),
    audio_url TEXT,
    notes TEXT,
    cleaned_notes TEXT,
    mood TEXT,
    workout_date TIMESTAMPTZ,
    workout_distance_miles DOUBLE PRECISION,
    workout_duration_minutes DOUBLE PRECISION
);

-- Enable RLS
ALTER TABLE public.training_logs ENABLE ROW LEVEL SECURITY;

-- Allow anonymous access for local development
CREATE POLICY "Allow all access" ON public.training_logs
    FOR ALL
    USING (true)
    WITH CHECK (true);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_training_logs_created_at ON public.training_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_training_logs_workout_date ON public.training_logs(workout_date);
