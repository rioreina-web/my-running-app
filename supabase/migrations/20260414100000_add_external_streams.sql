-- Add external_streams JSONB column to training_logs for rich sensor data.
-- Holds per-second streams (HR, pace, GPS, altitude, cadence, grade, temp, time),
-- manual laps, and source-specific metadata. Source-agnostic: works for Strava now,
-- can hold HealthKit or Garmin stream data later.
ALTER TABLE training_logs
  ADD COLUMN IF NOT EXISTS external_streams JSONB;

COMMENT ON COLUMN training_logs.external_streams IS
  'Per-second sensor streams + laps + source metadata. Shape: { source, activity_id, streams: { heartrate, velocity_smooth, latlng, altitude, cadence, grade_smooth, temp, time }, laps, meta }';
