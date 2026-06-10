-- ============================================================================
-- Test seed data for the coachable_moment V1 rules.
--
-- Spec: docs/specs/coachable_moment.md
-- Function: supabase/functions/evaluate-coachable-moment/index.ts
--
-- Running this SQL creates one test coach + one test athlete with training
-- data shaped to fire all three V1 rules. Then call the edge function and
-- confirm three coachable_moments rows land.
--
-- HOW TO RUN
--   1. Replace TEST_COACH_UUID and TEST_ATHLETE_UUID below if you want to
--      use real auth.users ids. Otherwise the placeholder UUIDs work fine —
--      no FK to auth.users on the relevant columns.
--   2. Run this whole file in psql or Supabase Studio SQL editor.
--   3. Call the function:
--        curl -X POST $SUPABASE_URL/functions/v1/evaluate-coachable-moment \
--             -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
--             -H "Content-Type: application/json" \
--             -d '{"athlete_user_id":"00000000-0000-0000-0000-0000000000a2"}'
--   4. Inspect the result:
--        SELECT rule_id, severity, action_type, summary
--          FROM coachable_moments
--         WHERE athlete_user_id = '00000000-0000-0000-0000-0000000000a2'
--         ORDER BY triggered_at DESC LIMIT 5;
--
-- TEARDOWN
--   See "-- CLEANUP" block at the bottom; uncomment and run to remove.
-- ============================================================================

-- Sentinel UUIDs — swap to real auth.users ids if you prefer.
-- Coach:   00000000-0000-0000-0000-0000000000a1
-- Athlete: 00000000-0000-0000-0000-0000000000a2
-- Plan:    00000000-0000-0000-0000-0000000000aa  (fixed for idempotent reruns)

-- ────────────────────────────────────────────────────────────────────────────
-- 1. Coach profile (idempotent on user_id)
-- ────────────────────────────────────────────────────────────────────────────
INSERT INTO coach_profiles (user_id, display_name)
VALUES ('00000000-0000-0000-0000-0000000000a1', 'Test Coach (seed)')
ON CONFLICT (user_id) DO UPDATE
    SET display_name = EXCLUDED.display_name;

-- ────────────────────────────────────────────────────────────────────────────
-- 2. Active coach-athlete relationship
-- ────────────────────────────────────────────────────────────────────────────
INSERT INTO coach_athlete_relationships (coach_id, athlete_user_id, status, accepted_at)
SELECT id, '00000000-0000-0000-0000-0000000000a2', 'active', now()
FROM coach_profiles
WHERE user_id = '00000000-0000-0000-0000-0000000000a1'
ON CONFLICT (coach_id, athlete_user_id) DO UPDATE
    SET status = 'active',
        accepted_at = now();

-- ────────────────────────────────────────────────────────────────────────────
-- 3. Training plan (scheduled_workouts requires plan_id)
-- ────────────────────────────────────────────────────────────────────────────
INSERT INTO training_plans (
    id, user_id, name, start_date, end_date,
    target_race_distance, target_time_seconds, status
) VALUES (
    '00000000-0000-0000-0000-0000000000aa',
    '00000000-0000-0000-0000-0000000000a2',
    'Test Plan (coachable_moments seed)',
    (date_trunc('week', current_date))::date,
    (date_trunc('week', current_date) + interval '12 weeks')::date,
    'marathon',
    14400,
    'active'
)
ON CONFLICT (id) DO NOTHING;

-- ────────────────────────────────────────────────────────────────────────────
-- 4. Training logs
--    Prior 3 weeks: ~25 mi/week of "easy" runs at neutral/positive mood.
--    This week: ~35 mi (40% above prior avg), one entry mentions
--               "right hip tight" (rule 1 trigger), and the 3 most recent
--               entries have mood in {tired, struggling, injured} (rule 2).
-- ────────────────────────────────────────────────────────────────────────────
DELETE FROM training_logs
 WHERE user_id = '00000000-0000-0000-0000-0000000000a2'
   AND notes LIKE '[seed]%';

-- Week -3 (days 22-26 ago): 5 runs × 5 mi = 25 mi
INSERT INTO training_logs (user_id, workout_date, workout_distance_miles, mood, notes)
SELECT '00000000-0000-0000-0000-0000000000a2',
       now() - (i || ' days')::interval, 5, 'positive',
       '[seed] week -3 day ' || i
  FROM generate_series(22, 26) AS i;

-- Week -2 (days 15-19 ago): 25 mi
INSERT INTO training_logs (user_id, workout_date, workout_distance_miles, mood, notes)
SELECT '00000000-0000-0000-0000-0000000000a2',
       now() - (i || ' days')::interval, 5, 'positive',
       '[seed] week -2 day ' || i
  FROM generate_series(15, 19) AS i;

-- Week -1 (days 8-12 ago): 25 mi
INSERT INTO training_logs (user_id, workout_date, workout_distance_miles, mood, notes)
SELECT '00000000-0000-0000-0000-0000000000a2',
       now() - (i || ' days')::interval, 5, 'neutral',
       '[seed] week -1 day ' || i
  FROM generate_series(8, 12) AS i;

-- This week (last 6 days): 7 runs × 5 mi = 35 mi, 40% above prior avg
INSERT INTO training_logs
    (user_id, workout_date, workout_distance_miles, mood, notes, cleaned_notes)
VALUES
    ('00000000-0000-0000-0000-0000000000a2', now() - interval '6 days', 5, 'positive',
     '[seed] this week d-6', NULL),
    ('00000000-0000-0000-0000-0000000000a2', now() - interval '5 days', 5, 'positive',
     '[seed] this week d-5', NULL),
    ('00000000-0000-0000-0000-0000000000a2', now() - interval '4 days', 5, 'neutral',
     '[seed] this week d-4 — felt fine', NULL),
    ('00000000-0000-0000-0000-0000000000a2', now() - interval '3 days', 5, 'neutral',
     '[seed] this week d-3', NULL),
    ('00000000-0000-0000-0000-0000000000a2', now() - interval '2 days', 5, 'tired',
     '[seed] this week d-2 — long run, right hip tight afterwards',
     'Long run today, right hip tight afterwards.'),
    ('00000000-0000-0000-0000-0000000000a2', now() - interval '1 days', 5, 'struggling',
     '[seed] this week d-1 — legs heavy', NULL),
    ('00000000-0000-0000-0000-0000000000a2', now() - interval '6 hours',  5, 'tired',
     '[seed] this week d-0 — recovery jog', NULL);

-- ────────────────────────────────────────────────────────────────────────────
-- 4b. Heat-impacted long run — fires rule 4 (weather_impacted_quality)
--     Adds one more log: a 10-mile MP-effort long run from ~36h ago, run in
--     71°F / 70°F-dewpoint conditions with an 18 sec/mi heat penalty.
--     Mood = struggling. Workout_type = long_run (passes the quality check).
--     This becomes the most recent QUALITY session in the 3-day window;
--     the d-1 and d-0 entries above don't have workout_type set so they're
--     skipped by rule 4's quality-type filter.
-- ────────────────────────────────────────────────────────────────────────────
INSERT INTO training_logs
    (user_id, workout_date, workout_distance_miles, mood, workout_type, notes,
     cleaned_notes, weather_actual, weather_adjusted_pace_delta_seconds_per_mile)
VALUES
    ('00000000-0000-0000-0000-0000000000a2',
     now() - interval '36 hours',
     10,
     'struggling',
     'long_run',
     '[seed] heat-tanked long run',
     '10mi MP run today. 71F with 70F dewpoint. Felt like soup. Goal was 6:00, ended up around 6:18.',
     '{"temp_f": 71, "dewpoint_f": 70, "humidity_pct": 95, "conditions": "humid, hot"}'::jsonb,
     18);

-- ────────────────────────────────────────────────────────────────────────────
-- 5. Scheduled workouts — 5 scheduled this week, 2 skipped → fires rule 3
-- ────────────────────────────────────────────────────────────────────────────
DELETE FROM scheduled_workouts
 WHERE plan_id = '00000000-0000-0000-0000-0000000000aa';

INSERT INTO scheduled_workouts
    (plan_id, user_id, date, day_of_week, week_number, workout_type, status)
VALUES
    ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a2',
     (date_trunc('week', current_date))::date,                       1, 1, 'easy',     'completed'),
    ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a2',
     (date_trunc('week', current_date) + interval '1 day')::date,    2, 1, 'tempo',    'skipped'),
    ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a2',
     (date_trunc('week', current_date) + interval '2 days')::date,   3, 1, 'easy',     'completed'),
    ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a2',
     (date_trunc('week', current_date) + interval '3 days')::date,   4, 1, 'easy',     'skipped'),
    ('00000000-0000-0000-0000-0000000000aa', '00000000-0000-0000-0000-0000000000a2',
     (date_trunc('week', current_date) + interval '4 days')::date,   5, 1, 'long_run', 'scheduled');

-- ────────────────────────────────────────────────────────────────────────────
-- Quick sanity check
-- ────────────────────────────────────────────────────────────────────────────
SELECT 'training_logs (last 7d)' AS slice,
       count(*) AS rows,
       round(sum(workout_distance_miles)::numeric, 1) AS miles
  FROM training_logs
 WHERE user_id = '00000000-0000-0000-0000-0000000000a2'
   AND workout_date >= now() - interval '7 days'
UNION ALL
SELECT 'training_logs (8-28d ago)',
       count(*),
       round(sum(workout_distance_miles)::numeric, 1)
  FROM training_logs
 WHERE user_id = '00000000-0000-0000-0000-0000000000a2'
   AND workout_date <  now() - interval '7 days'
   AND workout_date >= now() - interval '28 days'
UNION ALL
SELECT 'scheduled_workouts (this week, skipped)',
       count(*) FILTER (WHERE status = 'skipped'),
       NULL
  FROM scheduled_workouts
 WHERE plan_id = '00000000-0000-0000-0000-0000000000aa'
   AND date >= (date_trunc('week', current_date))::date
   AND date <  (date_trunc('week', current_date) + interval '7 days')::date;

-- Expected:
--   training_logs (last 7d)            8 rows   ~45.0 mi   (7 base + 1 heat-tanked LR)
--   training_logs (8-28d ago)         15 rows   ~75.0 mi   (3 weeks × 25 mi)
--   scheduled_workouts (this week skipped)   2 rows  NULL
--
-- Expected fired rules when the function is called against this seed:
--   - load_spike_plus_injury     (this week 45mi vs ~25mi baseline + "right hip tight")
--   - low_mood_streak            (last 3 mood entries: struggling, tired, tired)
--   - missed_workouts            (2 of 5 scheduled this week marked skipped)
--   - weather_impacted_quality   (10mi long_run, dewpoint 70°F, +18s/mi penalty, struggling)

-- ────────────────────────────────────────────────────────────────────────────
-- CLEANUP — uncomment when you want to remove the seed.
-- ────────────────────────────────────────────────────────────────────────────
-- DELETE FROM coachable_moments
--  WHERE athlete_user_id = '00000000-0000-0000-0000-0000000000a2';
-- DELETE FROM scheduled_workouts
--  WHERE plan_id = '00000000-0000-0000-0000-0000000000aa';
-- DELETE FROM training_plans
--  WHERE id = '00000000-0000-0000-0000-0000000000aa';
-- DELETE FROM training_logs
--  WHERE user_id = '00000000-0000-0000-0000-0000000000a2'
--    AND notes LIKE '[seed]%';
-- DELETE FROM coach_athlete_relationships
--  WHERE athlete_user_id = '00000000-0000-0000-0000-0000000000a2';
-- DELETE FROM coach_profiles
--  WHERE user_id = '00000000-0000-0000-0000-0000000000a1';
