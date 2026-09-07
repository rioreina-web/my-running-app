-- Skip-cause attribution — the branch a coach actually makes.
--
-- A missed Tuesday because work blew up and a missed Tuesday because the
-- athlete is cooked look identical in `status = 'skipped'` and demand
-- opposite responses: schedule → move the day and keep the load; fatigue →
-- drop it and cut the week. `missedWorkouts.ts` has carried a "V2: split
-- into 3a (body) and 3b (schedule) once skip-reason is captured" note since
-- it shipped. This is that capture.
--
-- Two changes, no new tables:
--   1. scheduled_workouts gains a closed-vocabulary cause + provenance.
--   2. plan_adjustments gains the trigger and actions the five coach moves
--      need — `fatigue_signal` (there was no fatigue trigger at all) and
--      `shift_day` / `insert_rest` (move-a-day and insert-rest were not
--      expressible, though the `shift-day` edge function already exists).
--
-- Cause stays on scheduled_workouts rather than plan_adjustments on purpose:
-- the coach's one-tap correction ("it was schedule, not fatigue") has to be a
-- user-writable field, and plan_adjustments is guarded by
-- enforce_plan_adjustment_user_columns() which exists precisely to stop users
-- editing trigger/action fields. The adjustment carries the cause in its
-- service-role-written trigger_evidence instead.
--
-- Hard rules: #5 append-only (new file, no edits to deployed migrations),
-- #9 reaches prod only via `supabase db push` from a committed SHA.

BEGIN;

-- ── 1. Cause on the skipped workout ──────────────────────────────────────

ALTER TABLE scheduled_workouts
    ADD COLUMN IF NOT EXISTS skip_cause TEXT,
    ADD COLUMN IF NOT EXISTS skip_cause_source TEXT,
    ADD COLUMN IF NOT EXISTS skip_cause_confidence TEXT,
    -- [{ kind: 'memo'|'note'|'mood'|'check_in', ref: <id>, excerpt: <text> }, ...]
    -- Every attribution shows its work; a guess with no evidence is a guess
    -- the coach can't audit.
    ADD COLUMN IF NOT EXISTS skip_cause_evidence JSONB,
    ADD COLUMN IF NOT EXISTS skip_cause_recorded_at TIMESTAMPTZ;

-- Closed vocabulary. `niggle` deliberately, never `injury`: the AI surfaces a
-- body mention as a pattern and routes the call to a human — it does not
-- diagnose (hard rule #2). Same discipline as the niggles classifier.
ALTER TABLE scheduled_workouts
    DROP CONSTRAINT IF EXISTS scheduled_workouts_skip_cause_check;
ALTER TABLE scheduled_workouts
    ADD CONSTRAINT scheduled_workouts_skip_cause_check
    CHECK (skip_cause IS NULL OR skip_cause IN (
        'fatigue',    -- cooked, heavy legs, drained
        'schedule',   -- work, travel, life logistics
        'illness',    -- sick — routes to a human, never a medical claim
        'niggle',     -- body-part mention, undiagnosed by design
        'weather',    -- heat, ice, storm
        'unknown'     -- no signal in the data; ask rather than assume
    ));

-- Who decided. A coach/athlete confirmation outranks an inference, and the
-- proposal UI has to be able to tell them apart to know when to stop asking.
ALTER TABLE scheduled_workouts
    DROP CONSTRAINT IF EXISTS scheduled_workouts_skip_cause_source_check;
ALTER TABLE scheduled_workouts
    ADD CONSTRAINT scheduled_workouts_skip_cause_source_check
    CHECK (skip_cause_source IS NULL OR skip_cause_source IN (
        'inferred',           -- model read it out of memos/notes/mood
        'athlete_confirmed',  -- athlete tapped it
        'coach_confirmed'     -- coach tapped it — highest authority
    ));

ALTER TABLE scheduled_workouts
    DROP CONSTRAINT IF EXISTS scheduled_workouts_skip_cause_confidence_check;
ALTER TABLE scheduled_workouts
    ADD CONSTRAINT scheduled_workouts_skip_cause_confidence_check
    CHECK (skip_cause_confidence IS NULL
           OR skip_cause_confidence IN ('low', 'medium', 'high'));

-- A cause without a source is unattributable; require them together.
ALTER TABLE scheduled_workouts
    DROP CONSTRAINT IF EXISTS scheduled_workouts_skip_cause_paired;
ALTER TABLE scheduled_workouts
    ADD CONSTRAINT scheduled_workouts_skip_cause_paired
    CHECK ((skip_cause IS NULL AND skip_cause_source IS NULL)
           OR (skip_cause IS NOT NULL AND skip_cause_source IS NOT NULL));

COMMENT ON COLUMN scheduled_workouts.skip_cause IS
    'Why this workout was missed. Closed vocabulary — drives the branch in '
    '_shared/cause.ts. Never a diagnosis; `niggle` is a mention, not a finding.';
COMMENT ON COLUMN scheduled_workouts.skip_cause_evidence IS
    'What the attribution was based on: [{kind, ref, excerpt}]. Shown to the '
    'coach so an inference can be audited and corrected in one tap.';

-- Partial index: the proposal builder only ever scans skipped workouts.
CREATE INDEX IF NOT EXISTS idx_scheduled_workouts_skipped_cause
    ON scheduled_workouts(plan_id, date DESC)
    WHERE status = 'skipped';

-- ── 2. The vocabulary the five coach moves need ──────────────────────────

-- Fatigue had no trigger at all — the single most common reason a coach
-- reaches for the plan, and the system could not express it.
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
        -- Present in the LIVE constraint and NOT in this file's first draft.
        -- Re-checked against pg_constraint 2026-08-24. Dropping 'user_action'
        -- would have re-created the April-to-July bug where every athlete
        -- day-move audit row failed its CHECK silently; 'coach_rewrite' landed
        -- with the coach rewrite work after this file was written.
        'user_action',
        'coach_rewrite',
        'fatigue_signal'     -- NEW
    ));

-- `shift_day` (move it, keep the load) and `insert_rest` (drop it) are the
-- two halves of the schedule/fatigue branch. Neither was expressible.
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
        -- 'shift_day' is NOT new — it is already in the live constraint. The
        -- four below arrived with reshape/rewrite/edit after this file was
        -- drafted; re-checked against pg_constraint 2026-08-24.
        'shift_day',
        'reshape_week',
        'rewrite_block',
        'edit_workout',
        'duplicate_workout',
        'insert_rest'        -- NEW
    ));

-- ── 3. Fail loudly if a CHECK survived the drop ──────────────────────────
--
-- The constraints above were declared inline in CREATE TABLE, so their names
-- are Postgres-generated (`<table>_<column>_check`). If that convention ever
-- differed on this database, `DROP CONSTRAINT IF EXISTS` no-ops silently and
-- the ADD succeeds — leaving TWO check constraints, the older one still
-- rejecting 'fatigue_signal' and 'shift_day'. That failure would not surface
-- here; it would surface as a runtime insert error weeks later.
--
-- So assert the end state instead of trusting the drop.
DO $$
DECLARE
    n INT;
    v TEXT;
BEGIN
    SELECT COUNT(*) INTO n
    FROM pg_constraint
    WHERE conrelid = 'plan_adjustments'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%trigger_type%';
    IF n <> 1 THEN
        RAISE EXCEPTION
            'Expected exactly 1 trigger_type CHECK on plan_adjustments, found %. '
            'An older inline constraint survived the drop under a different name.', n;
    END IF;

    SELECT COUNT(*) INTO n
    FROM pg_constraint
    WHERE conrelid = 'plan_adjustments'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%action_type%';
    IF n <> 1 THEN
        RAISE EXCEPTION
            'Expected exactly 1 action_type CHECK on plan_adjustments, found %.', n;
    END IF;

    -- Prove the new values actually pass the surviving constraint AND that no
    -- previously-allowed value was dropped. The second half is the one that
    -- matters: this file's first draft silently deleted 'user_action',
    -- 'coach_rewrite', 'reshape_week', 'rewrite_block', 'edit_workout' and
    -- 'duplicate_workout' by rewriting a list that four later migrations had
    -- since extended. plan_adjustments is empty, so ADD CONSTRAINT would have
    -- succeeded and the breakage would only have surfaced at insert time.
    FOR v IN SELECT unnest(ARRAY[
        'pace_over_target','pace_under_target','missed_sessions','race_result',
        'volume_ramp_risk','heat_forecast','weekly_rebalance','user_action',
        'coach_rewrite','fatigue_signal'
    ]) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conrelid = 'plan_adjustments'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ILIKE '%trigger_type%'
              AND pg_get_constraintdef(oid) LIKE '%' || v || '%'
        ) THEN
            RAISE EXCEPTION 'trigger_type CHECK lost the value %', v;
        END IF;
    END LOOP;

    FOR v IN SELECT unnest(ARRAY[
        'reprice_future_paces','reduce_volume','cap_volume','propose_swap',
        'update_fitness','pause_quality','shift_day','reshape_week',
        'rewrite_block','edit_workout','duplicate_workout','insert_rest'
    ]) LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_constraint
            WHERE conrelid = 'plan_adjustments'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ILIKE '%action_type%'
              AND pg_get_constraintdef(oid) LIKE '%' || v || '%'
        ) THEN
            RAISE EXCEPTION 'action_type CHECK lost the value %', v;
        END IF;
    END LOOP;
END $$;

COMMIT;
