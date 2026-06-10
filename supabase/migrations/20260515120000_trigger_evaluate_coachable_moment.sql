-- ============================================================================
-- SUPERSEDED — DO NOT APPLY.
--
-- This file originally proposed a direct pg_net trigger that fired
-- `evaluate-coachable-moment` on every training_logs INSERT/UPDATE.
-- It was authored 2026-05-15 but never deployed (its trigger doesn't
-- exist in production).
--
-- The pattern was correct in shape but wrong in mechanism for this
-- codebase: by the time we tried to apply it, the workout-insight side
-- (20260508150000_outbox_trigger_workout_insight.sql) had already moved
-- from direct pg_net to an outbox queue + cron drainer pattern, because
-- HealthKit-sync bursts overwhelmed edge-fn concurrency under direct
-- pg_net firing. Applying the original direct-pg_net version of this
-- file would have re-introduced the bug the May 8 refactor fixed.
--
-- Replaced by:
--   - 20260518100000_coachable_moment_outbox_trigger.sql
--   - 20260518110000_drain_coachable_moment_jobs_cron.sql
--
-- Kept as a stub so the migration ordering stays consistent and so a
-- future maintainer doesn't recreate the same pg_net version by
-- accident. Body intentionally empty — the BEGIN/COMMIT pair is a
-- valid no-op transaction.
-- ============================================================================

BEGIN;
-- no-op
COMMIT;
