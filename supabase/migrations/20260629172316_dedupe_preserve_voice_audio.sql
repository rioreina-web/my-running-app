-- Fix: voice-memo audio lost during training-log dedup.
--
-- ROOT CAUSE: dedupe_recent_training_logs() groups same-day / same-distance
-- logs, keeps the "best" one (the run with laps), MERGES the loser's
-- cleaned_notes/mood/etc. onto the keeper, then DELETES the loser. But the
-- merge never carried `audio_url` / `transcript_url` / `processing_status`.
-- So when a voice memo landed as its own row next to a Strava run for the same
-- workout, dedup copied the words to the run, deleted the voice row, and
-- ORPHANED the audio file (and deleted the row the iOS client was polling →
-- "voice memo loads forever" + the offline-queue "upload failed" banner).
--
-- FIX: carry audio_url / transcript_url / processing_status from the best voice
-- donor onto the keeper (COALESCE — keeper wins if it already has them) before
-- the loser is deleted. Audio is preserved on the surviving row. Everything
-- else about the dedup is unchanged.
--
-- Append-only migration; deploy via `supabase db push` from a committed SHA.

CREATE OR REPLACE FUNCTION public.dedupe_recent_training_logs(p_days integer DEFAULT 3)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- Now ALSO captures the best voice artifact (audio/transcript/status) so the
  -- keeper inherits the recording instead of orphaning it.
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
        FILTER (WHERE tl.workout_type IS NOT NULL))[1] AS best_workout_type,
      -- NEW: preserve the voice recording. Prefer a row that actually has audio.
      (array_agg(tl.audio_url ORDER BY
          (CASE WHEN tl.source = 'voice_log' THEN 0 ELSE 1 END), tl.created_at)
        FILTER (WHERE tl.audio_url IS NOT NULL))[1] AS best_audio_url,
      (array_agg(tl.transcript_url ORDER BY
          (CASE WHEN tl.source = 'voice_log' THEN 0 ELSE 1 END), tl.created_at)
        FILTER (WHERE tl.transcript_url IS NOT NULL))[1] AS best_transcript_url,
      (array_agg(tl.processing_status ORDER BY
          (CASE WHEN tl.audio_url IS NOT NULL THEN 0 ELSE 1 END), tl.created_at)
        FILTER (WHERE tl.processing_status IS NOT NULL))[1] AS best_processing_status
    FROM _dup_rank r
    JOIN public.training_logs tl ON tl.id = r.id
    WHERE r.grp_size > 1
    GROUP BY r.grp_id
  )
  SELECT r.id AS keeper_id, r.user_id, k.cleaned_notes AS old_cleaned,
         g.best_cleaned_notes, g.best_mood, g.best_notes,
         g.best_workout_notes, g.best_extracted, g.best_workout_type,
         g.best_audio_url, g.best_transcript_url, g.best_processing_status,
         k.audio_url AS keeper_audio_url
  FROM _dup_rank r
  JOIN grp g ON g.grp_id = r.grp_id
  JOIN public.training_logs k ON k.id = r.id
  WHERE r.rn = 1 AND r.grp_size > 1;

  -- 1. Merge onto the keeper. Voice content wins over placeholder titles for
  --    cleaned_notes/notes; mood/extracted_data/workout_type fill when missing;
  --    workout_notes keeps the keeper's lap-derived value, falling back to donor.
  --    NEW: audio_url / transcript_url / processing_status carry over (keeper
  --    wins if it already has them) so the recording is never orphaned.
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
      mood            = COALESCE(k.mood,            m.best_mood),
      workout_notes   = COALESCE(k.workout_notes,   m.best_workout_notes),
      extracted_data  = COALESCE(k.extracted_data,  m.best_extracted),
      workout_type    = COALESCE(k.workout_type,    m.best_workout_type),
      audio_url       = COALESCE(k.audio_url,        m.best_audio_url),
      transcript_url  = COALESCE(k.transcript_url,   m.best_transcript_url),
      -- Only adopt the donor's status when the keeper is gaining the audio.
      processing_status = CASE
        WHEN k.audio_url IS NULL AND m.best_audio_url IS NOT NULL
          THEN COALESCE(m.best_processing_status, k.processing_status)
        ELSE k.processing_status
      END
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
  --    SAFETY: never delete a loser that still holds an audio recording the
  --    keeper did NOT inherit (prevents orphaning when two rows both have audio).
  WITH del AS (
    DELETE FROM public.training_logs tl
    USING _dup_rank r
    WHERE tl.id = r.id
      AND r.grp_size > 1
      AND r.rn > 1
      AND (r.laps = 0
           OR (r.vital_workout_id IS NOT NULL AND r.vital_workout_id = r.keeper_vid))
      -- SAFETY: don't delete a loser that still holds audio the keeper didn't
      -- inherit (after the merge above, the keeper has it → safe to delete).
      AND (tl.audio_url IS NULL
           OR EXISTS (
             SELECT 1
             FROM _dup_rank rk
             JOIN public.training_logs keep ON keep.id = rk.id
             WHERE rk.grp_id = r.grp_id AND rk.rn = 1
               AND keep.audio_url IS NOT NULL
           ))
    RETURNING 1
  )
  SELECT count(*) INTO v_deleted FROM del;

  RETURN v_deleted;
END;
$function$;

COMMENT ON FUNCTION public.dedupe_recent_training_logs(integer) IS
  'Dedup recent training_logs; merges qualitative fields AND the voice recording '
  '(audio_url/transcript_url/processing_status) onto the keeper before deleting '
  'losers, so voice-memo audio is never orphaned. Fixed 2026-06-29.';
