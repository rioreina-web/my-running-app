-- ============================================================================
-- Cross-source dedup MERGE PRECEDENCE fix (WS7 follow-up).
--
-- PROBLEM (observed live 2026-06-17): the recurring sweep
-- (dedupe_recent_training_logs, 20260613240000) keeps the lap-owning Strava copy
-- as the keeper, then merges qualitative fields with
--     cleaned_notes = COALESCE(keeper, donor)
-- But a Strava row's cleaned_notes is its ACTIVITY TITLE — "Morning Run",
-- "Evening Run", etc. — not a real summary. So COALESCE keeps "Morning Run" and
-- DISCARDS the voice memo's actual content ("2K and 1K intervals at Zilker…"),
-- mood, RPE, and parsed structure when the voice copy (0 laps) is deleted as a
-- loser. Net: every voice memo on a run that also syncs from Strava silently
-- loses its words, and the surviving row reads "Morning Run".
--
-- FIX:
--   1. is_strava_placeholder_note() — treats Strava default titles (and blank)
--      as "no real note" so voice content can win over them. Custom titles
--      ("Finals 👽") are NOT placeholders and are preserved.
--   2. Merge picks the BEST qualitative value across the whole duplicate group,
--      preferring voice_log source + non-placeholder text, and now also ports
--      extracted_data (carries RPE/intervals) and workout_type onto the keeper.
--      workout_notes still prefers the keeper's lap-derived value.
--   3. When a keeper GAINS real voice content it didn't have (old note was a
--      placeholder/null, new is real), its coach_insight is cleared and a
--      coach_insight_job enqueued — so generate-workout-insight re-reads the now
--      richer row (laps + the athlete's words together). Bounded: only fires on
--      a genuine content gain, so steady-state sweeps don't churn.
--   4. Loser deletion is UNCHANGED (lapless always; lapped only on same key).
--
-- CREATE OR REPLACE only; the cron schedule from 20260613240000 already points
-- at this function name. search_path pinned, tables public.-qualified.
-- Validate read-only against prod before db push (see notes at bottom).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.is_strava_placeholder_note(t text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
SET search_path = pg_catalog, pg_temp
AS $$
  SELECT t IS NULL
      OR btrim(t) = ''
      OR btrim(t) ~* '^(early morning|morning|lunch|afternoon|evening|night|late night)\s+(run|ride|workout|activity|swim|walk|hike)$';
$$;

COMMENT ON FUNCTION public.is_strava_placeholder_note(text) IS
  'True when a note is empty or a Strava default activity title (e.g. "Morning Run"). Used by the dedup merge so a real voice-memo summary wins over a Strava title. Custom titles are NOT placeholders.';

CREATE OR REPLACE FUNCTION public.dedupe_recent_training_logs(p_days integer DEFAULT 3)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_deleted integer := 0;
BEGIN
  -- Rank duplicates within (user, day, ~0.5mi). Keeper = lap-owner first.
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

  -- Best qualitative value per group, preferring voice_log + non-placeholder.
  -- Captures the keeper's OLD cleaned_notes so we can detect a genuine gain.
  CREATE TEMP TABLE _merge ON COMMIT DROP AS
  WITH grp AS (
    SELECT r.grp_id,
      (array_agg(tl.cleaned_notes ORDER BY
          (CASE WHEN tl.source = 'voice_log' AND NOT public.is_strava_placeholder_note(tl.cleaned_notes) THEN 0
                WHEN NOT public.is_strava_placeholder_note(tl.cleaned_notes) THEN 1
                ELSE 2 END), tl.created_at)
        FILTER (WHERE tl.cleaned_notes IS NOT NULL))[1] AS best_cleaned_notes,
      (array_agg(tl.mood ORDER BY
          (CASE WHEN tl.source = 'voice_log' THEN 0 ELSE 1 END), tl.created_at)
        FILTER (WHERE tl.mood IS NOT NULL))[1] AS best_mood,
      (array_agg(tl.notes ORDER BY
          (CASE WHEN tl.source = 'voice_log' AND NOT public.is_strava_placeholder_note(tl.notes) THEN 0
                WHEN NOT public.is_strava_placeholder_note(tl.notes) THEN 1
                ELSE 2 END), tl.created_at)
        FILTER (WHERE tl.notes IS NOT NULL))[1] AS best_notes,
      (array_agg(tl.workout_notes ORDER BY tl.created_at)
        FILTER (WHERE tl.workout_notes IS NOT NULL))[1] AS best_workout_notes,
      (array_agg(tl.extracted_data ORDER BY
          (CASE WHEN tl.source = 'voice_log' THEN 0 ELSE 1 END), tl.created_at)
        FILTER (WHERE tl.extracted_data IS NOT NULL))[1] AS best_extracted,
      (array_agg(tl.workout_type ORDER BY
          (CASE WHEN tl.source = 'voice_log' THEN 0 ELSE 1 END), tl.created_at)
        FILTER (WHERE tl.workout_type IS NOT NULL))[1] AS best_workout_type
    FROM _dup_rank r
    JOIN public.training_logs tl ON tl.id = r.id
    WHERE r.grp_size > 1
    GROUP BY r.grp_id
  )
  SELECT r.id AS keeper_id, r.user_id, k.cleaned_notes AS old_cleaned,
         g.best_cleaned_notes, g.best_mood, g.best_notes,
         g.best_workout_notes, g.best_extracted, g.best_workout_type
  FROM _dup_rank r
  JOIN grp g ON g.grp_id = r.grp_id
  JOIN public.training_logs k ON k.id = r.id
  WHERE r.rn = 1 AND r.grp_size > 1;

  -- 1. Merge onto the keeper. Voice content wins over placeholder titles for
  --    cleaned_notes/notes; mood/extracted_data/workout_type fill when missing;
  --    workout_notes keeps the keeper's lap-derived value, falling back to donor.
  UPDATE public.training_logs k
  SET cleaned_notes = CASE
        WHEN m.best_cleaned_notes IS NOT NULL
             AND NOT public.is_strava_placeholder_note(m.best_cleaned_notes)
          THEN m.best_cleaned_notes
        ELSE COALESCE(k.cleaned_notes, m.best_cleaned_notes)
      END,
      notes = CASE
        WHEN m.best_notes IS NOT NULL
             AND NOT public.is_strava_placeholder_note(m.best_notes)
          THEN m.best_notes
        ELSE COALESCE(k.notes, m.best_notes)
      END,
      mood          = COALESCE(k.mood,           m.best_mood),
      workout_notes = COALESCE(k.workout_notes,  m.best_workout_notes),
      extracted_data= COALESCE(k.extracted_data, m.best_extracted),
      workout_type  = COALESCE(k.workout_type,   m.best_workout_type)
  FROM _merge m
  WHERE k.id = m.keeper_id;

  -- 2. Regenerate the insight for keepers that GAINED real voice content
  --    (old note was placeholder/null, new note is real). The merged row now
  --    has laps + the athlete's words, so the prior insight is stale.
  UPDATE public.training_logs k
  SET coach_insight = NULL, coach_insight_status = 'pending'
  FROM _merge m
  WHERE k.id = m.keeper_id
    AND public.is_strava_placeholder_note(m.old_cleaned)
    AND m.best_cleaned_notes IS NOT NULL
    AND NOT public.is_strava_placeholder_note(m.best_cleaned_notes);

  INSERT INTO public.coach_insight_jobs (training_log_id, user_id)
  SELECT m.keeper_id, m.user_id
  FROM _merge m
  WHERE public.is_strava_placeholder_note(m.old_cleaned)
    AND m.best_cleaned_notes IS NOT NULL
    AND NOT public.is_strava_placeholder_note(m.best_cleaned_notes)
  ON CONFLICT (training_log_id) DO NOTHING;

  -- 3. Delete losers — lapless always; lapped only when same external key.
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
  'WS7 recurring cross-source dedup. Groups by (user, day, ~0.5mi); merges the BEST qualitative fields (voice_log + non-placeholder wins; ports extracted_data/workout_type) onto the lap-owning keeper; regenerates coach_insight when a keeper gains real voice content; deletes lapless or same-external-key duplicates. Never deletes a lapped row matched only heuristically.';

COMMIT;

-- Validate read-only BEFORE db push (no writes):
--   -- groups where the keeper currently holds a Strava placeholder but a voice
--   -- copy has a real note (these are the rows the fix will heal going forward):
--   WITH base AS (
--     SELECT tl.*, (tl.workout_date AT TIME ZONE 'UTC')::date d,
--            round((tl.workout_distance_miles*2)::numeric)/2 mi
--     FROM training_logs tl WHERE tl.workout_distance_miles IS NOT NULL
--   )
--   SELECT d, mi,
--          bool_or(source='voice_log' AND NOT public.is_strava_placeholder_note(cleaned_notes)) voice_has_real,
--          bool_or(source='strava'   AND public.is_strava_placeholder_note(cleaned_notes))     strava_placeholder
--   FROM base GROUP BY d, mi HAVING count(*) > 1;
-- After push, one wider manual heal + verify:
--   SELECT public.dedupe_recent_training_logs(120);
