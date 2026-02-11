-- Scheduled Workouts Table
-- Stores individual scheduled workouts within a training plan

CREATE TABLE scheduled_workouts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES training_plans(id) ON DELETE CASCADE,
    date DATE NOT NULL,
    day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),
    week_number INTEGER NOT NULL CHECK (week_number > 0),
    workout_data JSONB,  -- Stores CanovaWorkout as JSON (null for rest days)
    workout_type TEXT NOT NULL CHECK (workout_type IN ('rest', 'easy', 'tempo', 'intervals', 'long_run', 'recovery', 'race')),
    status TEXT NOT NULL DEFAULT 'scheduled' CHECK (status IN ('scheduled', 'completed', 'skipped', 'modified')),
    completed_workout_id UUID,  -- HealthKit workout UUID when marked complete
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_scheduled_workouts_plan_id ON scheduled_workouts(plan_id);
CREATE INDEX idx_scheduled_workouts_date ON scheduled_workouts(date);
CREATE INDEX idx_scheduled_workouts_week ON scheduled_workouts(plan_id, week_number);
CREATE INDEX idx_scheduled_workouts_status ON scheduled_workouts(status);

-- Unique constraint: one workout per day per plan
CREATE UNIQUE INDEX idx_scheduled_workouts_unique_date ON scheduled_workouts(plan_id, date);

-- RLS Policies
ALTER TABLE scheduled_workouts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all operations on scheduled_workouts" ON scheduled_workouts
    FOR ALL USING (true) WITH CHECK (true);

-- Update trigger for updated_at
CREATE OR REPLACE FUNCTION update_scheduled_workouts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER scheduled_workouts_updated_at_trigger
    BEFORE UPDATE ON scheduled_workouts
    FOR EACH ROW EXECUTE FUNCTION update_scheduled_workouts_updated_at();
