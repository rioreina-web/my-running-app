-- ============================================================================
-- Durable cross-source dedup — recurring sweep (WS7 prevention).
--
-- The one-time migration (20260613220000) heals existing duplicates. This keeps
-- them from accumulating WITHOUT touching ingestion code.
--
-- WHY A SWEEP, NOT A TRIGGER: rep-level laps arrive ASYNCHRONOUSLY, after the
-- training_log row is inserted (strava-sync writes the log, then the laps). An
-- INSERT-time trigger can't know which cross-source copy is the lap-owner — it
-- depends on arrival order. A sweep a few minutes later sees the settled state.
--
-- MATCHING: duplicates carry DIFFERENT / absent external keys, so grouping is by
-- (user, day, ~0.5mi distance) — NOT vital_workout_id. The keeper's key is used
-- only to safely collapse an exact same-key re-import even when it has laps.
--
-- SAFETY (identical to the one-time heal, validated read-only on prod):
--   • notes/mood merged from losers onto the keeper before deletion.
--   • a loser is deleted only when it has ZERO laps, OR it shares the keeper's
--     non-null vital_workout_id (provably the same activity). A lapped loser with
--     a different key is left untouched for manual review.
--   • scoped to recent workout_date (default 3 days) — cheap, small blast radius.
--
-- search_path pinned + tables public.-qualified (avoids the schema-resolution
-- bug that silently broke the drain claim RPCs).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.dedupe_recent_training_logs(p_days integer DEFAULT 3)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted integer := 0;
BEGIN
  CREATE TEMP TABLE _dup_rank ON COMMIT DROP AS
  WITH base AS (
    SELECT
      tl.id, tl.user_id, tl.vital_workout_id,
      (tl.workout_date AT TIME ZONE 'UTC')::date AS d,
      round((tl.workout_distance_miles * 2)::numeric) / 2 AS dist_bucket,
      tl.created_at,
      (tl.pace_segments IS NOT NULL) AS has_seg,
      (tl.cleaned_notes IS NOT NULL) AS has_notes,
      (SELECT count(*) FROM public.running_workout_laps l WHERE l.workout_id = tl.id) AS laps
    FROM public.training_logs tl
    WHERE tl.workout_distance_miles IS NOT NULL
      AND tl.workout_date >= (now() - make_interval(days => p_days))
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
    JOIN public.training_logs tl ON tl.id = r.id
    WHERE r.grp_size > 1 AND r.rn > 1
    GROUP BY r.grp_id
  )
  UPDATE public.training_logs k
  SET cleaned_notes = COALESCE(k.cleaned_notes, d.cleaned_notes),
      mood          = COALESCE(k.mood,          d.mood),
      notes         = COALESCE(k.notes,         d.notes),
      workout_notes = COALESCE(k.workout_notes, d.workout_notes)
  FROM _dup_rank r
  JOIN donors d ON d.grp_id = r.grp_id
  WHERE r.rn = 1 AND r.grp_size > 1 AND k.id = r.id;

  -- 2. Delete losers — lapless always; lapped only when same external key.
  WITH del AS (
    DELETE FROM public.training_logs tl
    USING _dup_rank r
    WHERE tl.id = r.id
      AND r.grp_size > 1
      AND r.rn > 1
      AND (r.laps = 0
           OR (r.vital_workout_id IS NOT NULL AND r.vital_workout_id = r.keeper_vid))
    RETURNING 1
  )
  SELECT count(*) INTO v_deleted FROM del;

  RETURN v_deleted;
END;
$$;

COMMENT ON FUNCTION public.dedupe_recent_training_logs(integer) IS
  'WS7 recurring cross-source dedup. Groups by (user, day, ~0.5mi), merges notes onto the lap-owning keeper, deletes lapless or same-external-key duplicate training_logs within p_days. Never deletes a lapped row matched only heuristically.';

-- Every 30 minutes over the last 3 days (catches dups once laps have landed).
SELECT cron.schedule(
  'dedupe-training-logs',
  '*/30 * * * *',
  $job$ SELECT public.dedupe_recent_training_logs(3); $job$
);

COMMIT;

-- Verify (after apply):
--   SELECT public.dedupe_recent_training_logs(120);  -- one manual wider sweep
--   SELECT jobname, schedule FROM cron.job WHERE jobname = 'dedupe-training-logs';
