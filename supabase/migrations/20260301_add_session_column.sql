-- Add session column to support doubles (AM/PM workouts on the same day)
-- Session 1 = first run of the day, Session 2 = second run, etc.

ALTER TABLE scheduled_workouts
    ADD COLUMN IF NOT EXISTS session INTEGER NOT NULL DEFAULT 1;

-- Index for ordering within a day
CREATE INDEX IF NOT EXISTS idx_scheduled_workouts_date_session
    ON scheduled_workouts(plan_id, date, session);
