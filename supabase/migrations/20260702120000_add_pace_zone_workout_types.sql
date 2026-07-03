-- ─────────────────────────────────────────────────────────────────────
-- Add the pace-zone workout vocabulary (Wave 2 · H1)
-- ─────────────────────────────────────────────────────────────────────
--
-- Context: the product's canonical workout labels are now pace-zone
-- labels (Easy · Moderate · Steady · MP · HMP · LT · 10K · 5K · 3K ·
-- Mile) plus structural labels (Long run · Long wo · Cross-train ·
-- Strength · Rest · Race). See CLAUDE.md "Pace zones" / "Workout labels".
--
-- This migration WIDENS the workout_type CHECK constraints on
-- scheduled_workouts and workout_templates so the new zone keys are
-- accepted. It is deliberately ADDITIVE: every previously-allowed value
-- (including the legacy 'tempo', 'intervals', 'progression', 'fartlek',
-- 'hills') is retained, so no existing row is invalidated. "Tempo" is
-- kept for legacy data; it is simply no longer offered when logging a
-- NEW workout (enforced in the app, ManualWorkoutView).
--
-- training_logs.workout_type is intentionally left unconstrained (it has
-- always been free TEXT and holds historical/imported values like
-- 'other'); adding a CHECK there risks failing on legacy rows and buys
-- little, so we don't.
--
-- Reversibility: to roll back, drop these two constraints and re-add the
-- 10-value CHECK from 20260611130000_workout_type_vocabulary.sql. Do NOT
-- edit that migration — write a new one (migrations are append-only).
--
-- Apply via `supabase db push` from a committed SHA (hard rule #9). Do
-- not apply through the dashboard SQL editor or MCP apply_migration.

BEGIN;

-- The full accepted set = legacy vocabulary + pace zones + structural.
--   Legacy (retained):  long_run, tempo, intervals, progression,
--                        fartlek, hills, easy, recovery, rest, race
--   New effort zones:    moderate, steady
--   New race-pace zones: mp, hmp, lt, 10k, 5k, 3k, mile
--   New structural:      long_wo, cross_train, strength

ALTER TABLE scheduled_workouts
  DROP CONSTRAINT IF EXISTS scheduled_workouts_workout_type_check;

ALTER TABLE scheduled_workouts
  ADD CONSTRAINT scheduled_workouts_workout_type_check
  CHECK (workout_type IN (
    -- legacy (retained for existing rows)
    'long_run', 'tempo', 'intervals', 'progression', 'fartlek', 'hills',
    'easy', 'recovery', 'rest', 'race',
    -- new effort zones
    'moderate', 'steady',
    -- new race-pace zones
    'mp', 'hmp', 'lt', '10k', '5k', '3k', 'mile',
    -- new structural
    'long_wo', 'cross_train', 'strength'
  ));

ALTER TABLE workout_templates
  DROP CONSTRAINT IF EXISTS workout_templates_workout_type_check;

ALTER TABLE workout_templates
  ADD CONSTRAINT workout_templates_workout_type_check
  CHECK (workout_type IN (
    'long_run', 'tempo', 'intervals', 'progression', 'fartlek', 'hills',
    'easy', 'recovery', 'rest', 'race',
    'moderate', 'steady',
    'mp', 'hmp', 'lt', '10k', '5k', '3k', 'mile',
    'long_wo', 'cross_train', 'strength'
  ));

COMMIT;

-- ── Verification (run manually after deploy) ─────────────────────────
--   SELECT DISTINCT workout_type FROM scheduled_workouts;
--   SELECT DISTINCT workout_type FROM workout_templates;
--   -- Every value should be inside the set above; the migration fails
--   -- loudly on apply if any existing row falls outside it.
