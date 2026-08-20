-- ============================================================================
-- Rebuild `training_logs.pace_segments` from the watch's own laps.
--
-- WHY (Rio, 2026-08-20)
-- `pace_segments` was written from Strava's `splits_standard` — per-MILE
-- autolap splits. On an easy run that is a fair sample. On a quality day it is
-- wrong: one mile of an interval session holds work AND the jog between reps,
-- and the split reports their average.
--
-- Measured on the Trends pace spectrum, which buckets miles by pace_segments
-- pace: over a real 4-week window it credited 1.6 mi at 5:12-5:22/mi, while a
-- single Tuesday (2026-08-18) actually held ~1.4 mi in that band. The mile
-- splits recorded that session as 5:24 / 5:29 / 5:34 / 5:33 — one to two
-- buckets slow — and the fast tail of the chart collapsed. The Threshold Miles
-- card one screen below, which reads `running_workout_laps`, reported 21 mi in
-- the HM band off the same runs. Two surfaces, two segment definitions.
--
-- `strava-sync` now writes laps-first for NEW activities
-- (`_shared/paceSegments.ts`). This migration does the same for the rows
-- already ingested, using `external_streams.laps`, which we have stored
-- verbatim all along — so no Strava re-fetch and no API budget is needed.
--
-- SAFETY
--   * Only rows whose laps have >= 2 entries and cover >= 80% of the recorded
--     distance are rewritten. Everything else keeps its existing splits.
--   * The previous value is copied to `pace_segments_legacy_splits` first, so
--     this is reversible with a single UPDATE (see the DOWN note at the end).
--   * Idempotent: re-running rebuilds from the same laps and lands on the same
--     value. The legacy snapshot is only taken when it is still NULL.
--   * Read-only with respect to `external_streams` and `running_workout_laps`.
--
-- The rest rule below is a deliberate copy of `running_workout_laps.is_rest`
-- (generated column, `20260528222123_create_running_workout_laps.sql`):
--     distance_meters < 200 OR avg_speed_mps < 2.0
-- and of `isRestLap()` in `_shared/paceSegments.ts`. If it is ever retuned,
-- retune all three in the same migration.
-- ============================================================================

-- ── 1. Reversibility snapshot ───────────────────────────────────────────────

ALTER TABLE public.training_logs
    ADD COLUMN IF NOT EXISTS pace_segments_legacy_splits JSONB;

COMMENT ON COLUMN public.training_logs.pace_segments_legacy_splits IS
    'Pre-2026-08-20 pace_segments, built from Strava per-mile splits_standard. '
    'Kept only so the laps-based rebuild is reversible; nothing reads it. '
    'Safe to drop once the laps-based spectrum has been trusted for a cycle.';

-- ── 2. Segment builder, mirroring _shared/paceSegments.ts ───────────────────

CREATE OR REPLACE FUNCTION public.pace_segments_from_laps(
    laps            JSONB,
    avg_speed_mps   NUMERIC,
    activity_meters NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    meters_per_mile CONSTANT NUMERIC := 1609.34;
    avg_pace_sec    NUMERIC;
    covered         NUMERIC;
    result          JSONB;
BEGIN
    -- Two nested tests rather than one OR chain: 10 rows store `laps` as JSON
    -- `null`, which is NOT SQL NULL, so `laps IS NULL` does not catch them.
    -- SQL does not guarantee OR short-circuits, and jsonb_array_length()
    -- raises 22023 on a scalar, so the type test gets its own statement.
    IF laps IS NULL OR jsonb_typeof(laps) <> 'array' THEN
        RETURN NULL;
    END IF;

    IF jsonb_array_length(laps) < 2 THEN
        RETURN NULL;
    END IF;

    SELECT COALESCE(SUM(GREATEST((l->>'distance')::numeric, 0)), 0)
      INTO covered
      FROM jsonb_array_elements(laps) l;

    IF covered <= 0 THEN
        RETURN NULL;
    END IF;

    -- Laps must account for the run; a partially-lapped activity would
    -- under-report volume, and volume is load-bearing everywhere.
    IF activity_meters IS NOT NULL AND activity_meters > 0
       AND covered < activity_meters * 0.8 THEN
        RETURN NULL;
    END IF;

    avg_pace_sec := CASE WHEN COALESCE(avg_speed_mps, 0) > 0
                         THEN meters_per_mile / avg_speed_mps
                         ELSE 0 END;

    SELECT jsonb_agg(seg ORDER BY ord)
      INTO result
      FROM (
        SELECT
            l.ord,
            jsonb_build_object(
                'effort',
                    CASE
                        WHEN l.meters < 200 OR l.speed_mps < 2.0 THEN 'recovery'
                        WHEN avg_pace_sec = 0 THEN 'steady'
                        WHEN l.pace_sec / avg_pace_sec < 0.92 THEN 'fast'
                        WHEN l.pace_sec / avg_pace_sec > 1.08 THEN 'easy'
                        ELSE 'steady'
                    END,
                'distance_miles', round(l.meters / meters_per_mile, 2),
                'duration_seconds', l.moving_sec,
                -- Carry a 60-second rounding into the minute: 5:60 is not a pace.
                'pace_per_mile',
                    CASE WHEN round(l.pace_sec % 60) = 60
                         THEN (floor(l.pace_sec / 60) + 1)::int || ':00'
                         ELSE floor(l.pace_sec / 60)::int || ':'
                              || lpad(round(l.pace_sec % 60)::int::text, 2, '0')
                    END,
                'avg_heart_rate',
                    CASE WHEN l.hr IS NULL THEN NULL ELSE to_jsonb(round(l.hr)::int) END
            ) AS seg
        FROM (
            SELECT
                ordinality AS ord,
                (lap->>'distance')::numeric        AS meters,
                (lap->>'moving_time')::numeric     AS moving_sec,
                (lap->>'moving_time')::numeric
                    / ((lap->>'distance')::numeric / meters_per_mile) AS pace_sec,
                COALESCE(
                    NULLIF((lap->>'average_speed'), '')::numeric,
                    (lap->>'distance')::numeric / (lap->>'moving_time')::numeric
                ) AS speed_mps,
                NULLIF((lap->>'average_heartrate'), '')::numeric AS hr
            FROM jsonb_array_elements(laps) WITH ORDINALITY AS t(lap, ordinality)
            WHERE COALESCE((lap->>'distance')::numeric, 0) > 0
              AND COALESCE((lap->>'moving_time')::numeric, 0) > 0
        ) l
      ) segs;

    RETURN result;
END;
$$;

COMMENT ON FUNCTION public.pace_segments_from_laps(JSONB, NUMERIC, NUMERIC) IS
    'Builds training_logs.pace_segments from external_streams.laps. SQL twin of '
    'lapsToPaceSegments() in supabase/functions/_shared/paceSegments.ts — the '
    'rest rule matches running_workout_laps.is_rest exactly. Returns NULL when '
    'the laps are unusable (fewer than 2, or covering <80% of the run), which '
    'means "keep whatever is already stored".';

-- ── 3. Backfill ─────────────────────────────────────────────────────────────

WITH candidate AS (
    SELECT
        t.id,
        t.pace_segments AS old_segments,
        public.pace_segments_from_laps(
            t.external_streams->'laps',
            -- Whole-run average speed, derived from the row rather than read
            -- from external_streams.meta: strava-sync never stored
            -- `average_speed` there, and distance/duration are always present.
            -- Only the effort TAG depends on this; pace and distance, which is
            -- all the spectrum reads, are computed per lap either way.
            CASE
                WHEN COALESCE(t.workout_duration_minutes, 0) > 0
                     AND COALESCE(t.workout_distance_miles, 0) > 0
                -- Both columns are DOUBLE PRECISION, so this arithmetic is
                -- float8; cast the whole CASE, since Postgres will not
                -- implicitly widen float8 to the NUMERIC the function declares
                -- and overload resolution fails outright without it.
                THEN ((t.workout_distance_miles * 1609.34) / (t.workout_duration_minutes * 60))::numeric
                ELSE NULL
            END,
            (t.workout_distance_miles * 1609.34)::numeric
        ) AS new_segments
    FROM public.training_logs t
    WHERE t.external_streams ? 'laps'
      -- Guarded by CASE, not a flat AND chain. The planner splits top-level
      -- ANDs into independent quals and reorders them by cost, so the
      -- jsonb_typeof() test cannot be relied on to run first; on the 10 rows
      -- holding JSON `null` that let jsonb_array_length() see a scalar and
      -- abort the migration with 22023. CASE is the one construct whose
      -- evaluation order Postgres actually guarantees.
      AND CASE
              WHEN jsonb_typeof(t.external_streams->'laps') = 'array'
              THEN jsonb_array_length(t.external_streams->'laps') >= 2
              ELSE FALSE
          END
)
UPDATE public.training_logs t
   SET pace_segments_legacy_splits = COALESCE(t.pace_segments_legacy_splits, c.old_segments),
       pace_segments = c.new_segments
  FROM candidate c
 WHERE t.id = c.id
   AND c.new_segments IS NOT NULL
   AND c.new_segments IS DISTINCT FROM t.pace_segments;

-- ── DOWN (manual) ───────────────────────────────────────────────────────────
-- Migrations here are append-only (hard rule #5), so the revert is a one-liner
-- run by hand rather than a down-migration:
--
--   UPDATE public.training_logs
--      SET pace_segments = pace_segments_legacy_splits
--    WHERE pace_segments_legacy_splits IS NOT NULL;
--
-- WHAT THIS ACTUALLY TOUCHES, on the data as of 2026-08-20: continuous runs
-- (easy, long, recovery) arrive from Strava with a SINGLE whole-run lap, so
-- the >= 2 guard leaves them exactly as they are — their mile splits were
-- never the problem. Only the lapped quality sessions are rewritten, which is
-- precisely the set the mile splits were smearing. Expect the row count
-- updated to be roughly the number of interval/threshold days in the history,
-- not the whole table; that is the migration working, not failing.
