-- ============================================================================
-- Daily Coaching Reads — v5 sectioned editorial schema (additive)
--
-- The Read is moving from a flat `paragraph` to a labeled, sectioned narrative
-- (the editorial "coach's note" screen — see
-- outputs/the-read-narrative-screen-spec-for-xcode-agent-2026-06-15.md §3 and
-- supabase/functions/_shared/prompts/daily-read.v5.ts).
--
-- This migration is ADDITIVE and append-only (CLAUDE.md hard rules #5, #9):
--   - Adds `eyebrow`, `sections`, `question`. Existing rows keep `paragraph`
--     and read `sections IS NULL`, which is the iOS fallback signal (old card
--     view renders; nothing is lost).
--   - `coaching-daily-read` continues to populate `paragraph` (flattened from
--     `sections`) so pre-v5 consumers keep working.
--
-- RLS: unchanged. The four policies on daily_coaching_reads
-- (20260522130944_daily_coaching_reads.sql) are table-wide (owner
-- select/insert/update + service-role ALL) and already cover these new
-- columns — column additions do not require new policies.
-- ============================================================================

-- The goal/race backdrop scope line, e.g. "Chasing 3:16 · off your 3:28".
-- NULL when there is no goal/race to frame the week against.
ALTER TABLE daily_coaching_reads
    ADD COLUMN IF NOT EXISTS eyebrow TEXT;

-- The ordered editorial sections. NULL on legacy (pre-v5) rows — its presence
-- is what tells iOS to render the narrative screen instead of falling back.
-- Shape (validated in the edge function before the row is marked completed):
--   [
--     {
--       "label": "The week" | "The hard days" | "The long run"
--                | "How you felt" | "One thing",
--       "body": [
--         "plain prose string",
--         { "text": "the long run", "workout_id": "<uuid>" },  -- workout ref
--         { "text": "achilles",     "niggle": "right achilles" } -- niggle ref
--       ]
--     }, ...
--   ]
-- Workout refs are validated against training_logs; niggle refs against
-- body_mentions. An unresolved ref is degraded to its plain `text` (never a
-- dead link) by validateCitations() before persistence.
ALTER TABLE daily_coaching_reads
    ADD COLUMN IF NOT EXISTS sections JSONB;

-- The single soft question (rendered with a coral left-rule), or NULL.
-- One per Read, at most. The ONLY place a question is surfaced in v5.
ALTER TABLE daily_coaching_reads
    ADD COLUMN IF NOT EXISTS question TEXT;

COMMENT ON COLUMN daily_coaching_reads.eyebrow IS
    'v5 goal-backdrop scope line, e.g. "Chasing 3:16 · off your 3:28", or NULL.';

COMMENT ON COLUMN daily_coaching_reads.sections IS
    'v5 ordered editorial sections. NULL on legacy rows (iOS fallback signal). '
    'Each: {"label": <one of the fixed five>, "body": [ string | '
    '{"text","workout_id"} | {"text","niggle"} ]}. Workout refs validated '
    'against training_logs, niggle refs against body_mentions; unresolved refs '
    'are degraded to plain text before the row is marked completed.';

COMMENT ON COLUMN daily_coaching_reads.question IS
    'v5 single soft question (one per Read, at most), or NULL.';
