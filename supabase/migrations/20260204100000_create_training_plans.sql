-- Training Plans Table
-- Stores full training plan metadata for marathon preparation

CREATE TABLE training_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,
    goal_id UUID REFERENCES user_goals(id) ON DELETE SET NULL,
    name TEXT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    target_race_distance TEXT NOT NULL DEFAULT 'marathon',
    target_time_seconds INTEGER NOT NULL,
    status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'archived')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_training_plans_user_id ON training_plans(user_id);
CREATE INDEX idx_training_plans_goal_id ON training_plans(goal_id);
CREATE INDEX idx_training_plans_status ON training_plans(status);
CREATE INDEX idx_training_plans_dates ON training_plans(start_date, end_date);

-- RLS Policies
ALTER TABLE training_plans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all operations on training_plans" ON training_plans
    FOR ALL USING (true) WITH CHECK (true);

-- Update trigger for updated_at
CREATE OR REPLACE FUNCTION update_training_plans_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER training_plans_updated_at_trigger
    BEFORE UPDATE ON training_plans
    FOR EACH ROW EXECUTE FUNCTION update_training_plans_updated_at();
