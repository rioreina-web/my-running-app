-- ============================================================================
-- 20260528120000_create_running_workout_laps.sql
--
-- Normalize Strava lap data (currently buried in training_logs.external_streams)
-- into a proper queryable table. This is the foundation for honest pace×volume,
-- quality-day execution analysis, and any rep-level metrics downstream.
--
-- Source: training_logs.external_streams.laps (populated by strava-test-pull)
-- Shape per lap: distance (m), moving_time (s), elapsed_time (s),
--                average_speed, max_speed, average_heartrate, max_heartrate,
--                average_cadence, average_watts, pace_zone, lap_index,
--                start_index, end_index, start_date, total_elevation_gain.
--
-- RLS: user-scoped, matches training_logs (parent). user_id denormalized for
-- query speed — saves a join in every policy check.
-- ============================================================================

-- ── Table ────────────────────────────────────────────────────────────────────

CREATE TABLE running_workout_laps (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    workout_id UUID NOT NULL REFERENCES training_logs(id) ON DELETE CASCADE,
    user_id    TEXT NOT NULL,

    lap_index             INTEGER NOT NULL,
    distance_meters       NUMERIC(10, 2) NOT NULL,
    moving_time_seconds   INTEGER NOT NULL,
    elapsed_time_seconds  INTEGER NOT NULL,

    -- Derived for convenience. Computed on insert so downstream queries
    -- never need to redo the unit math.
    avg_pace_sec_per_mile NUMERIC(8, 2),

    avg_speed_mps         NUMERIC(6, 3),
    max_speed_mps         NUMERIC(6, 3),
    avg_heart_rate        INTEGER,
    max_heart_rate        INTEGER,
    avg_cadence           NUMERIC(6, 2),
    avg_watts             NUMERIC(8, 2),
    pace_zone             INTEGER,  -- Strava's 1–5 scale
    total_elevation_gain  NUMERIC(8, 2),

    -- Stream indices: lets us slice the per-second velocity/HR stream by
    -- lap when we need finer drill-down. Keep them; they're cheap.
    stream_start_index    INTEGER,
    stream_end_index      INTEGER,

    lap_start_at          TIMESTAMPTZ,

    -- Classification: is this lap a rest/recovery between work reps?
    -- Heuristic: short distance OR slow average speed. Tunable later;
    -- the values below catch standing rests (<200m) and walks (<2 m/s
    -- ≈ 4:30 min/km, well outside any running pace).
    is_rest BOOLEAN GENERATED ALWAYS AS (
        distance_meters < 200 OR avg_speed_mps < 2.0
    ) STORED,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (workout_id, lap_index)
);

-- ── Indexes ─────────────────────────────────────────────────────────────────

CREATE INDEX idx_workout_laps_workout
    ON running_workout_laps (workout_id);

CREATE INDEX idx_workout_laps_user_date
    ON running_workout_laps (user_id, lap_start_at DESC);

-- For quality-day analytics: "all non-rest laps for this user in pace order"
CREATE INDEX idx_workout_laps_user_work_pace
    ON running_workout_laps (user_id, avg_pace_sec_per_mile)
    WHERE is_rest = false;

-- ── RLS ─────────────────────────────────────────────────────────────────────
-- Mirror training_logs exactly. No "Allow all" placeholder.

ALTER TABLE running_workout_laps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_workout_laps_select" ON running_workout_laps
    FOR SELECT USING (user_id = auth.uid()::text);

CREATE POLICY "rls_workout_laps_insert" ON running_workout_laps
    FOR INSERT WITH CHECK (user_id = auth.uid()::text);

CREATE POLICY "rls_workout_laps_update" ON running_workout_laps
    FOR UPDATE USING (user_id = auth.uid()::text);

CREATE POLICY "rls_workout_laps_delete" ON running_workout_laps
    FOR DELETE USING (user_id = auth.uid()::text);

-- ── Backfill from existing external_streams.laps ─────────────────────────────
-- One-shot: read every training_logs row that has a laps array on its
-- external_streams blob, flatten it, write rows. ON CONFLICT is a guard
-- against re-running this migration in a dev environment.

INSERT INTO running_workout_laps (
    workout_id, user_id, lap_index,
    distance_meters, moving_time_seconds, elapsed_time_seconds,
    avg_pace_sec_per_mile,
    avg_speed_mps, max_speed_mps,
    avg_heart_rate, max_heart_rate,
    avg_cadence, avg_watts,
    pace_zone, total_elevation_gain,
    stream_start_index, stream_end_index, lap_start_at
)
SELECT
    tl.id,
    tl.user_id,
    (lap->>'lap_index')::int,
    (lap->>'distance')::numeric,
    (lap->>'moving_time')::int,
    (lap->>'elapsed_time')::int,
    -- pace = seconds per mile = moving_time / (meters / 1609.344)
    CASE
        WHEN (lap->>'distance')::numeric > 0
        THEN (lap->>'moving_time')::numeric
             / ((lap->>'distance')::numeric / 1609.344)
        ELSE NULL
    END,
    NULLIF((lap->>'average_speed'),  '')::numeric,
    NULLIF((lap->>'max_speed'),       '')::numeric,
    NULLIF((lap->>'average_heartrate'),'')::int,
    NULLIF((lap->>'max_heartrate'),    '')::int,
    NULLIF((lap->>'average_cadence'), '')::numeric,
    NULLIF((lap->>'average_watts'),    '')::numeric,
    NULLIF((lap->>'pace_zone'),        '')::int,
    NULLIF((lap->>'total_elevation_gain'), '')::numeric,
    NULLIF((lap->>'start_index'),      '')::int,
    NULLIF((lap->>'end_index'),        '')::int,
    NULLIF((lap->>'start_date'),       '')::timestamptz
FROM training_logs tl,
     jsonb_array_elements(tl.external_streams->'laps') AS lap
WHERE tl.external_streams ? 'laps'
  AND jsonb_typeof(tl.external_streams->'laps') = 'array'
  AND tl.user_id IS NOT NULL
ON CONFLICT (workout_id, lap_index) DO NOTHING;

-- ── Verification (run-once sanity, comment out before re-applying) ──────────
-- SELECT COUNT(*) AS lap_rows FROM running_workout_laps;
-- SELECT workout_id, COUNT(*) AS laps, MIN(lap_index), MAX(lap_index)
--   FROM running_workout_laps GROUP BY workout_id ORDER BY laps DESC LIMIT 10;
