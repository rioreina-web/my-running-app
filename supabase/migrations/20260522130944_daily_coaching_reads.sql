-- ============================================================================
-- Daily Coaching Reads Table
--
-- One AI-generated "Read" per athlete per day, posted at 6 AM athlete-local
-- and (optionally) re-rendered on-demand after a quality workout. Replaces
-- the freeform chat output of the legacy self-coached path with a structured,
-- editorial response: headline + segmented paragraph with workout/doc
-- citations + an honest "what I can't see" block + sources + confidence.
--
-- Mirrors `weekly_coaching_reports` in shape and process flow, but scoped
-- daily instead of weekly. See `coach-the-read-prompts.md` (Phase 1, Prompt
-- 1.1) for the design context.
--
-- Conventions applied (override the inline prompt where they differ):
--   - `user_id` is TEXT matching `auth.uid()::text` (per CLAUDE.md hard rule
--     and `docs/conventions/rls-checklist.md`), NOT a UUID FK to auth.users.
--     Cascade delete is enforced at the auth layer, not via FK.
--   - Strict RLS, no `auth.uid() IS NULL` fallback (per
--     `20260313100000_lock_down_rls.sql`).
--   - Service-role full-access policy for the edge function writer.
-- ============================================================================

CREATE TABLE IF NOT EXISTS daily_coaching_reads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL,

    -- The athlete-local calendar date this Read is for.
    read_date DATE NOT NULL,

    -- Lifecycle.
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'completed', 'failed')),

    -- One-line "what's happening" headline. NULL while pending.
    headline TEXT,

    -- The 4-6 sentence morning paragraph, as an ordered array of segments.
    -- Each element is one of:
    --   "plain text"                              — a string
    --   { "workout_id": "<uuid>" }                — workout citation
    --   { "doc_id":     "<uuid>" }                — knowledge-base citation
    -- The frontend renders strings inline and citations as kerned chips.
    -- The validator in `coaching-daily-read` strips any citation whose id
    -- does not exist in `training_logs` / `coaching_documents` before this
    -- row is updated to `completed`.
    paragraph JSONB NOT NULL DEFAULT '[]'::jsonb,

    -- Honest "what I can't see" block — rendered when there's a meaningful
    -- blind spot (missing sleep data, unsynced workouts, single-data-point
    -- niggles, low-confidence prediction). NULL when there is nothing
    -- worth flagging.
    -- Shape: { "eyebrow": "<string>", "body": "<string>" } | NULL.
    cant_see JSONB,

    -- Resolved sources, in the shape expected by the iOS SourcesPanel:
    --   {
    --     "workouts": ["<training_log_id>", ...],
    --     "docs":     ["<coaching_document_id>", ...],
    --     "memos":    [
    --       { "label": "<short label>", "excerpt": "<verbatim quote>",
    --         "log_id": "<voice_log_id>" },
    --       ...
    --     ]
    --   }
    -- Workouts/docs ids are duplicated from `paragraph` for fast hydration
    -- without re-walking the segment array; voice memos live only here
    -- because they never appear inline in the paragraph (♪ citation style
    -- is "Sources-only" per the design).
    sources JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Confidence assessment, computed by the model from workout count +
    -- doc count + recency.
    -- Shape: { "level": "HIGH" | "MEDIUM" | "LOW", "sub": "<one-line>" }.
    confidence JSONB NOT NULL DEFAULT '{}'::jsonb,

    -- Processing metadata.
    ai_model TEXT,
    generated_at TIMESTAMPTZ,
    triggered_by TEXT NOT NULL DEFAULT 'cron'
        CHECK (triggered_by IN ('cron', 'manual', 'workout_trigger')),
    error_message TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- One Read per athlete per day. The edge function short-circuits on
    -- this when invoked a second time.
    CONSTRAINT daily_coaching_reads_user_date_uniq UNIQUE (user_id, read_date)
);

-- Re-document the paragraph schema at the column level so it shows up in
-- generated docs and `\d+ daily_coaching_reads`.
COMMENT ON COLUMN daily_coaching_reads.paragraph IS
    'Ordered array of paragraph segments. Each element is either a plain '
    'string, {"workout_id": <uuid>}, or {"doc_id": <uuid>}. Citation ids '
    'are validated against training_logs / coaching_documents before the '
    'row is marked completed.';

COMMENT ON COLUMN daily_coaching_reads.cant_see IS
    'Optional honest-uncertainty block: {"eyebrow": "<string>", '
    '"body": "<string>"} or NULL. Rendered only when there is a meaningful '
    'blind spot. Surfaces brand voice attribute 3.4 ("Honest when uncertain").';

COMMENT ON COLUMN daily_coaching_reads.sources IS
    'Resolved sources: {"workouts": [<id>], "docs": [<id>], '
    '"memos": [{"label", "excerpt", "log_id"}]}. Voice memos live only '
    'here — they never render inline in the paragraph.';

COMMENT ON COLUMN daily_coaching_reads.confidence IS
    'Confidence assessment: {"level": "HIGH"|"MEDIUM"|"LOW", "sub": "<one-line>"}.';

COMMENT ON COLUMN daily_coaching_reads.triggered_by IS
    'What enqueued this Read: "cron" (6am dispatch), "manual" (athlete '
    'pulled to refresh), or "workout_trigger" (post-quality-session '
    're-render).';

-- ============================================================================
-- Indexes
-- ============================================================================

-- Primary lookup: athlete's most recent Reads.
CREATE INDEX IF NOT EXISTS idx_daily_coaching_reads_user_date
    ON daily_coaching_reads(user_id, read_date DESC);

-- The UNIQUE constraint above also covers (user_id, read_date) equality
-- lookups for the cron short-circuit.

-- ============================================================================
-- updated_at trigger
-- ============================================================================

CREATE OR REPLACE FUNCTION update_daily_coaching_reads_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE TRIGGER daily_coaching_reads_updated_at_trigger
    BEFORE UPDATE ON daily_coaching_reads
    FOR EACH ROW
    EXECUTE FUNCTION update_daily_coaching_reads_timestamp();

-- ============================================================================
-- RLS
--
-- Athletes can read, insert, and update their own row. Inserts/updates from
-- clients are scoped to their own user_id; the edge function (service role)
-- has unconditional access for the cron- and trigger-driven writes.
-- No DELETE policy — there is no client-side delete path; auth cascade
-- cleanup happens via a future scheduled job, not via RLS.
-- ============================================================================

ALTER TABLE daily_coaching_reads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_daily_coaching_reads_select" ON daily_coaching_reads
    FOR SELECT USING (user_id = auth.uid()::text);

CREATE POLICY "rls_daily_coaching_reads_insert" ON daily_coaching_reads
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);

CREATE POLICY "rls_daily_coaching_reads_update" ON daily_coaching_reads
    FOR UPDATE USING (user_id = auth.uid()::text)
                  WITH CHECK (user_id = auth.uid()::text);

-- Service role bypass for `coaching-daily-read` edge function writes.
CREATE POLICY "rls_daily_coaching_reads_service_role" ON daily_coaching_reads
    FOR ALL USING (auth.role() = 'service_role')
            WITH CHECK (auth.role() = 'service_role');
