-- ============================================================================
-- Plan Adjustments
--
-- Ledger of every mutation the adaptive system applies (or proposes) to a
-- user's plan. Every change is cited (trigger_evidence → reconciliation /
-- log IDs), reversible (action_payload carries before/after), and
-- acknowledgeable (users see the change, accept or revert).
--
-- One row per adjustment. `auto_applied=true` means the diff is already
-- live on scheduled_workouts / fitness_snapshots. `auto_applied=false`
-- is a proposal; `proposed_until` expires it if the athlete ignores it.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS plan_adjustments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,

    plan_id UUID NOT NULL REFERENCES training_plans(id) ON DELETE CASCADE,

    trigger_type TEXT NOT NULL
        CHECK (trigger_type IN (
            'pace_over_target',
            'pace_under_target',
            'missed_sessions',
            'race_result',
            'volume_ramp_risk',
            'heat_forecast',
            'weekly_rebalance'
        )),
    trigger_evidence JSONB NOT NULL,  -- [reconciliation_id | log_id, ...]

    action_type TEXT NOT NULL
        CHECK (action_type IN (
            'reprice_future_paces',
            'reduce_volume',
            'cap_volume',
            'propose_swap',
            'update_fitness',
            'pause_quality'
        )),
    action_payload JSONB NOT NULL,    -- { before: {...}, after: {...}, diff: [...] }

    auto_applied BOOLEAN NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    acknowledged_by_user_at TIMESTAMPTZ,
    reverted_at TIMESTAMPTZ,

    -- Proposals expire after this timestamp if the user hasn't acted on them.
    proposed_until TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_plan_adjustments_user_applied
    ON plan_adjustments(user_id, applied_at DESC);
CREATE INDEX IF NOT EXISTS idx_plan_adjustments_plan
    ON plan_adjustments(plan_id);

ALTER TABLE plan_adjustments ENABLE ROW LEVEL SECURITY;

-- Users read their own adjustments.
CREATE POLICY "Users read own plan adjustments"
    ON plan_adjustments FOR SELECT
    USING (auth.uid() = user_id);

-- Users can update ONLY acknowledged_by_user_at and reverted_at — never
-- the trigger/action fields. We enforce that at the column level by a
-- separate check trigger.
CREATE POLICY "Users update ack/revert on own plan adjustments"
    ON plan_adjustments FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE OR REPLACE FUNCTION enforce_plan_adjustment_user_columns()
RETURNS TRIGGER AS $$
BEGIN
    -- Only allow user-driven changes to these two columns.
    IF NEW.user_id IS DISTINCT FROM OLD.user_id
       OR NEW.plan_id IS DISTINCT FROM OLD.plan_id
       OR NEW.trigger_type IS DISTINCT FROM OLD.trigger_type
       OR NEW.trigger_evidence IS DISTINCT FROM OLD.trigger_evidence
       OR NEW.action_type IS DISTINCT FROM OLD.action_type
       OR NEW.action_payload IS DISTINCT FROM OLD.action_payload
       OR NEW.auto_applied IS DISTINCT FROM OLD.auto_applied
       OR NEW.applied_at IS DISTINCT FROM OLD.applied_at
       OR NEW.proposed_until IS DISTINCT FROM OLD.proposed_until THEN
        IF auth.role() <> 'service_role' THEN
            RAISE EXCEPTION 'Users may only update acknowledged_by_user_at and reverted_at';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_plan_adjustment_user_column_guard
    BEFORE UPDATE ON plan_adjustments
    FOR EACH ROW
    EXECUTE FUNCTION enforce_plan_adjustment_user_columns();

-- Service role writes everything.
CREATE POLICY "Service role full access to plan_adjustments"
    ON plan_adjustments FOR ALL
    USING (auth.role() = 'service_role');

COMMIT;
