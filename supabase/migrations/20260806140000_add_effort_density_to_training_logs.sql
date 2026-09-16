-- Density-aware effort load.
--
-- WHY
-- ---
-- `stress_load` is `intensity_score * duration`, and duration includes the
-- recovery between reps. So cutting the rest — which makes a session harder —
-- makes the number go DOWN. On a real pair:
--
--   10x1K @ 3:15 w/ 90" rest -> 66.0 min, stress_load 212.3
--   10x1K @ 3:15 w/ 60" rest -> 61.5 min, stress_load 207.8   <- harder, lower
--
-- Same work, same paces, a third less recovery, and the model preferred the
-- easier session. Rest was recorded on running_workout_laps and then discarded
-- by every load surface downstream.
--
-- WHAT THESE COLUMNS ARE
-- ----------------------
-- `effort_load` is the density-aware twin of `stress_load`, in the SAME unit
-- (weighted training-minutes, anchored to ZONE_WEIGHTS), so the two are
-- directly comparable and effort_load can accumulate into the same CTL/ATL/TSB
-- curve when we choose to promote it.
--
-- It is added ALONGSIDE stress_load, not over it. Flipping the canonical load
-- retroactively changes every athlete's fitness curve and needs its own
-- deliberate migration + backfill; it is not a side effect of shipping the
-- measurement. Until that call is made, stress_load stays canonical and
-- effort_load is the second opinion.
--
-- Conditions (heat, grade) are NOT a separate column here: they enter through
-- the pace. A rep in hot or hilly conditions is rewritten to its neutral
-- equivalent before segmentation, so it lands further up the intensity curve
-- and earns a higher weight on its own. See _shared/effortModel.ts.
--
-- density_baseline_source records what the density was measured against:
--   'athlete'    — this athlete's own median rest ratio in that zone
--                  (>= 3 prior sessions; strictly backward-looking)
--   'cold_start' — no rep history in the zone yet; ZONE_REST_RATIO_FALLBACK
--   'none'       — no measurable rep block (steady run, single rep, no laps)
--
-- New columns only; existing training_logs RLS covers them (no new table, so
-- no new policy required — hard rule #1 applies to new tables).

ALTER TABLE public.training_logs
  ADD COLUMN IF NOT EXISTS effort_load double precision,
  ADD COLUMN IF NOT EXISTS density_pct double precision,
  ADD COLUMN IF NOT EXISTS rest_ratio double precision,
  ADD COLUMN IF NOT EXISTS density_multiplier double precision,
  ADD COLUMN IF NOT EXISTS density_baseline_source text;

COMMENT ON COLUMN public.training_logs.effort_load IS
  'Density-aware per-workout effort in weighted training-minutes. Same unit as '
  'stress_load; work bouts scaled by density_multiplier, recovery unscaled. '
  'Computed by compute-workout-features via _shared/effortModel.ts.';
COMMENT ON COLUMN public.training_logs.density_pct IS
  'Work as a percent of the rep block (work + inter-rep recovery). Warmup and '
  'cooldown excluded. NULL when the session has no measurable rep block.';
COMMENT ON COLUMN public.training_logs.rest_ratio IS
  'Median recovery seconds per second of work between reps. Shape-independent, '
  'so 10x1K and 6xmile are comparable on it.';
COMMENT ON COLUMN public.training_logs.density_multiplier IS
  'Load multiplier applied to work bouts, from rest_ratio vs the athlete''s own '
  'habit in that zone. Exactly 1.0 when density is unknown — an unmeasurable '
  'session is never penalised or credited.';
COMMENT ON COLUMN public.training_logs.density_baseline_source IS
  'What density was measured against: athlete | cold_start | none.';
