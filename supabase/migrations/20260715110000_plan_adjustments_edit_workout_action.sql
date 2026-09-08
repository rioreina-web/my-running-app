-- Add 'edit_workout' to plan_adjustments.action_type.
--
-- Athletes editing their own scheduled workout's structure (reps/pace/warmup)
-- from the iOS day-detail sheet log a yellow-tier adjustment so the coach can
-- review what changed. The write path is the edit-scheduled-workout edge
-- function (athlete-scoped, mirrors shift-day's ownership check). trigger_type
-- 'user_action' and tier 'yellow' are already permitted by their CHECKs; only
-- action_type needs the new value.
--
-- Append-only per CLAUDE.md hard rule #5. Reaches prod via `supabase db push`
-- from a committed SHA (hard rule #9), never a dashboard/MCP apply.

ALTER TABLE plan_adjustments
  DROP CONSTRAINT IF EXISTS plan_adjustments_action_type_check;

ALTER TABLE plan_adjustments
  ADD CONSTRAINT plan_adjustments_action_type_check
  CHECK (action_type = ANY (ARRAY[
    'reprice_future_paces',
    'reduce_volume',
    'cap_volume',
    'propose_swap',
    'update_fitness',
    'pause_quality',
    'shift_day',
    'reshape_week',
    'rewrite_block',
    'edit_workout'
  ]));
