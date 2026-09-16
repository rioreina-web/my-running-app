-- ============================================================================
-- Athlete workout builder — duplicate-to-day vocabulary (2026-07-15)
--
-- The iOS workout builder lets an athlete duplicate a scheduled workout onto
-- another (future) day. The write path is the edit-scheduled-workout edge
-- function (service-role, ownership-checked — same posture as shift-day /
-- the 2026-07-09 edit_workout flow). Two vocab additions:
--
-- 1. scheduled_workouts.source gains 'user_created' — a workout the athlete
--    placed themselves via duplicate (or a future create-from-scratch flow).
--    Distinct from 'athlete_drag' (athlete placed a coach-authored quality
--    session from the weekly pool) and 'coach_locked' (coach prescription).
--    user_created rows are athlete-owned: movable, editable, not part of the
--    coach's prescription.
--
-- 2. plan_adjustments.action_type gains 'duplicate_workout' — the audit row
--    written when a duplicate lands. trigger_type 'user_action' and the
--    green/yellow tiers are already permitted by their CHECKs (20260703120000
--    / 20260424100000); only action_type needs the new value. Duplicating a
--    coach-issued ('coach_locked') workout logs yellow so the coach sees the
--    added quality volume; duplicating one's own workout logs green.
--
-- No new tables → no new RLS. plan_adjustments keeps its existing posture:
-- athlete SELECT own rows, guarded UPDATE (ack/revert columns only), all
-- INSERTs via service-role edge functions (20260417600000). scheduled_workouts
-- RLS is untouched.
--
-- Append-only per CLAUDE.md hard rule #5. Reaches prod only via
-- `supabase db push` from a committed SHA (hard rule #9).
-- ============================================================================

BEGIN;

-- ── 1. scheduled_workouts.source: add 'user_created' ───────────────────────

ALTER TABLE scheduled_workouts
    DROP CONSTRAINT IF EXISTS scheduled_workouts_source_check;

ALTER TABLE scheduled_workouts
    ADD CONSTRAINT scheduled_workouts_source_check
        CHECK (source IN (
            'coach_locked',   -- coach prescription (quality sessions)
            'athlete_drag',   -- athlete placed a pool quality session
            'easy_fill',      -- system-generated easy filler
            'legacy',         -- pre-two-lane rows
            'user_created'    -- athlete-created (duplicate / self-built), 2026-07-15
        ));

COMMENT ON COLUMN scheduled_workouts.source IS
    'Who placed this workout on this date. coach_locked = coach prescription; '
    'athlete_drag = athlete placed a pool session; easy_fill = system filler; '
    'legacy = pre-two-lane rows; user_created = athlete-created via the iOS '
    'workout builder (duplicate-to-day or self-built).';

-- ── 2. plan_adjustments.action_type: add 'duplicate_workout' ───────────────

ALTER TABLE plan_adjustments
    DROP CONSTRAINT IF EXISTS plan_adjustments_action_type_check;

ALTER TABLE plan_adjustments
    ADD CONSTRAINT plan_adjustments_action_type_check
        CHECK (action_type IN (
            'reprice_future_paces',
            'reduce_volume',
            'cap_volume',
            'propose_swap',
            'update_fitness',
            'pause_quality',
            'shift_day',          -- athlete shifts a single day within a week
            'reshape_week',       -- athlete re-plans a week within coach constraints
            'rewrite_block',      -- coach rewrites a multi-week block
            'edit_workout',       -- athlete edits a workout's structure (2026-07-09)
            'duplicate_workout'   -- athlete duplicates a workout to another day (2026-07-15)
        ));

COMMIT;
