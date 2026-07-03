-- ============================================================================
-- Cross-source duplicate training_logs cleanup (data hygiene follow-up to WS1)
--
-- PROBLEM (measured 2026-06-13, golden athlete 03857bf3, 90d window):
--   160 raw logs, ~50 of them duplicates (~30%), inflating volume ~+28%. The
--   same real activity is ingested by multiple sources — strava + voice_log, or
--   auto_sync + strava (occasionally two strava rows). One copy (strava) owns
--   the rep-level `running_workout_laps`; another (voice_log) owns the athlete's
--   notes/mood. Crucially the copies carry DIFFERENT (or absent) external keys,
--   so they must be matched by day + distance, not by vital_workout_id.
--
-- IMPACT: every volume/load/ACWR number runs ~28% high, the quality count
--   nearly doubles, and the lapless copy can win a per-day lookup so the WRONG
--   workout surfaces (May 20's 9×1K showed as "recovery" off the lapless copy).
--
-- STRATEGY — group by (user, day, ~0.5mi), keep the richest copy, MERGE:
--   1. Keeper = most laps, then has pace_segments, then has notes, then oldest.
--   2. Port qualitative fields (cleaned_notes/mood/notes/workout_notes) from the
--      dropped copies onto the keeper where it's missing them.
--   3. Delete a loser when it has ZERO laps (no rep structure to lose) OR it
--      shares the keeper's non-null vital_workout_id (provably the same activity,
--      safe even if lapped). A lapped loser with a *different* key is LEFT for
--      manual review rather than risk deleting unique lap data.
--   Child rows (workout_features, coach_insight_jobs, voice_processing_jobs,
--   workout_reconciliations, running_workout_laps) are ON DELETE CASCADE.
--
-- Validated read-only against prod: 50 deletions, 1 lapped-ambiguous row left,
-- the lap-owner kept in every group. Idempotent. Append-only.
-- Durable prevention = the recurring sweep in 20260613240000 + an eventual
-- ingestion-side merge (see outputs/the-read-implementation-spec.md WS7).
-- ============================================================================

BEGIN;

CREATE TEMP TABLE _dup_rank ON COMMIT DROP AS
WITH base AS (
  SELECT
    tl.id, tl.user_id, tl.vital_workout_id,
    (tl.workout_date AT TIME ZONE 'UTC')::date AS d,
    round((tl.workout_distance_miles * 2)::numeric) / 2 AS dist_bucket,
    tl.created_at,
    (tl.pace_segments IS NOT NULL) AS has_seg,
    (tl.cleaned_notes IS NOT NULL) AS has_notes,
    (SELECT count(*) FROM running_workout_laps l WHERE l.workout_id = tl.id) AS laps
  FROM training_logs tl
  WHERE tl.workout_distance_miles IS NOT NULL
)
SELECT *,
  (user_id || '|' || d::text || '|' || dist_bucket::text) AS grp_id,
  count(*)     OVER w AS grp_size,
  row_number() OVER w AS rn,
  first_value(vital_workout_id) OVER w AS keeper_vid
FROM base
WINDOW w AS (
  PARTITION BY user_id, d, dist_bucket
  ORDER BY laps DESC, has_seg DESC, has_notes DESC, created_at ASC
);

-- 1. Merge qualitative fields from losers onto the keeper.
WITH donors AS (
  SELECT r.grp_id,
    (array_remove(array_agg(tl.cleaned_notes) FILTER (WHERE tl.cleaned_notes IS NOT NULL), NULL))[1] AS cleaned_notes,
    (array_remove(array_agg(tl.mood)          FILTER (WHERE tl.mood          IS NOT NULL), NULL))[1] AS mood,
    (array_remove(array_agg(tl.notes)         FILTER (WHERE tl.notes         IS NOT NULL), NULL))[1] AS notes,
    (array_remove(array_agg(tl.workout_notes) FILTER (WHERE tl.workout_notes IS NOT NULL), NULL))[1] AS workout_notes
  FROM _dup_rank r
  JOIN training_logs tl ON tl.id = r.id
  WHERE r.grp_size > 1 AND r.rn > 1
  GROUP BY r.grp_id
)
UPDATE training_logs k
SET cleaned_notes = COALESCE(k.cleaned_notes, d.cleaned_notes),
    mood          = COALESCE(k.mood,          d.mood),
    notes         = COALESCE(k.notes,         d.notes),
    workout_notes = COALESCE(k.workout_notes, d.workout_notes)
FROM _dup_rank r
JOIN donors d ON d.grp_id = r.grp_id
WHERE r.rn = 1 AND r.grp_size > 1 AND k.id = r.id;

-- 2. Delete losers — lapless always; lapped only when provably same activity.
DELETE FROM training_logs tl
USING _dup_rank r
WHERE tl.id = r.id
  AND r.grp_size > 1
  AND r.rn > 1
  AND (r.laps = 0
       OR (r.vital_workout_id IS NOT NULL AND r.vital_workout_id = r.keeper_vid));

DO $$
DECLARE g INT;
BEGIN
  SELECT count(DISTINCT grp_id) INTO g FROM _dup_rank WHERE grp_size > 1;
  RAISE NOTICE 'dedupe_cross_source_training_logs: % duplicate groups processed', g;
END $$;

COMMIT;

-- Verification (run after apply):
--   WITH t AS (SELECT (workout_date AT TIME ZONE 'UTC')::date d,
--                     round((workout_distance_miles*2)::numeric)/2 mi
--              FROM training_logs
--              WHERE user_id='03857bf3-6276-4634-b3cc-15cc6d0bc653'
--                AND workout_date > now()-interval '90 days')
--   SELECT count(*) logs, count(*)-count(DISTINCT (d,mi)) dup_rows FROM t;  -- dup_rows → ~1
--   SELECT workout_type, workout_structure FROM workout_features
--    WHERE user_id='03857bf3-6276-4634-b3cc-15cc6d0bc653' AND workout_date::date='2026-05-20';
-- Then re-run compute-workout-features (backfill) + rebuild-athlete-state.
