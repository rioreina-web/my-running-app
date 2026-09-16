-- ============================================================================
-- workout_features.quality_load / quality_kind — persist the effort score the
-- calendar cannot compute for itself.
--
-- The Key Sessions grid in Trends already scores every session this way
-- (trends-timeline/keySessions.ts → qualityLoad.ts). The calendar and the
-- journal could not, so they each invented a cheaper rule — "any threshold
-- mileage at all", "this workout_type string is in my list" — and those rules
-- disagreed with the grid and with each other. Persisting the number is what
-- lets every surface ask the same question.
--
-- workout_features is the right home: one row per log (UNIQUE(training_log_id),
-- 20260318120000:67), already carrying the derived classification
-- (workout_type, workout_structure — 20260613200000). Append-only, nullable
-- columns, no RLS change — the same shape as that migration.
--
-- ⚠️  THE TRAP THAT WOULD STAR EVERY DAY IN THE CALENDAR
-- ------------------------------------------------------
-- The two load formulas are NOT interchangeable:
--
--   qualityLoadForBouts()  — WORK bouts only. Warmup, floats, rest and
--                            cooldown fall out.
--   aerobicLoadForBouts()  — EVERY bout. A 93-minute easy long run scores ~93.
--
-- aerobicLoadForBouts is legal ONLY when workout_type == 'long_run'. Apply it
-- to any run without work bouts and a routine 60-minute easy run scores ~60,
-- clears the floor of 25, and every single day gets a star. The branch is:
--
--   work bouts present        → 'quality',  qualityLoadForBouts(workBouts)
--   no work bouts + long_run  → 'long_run', aerobicLoadForBouts(allBouts)
--                                           (longRunLoadFromMinutes if lapless)
--   otherwise                 → NULL,       NULL
--
-- There is a named regression test for the easy-run case (KeySessionTests /
-- keySessions.test.ts). Do not relax that branch.
-- ============================================================================

BEGIN;

ALTER TABLE workout_features
  ADD COLUMN IF NOT EXISTS quality_load DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS quality_kind TEXT;

COMMENT ON COLUMN workout_features.quality_load IS
  'Weighted minutes of stimulus. Quality session: sum over WORK bouts '
  '(qualityLoadForBouts). Long run: sum over ALL bouts (aerobicLoadForBouts). '
  'NULL for an ordinary run. The key-session floor is applied client-side '
  '(QualityLoad.floor) so it can be tuned without an edge-function deploy, '
  'and so sub-floor work can still be drawn as an open ring rather than '
  'being told it does not exist.';

COMMENT ON COLUMN workout_features.quality_kind IS
  'quality | long_run | NULL. Which formula produced quality_load. NULL means '
  'neither applied and this session is not a derived key-session candidate.';

COMMIT;
