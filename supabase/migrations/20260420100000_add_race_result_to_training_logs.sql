-- Race Result: structured declaration on training_logs
--
-- Replaces regex-based race detection (athlete-state.ts rebuild) with an
-- explicit user-declared structure. Race detection should never be inferred
-- from notes — the user marks a run as a race, and this column holds the
-- canonical result.
--
-- race_result shape (when workout_type = 'race'):
-- {
--   "distance": "5K" | "10K" | "half" | "marathon" | "mile" | "other",
--   "distance_custom_meters": number | null,
--   "finish_time_seconds": integer,
--   "official": boolean,
--   "event_name": string | null
-- }

ALTER TABLE training_logs
    ADD COLUMN IF NOT EXISTS race_result jsonb;

CREATE INDEX IF NOT EXISTS idx_training_logs_race
    ON training_logs (user_id, workout_date DESC)
    WHERE workout_type = 'race';

-- Derived cache on athlete_state. Populated from training_logs.race_result
-- during rebuildAthleteState. Trusted, user-declared only.
ALTER TABLE athlete_state
    ADD COLUMN IF NOT EXISTS confirmed_races jsonb NOT NULL DEFAULT '[]'::jsonb;

-- Drop the legacy regex-inferred race_history. Replaced entirely by
-- confirmed_races (user-declared) per the no-race-inference constraint.
ALTER TABLE athlete_state
    DROP COLUMN IF EXISTS race_history;
