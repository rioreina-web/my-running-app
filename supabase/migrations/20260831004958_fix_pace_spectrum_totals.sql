CREATE OR REPLACE FUNCTION public.pace_spectrum(
    p_days      integer DEFAULT 84,
    p_bin_width integer DEFAULT 10,
    p_user_id   text    DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $function$
DECLARE
    v_user   text := pace_bins_target_user(p_user_id);
    v_from   timestamptz := now() - make_interval(days => p_days);
    v_width  integer := GREATEST(5, (p_bin_width / 5) * 5);  -- snap to the stored 5s grid
    v_binned numeric;
    v_logged numeric;
    v_runs   bigint;
    v_src    jsonb;
    v_bins   jsonb;
BEGIN
    IF v_user IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(miles), 0) INTO v_binned
      FROM workout_pace_bins
     WHERE user_id = v_user AND workout_date >= v_from;

    SELECT COUNT(*),
           COALESCE(SUM(workout_distance_miles), 0)::numeric,
           COALESCE(jsonb_object_agg(src, n) FILTER (WHERE src IS NOT NULL), '{}'::jsonb)
      INTO v_runs, v_logged, v_src
      FROM (
        SELECT id, workout_distance_miles,
               COALESCE(pace_bins_source, 'uncomputed') AS src,
               COUNT(*) OVER (PARTITION BY COALESCE(pace_bins_source, 'uncomputed')) AS n
          FROM training_logs
         WHERE user_id = v_user
           AND workout_date >= v_from
           AND COALESCE(stats_excluded, false) = false
           AND duplicate_of IS NULL
      ) s;

    SELECT COALESCE(jsonb_agg(jsonb_build_object(
               'start_sec', bucket,
               'end_sec',   bucket + v_width,
               'miles',     round(mi, 2),
               'seconds',   round(sec, 0),
               'pct',       CASE WHEN v_binned > 0 THEN round(mi / v_binned * 100, 1) END
           ) ORDER BY bucket), '[]'::jsonb)
      INTO v_bins
      FROM (
        SELECT (floor(bin_start_sec::numeric / v_width) * v_width)::integer AS bucket,
               SUM(miles) AS mi, SUM(seconds) AS sec
          FROM workout_pace_bins
         WHERE user_id = v_user AND workout_date >= v_from
         GROUP BY 1
      ) g;

    RETURN jsonb_build_object(
        'window_days',    p_days,
        'bin_width_sec',  v_width,
        'binned_miles',   round(v_binned, 2),
        'logged_miles',   round(v_logged, 2),
        'coverage_pct',   CASE WHEN v_logged > 0 THEN round(v_binned / v_logged * 100, 1) END,
        'runs',           v_runs,
        'runs_by_source', v_src,
        'bins',           v_bins
    );
END;
$function$;;
