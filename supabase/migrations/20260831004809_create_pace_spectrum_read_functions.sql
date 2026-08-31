-- Both the PACE spectrum and the THRESHOLD MILES card read workout_pace_bins.
-- They were separate code paths and gave different answers for the same window;
-- one source means they can only agree.
--
-- SECURITY INVOKER: RLS on workout_pace_bins does the access control. p_user_id
-- is honoured only for service_role (the coach-facing edge functions); an
-- athlete calling directly always gets their own data whatever they pass.

CREATE OR REPLACE FUNCTION public.pace_bins_target_user(p_user_id text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
    SELECT CASE
             WHEN auth.role() = 'service_role' AND p_user_id IS NOT NULL THEN p_user_id
             ELSE (auth.uid())::text
           END;
$$;

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
    v_result jsonb;
BEGIN
    IF v_user IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(miles), 0) INTO v_binned
      FROM workout_pace_bins
     WHERE user_id = v_user AND workout_date >= v_from;

    SELECT jsonb_build_object(
        'window_days',   p_days,
        'bin_width_sec', v_width,
        'binned_miles',  round(v_binned, 2),
        'logged_miles',  round(COALESCE(l.logged, 0), 2),
        'coverage_pct',  CASE WHEN COALESCE(l.logged, 0) > 0
                              THEN round(v_binned / l.logged * 100, 1) END,
        'runs',          COALESCE(l.runs, 0),
        'runs_by_source', COALESCE(l.by_source, '{}'::jsonb),
        'bins',          COALESCE(b.bins, '[]'::jsonb)
    )
      INTO v_result
      FROM (
        SELECT jsonb_agg(jsonb_build_object(
                   'start_sec', bucket,
                   'end_sec',   bucket + v_width,
                   'miles',     round(mi, 2),
                   'seconds',   round(sec, 0),
                   'pct',       CASE WHEN v_binned > 0 THEN round(mi / v_binned * 100, 1) END
               ) ORDER BY bucket) AS bins
          FROM (
            SELECT (floor(bin_start_sec::numeric / v_width) * v_width)::integer AS bucket,
                   SUM(miles) AS mi, SUM(seconds) AS sec
              FROM workout_pace_bins
             WHERE user_id = v_user AND workout_date >= v_from
             GROUP BY 1
          ) g
      ) b
      CROSS JOIN (
        SELECT COUNT(*) AS runs,
               SUM(workout_distance_miles) AS logged,
               jsonb_object_agg(src, n) AS by_source
          FROM (
            SELECT COALESCE(pace_bins_source, 'uncomputed') AS src,
                   COUNT(*) AS n,
                   SUM(workout_distance_miles) AS workout_distance_miles
              FROM training_logs
             WHERE user_id = v_user
               AND workout_date >= v_from
               AND COALESCE(stats_excluded, false) = false
               AND duplicate_of IS NULL
             GROUP BY 1
          ) s
      ) l;

    RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.pace_spectrum(integer, integer, text) IS
  'Pace histogram for a rolling window, aggregated from workout_pace_bins to any bin width that is a multiple of 5 sec/mile. Percentages are against binned_miles, never logged_miles -- a run that could not be binned must not silently deflate every bucket. coverage_pct and runs_by_source say how much of the window is actually measured.';

CREATE OR REPLACE FUNCTION public.pace_band_totals(
    p_low_sec   integer,
    p_high_sec  integer,
    p_days      integer DEFAULT 84,
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
    v_binned numeric;
    v_mi     numeric;
    v_sec    numeric;
    v_runs   integer;
BEGIN
    IF v_user IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(miles), 0) INTO v_binned
      FROM workout_pace_bins
     WHERE user_id = v_user AND workout_date >= v_from;

    -- A bucket is in the band when the pace it represents is. Buckets are
    -- [start, start+5), so the high edge is inclusive of the bucket containing it.
    SELECT COALESCE(SUM(miles), 0), COALESCE(SUM(seconds), 0), COUNT(DISTINCT workout_id)
      INTO v_mi, v_sec, v_runs
      FROM workout_pace_bins
     WHERE user_id = v_user
       AND workout_date >= v_from
       AND bin_start_sec >= (floor(p_low_sec::numeric / 5) * 5)
       AND bin_start_sec <= (floor(p_high_sec::numeric / 5) * 5);

    RETURN jsonb_build_object(
        'low_sec',      p_low_sec,
        'high_sec',     p_high_sec,
        'window_days',  p_days,
        'miles',        round(v_mi, 1),
        'seconds',      round(v_sec, 0),
        'minutes',      round(v_sec / 60, 0),
        'runs',         v_runs,
        'avg_pace_sec', CASE WHEN v_mi > 0 THEN round(v_sec / v_mi, 0) END,
        'pct_of_binned', CASE WHEN v_binned > 0 THEN round(v_mi / v_binned * 100, 1) END
    );
END;
$function$;

COMMENT ON FUNCTION public.pace_band_totals(integer, integer, integer, text) IS
  'Miles and minutes inside a pace band for a rolling window. Same source as pace_spectrum() -- the THRESHOLD MILES card and the histogram are now arithmetically consistent by construction.';

REVOKE ALL ON FUNCTION public.pace_spectrum(integer, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pace_band_totals(integer, integer, integer, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.pace_bins_target_user(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pace_spectrum(integer, integer, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pace_band_totals(integer, integer, integer, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.pace_bins_target_user(text) TO authenticated, service_role;;
