-- ============================================================================
-- Resolve scheduled_workouts.workout_data paces to concrete seconds/mile
--
-- Transforms the per-step JSONB so every step carries:
--   target_pace_seconds_per_mile  numeric   -- the real pace to run
--   target_pace_seconds_high      numeric   -- optional slow-end of a range
--   pace_reference                text      -- "easy" | "marathon" | "half"
--                                             | "10K" | "5K" | "mile"
--   resolved_from_snapshot_id     uuid      -- provenance: which fitness
--                                             snapshot fed the pace profile
--   resolved_at                   timestamptz
--
-- Step priority when resolving:
--   1. pacePercentage exists → seconds = goal_pace × (100 / pct)
--   2. paceSecondsPerKm  exists → seconds = km × 1.609344
--   3. Neither                 → pace_reference = 'easy', use easy pace
--
-- The legacy pacePercentage / paceSecondsPerKm fields are KEPT in place for
-- one release so rollback is safe. A follow-up migration will drop them.
-- ============================================================================

BEGIN;

-- ── 1. Per-step transformer ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION resolve_step_paces(data jsonb, profile jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    step           jsonb;
    new_steps      jsonb := '[]'::jsonb;
    out_step       jsonb;
    pct            numeric;
    km_low         numeric;
    km_high        numeric;
    goal_seconds   numeric;
    easy_seconds   numeric;
    snapshot_id    text;
    sec_per_mile   numeric;
    sec_high       numeric;
    reference      text;
    now_ts         timestamptz := now();
BEGIN
    IF data IS NULL OR data->'steps' IS NULL THEN
        RETURN data;
    END IF;

    goal_seconds := NULLIF(profile->>'goal_pace_seconds', '')::numeric;
    easy_seconds := NULLIF(profile->>'easy_pace_seconds', '')::numeric;
    snapshot_id  := profile->>'based_on_snapshot_id';

    FOR step IN SELECT * FROM jsonb_array_elements(data->'steps') LOOP
        out_step := step;
        pct      := NULLIF(step->>'pacePercentage', '')::numeric;
        km_low   := NULLIF(step->>'paceSecondsPerKm', '')::numeric;
        km_high  := NULLIF(step->>'paceSecondsPerKmHigh', '')::numeric;

        sec_per_mile := NULL;
        sec_high     := NULL;
        reference    := NULL;

        IF pct IS NOT NULL AND goal_seconds IS NOT NULL THEN
            sec_per_mile := ROUND(goal_seconds * (100.0 / pct), 1);
        ELSIF km_low IS NOT NULL THEN
            sec_per_mile := ROUND(km_low * 1.609344, 1);
            IF km_high IS NOT NULL THEN
                sec_high := ROUND(km_high * 1.609344, 1);
            END IF;
        ELSIF easy_seconds IS NOT NULL THEN
            sec_per_mile := easy_seconds;
            reference    := 'easy';
        END IF;

        IF sec_per_mile IS NOT NULL THEN
            out_step := out_step || jsonb_build_object(
                'target_pace_seconds_per_mile', sec_per_mile,
                'resolved_at', now_ts
            );
            IF sec_high IS NOT NULL THEN
                out_step := out_step || jsonb_build_object(
                    'target_pace_seconds_high', sec_high
                );
            END IF;
            IF reference IS NOT NULL THEN
                out_step := out_step || jsonb_build_object(
                    'pace_reference', reference
                );
            END IF;
            IF snapshot_id IS NOT NULL THEN
                out_step := out_step || jsonb_build_object(
                    'resolved_from_snapshot_id', snapshot_id
                );
            END IF;
        END IF;

        new_steps := new_steps || out_step;
    END LOOP;

    RETURN jsonb_set(data, '{steps}', new_steps);
END;
$$;

-- ── 2. One-time backfill over existing scheduled_workouts ─────────────────
--
-- Joins scheduled_workouts → training_plans → athlete_pace_profiles by user.
-- Rows whose owner has no pace profile yet are left untouched — they'll be
-- picked up the next time build-pace-profile runs for that user.
--
-- Runs in batches of 500 so long backfills don't hold a single giant
-- transaction. RAISE NOTICE emits a progress log every batch.

DO $backfill$
DECLARE
    batch_size   integer := 500;
    batch_count  integer := 0;
    total_done   integer := 0;
    rows_in_batch integer;
BEGIN
    LOOP
        WITH candidates AS (
            SELECT
                sw.id,
                sw.workout_data,
                jsonb_build_object(
                    'based_on_snapshot_id', app.based_on_snapshot_id,
                    'easy_pace_seconds', app.easy_pace_seconds,
                    'goal_pace_seconds', CASE app.goal_race_distance
                        WHEN 'marathon' THEN app.marathon_pace_seconds
                        WHEN 'half'     THEN app.half_pace_seconds
                        WHEN '10K'      THEN app.ten_k_pace_seconds
                        WHEN '5K'       THEN app.five_k_pace_seconds
                        WHEN 'mile'     THEN app.mile_pace_seconds
                        ELSE app.marathon_pace_seconds
                    END
                ) AS profile_json
            FROM scheduled_workouts sw
            JOIN training_plans tp ON tp.id = sw.plan_id
            JOIN athlete_pace_profiles app ON app.user_id = tp.user_id
            WHERE sw.workout_data IS NOT NULL
              AND sw.workout_data->'steps' IS NOT NULL
              AND NOT (sw.workout_data->'steps'->0 ? 'target_pace_seconds_per_mile')
            LIMIT batch_size
        )
        UPDATE scheduled_workouts sw
           SET workout_data = resolve_step_paces(c.workout_data, c.profile_json)
          FROM candidates c
         WHERE sw.id = c.id;

        GET DIAGNOSTICS rows_in_batch = ROW_COUNT;
        total_done := total_done + rows_in_batch;
        batch_count := batch_count + 1;

        RAISE NOTICE 'resolve_scheduled_workout_paces: batch % updated % rows (total %)',
            batch_count, rows_in_batch, total_done;

        EXIT WHEN rows_in_batch = 0;
    END LOOP;

    RAISE NOTICE 'resolve_scheduled_workout_paces backfill complete: % rows updated across % batches',
        total_done, batch_count;
END
$backfill$;

COMMIT;
