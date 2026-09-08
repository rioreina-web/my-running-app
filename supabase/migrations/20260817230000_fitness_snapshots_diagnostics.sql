-- fitness_snapshots.diagnostics — the workings behind the number.
--
-- Asked on 2026-08-17 how much of the gap between a 31:20 anchor and a
-- published 32:00 was decay versus training, the honest answer was that
-- nothing recorded it. Inputs were queryable, the output was queryable, and
-- every stage in between was computed and discarded. The question could only
-- be answered by re-deriving it by hand, and the re-derivation disagreed with
-- the stored value — which is exactly the moment you want the record.
--
-- Holds: anchor pace and age, weekly volume and stimulus, quality density,
-- maintenance and decay factors, the training signal BEFORE blending, the
-- blend weight, both caps and whether either bound, the EF verdict, and the
-- curve's alpha/cap/reason. Written by compute-fitness-snapshot.
--
-- Diagnostic only. Nothing reads it to make a decision, so it can change shape
-- freely without a migration. Additive and nullable.

ALTER TABLE public.fitness_snapshots
  ADD COLUMN IF NOT EXISTS diagnostics JSONB;

COMMENT ON COLUMN public.fitness_snapshots.diagnostics IS
  'Predictor intermediates: anchor -> decay -> training blend -> caps -> curve. '
  'Diagnostic only; no consumer branches on it. Shape may change without migration.';
