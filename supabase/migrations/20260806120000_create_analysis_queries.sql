-- ============================================================================
-- analysis_queries — the audit ledger for the Ask surface
--
-- One row per question asked of `ask`, whether it was a chip tap, typed free
-- text, or a follow-up. The table earns its keep three ways:
--
--   1. PROMOTE-TO-CASSETTE. `raw_question` + `facts` + `narration` is exactly
--      the input/output pair the eval harness records. Real usage becomes
--      golden coverage for `ask-narration` instead of synthetic authoring
--      (outputs/ai-feedback-loop-design-2026-07-07.md).
--   2. WHAT DO PEOPLE ACTUALLY ASK. The v1 chip library is a guess. This is
--      the evidence for v2, and the sequencing input for the BUILD-tier
--      analyzers in ASK-REGISTRY.md §4 phase E.
--   3. GUARD DRIFT. `guard_tripped` fires when the Layer-2 model spoke a
--      number Layer 1 never printed. A rising rate is the signal that the
--      narration prompt has started reasoning past its evidence — the exact
--      failure the guard exists to catch, and one nobody would otherwise see.
--
-- WRITES ARE SERVICE-ROLE ONLY, matching the posture hard rule #4 sets for
-- `coachable_moments`: the athlete never inserts their own audit row. They may
-- read their own history (it is their question and their answer).
--
-- `facts` stores the fact lines verbatim rather than a re-derivable reference.
-- Analyzer math will change; what the athlete was actually shown must not.
--
-- user_id is TEXT to match auth.uid()::text — the schema-wide convention.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS analysis_queries (
    id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id        TEXT NOT NULL,
    asked_at       TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- How the question arrived. 'chip' = tapped a standing/contextual chip
    -- (no Layer-0 model call). 'text' = typed. 'followup' = tapped a chip the
    -- previous answer emitted.
    source         TEXT NOT NULL,
    raw_question   TEXT,                       -- NULL for chips

    analyzer_id    TEXT,                       -- NULL when routed to prose
    params         JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- 'analyzed' = an analyzer ran. 'prose' = no analyzer fit, handed to
    -- coaching-agent. 'ambiguous' = the router offered disambiguation chips
    -- instead of an answer.
    mode           TEXT NOT NULL,

    annotated      BOOLEAN NOT NULL DEFAULT FALSE,  -- did Layer 2 survive?
    confidence     TEXT,                            -- coverage confidence tier
    facts          JSONB,                           -- the fact lines, verbatim
    narration      TEXT,

    latency_ms     INTEGER,
    model_used     TEXT,
    -- TRUE only when the narration was rejected for speaking a number absent
    -- from the facts. Parse failures and length violations are NOT this —
    -- they are prompt-format noise, this is an evidence violation.
    guard_tripped  BOOLEAN NOT NULL DEFAULT FALSE,

    CONSTRAINT analysis_queries_source_chk
        CHECK (source IN ('chip', 'text', 'followup')),
    CONSTRAINT analysis_queries_mode_chk
        CHECK (mode IN ('analyzed', 'prose', 'ambiguous')),
    CONSTRAINT analysis_queries_confidence_chk
        CHECK (confidence IS NULL OR confidence IN ('high', 'moderate', 'low'))
);

COMMENT ON TABLE analysis_queries IS
    'Audit ledger for the Ask surface (supabase/functions/ask). Service-role '
    'write, athlete reads own. Feeds promote-to-cassette for ask-narration, '
    'chip-library v2 prioritisation, and guard-drift monitoring.';

COMMENT ON COLUMN analysis_queries.guard_tripped IS
    'Layer-2 narration was rejected for introducing a number absent from the '
    'Layer-1 facts. A rising rate means the narration prompt is drifting.';

-- The two read patterns: an athlete''s own history (newest first), and the
-- ops question "what is the guard rejection rate this week".
CREATE INDEX IF NOT EXISTS analysis_queries_user_asked_idx
    ON analysis_queries (user_id, asked_at DESC);

CREATE INDEX IF NOT EXISTS analysis_queries_analyzer_asked_idx
    ON analysis_queries (analyzer_id, asked_at DESC);

CREATE INDEX IF NOT EXISTS analysis_queries_guard_tripped_idx
    ON analysis_queries (asked_at DESC)
    WHERE guard_tripped;

ALTER TABLE analysis_queries ENABLE ROW LEVEL SECURITY;

-- Athletes read their own questions and answers. No INSERT/UPDATE/DELETE
-- policy for clients by design — the ledger is written by the edge function
-- under the service role, and an athlete cannot rewrite their own audit trail.
CREATE POLICY "athletes read own analysis queries"
    ON analysis_queries FOR SELECT
    USING (user_id = (auth.uid())::text);

COMMIT;
