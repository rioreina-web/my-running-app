-- Plan Builder setup: expand workout types and create storage bucket

-- Expand workout_type constraint to include progression and strides
ALTER TABLE scheduled_workouts
    DROP CONSTRAINT IF EXISTS scheduled_workouts_workout_type_check;

ALTER TABLE scheduled_workouts
    ADD CONSTRAINT scheduled_workouts_workout_type_check
    CHECK (workout_type IN ('rest', 'easy', 'tempo', 'intervals', 'long_run',
                            'recovery', 'race', 'progression', 'strides'));

-- Drop unique date constraint to allow AM/PM double days
DROP INDEX IF EXISTS idx_scheduled_workouts_unique_date;

-- Create plan-attachments storage bucket
INSERT INTO storage.buckets (id, name, public)
VALUES ('plan-attachments', 'plan-attachments', true)
ON CONFLICT (id) DO NOTHING;

-- RLS policies for plan-attachments bucket
CREATE POLICY "Allow authenticated uploads to plan-attachments"
ON storage.objects FOR INSERT
WITH CHECK (bucket_id = 'plan-attachments');

CREATE POLICY "Allow public reads from plan-attachments"
ON storage.objects FOR SELECT
USING (bucket_id = 'plan-attachments');
