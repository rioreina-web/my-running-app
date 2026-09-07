-- ============================================================================
-- Daily self-reports — the one-tap nightly check-in
--
-- Home for athlete-entered daily signals that aren't tied to a workout. First
-- field: self-reported sleep quality — the strongest single prospective signal
-- in the runner injury literature (recovery-trend-v2 §1, §2b Tier 1), and
-- cheaper and better than the entire Garmin sleep pipeline.
--
-- This is CLIENT-WRITABLE (unlike daily_biometrics, which is device data). The
-- athlete owns these rows: read/write their own, full RLS. Kept in its own
-- table rather than on training_logs because a check-in can happen on a rest
-- day with no run, and rather than on daily_biometrics because that table is
-- service-role-write only.
--
-- sleep_quality uses a closed 3-value vocabulary — 'rough' | 'ok' | 'good' —
-- matching the closed-vocabulary discipline already used for mood. The number
-- is derived downstream (the ledger), never stored numerically, so the scale
-- can be retuned without a migration.
--
-- user_id is TEXT to match auth.uid()::text — the schema-wide convention.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS daily_checkins (
    user_id        TEXT NOT NULL,
    date           DATE NOT NULL,            -- the night being rated (local date)
    sleep_quality  TEXT,                     -- 'rough' | 'ok' | 'good' | NULL
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, date),
    CONSTRAINT daily_checkins_sleep_quality_chk
        CHECK (sleep_quality IS NULL OR sleep_quality IN ('rough', 'ok', 'good'))
);

COMMENT ON TABLE daily_checkins IS
    'Athlete-entered daily self-report (one-tap check-in). sleep_quality is the '
    'first field — Tier-1 recovery signal per recovery-trend-v2 §2b. '
    'Client read/write own rows; one row per athlete per local date.';

CREATE INDEX IF NOT EXISTS daily_checkins_user_date_idx
    ON daily_checkins (user_id, date DESC);

ALTER TABLE daily_checkins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "athletes read own checkins"
    ON daily_checkins FOR SELECT
    USING (user_id = (auth.uid())::text);

CREATE POLICY "athletes write own checkins"
    ON daily_checkins FOR INSERT
    WITH CHECK (user_id = (auth.uid())::text);

CREATE POLICY "athletes update own checkins"
    ON daily_checkins FOR UPDATE
    USING (user_id = (auth.uid())::text)
    WITH CHECK (user_id = (auth.uid())::text);

COMMIT;
