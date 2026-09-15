-- ============================================================================
-- Daily Coaching Reads — soft questions
--
-- The v3 Read prompt (`_shared/prompts/daily-read.v3.ts`) ends every Read
-- with one or two soft questions for the athlete to sit with, rendered
-- italic and set apart from the paragraph on iOS. They were previously
-- folded into the paragraph's last sentence, where they read as just more
-- prose. Giving them their own column lets the client render them as
-- their own block and lets the edge function feed yesterday's questions
-- back into today's context so the coach doesn't repeat itself.
--
-- Shape: JSONB array of 0-2 plain strings. No citations.
--
-- Existing table — RLS policies from 20260522130944_daily_coaching_reads
-- already cover every column; no policy change needed. Additive and
-- idempotent so `supabase db push` is safe against a partially applied
-- environment.
-- ============================================================================

ALTER TABLE daily_coaching_reads
    ADD COLUMN IF NOT EXISTS questions JSONB NOT NULL DEFAULT '[]'::jsonb;

COMMENT ON COLUMN daily_coaching_reads.questions IS
    'Soft questions the coach leaves the athlete to sit with: JSONB array '
    'of 0-2 plain strings. Rendered italic below the paragraph. Never '
    'directives. Empty on an empty-state Read.';
