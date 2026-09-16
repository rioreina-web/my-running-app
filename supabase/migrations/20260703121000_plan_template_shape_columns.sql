-- ============================================================================
-- plan_templates — shape + structure columns the builder now writes
-- (outputs/adaptive-coach-plan-builder-spec-2026-07-03.md, Phase A)
--
-- `subscribe-to-plan` has read template.rest_day_of_week,
-- auto_strides_on_pre_quality, and recovery_after_long_run since April, but
-- no migration in the ledger ever added them (they exist in prod only if an
-- ad-hoc apply created them — cf. docs/migration-ledger-reconciliation-
-- 2026-06-11.md). ADD COLUMN IF NOT EXISTS makes this migration correct in
-- either world and puts the columns in the ledger where they belong.
--
-- No RLS changes: plan_templates policies (20260313100000_lock_down_rls.sql)
-- already scope by coach; these are plain columns on an existing table.
-- ============================================================================

BEGIN;

ALTER TABLE plan_templates
    ADD COLUMN IF NOT EXISTS rest_day_of_week INTEGER
        CHECK (rest_day_of_week IS NULL OR (rest_day_of_week BETWEEN 0 AND 6)),
    ADD COLUMN IF NOT EXISTS auto_strides_on_pre_quality BOOLEAN NOT NULL DEFAULT true,
    ADD COLUMN IF NOT EXISTS recovery_after_long_run BOOLEAN NOT NULL DEFAULT true;

COMMENT ON COLUMN plan_templates.rest_day_of_week IS
    'Plan-level forced rest day (0=Mon..6=Sun). Null = no forced rest. '
    'Written by the builder''s Plan setup section; mirrors the day_structure '
    'role=rest entry for older readers.';

COMMENT ON COLUMN plan_templates.auto_strides_on_pre_quality IS
    'Materializer adds strides to the easy day before a quality session.';

COMMENT ON COLUMN plan_templates.recovery_after_long_run IS
    'Materializer converts the day after the long run into a recovery run.';

COMMIT;
