\set ON_ERROR_STOP on
\pset pager off

-- ══ A. Real edits must STILL enqueue. If this regresses, the fix broke the
--       feature: an athlete's words would stop reshaping their run.
DELETE FROM public.training_logs; DELETE FROM public.workout_notes;
DELETE FROM public.workout_parse_jobs; DELETE FROM public.llm_call_ledger;

INSERT INTO public.training_logs (id, user_id, source, audio_url, cleaned_notes, external_streams)
VALUES ('11111111-1111-1111-1111-111111111111','athlete-1','strava',
        'https://example/audio.m4a','felt strong','{"streams":{}}'::jsonb);

SELECT 'A1 insert enqueues' AS check,
       (SELECT count(*) FROM public.workout_parse_jobs) = 1 AS pass;

DELETE FROM public.workout_parse_jobs;
UPDATE public.workout_notes SET cleaned_text = 'actually it was 6x800 at threshold';
SELECT 'A2 real note edit enqueues' AS check,
       (SELECT count(*) FROM public.workout_parse_jobs) = 1 AS pass;

DELETE FROM public.workout_parse_jobs;
UPDATE public.workout_notes SET cleaned_text = 'actually it was 6x800 at threshold';
SELECT 'A3 rewriting SAME text does not enqueue' AS check,
       (SELECT count(*) FROM public.workout_parse_jobs) = 0 AS pass;

DELETE FROM public.workout_parse_jobs;
UPDATE public.training_logs SET cleaned_notes = 'new words from the athlete'
 WHERE id = '11111111-1111-1111-1111-111111111111';
SELECT 'A4 real training_logs note edit enqueues' AS check,
       (SELECT count(*) FROM public.workout_parse_jobs) = 1 AS pass;

DELETE FROM public.workout_parse_jobs;
UPDATE public.training_logs SET stress_load = 42
 WHERE id = '11111111-1111-1111-1111-111111111111';
SELECT 'A5 unrelated column write does not enqueue' AS check,
       (SELECT count(*) FROM public.workout_parse_jobs) = 0 AS pass;

-- ══ B. Per-subject ceiling: the Aug-11 loop detector.
DELETE FROM public.llm_call_ledger;
SELECT 'B1 first 6 calls for one subject allowed' AS check,
       bool_and(public.llm_budget_allows('workout_parse','22222222-2222-2222-2222-222222222222','a')) AS pass
  FROM generate_series(1,6);

SELECT 'B2 seventh call for same subject refused' AS check,
       public.llm_budget_allows('workout_parse','22222222-2222-2222-2222-222222222222','a') = false AS pass;

SELECT 'B3 a DIFFERENT subject is unaffected' AS check,
       public.llm_budget_allows('workout_parse','33333333-3333-3333-3333-333333333333','a') AS pass;

-- ══ C. Global daily ceiling: hard stop.
DELETE FROM public.llm_call_ledger;
INSERT INTO public.llm_call_ledger (surface, occurred_at)
SELECT 'backfill', now() FROM generate_series(1, 249);

SELECT 'C1 headroom reports 1 remaining' AS check,
       public.llm_budget_headroom() = 1 AS pass;

SELECT 'C2 call 250 allowed' AS check,
       public.llm_budget_allows('workout_parse','44444444-4444-4444-4444-444444444444','a') AS pass;

SELECT 'C3 call 251 refused' AS check,
       public.llm_budget_allows('workout_parse','55555555-5555-5555-5555-555555555555','a') = false AS pass;

SELECT 'C4 headroom now zero' AS check, public.llm_budget_headroom() = 0 AS pass;

-- ══ D. The dispatcher must claim NOTHING when the budget is spent, or it
--       burns a retry on every job every minute and exhausts jobs that never ran.
INSERT INTO public.workout_parse_jobs (training_log_id, user_id, created_at)
VALUES ('66666666-6666-6666-6666-666666666666','athlete-1', now())
ON CONFLICT DO NOTHING;
UPDATE public.workout_parse_jobs SET attempts = 0, last_attempt_at = NULL;

SELECT 'D1 dispatcher sends nothing when ceiling spent' AS check,
       public.dispatch_workout_parse(6) = 0 AS pass;

SELECT 'D2 no retry was burned' AS check,
       (SELECT bool_and(attempts = 0) FROM public.workout_parse_jobs) AS pass;

-- ══ E. With budget restored, the dispatcher works normally again.
DELETE FROM public.llm_call_ledger;
SELECT 'E1 dispatcher resumes when budget resets' AS check,
       public.dispatch_workout_parse(6) >= 1 AS pass;

SELECT 'E2 the dispatch was recorded in the ledger' AS check,
       (SELECT count(*) FROM public.llm_call_ledger WHERE surface='workout_parse') >= 1 AS pass;
