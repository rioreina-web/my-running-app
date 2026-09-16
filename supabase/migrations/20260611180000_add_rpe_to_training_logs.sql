-- ============================================================================
-- RPE (rate of perceived exertion) on training_logs.
--
-- Backs the Training tab's "Effort · Felt vs Planned" section
-- (training-tab-spec.md §8). Today the app has no felt/planned effort signal
-- anywhere — `mood` is the only subjective field — so this is net-new.
--
--   felt_rpe        1–10 perceived effort, extracted from the voice-memo
--                   transcript by the `extract-rpe` edge function. NULL until
--                   extracted — the UI renders the row ONLY when felt exists,
--                   never a fabricated value (spec core-rule: never fake data).
--   planned_rpe     1–10 prescribed effort, from the plan when one is loaded.
--                   NULL => the client falls back to session-type defaults
--                   (easy≈3, tempo≈6, intervals≈7) at read time.
--   rpe_pull_quote  short verbatim line from the transcript shown italicised
--                   under the day-grid expansion.
--   rpe_tags        a few lowercase tags (e.g. {tired, humid}) surfaced as
--                   uppercase chips.
--   rpe_extracted_at  when extraction last ran (idempotency / re-run guard).
--
-- Additive + nullable: existing reads/writes are unaffected, and the iOS
-- client fetches these columns in a separate resilient query so the Training
-- tab keeps working even before this migration is applied.
-- ============================================================================

BEGIN;

ALTER TABLE training_logs
  ADD COLUMN IF NOT EXISTS felt_rpe         SMALLINT,
  ADD COLUMN IF NOT EXISTS planned_rpe      SMALLINT,
  ADD COLUMN IF NOT EXISTS rpe_pull_quote   TEXT,
  ADD COLUMN IF NOT EXISTS rpe_tags         TEXT[],
  ADD COLUMN IF NOT EXISTS rpe_extracted_at TIMESTAMPTZ;

-- Keep the scale honest (1–10) without rejecting NULLs.
ALTER TABLE training_logs
  DROP CONSTRAINT IF EXISTS training_logs_felt_rpe_range;
ALTER TABLE training_logs
  ADD CONSTRAINT training_logs_felt_rpe_range
  CHECK (felt_rpe IS NULL OR (felt_rpe BETWEEN 1 AND 10));

ALTER TABLE training_logs
  DROP CONSTRAINT IF EXISTS training_logs_planned_rpe_range;
ALTER TABLE training_logs
  ADD CONSTRAINT training_logs_planned_rpe_range
  CHECK (planned_rpe IS NULL OR (planned_rpe BETWEEN 1 AND 10));

COMMENT ON COLUMN training_logs.felt_rpe IS
  'Perceived effort 1–10, extracted from the voice-memo transcript by the '
  'extract-rpe edge function. NULL until extracted — UI never fabricates effort.';
COMMENT ON COLUMN training_logs.planned_rpe IS
  'Prescribed effort 1–10 from the plan; NULL => client uses session-type defaults.';
COMMENT ON COLUMN training_logs.rpe_pull_quote IS
  'Short verbatim transcript line shown under the Training day-grid expansion.';
COMMENT ON COLUMN training_logs.rpe_tags IS
  'Lowercase effort tags (e.g. {tired, humid}) rendered as uppercase chips.';

COMMIT;
