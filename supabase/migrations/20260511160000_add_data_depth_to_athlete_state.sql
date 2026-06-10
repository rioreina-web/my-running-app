-- Adds `data_depth` to athlete_state — a 0–3 UI register gate.
-- Semantics:
--   0  new account, no runs/voice logs
--   1  1+ run OR 1+ voice log
--   2  7+ distinct training days
--   3  21+ distinct training days, OR a goal set with 1+ run
-- The value is recomputed inside rebuildAthleteState() on every rebuild.
-- See supabase/functions/_shared/athlete-state.ts:computeDataDepth.

ALTER TABLE public.athlete_state
  ADD COLUMN IF NOT EXISTS data_depth integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN public.athlete_state.data_depth IS
  'UI register gate (0..3). Derived in rebuildAthleteState — see athlete-state.ts.';
