-- Allow plan templates from 1 to 24 weeks (previously 8-24).
ALTER TABLE plan_templates DROP CONSTRAINT IF EXISTS plan_templates_duration_weeks_check;
ALTER TABLE plan_templates
    ADD CONSTRAINT plan_templates_duration_weeks_check
    CHECK (duration_weeks BETWEEN 1 AND 24);
