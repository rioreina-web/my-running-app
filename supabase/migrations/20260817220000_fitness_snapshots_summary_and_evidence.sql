-- fitness_snapshots: the last two things the device still computed itself.
--
-- The iOS app stopped WRITING this table on 2026-08-17 and stopped deriving
-- its numbers from a local model the same day — but `canonicalPrediction`
-- still borrowed three context fields from the on-device estimate: the prose
-- summary, the voice-log count and the hard-effort count. Those three strings
-- were the only reason an 851-line duplicate model still ran on every launch,
-- fetching 180 days of workouts to produce them.
--
-- Persisting them here retires that model. `summary` is the predictor's own
-- one-line account; `supporting_training` is the workings it already returns
-- (`FitnessPredictionResult.supportingTraining`) — which sessions the estimate
-- rests on, and which were read and set aside with the reason.
--
-- Additive and nullable: a NULL column reads exactly as it did before, so old
-- rows and any un-redeployed writer keep working.

ALTER TABLE public.fitness_snapshots
  ADD COLUMN IF NOT EXISTS summary TEXT,
  ADD COLUMN IF NOT EXISTS supporting_training JSONB;

COMMENT ON COLUMN public.fitness_snapshots.summary IS
  'The predictor''s one-line account of the estimate. Replaces the on-device fitnessSummary.';

COMMENT ON COLUMN public.fitness_snapshots.supporting_training IS
  'The workings: {used:[ZoneEstimate], readButNotUsed:[{date,reason}], workMinutes}. '
  'used = sessions the estimate rests on; readButNotUsed = read and set aside, with why. '
  'Written by compute-fitness-snapshot from trainingZoneSignal.ts.';
