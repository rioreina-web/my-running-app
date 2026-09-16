-- athlete_state — objective fitness signal (pace-at-HR efficiency trend)
--
-- See outputs/the-read-handoff-2026-06-15.md item #3 and
-- _shared/fitnessSignal.ts.
--
-- Adds one more JSONB "satellite" block to the existing athlete_state row, in
-- the same append-only style as 20260612120000_athlete_state_v2_satellites.sql.
-- Assembled by rebuildAthleteState() from running_workout_laps:
--
--   fitness_signal — pace-at-HR efficiency trend over a 12-week scan window.
--                    Per-rep pace + HR rolled UP across sessions, bucketed by
--                    comparable effort (easy / threshold / interval): "same
--                    pace, HR direction" = the objective fitness verdict, plus
--                    long-run aerobic decoupling. Direction + window +
--                    sample-based confidence — never a point estimate
--                    (hard rule #7).
--
-- Nullable, no default beyond NULL, so existing rows and the existing rebuild
-- path are unaffected until the builder populates it. RLS on athlete_state
-- already covers this column (same row, existing policies) — no policy change
-- is required.

ALTER TABLE public.athlete_state
  ADD COLUMN IF NOT EXISTS fitness_signal jsonb;

COMMENT ON COLUMN public.athlete_state.fitness_signal IS
  'Objective fitness backbone: pace-at-HR efficiency trend (speed-per-heartbeat) over a 12-week window, bucketed by comparable effort, plus long-run aerobic decoupling. Direction + window + confidence, never a point estimate. Built by _shared/fitnessSignal.ts.';
