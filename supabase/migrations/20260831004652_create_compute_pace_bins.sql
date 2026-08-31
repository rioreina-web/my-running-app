-- Bin every moving meter of a run by the pace being run at that moment.
--
-- Tier 1 (stream): a centred +/-15s rolling window over a MOVING clock. Pauses are
--   dropped from both the clock and the distance, so a 2-minute stop no longer
--   drags the mile it happened in into the wrong bucket.
-- Tier 2 (laps): lap averages. Mile resolution -- only used when streams are absent.
-- Tier 3 (average): the whole run at one pace. Keeps the run in the denominator.
-- Tier 4 (none): no distance or no duration. Excluded, and recorded as excluded.

CREATE OR REPLACE FUNCTION public.compute_pace_bins(p_workout_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    MPM     CONSTANT numeric := 1609.34;  -- meters per mile
    WIN     CONSTANT integer := 15;       -- half-width of the smoothing window, seconds
    BINW    CONSTANT integer := 5;        -- bucket width, sec/mile
    BIN_MIN CONSTANT integer := 180;      -- clamp floor  (3:00/mi)
    BIN_MAX CONSTANT integer := 1500;     -- clamp ceil  (25:00/mi)
    MOVE_MPS CONSTANT numeric := 0.5;     -- below this the watch was stopped, not running

    v_user   text;
    v_date   timestamptz;
    v_dist   numeric;
    v_dur    numeric;
    v_d      jsonb;
    v_t      jsonb;
    v_segs   jsonb;
    v_source text;
    v_miles  numeric;
BEGIN
    SELECT user_id,
           workout_date,
           workout_distance_miles,
           workout_duration_minutes,
           external_streams->'streams'->'distance',
           external_streams->'streams'->'time',
           pace_segments
      INTO v_user, v_date, v_dist, v_dur, v_d, v_t, v_segs
      FROM training_logs
     WHERE id = p_workout_id;

    IF NOT FOUND OR v_user IS NULL OR v_date IS NULL THEN
        RETURN NULL;
    END IF;

    DELETE FROM workout_pace_bins WHERE workout_id = p_workout_id;

    ----------------------------------------------------------------------
    -- Tier 1: 1 Hz distance + time streams
    ----------------------------------------------------------------------
    IF jsonb_typeof(v_d) = 'array'
       AND jsonb_typeof(v_t) = 'array'
       AND jsonb_array_length(v_d) > 30
       AND jsonb_array_length(v_d) = jsonb_array_length(v_t)
    THEN
        WITH d AS (
            SELECT ord, val::text::numeric AS v
              FROM jsonb_array_elements(v_d) WITH ORDINALITY x(val, ord)
        ),
        t AS (
            SELECT ord, val::text::numeric AS v
              FROM jsonb_array_elements(v_t) WITH ORDINALITY x(val, ord)
        ),
        s AS (
            SELECT d.ord, d.v AS dist_m, t.v AS t_s
              FROM d JOIN t USING (ord)
             WHERE d.v IS NOT NULL AND t.v IS NOT NULL
        ),
        step AS (
            SELECT ord,
                   dist_m - lag(dist_m) OVER (ORDER BY ord) AS dd,
                   t_s    - lag(t_s)    OVER (ORDER BY ord) AS dt
              FROM s
        ),
        flagged AS (
            -- A sample counts only if the watch moved. A time gap with no
            -- distance is a stop; standing still is not a 40:00 mile.
            SELECT ord, dd, dt,
                   (dd > 0 AND dt > 0 AND dt <= 30 AND dd / dt >= MOVE_MPS) AS is_moving
              FROM step
        ),
        clock AS (
            SELECT ord, dd, dt, is_moving,
                   SUM(CASE WHEN is_moving THEN dt ELSE 0 END)
                       OVER (ORDER BY ord ROWS UNBOUNDED PRECEDING) AS t_move,
                   SUM(CASE WHEN is_moving THEN dd ELSE 0 END)
                       OVER (ORDER BY ord ROWS UNBOUNDED PRECEDING) AS d_move
              FROM flagged
        ),
        win AS (
            SELECT dd, dt,
                   MAX(d_move) OVER w - MIN(d_move) OVER w AS win_dist,
                   MAX(t_move) OVER w - MIN(t_move) OVER w AS win_time
              FROM clock
             WHERE is_moving
            WINDOW w AS (ORDER BY t_move RANGE BETWEEN WIN PRECEDING AND WIN FOLLOWING)
        )
        INSERT INTO workout_pace_bins (workout_id, user_id, workout_date, bin_start_sec, miles, seconds)
        SELECT p_workout_id,
               v_user,
               v_date,
               GREATEST(BIN_MIN, LEAST(BIN_MAX,
                   (floor((win_time / (win_dist / MPM)) / BINW) * BINW)::integer)),
               SUM(dd) / MPM,
               SUM(dt)
          FROM win
         WHERE win_dist > 0 AND win_time > 0
         GROUP BY 4;

        SELECT COALESCE(SUM(miles), 0) INTO v_miles
          FROM workout_pace_bins WHERE workout_id = p_workout_id;

        -- A stream that accounts for the run is authoritative. One that does not
        -- is a broken export, and the coarser sources are better than a lie.
        IF v_miles > 0 AND (v_dist IS NULL OR v_dist <= 0 OR v_miles >= v_dist * 0.8) THEN
            v_source := 'stream';
        ELSE
            DELETE FROM workout_pace_bins WHERE workout_id = p_workout_id;
            v_miles := NULL;
        END IF;
    END IF;

    ----------------------------------------------------------------------
    -- Tier 2: lap averages
    ----------------------------------------------------------------------
    IF v_source IS NULL AND jsonb_typeof(v_segs) = 'array' AND jsonb_array_length(v_segs) > 0 THEN
        INSERT INTO workout_pace_bins (workout_id, user_id, workout_date, bin_start_sec, miles, seconds)
        SELECT p_workout_id, v_user, v_date,
               GREATEST(BIN_MIN, LEAST(BIN_MAX,
                   (floor(((s->>'duration_seconds')::numeric
                           / (s->>'distance_miles')::numeric) / BINW) * BINW)::integer)),
               SUM((s->>'distance_miles')::numeric),
               SUM((s->>'duration_seconds')::numeric)
          FROM jsonb_array_elements(v_segs) s
         WHERE (s->>'distance_miles')::numeric > 0
           AND (s->>'duration_seconds')::numeric > 0
         GROUP BY 4;

        SELECT COALESCE(SUM(miles), 0) INTO v_miles
          FROM workout_pace_bins WHERE workout_id = p_workout_id;

        IF v_miles > 0 THEN
            v_source := 'laps';
        ELSE
            v_miles := NULL;
        END IF;
    END IF;

    ----------------------------------------------------------------------
    -- Tier 3: whole run at its average pace
    ----------------------------------------------------------------------
    IF v_source IS NULL AND COALESCE(v_dist, 0) > 0 AND COALESCE(v_dur, 0) > 0 THEN
        INSERT INTO workout_pace_bins (workout_id, user_id, workout_date, bin_start_sec, miles, seconds)
        VALUES (p_workout_id, v_user, v_date,
                GREATEST(BIN_MIN, LEAST(BIN_MAX,
                    (floor(((v_dur * 60) / v_dist) / BINW) * BINW)::integer)),
                v_dist,
                v_dur * 60);
        v_source := 'average';
        v_miles  := v_dist;
    END IF;

    ----------------------------------------------------------------------
    -- Tier 4: not binnable
    ----------------------------------------------------------------------
    IF v_source IS NULL THEN
        v_source := 'none';
        v_miles  := 0;
    END IF;

    UPDATE training_logs
       SET pace_bins_source      = v_source,
           pace_bins_miles       = v_miles,
           pace_bins_computed_at = now()
     WHERE id = p_workout_id;

    RETURN v_source;
END;
$function$;

REVOKE ALL ON FUNCTION public.compute_pace_bins(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.compute_pace_bins(uuid) TO service_role;

COMMENT ON FUNCTION public.compute_pace_bins(uuid) IS
  'Rebuilds workout_pace_bins for one training log. Stream-first, lap and average fallbacks, and records which was used in training_logs.pace_bins_source. Service role only -- the ingest trigger calls it.';;
