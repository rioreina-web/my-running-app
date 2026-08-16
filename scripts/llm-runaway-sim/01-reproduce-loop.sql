\set ON_ERROR_STOP on
\pset pager off

-- A Strava run that carries a voice memo: the shape that loops in prod, because
-- the mirror gives it BOTH a run_id (source = strava) and note text (audio_url
-- present), which is what arms trg_enqueue_workout_parse_from_note.
INSERT INTO public.training_logs (id, user_id, source, audio_url, cleaned_notes, external_streams)
VALUES ('11111111-1111-1111-1111-111111111111', 'athlete-1', 'strava',
        'https://example/audio.m4a', 'felt strong on the second half', '{"streams":{}}'::jsonb);

SELECT '--- setup: note linked to run? ---' AS step;
SELECT run_id IS NOT NULL AS note_has_run_id, cleaned_text FROM public.workout_notes;

-- Clear the queue so the next count is unambiguous, then simulate exactly what
-- parse-workout-structure writes back when it succeeds.
DELETE FROM public.workout_parse_jobs;

UPDATE public.training_logs
   SET parsed_structure = '{"type":"easy"}'::jsonb,
       structure_parsed_at = now()
 WHERE id = '11111111-1111-1111-1111-111111111111';

SELECT '--- RESULT: jobs created by a completed parse ---' AS step;
SELECT count(*) AS jobs_after_writeback FROM public.workout_parse_jobs;
