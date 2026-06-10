-- ============================================================================
-- Re-fire suppression for coachable_moments (V1)
--
-- The evaluator runs on every training_log insert (and likely on cron later);
-- without this index, rule 3 ("missed_workouts" — checks 2+ skipped this
-- week) would re-fire every cron tick from the moment the second skip lands
-- until Sunday rolls over, producing dozens of duplicate "Sarah missed 2"
-- rows in a single afternoon.
--
-- This partial unique index guarantees: at most one OPEN moment per
-- (athlete, rule) at a time. Once the coach handles or dismisses it, the
-- index lets a fresh moment fire — by design, that's the cycle we want.
--
-- The evaluator (supabase/functions/evaluate-coachable-moment/index.ts)
-- pre-flights a SELECT for open rule_ids and filters them out of the
-- batch insert; the index is the belt-and-suspenders enforcement.
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS coachable_moments_one_open_per_rule
    ON coachable_moments (athlete_user_id, rule_id)
    WHERE status = 'open';

COMMENT ON INDEX coachable_moments_one_open_per_rule IS
    'V1 re-fire suppression: at most one open coachable_moment per athlete+rule. The evaluator pre-flights a SELECT to filter the batch; this index is the DB-level guarantee.';
