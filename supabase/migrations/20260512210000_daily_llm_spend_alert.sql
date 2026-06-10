-- ============================================================================
-- Daily LLM spend alert to Slack.
--
-- Part of W1.1 in TASKS.md — "Replace in-code LLM cost cap with provider-side
-- hard cap." The hard cap lives in Google Cloud Billing (see
-- docs/deploy/llm-cost-controls.md). This migration adds the observability
-- layer: a daily Slack message that shows yesterday's LLM spend, broken
-- down by model, so the operator sees the trend and any anomaly *before*
-- the Cloud billing cap fires.
--
-- Source of truth: usage_tracking rows written by edge functions on every
-- LLM call. Eight functions write today (coaching-agent, transcribe,
-- weekly-coaching-report, fitness-predictor, injury-analysis,
-- training-analysis, biomechanics-analysis, form-check-analysis). Functions
-- that don't yet write (generate-workout-insight, evaluate-coachable-moment,
-- process-training-memo, parse-*, race-intel, post-run-analysis, etc.) are
-- approximated using coach_insight_jobs.completed count as a proxy.
--
-- The Cloud billing dashboard is ground truth. This alert is a trend
-- signal — close enough to spot a 10× spike, not for accounting.
--
-- AI-advises-never-acts compliance: this migration is observability-only.
-- It does not gate, throttle, or block any LLM call.
--
-- Prerequisites:
--   1. Slack incoming webhook URL stored in vault.decrypted_secrets as
--      'slack_alerts_webhook_url' (see docs/deploy/llm-cost-controls.md)
--   2. supabase_url and service_role_key already in vault (used by other crons)
--   3. pg_cron + pg_net extensions enabled (already on for other crons)
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_net    WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_cron;

-- ---------------------------------------------------------------------------
-- Pricing table — kept in-DB so the alert reflects current rates without
-- a code deploy. Update when a provider changes prices (use insert ON
-- CONFLICT DO UPDATE in a follow-up migration; don't edit this one).
-- Prices are USD per 1M tokens.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS llm_model_pricing (
    model TEXT PRIMARY KEY,
    input_per_1m_usd NUMERIC NOT NULL,
    output_per_1m_usd NUMERIC NOT NULL,
    notes TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO llm_model_pricing (model, input_per_1m_usd, output_per_1m_usd, notes) VALUES
    ('gemini-2.5-pro',          1.25,  10.00, 'Used in generate-training-plan, training-analysis'),
    ('gemini-2.5-flash',        0.30,   2.50, 'Workhorse — coaching-agent, generate-workout-insight, parse-*'),
    ('gemini-2.0-flash',        0.10,   0.40, 'Legacy — race-intel, weekly-plan-review, cuts pending deletion'),
    ('gemini-2.5-flash-lite',   0.10,   0.40, 'Pilot — parse-workout-shorthand if C.9 ships'),
    ('claude-3-5-haiku',        0.80,   4.00, 'fitness-predictor'),
    ('claude-3-5-haiku-20241022', 0.80, 4.00, 'fitness-predictor (full version string)'),
    ('moderate-gemini-gemini-2.5-flash', 0.30, 2.50, 'router.ts identifier for moderate tier'),
    ('complex-gemini-gemini-2.5-flash',  0.30, 2.50, 'router.ts identifier for complex tier'),
    ('simple-groq-llama-3.1-8b-instant', 0.05, 0.08, 'router.ts identifier for simple tier'),
    ('groq-whisper',            0.04,   0.04, 'transcribe — per-second pricing approximated'),
    ('openai-whisper',          0.10,   0.10, 'transcribe fallback'),
    ('gemini-whisper',          0.30,   0.30, 'transcribe fallback'),
    ('cache',                   0.00,   0.00, 'usage_tracking cache hit — no model call')
ON CONFLICT (model) DO UPDATE
    SET input_per_1m_usd  = EXCLUDED.input_per_1m_usd,
        output_per_1m_usd = EXCLUDED.output_per_1m_usd,
        notes             = EXCLUDED.notes,
        updated_at        = NOW();

COMMENT ON TABLE llm_model_pricing IS
    'Per-model LLM pricing for the daily Slack spend alert. Edit prices via a follow-up migration when providers change rates.';

-- ---------------------------------------------------------------------------
-- View: yesterday_llm_spend
-- Aggregates usage_tracking for the previous calendar day, joins pricing,
-- returns one row per model with token counts and estimated cost. Includes
-- a synthetic 'coach_insight (proxy)' row counting completed
-- coach_insight_jobs (since generate-workout-insight doesn't write to
-- usage_tracking yet — gap to fix in C.2).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW yesterday_llm_spend AS
WITH tracked AS (
    SELECT
        u.model_used                                          AS model,
        COUNT(*)                                              AS calls,
        SUM(u.input_tokens)::BIGINT                           AS input_tokens,
        SUM(u.output_tokens)::BIGINT                          AS output_tokens,
        ROUND(
            (SUM(u.input_tokens)  / 1e6 * COALESCE(p.input_per_1m_usd,  0))
          + (SUM(u.output_tokens) / 1e6 * COALESCE(p.output_per_1m_usd, 0)),
            4
        )::NUMERIC                                            AS est_cost_usd
    FROM usage_tracking u
    LEFT JOIN llm_model_pricing p ON p.model = u.model_used
    WHERE u.date = (CURRENT_DATE - INTERVAL '1 day')::DATE
      AND u.model_used IS NOT NULL
    GROUP BY u.model_used, p.input_per_1m_usd, p.output_per_1m_usd
),
coach_proxy AS (
    -- generate-workout-insight doesn't write to usage_tracking yet.
    -- Approximate cost from completed coach_insight_jobs in last 24h
    -- using avg ~1500 in / ~150 out @ gemini-2.5-flash rates.
    SELECT
        'coach_insight_proxy_gemini-2.5-flash' AS model,
        COUNT(*)                                AS calls,
        (COUNT(*) * 1500)::BIGINT               AS input_tokens,
        (COUNT(*) * 150)::BIGINT                AS output_tokens,
        ROUND(
            COUNT(*) * ((1500 / 1e6 * 0.30) + (150 / 1e6 * 2.50)),
            4
        )::NUMERIC                              AS est_cost_usd
    FROM coach_insight_jobs
    WHERE status     = 'completed'
      AND completed_at >= (CURRENT_DATE - INTERVAL '1 day')
      AND completed_at <  CURRENT_DATE
    HAVING COUNT(*) > 0
)
SELECT * FROM tracked
UNION ALL
SELECT * FROM coach_proxy;

COMMENT ON VIEW yesterday_llm_spend IS
    'Per-model token + estimated cost summary for yesterday. Operator-facing.';

-- ---------------------------------------------------------------------------
-- Cron job: 13:00 UTC daily.
-- Builds a Slack message from yesterday_llm_spend, posts to the webhook.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    BEGIN
        PERFORM cron.unschedule('daily-llm-spend-alert');
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    SELECT cron.schedule(
        'daily-llm-spend-alert',
        '0 13 * * *',  -- 13:00 UTC = ~6am Pacific / 9am Eastern / 2pm UTC summer
        $cron$
        DO $inner$
        DECLARE
            _webhook_url TEXT;
            _total_cost  NUMERIC;
            _total_calls BIGINT;
            _breakdown   TEXT;
            _slack_body  TEXT;
        BEGIN
            _webhook_url := (
                SELECT decrypted_secret
                FROM vault.decrypted_secrets
                WHERE name = 'slack_alerts_webhook_url'
                LIMIT 1
            );

            IF _webhook_url IS NULL OR _webhook_url = '' THEN
                RAISE NOTICE 'daily-llm-spend-alert skipped — slack_alerts_webhook_url not configured';
                RETURN;
            END IF;

            -- Totals
            SELECT
                COALESCE(SUM(est_cost_usd), 0),
                COALESCE(SUM(calls), 0)
            INTO _total_cost, _total_calls
            FROM yesterday_llm_spend;

            -- Per-model breakdown (top 8 by cost)
            SELECT COALESCE(
                STRING_AGG(
                    format('• `%s` — %s calls, $%s',
                           model,
                           to_char(calls, 'FM999G999'),
                           to_char(est_cost_usd, 'FM999G990.00')),
                    E'\n'
                ),
                'No LLM calls yesterday.'
            )
            INTO _breakdown
            FROM (
                SELECT model, calls, est_cost_usd
                FROM yesterday_llm_spend
                ORDER BY est_cost_usd DESC NULLS LAST
                LIMIT 8
            ) top;

            _slack_body := jsonb_build_object(
                'text', format(
                    E':bar_chart: *LLM spend yesterday* — $%s across %s calls\n\n%s\n\n_Cloud billing dashboard is ground truth; this is a trend signal._ Budget cap: $50/mo (see docs/deploy/llm-cost-controls.md).',
                    to_char(_total_cost, 'FM999G990.00'),
                    to_char(_total_calls, 'FM999G999'),
                    _breakdown
                )
            )::TEXT;

            PERFORM net.http_post(
                url     := _webhook_url,
                headers := jsonb_build_object('Content-Type', 'application/json'),
                body    := _slack_body::JSONB
            );

            RAISE NOTICE 'daily-llm-spend-alert sent: $% across % calls', _total_cost, _total_calls;
        END
        $inner$;
        $cron$
    ) INTO _job_id;

    RAISE NOTICE 'daily-llm-spend-alert cron scheduled (job id %)', _job_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — daily-llm-spend-alert not scheduled';
END;
$$;

COMMIT;

-- ============================================================================
-- Manual dry-run from a Supabase SQL editor (no cron, sends immediately):
--
--   SELECT * FROM yesterday_llm_spend ORDER BY est_cost_usd DESC NULLS LAST;
--
-- Manual trigger of the cron job (fires the alert right now):
--
--   SELECT cron.schedule('one-shot-spend-alert', '* * * * *', $$ -- ... $$);
--   -- wait one minute, then SELECT cron.unschedule('one-shot-spend-alert');
--
-- Or unschedule entirely:
--
--   SELECT cron.unschedule('daily-llm-spend-alert');
-- ============================================================================
