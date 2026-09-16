-- ============================================================================
-- scheduled_workouts.is_key_session — the plan's intent.
--
-- A key session is a thing you INTEND, not a thing a classifier notices
-- afterwards. Marking it when the session is scheduled makes it knowable
-- BEFORE you run it — which is why the calendar can now show a star on a
-- dashed future cell, a state that could not exist before.
--
-- THREE STATES, same contract as day_overrides:
--   NULL  = nothing said → fall through to the derived rule
--   true  = key session
--   false = deliberately not a key session
--
-- INTENT ONLY. No pipeline may ever write this column — same law as
-- parsed_structure.edited_by_user: once a human says it, nothing recomputes
-- over it. The plan generator knows which sessions are a week's anchors and
-- it is tempting to have it fill this in; if that's wanted, it writes a
-- SUGGESTION the athlete confirms, not this field.
--
-- Keyed per scheduled session, not per day, and correctly so:
-- scheduled_workouts has a real per-session identity (plan_id, date, session).
-- The blanket UNIQUE(plan_id, date) was dropped in
-- 20260227_plan_builder_setup.sql:13 and `session` was added by
-- 20260301_add_session_column.sql, so doubles work.
--
-- ⚠️  KNOWN, TRACKED, NOT FIXED HERE: scheduled_workouts RLS is
--     `FOR ALL USING (true) WITH CHECK (true)` (20260204110000:31-32) — the
--     exact "Allow all" placeholder hard rule #1 forbids. This column inherits
--     it, which means plan intent is something any authenticated caller could
--     rewrite. Fixing it is a real and separate job; folding a security change
--     into this diff would make both harder to review.
-- ============================================================================

BEGIN;

ALTER TABLE scheduled_workouts
  ADD COLUMN IF NOT EXISTS is_key_session BOOLEAN;

COMMENT ON COLUMN scheduled_workouts.is_key_session IS
  'Coach/athlete intent set when scheduling. NULL = nothing said, fall through '
  'to the derived rule. Never written by a pipeline — intent only.';

COMMIT;
