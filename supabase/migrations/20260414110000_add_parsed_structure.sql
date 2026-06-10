-- Parsed workout structure — output of the Observer-layer AI pass.
-- Turns raw per-second streams into a structured understanding of the workout:
-- warmup/work_reps/recovery/cooldown, inferred pattern (e.g. "8x800m @ 2:30"),
-- equivalent race pace. Used by the fitness predictor for training-based anchors.
ALTER TABLE training_logs
  ADD COLUMN IF NOT EXISTS parsed_structure JSONB;

COMMENT ON COLUMN training_logs.parsed_structure IS
  'Observer-layer parse: { type, pattern, blocks[{role, rep_num, distance_miles, duration_s, avg_pace_per_mile, avg_hr}], work_summary{total_distance, total_duration_s, avg_pace, peak_pace}, equivalent_race_pace{distance_key, pace_per_mile, confidence}, parsed_at }';

-- Index for filtering on structure type (finding all intervals, tempos, etc.)
CREATE INDEX IF NOT EXISTS idx_training_logs_structure_type
  ON training_logs ((parsed_structure->>'type'))
  WHERE parsed_structure IS NOT NULL;
