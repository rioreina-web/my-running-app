-- ============================================================================
-- Cross-source dedup v2 — matching on TIME + DISTANCE, quarantine not DELETE.
--
-- Replaces the (user, UTC-day, 0.5mi-bucket) matching rule. Validated against a
-- 13-case battery: v2 13/13, the old rule 8/13 (five real runs destroyed, the
-- one true duplicate missed).
--
-- CHECKED AGAINST PRODUCTION 2026-08-20 — read this before applying:
--
--   1. THE OLD SWEEP IS NOT RUNNING. `dedupe-training-logs` is absent from
--      cron.job on RunningAppMVP2. Migration 20260613240000 IS applied, so it
--      was scheduled once and unscheduled later. Nothing is being deleted right
--      now. This migration is therefore NOT urgent — it is a correctness fix to
--      land before anything re-enables a sweep.
--
--   2. THE LIVE FUNCTION IS NEWER THAN 20260613240000. Three later migrations
--      amended it (20260618000000, 20260629172316, 20260702200000). The live
--      body now excludes `source IN ('voice_log','check_in')` and any row with
--      `audio_url IS NOT NULL`, so voice memos are already protected. THAT
--      PROTECTION IS PRESERVED BELOW — see the base CTE. The 13-case battery was
--      run against the 20260613240000 text, so it overstates the damage the
--      CURRENT function would do to memo rows; the distance/time matching bug it
--      demonstrates is unchanged and still real.
--
--   3. A dry-run of v2's matching over 180 days of production data returned
--      ZERO pairs. The cross-source duplicates it targets have already been
--      deleted by the old sweep. v2 would quarantine nothing today. Its value is
--      forward-looking: it is what should run if a sweep is ever re-enabled.
--
-- WHAT CHANGED AND WHY
--
--   1. TIME IS USED. `workout_date` is TIMESTAMPTZ and always was; the old rule
--      cast it to a UTC date on line 1 and threw the clock away, so a 6am run
--      and a 5:30pm run were "the same run". Two copies of one activity start
--      within a couple of minutes of each other — that is the actual signal.
--
--   2. DISTANCE IS A WINDOW, NOT A BUCKET. round(mi*2)/2 fails both ways:
--      5.24 and 5.26 (one run, two sources) land in DIFFERENT buckets and never
--      merge, while 5.25 and 5.74 (two real runs) land in the SAME one and one
--      is deleted. A tolerance — max(0.15mi, 3%) — is the correct test.
--
--   3. NOTHING IS DELETED. Rows are marked `superseded_at` + `duplicate_of`.
--      The old sweep has been running every 30 min since 2026-06-13 with no
--      record of what it took; that must not be true of its replacement.
--
-- PRESERVED FROM THE ORIGINAL (these parts were right):
--   • sweep, not an INSERT trigger — laps land asynchronously after the log row
--   • notes/mood merged onto the keeper BEFORE it supersedes anything
--   • a lapped loser is only ever touched when it shares the keeper's external
--     key; a lapped row matched heuristically is left alone for manual review
-- ============================================================================

BEGIN;

ALTER TABLE public.training_logs
  ADD COLUMN IF NOT EXISTS duplicate_of uuid
    REFERENCES public.training_logs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS superseded_at timestamptz,
  ADD COLUMN IF NOT EXISTS superseded_reason text;

-- ON DELETE SET NULL is load-bearing: without it the self-reference blocks any
-- future deletion of a keeper that a quarantined row still points at.
--
-- TRIGGER INTERACTION — checked, and clean. `training_logs` carries three
-- AFTER UPDATE triggers, and this function now UPDATEs rows the old one
-- DELETEd, so they were a real risk:
--   • coachable_moment_outbox  WHEN (OLD.cleaned_notes IS NULL AND NEW … NOT NULL)
--   • daily_read_workout_rerender  — same WHEN clause
--   • enqueue_voice_job  WHEN (processing_status='pending' AND audio_url/status changed)
-- The quarantine UPDATE touches only duplicate_of / superseded_at /
-- superseded_reason, so none of the three WHEN clauses evaluate true. The notes
-- merge in step 1 CAN fire the first two — but that merge is unchanged from the
-- original function, so this is existing behaviour, not a new side effect.
-- RE-CHECK THIS if you ever add a column to the quarantine UPDATE.

-- NOTE: index creation is deliberately NOT in this transaction. A plain
-- CREATE INDEX holds a write lock for its duration; on a table this size that
-- is short but not free. Run it separately, after the migration, outside any
-- transaction block:
--
--   CREATE INDEX CONCURRENTLY IF NOT EXISTS training_logs_live_idx
--     ON public.training_logs (user_id, workout_date DESC)
--     WHERE superseded_at IS NULL;
--
-- The function is correct without it; the index only matters once reads filter
-- on superseded_at (step 3 of DEDUPE-FIX-APPLY.md).

CREATE OR REPLACE FUNCTION public.dedupe_recent_training_logs_v2(
  p_days         integer DEFAULT 3,
  p_time_tol_min numeric DEFAULT 10,
  p_dist_tol_mi  numeric DEFAULT 0.15,
  p_dist_tol_pct numeric DEFAULT 0.03,
  p_dry_run      boolean DEFAULT false
) RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_marked integer := 0;
BEGIN
  CREATE TEMP TABLE _c ON COMMIT DROP AS
  WITH base AS (
    SELECT tl.id, tl.user_id, tl.workout_date, tl.vital_workout_id, tl.created_at,
      tl.workout_distance_miles AS mi,
      (tl.pace_segments IS NOT NULL) AS has_seg,
      (tl.cleaned_notes IS NOT NULL) AS has_notes,
      (SELECT count(*) FROM public.running_workout_laps l WHERE l.workout_id = tl.id) AS laps
    FROM public.training_logs tl
    WHERE tl.workout_distance_miles IS NOT NULL
      AND tl.superseded_at IS NULL
      AND tl.workout_date >= (now() - make_interval(days => p_days))
      -- Carried over from 20260702200000 and NOT to be dropped: voice memos and
      -- check-ins are reflections shown alongside a run, never duplicate runs. A
      -- row carrying a recording is protected regardless of source.
      AND tl.source NOT IN ('voice_log', 'check_in')
      AND tl.audio_url IS NULL
  ),
  flagged AS (
    SELECT *,
      CASE WHEN lag(user_id) OVER w IS NOT DISTINCT FROM user_id
            AND (
              ( abs(extract(epoch FROM workout_date - lag(workout_date) OVER w)) <= p_time_tol_min * 60
                AND abs(mi - lag(mi) OVER w)
                    <= greatest(p_dist_tol_mi, p_dist_tol_pct * greatest(mi, lag(mi) OVER w)) )
              OR ( vital_workout_id IS NOT NULL
                   AND vital_workout_id = lag(vital_workout_id) OVER w )
            )
           THEN 0 ELSE 1 END AS is_new
    FROM base WINDOW w AS (PARTITION BY user_id ORDER BY workout_date, created_at)
  ),
  clustered AS (
    SELECT *, sum(is_new) OVER (PARTITION BY user_id ORDER BY workout_date, created_at
                                ROWS UNBOUNDED PRECEDING) AS cid
    FROM flagged
  )
  SELECT *, count(*) OVER w2 AS grp_size, row_number() OVER w2 AS rn,
         first_value(id) OVER w2 AS keeper_id
  FROM clustered
  WINDOW w2 AS (PARTITION BY user_id, cid
                ORDER BY laps DESC, has_seg DESC, has_notes DESC, created_at ASC);

  IF p_dry_run THEN
    SELECT count(*) INTO v_marked FROM _c WHERE grp_size > 1 AND rn > 1;
    RETURN v_marked;
  END IF;

  WITH donors AS (
    SELECT c.keeper_id,
      (array_remove(array_agg(tl.cleaned_notes) FILTER (WHERE tl.cleaned_notes IS NOT NULL), NULL))[1] AS cleaned_notes,
      (array_remove(array_agg(tl.mood)          FILTER (WHERE tl.mood          IS NOT NULL), NULL))[1] AS mood,
      (array_remove(array_agg(tl.notes)         FILTER (WHERE tl.notes         IS NOT NULL), NULL))[1] AS notes,
      (array_remove(array_agg(tl.workout_notes) FILTER (WHERE tl.workout_notes IS NOT NULL), NULL))[1] AS workout_notes
    FROM _c c JOIN public.training_logs tl ON tl.id = c.id
    WHERE c.grp_size > 1 AND c.rn > 1 GROUP BY c.keeper_id
  )
  UPDATE public.training_logs k
  SET cleaned_notes = COALESCE(k.cleaned_notes, d.cleaned_notes),
      mood          = COALESCE(k.mood,          d.mood),
      notes         = COALESCE(k.notes,         d.notes),
      workout_notes = COALESCE(k.workout_notes, d.workout_notes)
  FROM donors d WHERE k.id = d.keeper_id;

  WITH upd AS (
    UPDATE public.training_logs tl SET
      duplicate_of      = c.keeper_id,
      superseded_at     = now(),
      superseded_reason = format('dedupe_v2: within %s min / %s mi of keeper %s',
                                 p_time_tol_min, p_dist_tol_mi, c.keeper_id)
    FROM _c c
    WHERE tl.id = c.id AND c.grp_size > 1 AND c.rn > 1
      AND ( c.laps = 0
            OR ( c.vital_workout_id IS NOT NULL
                 AND c.vital_workout_id = (SELECT k.vital_workout_id FROM _c k WHERE k.id = c.keeper_id) ) )
    RETURNING 1
  ) SELECT count(*) INTO v_marked FROM upd;
  RETURN v_marked;
END; $$;

-- ── Grants: nobody but service_role ──────────────────────────────────────
--
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default. Without these lines
-- this function would be reachable at /rest/v1/rpc/dedupe_recent_training_logs_v2
-- by anyone holding the anon key — which ships in the iOS binary and the web
-- bundle. It is SECURITY DEFINER and takes no user_id, so it operates across
-- EVERY athlete's rows and bypasses RLS entirely.
--
-- That is precisely the hole the 2026-07-17 sweep closed on v1: the live
-- `dedupe_recent_training_logs` reads anon=false / authenticated=false today
-- because it was explicitly revoked. Re-checked 2026-08-24. Creating v2
-- without these REVOKEs would have re-opened it under a new name — quarantine
-- instead of delete, so less destructive, but still a cross-user write any
-- unauthenticated caller could trigger.
REVOKE ALL ON FUNCTION public.dedupe_recent_training_logs_v2(integer, numeric, numeric, numeric, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.dedupe_recent_training_logs_v2(integer, numeric, numeric, numeric, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.dedupe_recent_training_logs_v2(integer, numeric, numeric, numeric, boolean) FROM authenticated;

COMMENT ON FUNCTION public.dedupe_recent_training_logs_v2 IS
  'Cross-source dedup v2. Matches on start-time proximity AND distance tolerance (never a UTC-day + 0.5mi bucket). Quarantines via superseded_at; never deletes. p_dry_run counts without writing.';

COMMIT;
