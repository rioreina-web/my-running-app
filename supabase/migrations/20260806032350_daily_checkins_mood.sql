-- ============================================================================
-- Daily self-reports — add one-tap MOOD to the check-in
--
-- The Today-screen mood prompt (`TodayMoodPrompt`) has always stored the tap
-- in @AppStorage only: it never reached the database, so the recovery ledger's
-- lead factor — mood — could only ever see moods attached to a logged *run*
-- (training_logs.mood, via voice log). The 2026-08-05 backtest measured the
-- cost: mood coverage collapsed from ~60% of days in January to under 26% since
-- April and 0% in August, because most days have no voice-logged run mood.
--
-- This adds `mood` alongside `sleep_quality` on the same one-row-per-local-date
-- check-in, so a tap on a rest day (or any day without a run) reaches the
-- database and feeds the score. Same table, same RLS, same client-writable
-- contract — sleep_quality already proved the pattern.
--
-- Closed vocabulary, matching the ledger's `moodPoints` keys
-- (TrendsRecoveryFactors.swift) and the lowercase convention of
-- training_logs.mood. 'injured' is included for forward-compatibility though
-- the one-tap prompt does not currently offer it (it arrives via voice logs).
-- The number is derived downstream (the ledger), never stored — so the scale
-- can be retuned without a migration.
-- ============================================================================

BEGIN;

ALTER TABLE daily_checkins
    ADD COLUMN IF NOT EXISTS mood TEXT;

ALTER TABLE daily_checkins
    DROP CONSTRAINT IF EXISTS daily_checkins_mood_chk;

ALTER TABLE daily_checkins
    ADD CONSTRAINT daily_checkins_mood_chk
    CHECK (
        mood IS NULL OR mood IN (
            'energized', 'positive', 'neutral', 'tired', 'struggling', 'injured'
        )
    );

COMMENT ON COLUMN daily_checkins.mood IS
    'One-tap self-reported mood, closed vocabulary matching the ledger''s '
    'moodPoints keys. Fills the recovery ledger''s Mood factor on days with no '
    'run-attached mood. Client read/write own rows; one row per athlete per '
    'local date (shared with sleep_quality).';

COMMIT;
