-- ============================================================================
-- WS1: persist derived workout classification on workout_features
--
-- compute-workout-features now classifies each session from rep-level laps
-- (see supabase/functions/_shared/workoutSegmentation.ts). Persist the derived
-- session type + human-readable structure string so downstream surfaces (the
-- Read, the model-of-you workout card) can name the session without recomputing.
--
-- `workout_type` here is the detection label (intervals / threshold / tempo /
-- fartlek / progression / long_run / easy / recovery / race). training_logs
-- also carries workout_type (backfilled by the function where it was null) for
-- scheduling/display; this column is the load-engine's own derivation.
--
-- Append-only. No RLS change: workout_features already has row-level security
-- from its creating migration; adding nullable columns does not alter it.
-- ============================================================================

ALTER TABLE workout_features
  ADD COLUMN IF NOT EXISTS workout_type TEXT,
  ADD COLUMN IF NOT EXISTS workout_structure TEXT;

COMMENT ON COLUMN workout_features.workout_type IS
  'WS1 detection label from pace-classified bouts: intervals|threshold|tempo|fartlek|progression|long_run|easy|recovery|race.';
COMMENT ON COLUMN workout_features.workout_structure IS
  'WS1 human-readable rep structure, e.g. "9×1K @ 5:07 (5K)". Null for non-structured sessions.';
