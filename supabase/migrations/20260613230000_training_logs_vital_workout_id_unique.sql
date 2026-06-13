-- ============================================================================
-- Durable guard: one training_log per (user, external activity).
--
-- Defense-in-depth against the re-import duplicate class (the strava×2 /
-- auto_sync×2 rows seen on 2026-05-05 and 2026-05-23). strava-sync already
-- app-checks `vital_workout_id` before insert, but nothing enforced it at the
-- DB, so a race or a second ingestion path could still double-insert the same
-- activity. This makes it impossible.
--
-- Partial index: only rows that carry an external key are constrained. Manual
-- and voice-only logs (vital_workout_id NULL/'') are unaffected.
--
-- ORDER DEPENDENCY: must run AFTER 20260613220000_dedupe_cross_source_
-- training_logs.sql, whose exact-key pass removes every duplicate
-- vital_workout_id — otherwise CREATE UNIQUE INDEX would fail on existing dups.
--
-- SCOPE NOTE: this does NOT cover cross-source duplicates where the two copies
-- carry *different* keys (e.g. auto_sync's HealthKit id vs strava's strava_<id>
-- for the same run) or where one copy is a keyless voice_log. Those require an
-- ingestion-side same-day/near-distance merge (a behavioral change in the
-- secondary-source paths) — tracked separately, not enforceable as a hard
-- constraint without risking legitimate same-day double-runs.
--
-- Append-only; idempotent (IF NOT EXISTS).
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS training_logs_user_vital_workout_uniq
  ON training_logs (user_id, vital_workout_id)
  WHERE vital_workout_id IS NOT NULL AND vital_workout_id <> '';

COMMENT ON INDEX training_logs_user_vital_workout_uniq IS
  'One training_log per (user_id, external activity). Prevents same-source re-import duplicates. Cross-source (differing keys) dedup is handled at ingestion + the dedupe migration.';
