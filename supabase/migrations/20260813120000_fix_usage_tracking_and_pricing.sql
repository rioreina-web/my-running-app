-- ============================================================================
-- Cost audit 2026-08-13 — make LLM spend tracking actually record spend
--
-- Context: a $7 single-day Gemini bill on a one-user beta, while
-- usage_tracking recorded ~$0.02 of it. Two data-layer causes fixed here:
--
--   1. usage_tracking's feature CHECK only allows
--      ('coaching','transcription','insight'). Every insert with any other
--      label — coaching-agent's 'coaching_proactive', and the new
--      'daily_read' rows from coaching-daily-read — fails the constraint.
--      supabase-js returns the error in the result object rather than
--      throwing, and no call site checks it, so the rows were dropped
--      SILENTLY. The daily spend alert therefore reported pennies while
--      the real bill climbed. The check is widened to "non-empty, sane
--      length" — feature labels are an open, code-owned vocabulary and the
--      closed list buys nothing but silent data loss.
--
--   2. llm_model_pricing had no row for gemini-3.1-pro-preview (the model
--      coaching-daily-read was calling), so even correctly-tracked calls
--      would have priced at $0 in yesterday_llm_spend. Rows added for the
--      Gemini 3.x preview tier ($2 in / $12 out per 1M as of 2026-08).
--
-- Apply via `supabase db push` from a committed SHA (hard rule #9).
-- ============================================================================

BEGIN;

-- 1. Widen the feature check. Append-only: drop + re-add under the same name.
ALTER TABLE usage_tracking
    DROP CONSTRAINT IF EXISTS usage_tracking_feature_check;

ALTER TABLE usage_tracking
    ADD CONSTRAINT usage_tracking_feature_check
    CHECK (feature IS NOT NULL AND length(feature) BETWEEN 1 AND 64);

COMMENT ON COLUMN usage_tracking.feature IS
    'Open vocabulary of feature labels (daily_read, coaching, insight, '
    'transcription, coaching_proactive, ...). Widened 2026-08-13 — the old '
    'closed CHECK silently dropped rows for unlisted features, blinding the '
    'daily spend alert.';

-- 2. Pricing rows for the Gemini 3.x preview tier (USD per 1M tokens,
--    checked 2026-08). Thinking tokens are billed as output on these models.
INSERT INTO llm_model_pricing (model, input_per_1m_usd, output_per_1m_usd, notes) VALUES
    ('gemini-3.1-pro-preview', 2.00, 12.00,
     'Frontier preview tier. Was used by coaching-daily-read until 2026-08-13; retained for historical spend attribution.'),
    ('gemini-3-pro-preview',   2.00, 12.00,
     'Alias/earlier preview id, same tier.')
ON CONFLICT (model) DO UPDATE
    SET input_per_1m_usd  = EXCLUDED.input_per_1m_usd,
        output_per_1m_usd = EXCLUDED.output_per_1m_usd,
        notes             = EXCLUDED.notes,
        updated_at        = NOW();

COMMIT;

-- Verification (run after applying):
--   INSERT INTO usage_tracking (user_id, feature, model_used, input_tokens, output_tokens)
--   VALUES (gen_random_uuid(), 'daily_read', 'gemini-2.5-flash', 1, 1);
--   -- expect: success. Then delete the test row.
--   SELECT model, input_per_1m_usd, output_per_1m_usd FROM llm_model_pricing
--   WHERE model LIKE 'gemini-3%';
