-- Revert the SPLIT introduced by 20260702120100_restore_folded_voice_memos.
--
-- That migration recreated 4 folded memos as standalone `voice_log` rows and
-- stripped the audio off their run rows. But the app links a memo to a run only
-- when the row itself carries BOTH workout_date AND workout_distance_miles
-- (TrainingLog.hasLinkedWorkout), and the Trends volume sum adds every row's
-- miles — so a separate memo-with-distance double-counts the run's mileage. The
-- app's actual model is ONE row: the audio lives on the run row (see
-- VoiceLogViewModel attach path). Splitting them left the memos floating and
-- unlinked. Product decision 2026-07-02: revert to the one-row shape.
--
-- Each restored memo is identified by its insert timestamp (all 4 were bulk
-- inserted in the 2026-07-02 13:46 UTC minute) and maps 1:1 back to its run via
-- same user + same UTC day + identical cleaned_notes (the notes were copied off
-- the run when it was folded, so they match exactly).
--
-- Append-only migration; deploy via `supabase db push` from a committed SHA.

-- 1. Reattach the recording onto the run row each memo was split from.
UPDATE public.training_logs r
SET audio_url         = m.audio_url,
    transcript_url    = m.transcript_url,
    processing_status = 'completed'
FROM public.training_logs m
WHERE m.source = 'voice_log'
  AND m.audio_url IS NOT NULL
  AND m.created_at >= '2026-07-02 13:46:00+00'
  AND m.created_at <  '2026-07-02 13:47:00+00'
  AND r.source IN ('strava', 'auto_sync')
  AND r.user_id = m.user_id
  AND (r.workout_date AT TIME ZONE 'UTC')::date = (m.workout_date AT TIME ZONE 'UTC')::date
  AND r.cleaned_notes IS NOT DISTINCT FROM m.cleaned_notes;

-- 2. Delete each duplicate memo ONLY once its audio is confirmed back on a run
--    (guard prevents losing a recording if step 1 found no matching run).
DELETE FROM public.training_logs m
WHERE m.source = 'voice_log'
  AND m.audio_url IS NOT NULL
  AND m.created_at >= '2026-07-02 13:46:00+00'
  AND m.created_at <  '2026-07-02 13:47:00+00'
  AND EXISTS (
    SELECT 1 FROM public.training_logs r
    WHERE r.source IN ('strava', 'auto_sync')
      AND r.user_id = m.user_id
      AND r.audio_url = m.audio_url
  );
