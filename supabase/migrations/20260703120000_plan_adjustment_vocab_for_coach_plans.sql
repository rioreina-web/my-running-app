-- ============================================================================
-- Plan adjustments — vocabulary for the coach adaptive-plan work
-- (outputs/adaptive-coach-plan-builder-spec-2026-07-03.md, Phase A)
--
-- Two things:
--
-- 1. BUG FIX: `shift-day` has been inserting trigger_type='user_action'
--    since 2026-04, but the trigger_type CHECK (20260417600000) never
--    included that value — so every athlete day-move audit insert has been
--    silently failing (the fn logs and continues; workouts moved, ledger
--    stayed empty). Add 'user_action' so the ledger actually records
--    athlete shifts.
--
-- 2. Phase B vocabulary, added now so the constraint churn happens once:
--    trigger_type 'coach_rewrite' + action_type 'rewrite_block' for the
--    coach mid-block rewrite flow (`rewrite-block` edge fn).
--
-- Also refreshes the reason_code comment with the closed vocabulary the
-- move-day UX uses. reason_code intentionally stays comment-documented
-- rather than CHECK-constrained: it's a UI picker bucket, not an integrity
-- boundary, and older rows carry the 2026-04 vocabulary.
-- ============================================================================

BEGIN;

ALTER TABLE plan_adjustments
    DROP CONSTRAINT IF EXISTS plan_adjustments_trigger_type_check;

ALTER TABLE plan_adjustments
    ADD CONSTRAINT plan_adjustments_trigger_type_check
        CHECK (trigger_type IN (
            'pace_over_target',
            'pace_under_target',
            'missed_sessions',
            'race_result',
            'volume_ramp_risk',
            'heat_forecast',
            'weekly_rebalance',
            'user_action',       -- athlete-initiated (shift-day, reshape-week)
            'coach_rewrite'      -- coach edits a live plan block (Phase B)
        ));

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
            'shift_day',           -- athlete shifts a single day within a week
            'reshape_week',        -- athlete re-plans a week within coach constraints
            'rewrite_block'        -- coach rewrites a multi-week block (Phase B)
        ));

COMMENT ON COLUMN plan_adjustments.reason_code IS
    'Bucket for the change. Move-day vocabulary (2026-07): work, fatigue, '
    'schedule_conflict, weather, travel, feeling_good, other. Coach-rewrite '
    'vocabulary: sickness, injury_niggle, race_change, life_event, '
    'performance, other. Legacy 2026-04 values (flat_week, extra_rest_day, '
    'extra_day, shift_day) remain valid on old rows.';

COMMIT;
