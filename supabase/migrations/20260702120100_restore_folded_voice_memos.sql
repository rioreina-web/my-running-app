-- One-time data repair: bring back voice memos that a prior dedup run already
-- folded into Strava runs (see 20260702120000 for the root cause).
--
-- Fingerprint of a folded memo: a `strava` (or `auto_sync`) run row that carries
-- an `audio_url`. Strava/HealthKit runs never bring their own audio — the only
-- way a run row has audio is that dedup copied it off a deleted voice_log row.
--
-- REPAIR, per folded run:
--   1. Recreate the voice memo as its own `voice_log` entry so it reappears in
--      the Log. It carries the recording (audio_url / transcript_url), the
--      transcript text, and mood. workout_distance_miles is left NULL so the
--      reflection does NOT double-count mileage against the run in Trends.
--   2. Strip the audio pointers off the run row so the recording plays from the
--      restored memo only (not from two cards). The run keeps its own text.
--
-- Idempotent: after step 2 the run no longer has audio, so a re-run finds no
-- folded rows; a NOT EXISTS guard on step 1 is belt-and-suspenders.
--
-- Also fixes one voice memo with a NULL workout_date (would drop out of the
-- date-windowed Log feed) by dating it to its created_at.
--
-- Append-only migration; deploy via `supabase db push` from a committed SHA.

-- 1. Recreate folded voice memos as standalone voice_log entries.
INSERT INTO public.training_logs (
  user_id, source, workout_date,
  audio_url, transcript_url, processing_status,
  notes, cleaned_notes, mood, workout_type, extracted_data
)
SELECT
  s.user_id, 'voice_log', s.workout_date,
  s.audio_url, s.transcript_url, 'completed',
  s.notes, s.cleaned_notes, s.mood, s.workout_type, s.extracted_data
FROM public.training_logs s
WHERE s.source IN ('strava', 'auto_sync')
  AND s.audio_url IS NOT NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.training_logs v
    WHERE v.source = 'voice_log'
      AND v.user_id = s.user_id
      AND v.audio_url = s.audio_url
  );

-- 2. Detach audio from the run rows so playback lives on the restored memo only.
UPDATE public.training_logs s
SET audio_url = NULL,
    transcript_url = NULL
WHERE s.source IN ('strava', 'auto_sync')
  AND s.audio_url IS NOT NULL;

-- 3. Give any dateless voice memo a workout_date so it appears in the feed.
UPDATE public.training_logs
SET workout_date = created_at
WHERE source = 'voice_log'
  AND workout_date IS NULL
  AND created_at IS NOT NULL;
