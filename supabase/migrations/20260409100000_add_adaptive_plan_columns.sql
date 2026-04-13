-- Add columns needed by the adaptive plan builder.
-- The web plan-builder writes plan_type, day_structure, phase_config, and
-- weekly_mileage_targets when saving an adaptive plan, but plan_templates
-- (created in 20260312_coach_training_plans.sql) only has the columns for
-- fixed-week plans. Without these columns the adaptive save silently drops
-- the config (or errors, depending on PostgREST settings).

ALTER TABLE plan_templates
    ADD COLUMN IF NOT EXISTS plan_type TEXT NOT NULL DEFAULT 'fixed'
        CHECK (plan_type IN ('fixed', 'adaptive')),
    ADD COLUMN IF NOT EXISTS day_structure JSONB NOT NULL DEFAULT '[]'::jsonb,
        -- [{ "dayOfWeek": 0, "role": "easy" }, ...]   0=Mon..6=Sun
        -- role ∈ rest|easy|speed|moderate|long_run|recovery|strides
    ADD COLUMN IF NOT EXISTS phase_config JSONB NOT NULL DEFAULT '{}'::jsonb,
        -- { "phases": [{ "name": "base", "startWeek": 1, "endWeek": 4 }, ...] }
        -- name ∈ base|build|specific|taper
    ADD COLUMN IF NOT EXISTS weekly_mileage_targets JSONB NOT NULL DEFAULT '[]'::jsonb;
        -- [{ "weekNumber": 1, "targetMiles": 40, "phase": "base" }, ...]
