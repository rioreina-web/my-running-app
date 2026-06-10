-- Marathon-prediction honesty (Phase 5).
-- Predictions ship with range + confidence per CLAUDE.md hard rule #7.
--
-- confidence_tier ('high'|'medium'|'low') is the canonical field. The legacy
-- `confidence` column (mixed-case strings) stays for older clients but new
-- code reads confidence_tier.
--
-- range_*_seconds is the half-window around the corresponding point estimate.
-- Renderers show `point ± range` (e.g. 3:11 marathon ± 3 minutes → "3:08–3:14").

ALTER TABLE public.fitness_snapshots
  ADD COLUMN IF NOT EXISTS confidence_tier      text,
  ADD COLUMN IF NOT EXISTS range_mile_seconds     integer,
  ADD COLUMN IF NOT EXISTS range_5k_seconds       integer,
  ADD COLUMN IF NOT EXISTS range_10k_seconds      integer,
  ADD COLUMN IF NOT EXISTS range_half_seconds     integer,
  ADD COLUMN IF NOT EXISTS range_marathon_seconds integer;

-- Constrain confidence_tier values. NULL allowed for legacy rows.
ALTER TABLE public.fitness_snapshots
  DROP CONSTRAINT IF EXISTS fitness_snapshots_confidence_tier_chk;
ALTER TABLE public.fitness_snapshots
  ADD CONSTRAINT fitness_snapshots_confidence_tier_chk
  CHECK (confidence_tier IS NULL OR confidence_tier IN ('high','medium','low'));

COMMENT ON COLUMN public.fitness_snapshots.confidence_tier IS
  'Deterministic tier from signal strength. high = recent race ≥10K or multiple MP workouts; medium = threshold sessions; low = neither.';
COMMENT ON COLUMN public.fitness_snapshots.range_marathon_seconds IS
  'Half-window in seconds around predicted_marathon_seconds. Renderer shows point ± this value.';
