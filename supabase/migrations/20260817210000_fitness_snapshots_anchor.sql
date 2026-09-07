-- fitness_snapshots: carry the ANCHOR, so consumers read instead of re-deriving.
--
-- WHY (2026-08-17)
--
-- `generateFitnessPrediction` has always chosen an anchor race, normalized it
-- to its flat-cool equivalent, and then thrown all of that away — the row it
-- wrote held predicted times and a prose `summary`, nothing machine-readable
-- about what the estimate rested on.
--
-- So every consumer that needed the anchor re-derived it. Seven call sites
-- independently pick an anchor race (build-pace-profile, evaluate-coachable-
-- moment, buildVsLastCycle, trainingZoneSignal, paces.ts, fitnessPrediction,
-- and the iOS on-device predictor), each with its own selection rule and its
-- own idea of whether to normalize for heat. Twelve touch heat normalization.
-- The result: on 2026-08-17 this athlete held FIVE different values for
-- "current fitness" simultaneously (server 10K 32:00, iOS screen 33:44, pace
-- ladder ~32:25, anchor raw 33:02, anchor neutral 32:23) — all correct by
-- their own lights, none authoritative.
--
-- These columns end that argument. One producer (compute-fitness-snapshot)
-- writes the anchor it actually used; consumers read it.
--
-- RAW vs NEUTRAL — the distinction that must never collapse:
--   anchor_raw_seconds     what the athlete RAN. Display. PR eligibility.
--   anchor_neutral_seconds what it PROVES — flat-cool equivalent. Math only.
-- A normalized time is never shown as a time she ran (no-hallucination rule).
-- When nothing was normalizable the two are equal: a missing correction
-- leaves the real number, never a guess.
--
-- Additive + nullable: old rows keep NULL anchors and every existing reader
-- is unaffected. No backfill — these describe a computation, and a row this
-- model didn't write has no anchor to claim. Consumers must treat NULL as
-- "fall back to today's behavior", which is what makes the migration safe to
-- land before any consumer is switched over.

ALTER TABLE public.fitness_snapshots
  ADD COLUMN IF NOT EXISTS anchor_race_log_id     uuid,
  ADD COLUMN IF NOT EXISTS anchor_distance_key    text,
  ADD COLUMN IF NOT EXISTS anchor_raw_seconds     integer,
  ADD COLUMN IF NOT EXISTS anchor_neutral_seconds integer,
  ADD COLUMN IF NOT EXISTS anchor_date            date,
  ADD COLUMN IF NOT EXISTS anchor_weeks_ago       numeric,
  ADD COLUMN IF NOT EXISTS anchor_conditions      jsonb,
  ADD COLUMN IF NOT EXISTS lifetime_prs           jsonb;

COMMENT ON COLUMN public.fitness_snapshots.anchor_race_log_id IS
  'training_logs id of the race this estimate rests on. NULL when no race anchored it (training-only estimate) or when written before 2026-08-17.';
COMMENT ON COLUMN public.fitness_snapshots.anchor_raw_seconds IS
  'What the athlete actually ran. Use for display and PR context — never for math.';
COMMENT ON COLUMN public.fitness_snapshots.anchor_neutral_seconds IS
  'Flat-cool (heat + grade) equivalent of the anchor. Use for math — never displayed as a time she ran. Equals raw when nothing was normalizable.';
COMMENT ON COLUMN public.fitness_snapshots.anchor_conditions IS
  'Conditions the anchor race was run in: {tempF, dewPointF, ...}. The evidence behind anchor_neutral_seconds.';
COMMENT ON COLUMN public.fitness_snapshots.lifetime_prs IS
  'Fastest confirmed finish per distance, any age: {distance: {timeSeconds, date}}. Context alongside a projection (CLAUDE.md hard rule #7) — never a fitness anchor.';
