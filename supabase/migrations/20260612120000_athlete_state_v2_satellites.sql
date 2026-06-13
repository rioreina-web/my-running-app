-- athlete_state v2 — coach-grade satellite columns
--
-- See outputs/athlete-state-v2-coach-grade-2026-06-12.md.
--
-- Adds JSONB "satellite" blocks to the existing athlete_state row rather
-- than widening it with dozens of scalar columns. Each block is assembled
-- by rebuildAthleteState() from precomputed source tables:
--
--   load_distribution  — volume × intensity distribution (NOT ACWR), from
--                        workout_features time-in-zone (easy/moderate/
--                        threshold/hard seconds) + effort_distribution +
--                        intensity_score. Mirrors PaceVolumeSpectrumChart.
--   fitness_prediction — range_* low/high + confidence_tier from
--                        fitness_snapshots (range + confidence, never a
--                        point estimate — hard rule #7).
--   memories           — durable coach memory from user_memories
--                        (preferences, life context, constraints, decisions).
--   execution          — per-quality-session pacing/HR-drift/split analysis
--                        from running_workout_laps. (Phase B — reserved.)
--   environment        — per-run heat/elevation context from
--                        running_workout_laps. (Phase B — reserved.)
--   patterns           — longitudinal correlations. (Phase D — reserved.)
--   field_provenance   — per-field source + as-of + confidence envelope.
--                        (Phase E — reserved.)
--
-- All columns are nullable with no default beyond NULL, so existing rows
-- and the existing rebuild path are unaffected until the builder populates
-- them. Append-only; RLS on athlete_state already covers these columns
-- (same row, existing policies) so no policy change is required.

ALTER TABLE public.athlete_state
  ADD COLUMN IF NOT EXISTS load_distribution jsonb,
  ADD COLUMN IF NOT EXISTS fitness_prediction jsonb,
  ADD COLUMN IF NOT EXISTS memories jsonb,
  ADD COLUMN IF NOT EXISTS execution jsonb,
  ADD COLUMN IF NOT EXISTS environment jsonb,
  ADD COLUMN IF NOT EXISTS patterns jsonb,
  ADD COLUMN IF NOT EXISTS data_gaps jsonb,
  ADD COLUMN IF NOT EXISTS field_provenance jsonb;

COMMENT ON COLUMN public.athlete_state.load_distribution IS
  'Volume x intensity distribution from workout_features time-in-zone. Replaces ACWR as the prompt-facing load model. See athlete-state-v2 spec.';
COMMENT ON COLUMN public.athlete_state.fitness_prediction IS
  'Range + confidence predictions from fitness_snapshots (never point estimates).';
COMMENT ON COLUMN public.athlete_state.memories IS
  'Durable coach memory assembled from user_memories.';
COMMENT ON COLUMN public.athlete_state.data_gaps IS
  'Computed blind spots (no mood, no laps, thin prediction, one-point niggle) that ground the Read''s cant_see block instead of the model guessing.';
