-- Add pace_segments column to training_logs
-- Stores per-segment breakdown from Garmin/Vital stream data
-- Each segment: { effort, distance_miles, duration_seconds, pace_per_mile, avg_heart_rate }
-- Example: [
--   { "effort": "easy", "distance_miles": 2.0, "duration_seconds": 1020, "pace_per_mile": "8:30", "avg_heart_rate": 135 },
--   { "effort": "threshold", "distance_miles": 6.0, "duration_seconds": 2460, "pace_per_mile": "6:50", "avg_heart_rate": 168 },
--   { "effort": "easy", "distance_miles": 2.0, "duration_seconds": 1020, "pace_per_mile": "8:30", "avg_heart_rate": 140 }
-- ]

ALTER TABLE training_logs ADD COLUMN IF NOT EXISTS pace_segments jsonb;

COMMENT ON COLUMN training_logs.pace_segments IS 'Per-segment pace breakdown from watch/GPS stream data';
