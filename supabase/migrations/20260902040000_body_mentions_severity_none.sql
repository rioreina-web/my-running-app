-- ============================================================================
-- body_mentions: allow severity_hint = 'none' (step 6 of the drip-scores
-- handoff — explicit "nothing hurts").
--
-- The memo pipeline (process-training-memo.v5 + niggleWriter) now writes a
-- severity 'none' row when the athlete gives an explicit all-clear — per
-- part from resolved_niggles ("knee feels fine now") or globally on the
-- 'legs' area from the new no_niggles signal ("nothing hurts"). The
-- daily_scores scorer has mapped 'none' -> soreness 0 since v1.0, so these
-- rows make soreness baselines include zero days instead of only
-- complaint days. Silence is still silence: 'none' is written only from
-- structured all-clear extraction, never inferred from absence.
-- ============================================================================

BEGIN;

ALTER TABLE body_mentions
    DROP CONSTRAINT IF EXISTS body_mentions_severity_hint_check;

ALTER TABLE body_mentions
    ADD CONSTRAINT body_mentions_severity_hint_check
    CHECK (severity_hint = ANY (ARRAY['tight'::text, 'sore'::text, 'pain'::text, 'sharp'::text, 'none'::text]));

COMMIT;

-- Verification:
--   SELECT pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conname = 'body_mentions_severity_hint_check';
--   Expected to include 'none'.
