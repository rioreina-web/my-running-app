-- ============================================================================
-- plan_templates.doubles_config — coach-assigned doubles
--
-- Phase 2 of outputs/doubles-and-activity-types-spec-2026-07-16.md.
--
-- The coach sets how many doubles per week and the mileage range for each PM
-- run. The subscribe-to-plan materializer reads this and generates session:2
-- (PM) runs on eligible easy days. Athlete-agnostic: self-coached Maya can
-- inherit the same shape via athlete_plan_subscriptions.shape_prefs.doubles.
--
-- Shape (all keys optional; absent OR mode:"off" = no doubles = today's
-- behavior byte-for-byte):
--   {
--     "mode":         "off" | "assigned" | "adaptive",
--     "per_week":     2,                       -- assigned mode: PM runs/week
--     "range_miles":  { "min": 3, "max": 5 },  -- each PM run
--     "distribution": "split" | "add",         -- split preserves weekly volume
--     "eligible_dows": [2, 3],                 -- 0=Mon..6=Sun; null = auto-pick
--     "placement":    "easy_only"              -- PM quality stays coach-authored
--   }
--
-- Backwards-compatible: nullable, DEFAULT NULL. Every existing template
-- materializes exactly as before until a coach opts in. Append-only
-- (hard rule #5); plan_templates RLS is already coach-scoped so no policy
-- change is needed. Reaches prod only via `supabase db push` (hard rule #9).
-- ============================================================================

BEGIN;

ALTER TABLE plan_templates
    ADD COLUMN IF NOT EXISTS doubles_config JSONB;

COMMENT ON COLUMN plan_templates.doubles_config IS
    'Coach-assigned doubles config: { mode: off|assigned|adaptive, per_week, '
    'range_miles:{min,max}, distribution: split|add, eligible_dows:int[0..6], '
    'placement:easy_only }. NULL or mode=off means no auto-generated doubles '
    '(default). Read by subscribe-to-plan; athlete may dial the count down via '
    'athlete_plan_subscriptions.shape_prefs.doubles. See '
    'outputs/doubles-and-activity-types-spec-2026-07-16.md Part B.';

COMMIT;
