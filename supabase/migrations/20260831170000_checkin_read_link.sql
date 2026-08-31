-- Check-in ↔ Read link — which Read a journal reply answers.
--
-- The Read tab's check-in block (2026-08-31) writes mood/text/voice replies
-- as training_logs rows (source 'check_in', or 'voice_log' for typed notes).
-- Until now the row carried no reference to the Read whose question it
-- answers, so the conversation had no data shape: the weekly Read asks
-- "is that tiredness still lingering?", the athlete answers, and the next
-- Read couldn't tell the answer from any other memo.
--
-- One nullable FK closes the loop:
--   * iOS stamps replied_to_read_id at insert for every reply made from the
--     Read tab (mood-only, text, and voice paths alike).
--   * The Read surface lists the replies under its own question.
--   * coaching-daily-read feeds "replies to your last read" to the model as
--     a labelled block, so next week's Read is written knowing its last
--     question was answered.
--
-- ON DELETE SET NULL: a regenerated/deleted read must never take the
-- athlete's journal entries with it — the words outlive the question.
--
-- RLS: no new policies needed. The column rides training_logs' existing
-- owner-scoped policies; it adds a UUID reference, not new readable data.
-- Hard rules: #5 append-only, #9 prod only via `supabase db push` from a
-- committed SHA.

BEGIN;

ALTER TABLE training_logs
    ADD COLUMN IF NOT EXISTS replied_to_read_id UUID
        REFERENCES daily_coaching_reads(id) ON DELETE SET NULL;

-- Partial: almost every training_logs row is NOT a reply; only replies pay
-- for the index. Serves "all replies to read X" (the Read surface) and the
-- coaching-daily-read context fetch.
CREATE INDEX IF NOT EXISTS idx_training_logs_replied_to_read
    ON training_logs (replied_to_read_id)
    WHERE replied_to_read_id IS NOT NULL;

COMMENT ON COLUMN training_logs.replied_to_read_id IS
    'The daily_coaching_reads row this entry replies to (Read-tab check-ins). '
    'Stamped by iOS at insert; null for entries not made from the Read tab.';

COMMIT;
