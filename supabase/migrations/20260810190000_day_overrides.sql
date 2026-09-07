-- ============================================================================
-- day_overrides — the athlete's word, on a day
--
-- The day-scoped half of the overrides layer WORKOUT-EDITABILITY-EVAL.md
-- §Change 2 argued for. First field: 'is_key_session'. The next one needs no
-- migration — that genericity is the point.
--
-- Modeled on daily_checkins (20260804090100): athlete-owned, CLIENT-WRITABLE,
-- real RLS, user_id TEXT to match auth.uid()::text (schema-wide convention),
-- date is the LOCAL date.
--
-- WHY THE DAY, NOT THE LOG (KEY-SESSION-APPLY.md §"Why the athlete override
-- is keyed by DAY"):
--   1. The star is drawn on a day cell, and the week row aggregates three
--      runs into one row. A per-row flag has no defined answer there.
--   2. A Strava-linked run is TWO training_logs rows paired by a fuzzy
--      read-time heuristic. workout_notes edits already land on the wrong one
--      and silently vanish. A day-keyed override cannot fail that way.
--   3. LogDedup picks the representative row at READ time, and the dedupe
--      sweep cascade-deletes rows. A row-keyed flag can be deleted out from
--      under the athlete. A day cannot.
--
-- THREE STATES, and the middle one is load-bearing:
--   no row  = nothing said     → fall through to plan intent, then derived
--   true    = key session
--   false   = explicitly NOT a key session
-- Never write null into `value`. Clearing an override DELETES the row —
-- otherwise "back to auto" and "explicitly not key" collapse into one state,
-- which is the exact ambiguity this table exists to avoid.
--
-- NOTE the FOR DELETE policy below. daily_checkins doesn't have one because it
-- never deletes a check-in. We do delete, and without that policy RLS drops
-- the delete SILENTLY: the call returns success, zero rows affected, and the
-- override looks stuck on. That bug is very hard to see from the client.
--
-- NOTHING IN ANY PIPELINE MAY WRITE THIS TABLE. Same law as
-- parsed_structure.edited_by_user: once a human says it, nothing recomputes
-- over it. Client-written only.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS day_overrides (
    user_id    TEXT NOT NULL,             -- matches auth.uid()::text
    date       DATE NOT NULL,             -- LOCAL date, as in daily_checkins
    field      TEXT NOT NULL,             -- 'is_key_session'
    value      JSONB NOT NULL,            -- true | false  (never null)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, date, field)
);

COMMENT ON TABLE day_overrides IS
    'Athlete-entered corrections scoped to a local date. Generic by design: '
    '(field, value) so the next override needs no migration. First field is '
    'is_key_session. Client read/write own rows only; never written by a '
    'pipeline. Clearing an override deletes the row — null is not a value.';

COMMENT ON COLUMN day_overrides.value IS
    'The athlete''s value as JSONB. For is_key_session: true | false. NEVER '
    'null — absence of a row is how "nothing said" is represented.';

CREATE INDEX IF NOT EXISTS day_overrides_user_date_idx
    ON day_overrides (user_id, date DESC);

ALTER TABLE day_overrides ENABLE ROW LEVEL SECURITY;

CREATE POLICY "athletes read own day overrides"
    ON day_overrides FOR SELECT
    USING (user_id = (auth.uid())::text);

CREATE POLICY "athletes write own day overrides"
    ON day_overrides FOR INSERT
    WITH CHECK (user_id = (auth.uid())::text);

CREATE POLICY "athletes update own day overrides"
    ON day_overrides FOR UPDATE
    USING (user_id = (auth.uid())::text)
    WITH CHECK (user_id = (auth.uid())::text);

-- The one daily_checkins doesn't need and we do: "back to auto" is a DELETE.
CREATE POLICY "athletes delete own day overrides"
    ON day_overrides FOR DELETE
    USING (user_id = (auth.uid())::text);

COMMIT;
