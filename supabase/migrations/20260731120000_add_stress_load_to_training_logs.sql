-- Per-workout cumulative-stress foundation.
--
-- Adds a persisted per-workout training-stress scalar to training_logs so the
-- workout carries its own load, and downstream (Phase 2: CTL/ATL/TSB) can
-- accumulate a coherent fitness curve. Until now the only per-workout load
-- number (`intensity_score * duration`) was computed on the fly in
-- weeklyAnalytics.ts:computeWeightedLoadForLog and never stored — so nothing
-- was visible on the workout and nothing could be rolled up.
--
-- UNIT: weighted training-minutes. Same unit as computeWeightedLoadForLog and
-- anchored to workout_features.intensity_score / ZONE_WEIGHTS. This is a
-- MECHANICAL load model (pace/impact), not cardiovascular — consistent with
-- the rest of the system (cross-training/strength are excluded; see
-- compute-workout-features). All source tiers estimate THIS quantity so the
-- values remain comparable across workouts.
--
-- stress_source records which tier produced the value:
--   'pace'     — intensity_score * duration (real intra-workout pace data)
--   'rpe'      — felt_rpe mapped to intensity * duration (no usable splits)
--   'type'     — workout_type fallback weight * duration
--   'hr'       — HR-derived intensity * duration (reserved; needs HR profile)
--   'excluded' — cross_training / strength / rest (not running mechanical load)
--   'none'     — no duration; nothing to score
--
-- New columns only; existing training_logs RLS covers them (no new table, so
-- no new policy required — hard rule #1 applies to new tables).

ALTER TABLE public.training_logs
  ADD COLUMN IF NOT EXISTS stress_load double precision,
  ADD COLUMN IF NOT EXISTS stress_source text;

COMMENT ON COLUMN public.training_logs.stress_load IS
  'Per-workout training stress in weighted training-minutes (mechanical load). '
  'Computed by compute-workout-features. Accumulated into CTL/ATL/TSB (Phase 2).';
COMMENT ON COLUMN public.training_logs.stress_source IS
  'Which tier produced stress_load: pace | rpe | type | hr | excluded | none.';
