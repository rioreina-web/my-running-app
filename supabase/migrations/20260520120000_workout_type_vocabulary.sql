-- Workout type vocabulary — v1 canonical taxonomy
--
-- See outputs/workout-system-rebuild.md for full context and decisions.
--
-- Changes:
--   1. Backfills workout_type = 'strides' rows to workout_type = 'easy'
--      with a strides modifier in workout_data. Strides become a property
--      of an easy workout, not a workout type themselves.
--   2. Updates scheduled_workouts.workout_type CHECK to the canonical
--      10-value vocabulary (adds fartlek, hills; removes strides).
--   3. Adds the same CHECK to workout_templates.workout_type
--      (previously unconstrained TEXT with DEFAULT 'easy').
--
-- The canonical 10 workout types:
--   long_run, tempo, intervals, progression, fartlek, hills,
--   easy, recovery, rest, race
--
-- Strides modifier shape in workout_data:
--   { ..., "strides": { "count": 6, "effort": "relaxed" } }
--
-- This migration is reversible only by writing a new migration that
-- restores the old CHECK constraints and back-migrates the strides
-- modifier into separate rows. Per CLAUDE.md rule #5, migrations are
-- append-only.

BEGIN;

-- ── 1. Backfill: strides workouts → easy + modifier ──────────────
--
-- Existing rows with workout_type = 'strides' get rewritten:
--   - workout_type becomes 'easy'
--   - workout_data gains a strides modifier (count: 6, effort: 'relaxed')
--   - workout_data.name retains "+ strides" suffix if not already present
--
-- Default modifier values (count 6, effort 'relaxed') are conservative.
-- Coaches can adjust per-workout via the coach portal after the migration.

UPDATE scheduled_workouts
SET
  workout_type = 'easy',
  workout_data = jsonb_set(
    COALESCE(workout_data, '{}'::jsonb),
    '{strides}',
    '{"count": 6, "effort": "relaxed"}'::jsonb,
    true
  )
WHERE workout_type = 'strides';

UPDATE workout_templates
SET
  workout_type = 'easy',
  workout_data = jsonb_set(
    COALESCE(workout_data, '{}'::jsonb),
    '{strides}',
    '{"count": 6, "effort": "relaxed"}'::jsonb,
    true
  )
WHERE workout_type = 'strides';

-- ── 2. Update scheduled_workouts.workout_type CHECK ──────────────
--
-- Old CHECK allowed: rest, easy, tempo, intervals, long_run, recovery,
--                    race, progression, strides (9 values).
-- New CHECK allows:  long_run, tempo, intervals, progression, fartlek,
--                    hills, easy, recovery, rest, race (10 values).
--
-- Net change: adds fartlek + hills; removes strides (now a modifier).

ALTER TABLE scheduled_workouts
  DROP CONSTRAINT IF EXISTS scheduled_workouts_workout_type_check;

ALTER TABLE scheduled_workouts
  ADD CONSTRAINT scheduled_workouts_workout_type_check
  CHECK (workout_type IN (
    'long_run',
    'tempo',
    'intervals',
    'progression',
    'fartlek',
    'hills',
    'easy',
    'recovery',
    'rest',
    'race'
  ));

-- ── 3. Add CHECK to workout_templates.workout_type ───────────────
--
-- workout_templates.workout_type was previously unconstrained TEXT with
-- DEFAULT 'easy'. The coach portal UI gated authoring to a subset of
-- values but the database accepted anything. This adds the canonical
-- 10-value enforcement.
--
-- If any existing template rows fall outside the canonical 10, this
-- migration will fail with a constraint violation — that's intended.
-- Investigate the offending rows, decide whether to migrate them
-- (likely to the closest canonical type) or remove them, and add the
-- correction to this migration before reapplying.

ALTER TABLE workout_templates
  ADD CONSTRAINT workout_templates_workout_type_check
  CHECK (workout_type IN (
    'long_run',
    'tempo',
    'intervals',
    'progression',
    'fartlek',
    'hills',
    'easy',
    'recovery',
    'rest',
    'race'
  ));

COMMIT;

-- ── Verification queries (run manually after deploy) ─────────────
--
-- Confirm no strides rows remain:
--   SELECT COUNT(*) FROM scheduled_workouts WHERE workout_type = 'strides';
--   SELECT COUNT(*) FROM workout_templates  WHERE workout_type = 'strides';
--   Both should return 0.
--
-- Confirm strides modifier was attached correctly on migrated rows:
--   SELECT id, workout_data->'strides' FROM scheduled_workouts
--   WHERE workout_data ? 'strides' LIMIT 10;
--
-- Confirm distinct workout_type values are all canonical:
--   SELECT DISTINCT workout_type FROM scheduled_workouts;
--   SELECT DISTINCT workout_type FROM workout_templates;
