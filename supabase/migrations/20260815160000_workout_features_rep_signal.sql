-- ============================================================================
-- workout_features.rep_signal — persist the per-rep shape + recovery read.
--
-- WHAT IT IS. For a quality session with ≥4 settled reps of ≥90s, the JSONB
-- holds the output of `_shared/repSignal.ts`: the per-rep series (hrPeak,
-- hrr60, carryover, recovery) and the session score (four slopes over reps
-- 1..n−1, the final-rep close, sensor flags, confidence, verdict key). Design
-- + calibration: REP-RECOVERY-SCORE-APPLY.md, CURRENT-FITNESS-APPLY.md §2.2 —
-- every threshold was measured against real sessions on 2026-08-14.
--
-- WHY PERSISTED, NOT COMPUTED ON READ. hrr60 needs the per-second HR stream
-- (`training_logs.external_streams`), which the 2026-08-13 cost audit names
-- the single largest cost in the app. compute-workout-features computes it
-- ONCE at ingest — and only for sessions whose LAPS already show ≥4 rep
-- candidates of ≥90s, so the expensive stream fetch is gated by a cheap check
-- (~2–3 sessions/week, not every run). Same discipline as quality_load.
--
-- SHAPE (stable keys; clients tolerate missing fields):
--   { "v": 1,
--     "reps": [ { "index", "durationS", "paceSecPerMile", "hrPeak",
--                 "hrr30", "hrr60", "hrFloor", "hrAtNextRepStart",
--                 "recoverySeconds", "hrSettled", "tooShort" }, … ],
--     "score": { "scored", "reason", "repsUsable", "level",
--                "recovery": {"total","direction"}, "carryover": {…},
--                "pace": {…}, "hrCost": {…},
--                "finalRep": {"paceSecPerMile","deltaVsMedianSec","close"},
--                "flags": [], "confidence", "verdict": {"key","label"}|null } }
--
-- NULL means "not computed" (no laps, no stream, or the session isn't a rep
-- session). `score.scored=false` means "computed and honestly unscoreable"
-- (e.g. all reps under 90s). The two are different claims — same distinction
-- quality_load draws between NULL and 0.
--
-- workout_features is the right home: one row per log (UNIQUE(training_log_id)),
-- already carrying quality_load/quality_kind. Append-only, nullable column,
-- no RLS change.
-- ============================================================================

BEGIN;

ALTER TABLE workout_features
  ADD COLUMN IF NOT EXISTS rep_signal JSONB;

COMMENT ON COLUMN workout_features.rep_signal IS
  'Per-rep shape + recovery read (repSignal.ts, v1). Per-rep hrPeak/hrr60/'
  'carryover series plus the session score: four slopes over reps 1..n-1, '
  'final-rep close, sensor flags, confidence, verdict. NULL = not computed '
  '(not a rep session / no stream). score.scored=false = computed and '
  'unscoreable, with the reason. Verdict is withheld (null) at low '
  'confidence while the facts remain — the Ask posture.';

COMMIT;
