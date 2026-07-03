-- Fix: voice memos disappearing from the Log ("voice memos are hidden").
--
-- ROOT CAUSE: dedupe_recent_training_logs() (cron job 15, every 30 min) groups
-- same-day / same-distance training_logs, keeps the run with laps as the
-- "keeper", merges the loser's qualitative fields onto it, then DELETES the
-- loser. A voice memo recorded about a run that ALSO synced from Strava lands as
-- its own row with a distance, so it was treated as a deletable "loser": its
-- words/mood/audio were folded onto the Strava run and the standalone voice-memo
-- entry the athlete created vanished from the journal.
--
-- The 2026-06-29 migration only stopped the AUDIO FILE from being orphaned; it
-- still deleted the voice row and folded it into the run.
--
-- PRODUCT DECISION (2026-07-02): a voice memo is a first-class journal entry
-- (the qualitative signal is the whole point of the product) and must be shown
-- ALONGSIDE the run, never absorbed into it. See CLAUDE.md IA: "voice memos
-- transcribed and processed ... shown alongside runs."
--
-- FIX: exclude qualitative / audio-bearing rows from the dedup grouping
-- entirely. Voice logs, check-ins, and any row carrying a recording are never
-- grouped, never donate their content, and never deleted. Quantitative sources
-- (strava / auto_sync / manual runs) still dedup against each other exactly as
-- before. The ONLY change vs. 20260629172316 is the `base` WHERE clause.
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
      -- NEW (2026-07-02): never dedup qualitative / audio-bearing entries.
      -- Voice memos and check-ins are reflections shown alongside the run, not
      -- duplicate runs. A row carrying a recording is protected regardless of
      -- source. These rows are neither keepers-that-absorb nor losers-that-get-
      -- deleted; they pass through the dedup untouched.
      AND tl.source NOT IN ('voice_log', 'check_in')
      AND tl.audio_url IS NULL
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

  -- Best qualitative value per group (strava vs auto_sync collapse only, now
  -- that voice/check-in rows are excluded above).
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

  -- 1. Merge onto the keeper (unchanged).
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
      processing_status = CASE
        WHEN k.audio_url IS NULL AND m.best_audio_url IS NOT NULL
          THEN COALESCE(m.best_processing_status, k.processing_status)
        ELSE k.processing_status
      END
  FROM _merge m
  WHERE k.id = m.keeper_id;

  -- 2. Regenerate stale insights for enriched keepers (unchanged).
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
  --    Voice/check-in/audio rows are not in _dup_rank at all, so they can
  --    never be deleted here. The audio-orphan safety clause is retained for
  --    the strava/auto_sync case.
  WITH del AS (
    DELETE FROM public.training_logs tl
    USING _dup_rank r
    WHERE tl.id = r.id
      AND r.grp_size > 1
      AND r.rn > 1
      AND (r.laps = 0
           OR (r.vital_workout_id IS NOT NULL AND r.vital_workout_id = r.keeper_vid))
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
  'Dedup recent training_logs across QUANTITATIVE sources only (strava/auto_sync/'
  'manual). Voice memos, check-ins, and any row carrying an audio recording are '
  'excluded from grouping entirely — they are shown alongside runs as their own '
  'journal entries and are never merged or deleted. Fixed 2026-07-02 (was '
  'hiding voice memos by folding them into runs).';
