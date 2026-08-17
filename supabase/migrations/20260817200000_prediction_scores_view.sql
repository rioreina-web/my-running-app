-- prediction_scores — every confirmed race scores the prediction that preceded it.
--
-- WHY THIS EXISTS (2026-08-17)
--
-- The fitness predictor has shipped for five months and been scored zero
-- times. Its one scoreable moment (the 2026-04-12 10K) was only examined by
-- hand today, and what that exam found was two writers bracketing reality
-- four minutes apart. "How good is the prediction?" must be a query, not an
-- archaeology project — this view makes every confirmed race a scoring event.
--
-- SHAPE
--
-- One row per confirmed race (training_logs.race_result) that has at least
-- one fitness_snapshot written strictly BEFORE race day. The scored
-- prediction is the LAST row before the race date — chosen by the same
-- "most recent, never fastest" rule as the curve prior, and immune to
-- hindsight by construction: post-race rows fail the date predicate, so a
-- snapshot that merely echoes the finished race can never score itself.
--
-- A VIEW, deliberately. Scores derive entirely from two existing tables, so
-- persisting them would create a second writer and a backfill obligation —
-- the exact drift class this repo keeps paying for (TS/SQL writer skew,
-- effort_load backfills, the two-writer sawtooth this view exists to
-- measure). A view has no writer, no backfill, and cannot disagree with its
-- sources.
--
-- READING IT
--
-- error_seconds > 0 means the model predicted SLOWER than the athlete ran.
-- `data_source` tells you which writer's number is being scored; rows with
-- the '· v2' marker are this model's own (`is_own_model`), and only those
-- speak for the current pipeline. Legacy rows (device writer, pre-v2 server)
-- are kept and labeled rather than filtered — n is too small to discard
-- history, and writer disagreement is itself a finding worth querying.
--
-- `actual_seconds` is the RAW finish time. Score against neutral-air setups
-- read-side where conditions warrant (weather columns are carried along) —
-- the heat math lives in TypeScript (pace-heat-adjustment.ts) and is not
-- duplicated here; a second SQL implementation is how the lap writers
-- drifted (see 20260813 heat notes). One writer, one answer.
--
-- RLS: security_invoker, so the base tables' own policies decide visibility.
-- No new policy surface; athletes see their own races, service role sees all.

CREATE OR REPLACE VIEW public.prediction_scores
WITH (security_invoker = true) AS
SELECT
  t.user_id,
  t.id                                   AS training_log_id,
  t.workout_date::date                   AS race_date,
  t.race_result ->> 'distance'           AS distance_key,
  (t.race_result ->> 'finish_time_seconds')::integer AS actual_seconds,
  s.predicted_seconds,
  s.predicted_seconds
    - (t.race_result ->> 'finish_time_seconds')::integer  AS error_seconds,
  round(
    (s.predicted_seconds
      - (t.race_result ->> 'finish_time_seconds')::integer)::numeric
    * 100.0
    / nullif((t.race_result ->> 'finish_time_seconds')::integer, 0),
    2
  )                                      AS error_pct,
  s.created_at                           AS predicted_at,
  round(
    extract(epoch from (t.workout_date - s.created_at))::numeric / 86400.0,
    1
  )                                      AS prediction_age_days,
  s.data_source,
  (s.data_source LIKE '%· v2%')          AS is_own_model,
  s.confidence_tier,
  (t.weather_actual ->> 'temp_f')::numeric      AS race_temp_f,
  (t.weather_actual ->> 'dew_point_f')::numeric AS race_dew_point_f
FROM public.training_logs t
CROSS JOIN LATERAL (
  SELECT
    s.created_at,
    s.data_source,
    s.confidence_tier,
    CASE lower(t.race_result ->> 'distance')
      WHEN 'mile'     THEN s.predicted_mile_seconds
      WHEN '5k'       THEN s.predicted_5k_seconds
      WHEN '10k'      THEN s.predicted_10k_seconds
      WHEN 'half'     THEN s.predicted_half_seconds
      WHEN 'marathon' THEN s.predicted_marathon_seconds
    END AS predicted_seconds
  FROM public.fitness_snapshots s
  WHERE s.user_id = t.user_id
    AND s.created_at < t.workout_date::date  -- strictly before race DAY: no hindsight
  ORDER BY s.created_at DESC
  LIMIT 1
) s
WHERE t.race_result IS NOT NULL
  AND (t.race_result ->> 'finish_time_seconds') ~ '^\d+$'
  AND s.predicted_seconds IS NOT NULL;

COMMENT ON VIEW public.prediction_scores IS
  'Every confirmed race scored against the last fitness prediction written '
  'before race day. No writer, no backfill — derives live from training_logs '
  '+ fitness_snapshots. error_seconds > 0 = model predicted slower than the '
  'athlete ran. Filter is_own_model for the current pipeline''s record; '
  'legacy writers are labeled, not hidden. Actuals are raw finish times — '
  'normalize for conditions read-side (pace-heat-adjustment.ts), never here.';

GRANT SELECT ON public.prediction_scores TO authenticated, service_role;
