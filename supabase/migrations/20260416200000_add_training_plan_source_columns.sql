-- Add source_type and plan_type columns to training_plans.
-- The Swift model already reads these fields; without them in the DB the
-- select query returns NULL for both, which means isCoachPlan and isAdaptive
-- always return false regardless of how the plan was created.

ALTER TABLE training_plans
    ADD COLUMN IF NOT EXISTS source_type TEXT NOT NULL DEFAULT 'self'
        CHECK (source_type IN ('self', 'coach', 'ai')),
    ADD COLUMN IF NOT EXISTS plan_type TEXT NOT NULL DEFAULT 'fixed'
        CHECK (plan_type IN ('fixed', 'adaptive'));
