-- ============================================================================
-- workout_templates — pinned flag for the library rail
-- (adaptive-plan-builder-opus-buildplan-2026-07-05.md, Phase 4)
--
-- Coaches can pin frequently-used templates so they sort to the top of the
-- plan builder's library rail. The web UI already reads and sorts on this
-- column (plan-builder-client.tsx: filteredTemplates sort pinned-first);
-- absent/false is inert, so the UI is safe to ship ahead of this migration.
--
-- No RLS changes: workout_templates policies (20260313100000_lock_down_rls.sql)
-- already scope every row by its owning coach (the `coach_id` column), and a
-- plain column is covered by those table-level policies. This mirrors the
-- precedent set by 20260703121000_plan_template_shape_columns.sql.
--
-- Hard rule #9: authored only. This reaches prod via `supabase db push` from a
-- committed SHA — never a dashboard/MCP apply. Batch with the other pending
-- authored migrations (20260703*, 20260615*, and Phase 2's coach_ai_guidance).
-- ============================================================================

BEGIN;

ALTER TABLE workout_templates
    ADD COLUMN IF NOT EXISTS pinned BOOLEAN NOT NULL DEFAULT false;

COMMENT ON COLUMN workout_templates.pinned IS
    'Coach-pinned templates sort to the top of the plan-builder library rail. '
    'Default false. Read + sorted client-side in plan-builder-client.tsx.';

-- Partial index: only pinned rows are indexed, so the common "pinned first"
-- ordering stays cheap without bloating the index with every unpinned row.
CREATE INDEX IF NOT EXISTS idx_workout_templates_pinned
    ON workout_templates (coach_id)
    WHERE pinned;

COMMIT;
