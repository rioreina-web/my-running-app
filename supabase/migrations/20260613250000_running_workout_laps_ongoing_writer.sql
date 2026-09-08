-- ============================================================================
-- Ongoing writer for running_workout_laps (fixes the silent lap-ingestion gap)
--
-- ROOT CAUSE: running_workout_laps was populated ONCE by a one-shot backfill in
-- 20260528222123_create_running_workout_laps.sql. Nothing wrote it afterward, so
-- every workout after ~May 21 had zero rep-level laps — even though Strava sync
-- stores each activity's laps in training_logs.external_streams.laps. Result:
-- the lap-based workout detection silently missed all recent quality sessions
-- (e.g. every Tuesday workout).
--
-- FIX: a trigger that parses external_streams.laps into running_workout_laps on
-- every training_logs INSERT/UPDATE, plus a one-time global re-backfill of the
-- gap. Ints are cast THROUGH numeric — Strava sends decimals where the original
-- migration assumed integers ("invalid input syntax for type integer: 125.6"),
-- which crashes a naive parse.
--
-- search_path pinned + public.-qualified (avoids the drain-RPC schema bug).
-- Append-only. Idempotent (ON CONFLICT).
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.sync_workout_laps_from_streams()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.external_streams IS NULL
     OR NOT (NEW.external_streams ? 'laps')
     OR jsonb_typeof(NEW.external_streams->'laps') <> 'array'
     OR NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.running_workout_laps (
    workout_id, user_id, lap_index,
    distance_meters, moving_time_seconds, elapsed_time_seconds,
    avg_pace_sec_per_mile, avg_speed_mps, max_speed_mps,
    avg_heart_rate, max_heart_rate, avg_cadence, avg_watts,
    pace_zone, total_elevation_gain,
    stream_start_index, stream_end_index, lap_start_at
  )
  SELECT
    NEW.id, NEW.user_id, (lap->>'lap_index')::numeric::int,
    (lap->>'distance')::numeric, (lap->>'moving_time')::numeric::int, (lap->>'elapsed_time')::numeric::int,
    CASE WHEN (lap->>'distance')::numeric > 0
         THEN (lap->>'moving_time')::numeric / ((lap->>'distance')::numeric / 1609.344)
         ELSE NULL END,
    NULLIF((lap->>'average_speed'),'')::numeric, NULLIF((lap->>'max_speed'),'')::numeric,
    NULLIF((lap->>'average_heartrate'),'')::numeric::int, NULLIF((lap->>'max_heartrate'),'')::numeric::int,
    NULLIF((lap->>'average_cadence'),'')::numeric, NULLIF((lap->>'average_watts'),'')::numeric,
    NULLIF((lap->>'pace_zone'),'')::numeric::int, NULLIF((lap->>'total_elevation_gain'),'')::numeric,
    NULLIF((lap->>'start_index'),'')::numeric::int, NULLIF((lap->>'end_index'),'')::numeric::int,
    NULLIF((lap->>'start_date'),'')::timestamptz
  FROM jsonb_array_elements(NEW.external_streams->'laps') AS lap
  ON CONFLICT (workout_id, lap_index) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Fire only when external_streams actually changes (cheap; skips unrelated updates).
DROP TRIGGER IF EXISTS trg_sync_workout_laps ON training_logs;
CREATE TRIGGER trg_sync_workout_laps
  AFTER INSERT OR UPDATE OF external_streams ON training_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_workout_laps_from_streams();

-- ── One-time global re-backfill of the gap (May 22 → present, all users) ─────
INSERT INTO public.running_workout_laps (
  workout_id, user_id, lap_index,
  distance_meters, moving_time_seconds, elapsed_time_seconds,
  avg_pace_sec_per_mile, avg_speed_mps, max_speed_mps,
  avg_heart_rate, max_heart_rate, avg_cadence, avg_watts,
  pace_zone, total_elevation_gain,
  stream_start_index, stream_end_index, lap_start_at
)
SELECT
  tl.id, tl.user_id, (lap->>'lap_index')::numeric::int,
  (lap->>'distance')::numeric, (lap->>'moving_time')::numeric::int, (lap->>'elapsed_time')::numeric::int,
  CASE WHEN (lap->>'distance')::numeric > 0
       THEN (lap->>'moving_time')::numeric / ((lap->>'distance')::numeric / 1609.344)
       ELSE NULL END,
  NULLIF((lap->>'average_speed'),'')::numeric, NULLIF((lap->>'max_speed'),'')::numeric,
  NULLIF((lap->>'average_heartrate'),'')::numeric::int, NULLIF((lap->>'max_heartrate'),'')::numeric::int,
  NULLIF((lap->>'average_cadence'),'')::numeric, NULLIF((lap->>'average_watts'),'')::numeric,
  NULLIF((lap->>'pace_zone'),'')::numeric::int, NULLIF((lap->>'total_elevation_gain'),'')::numeric,
  NULLIF((lap->>'start_index'),'')::numeric::int, NULLIF((lap->>'end_index'),'')::numeric::int,
  NULLIF((lap->>'start_date'),'')::timestamptz
FROM training_logs tl, jsonb_array_elements(tl.external_streams->'laps') AS lap
WHERE tl.external_streams ? 'laps'
  AND jsonb_typeof(tl.external_streams->'laps') = 'array'
  AND tl.user_id IS NOT NULL
ON CONFLICT (workout_id, lap_index) DO NOTHING;

COMMIT;

-- After apply: re-run compute-workout-features (backfill) + rebuild-athlete-state
-- per affected user so the newly-parsed laps flow into classification + state.
