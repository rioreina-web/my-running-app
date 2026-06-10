-- ============================================================================
-- Two-Lane Canvas: Quality Session Pool
--
-- Enables the "coach commits quality sessions, athlete places them" model.
-- Quality sessions live as undated templates per week; the athlete drags them
-- onto specific days, and easy/recovery days auto-fill around them.
--
-- Key concepts:
--   quality_session_templates — the "pool" of quality work per week
--   scheduled_workouts.source — who placed this workout on this date
--   scheduled_workouts.is_movable — can the athlete drag it to another day?
--   scheduled_workouts.pool_template_id — links back to quality pool origin
-- ============================================================================

-- ============================================================================
-- 1. QUALITY SESSION TEMPLATES
-- One row per quality session the coach/AI prescribes for a given week.
-- NOT tied to a specific date — the athlete decides when to run it.
-- ============================================================================

CREATE TABLE IF NOT EXISTS quality_session_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES training_plans(id) ON DELETE CASCADE,
    week_number INTEGER NOT NULL CHECK (week_number > 0),

    -- What this session is for
    purpose TEXT NOT NULL,
        -- e.g. "threshold development", "race-specific endurance", "long run", "VO2max"
    workout_type TEXT NOT NULL DEFAULT 'intervals'
        CHECK (workout_type IN ('tempo', 'intervals', 'long_run', 'progression',
                                'strides', 'race', 'easy', 'recovery')),

    -- Prescription
    workout_data JSONB,
        -- Full PlannedWorkout JSON blob — same shape as scheduled_workouts.workout_data
    target_pace_percentage REAL,
        -- % of goal race pace (e.g. 95.0 for race-pace work, 110.0 for speed)
    target_distance_miles REAL,
    target_duration_minutes REAL,

    -- Ordering: 1 = most important session of the week
    priority_rank INTEGER NOT NULL DEFAULT 1
        CHECK (priority_rank BETWEEN 1 AND 7),

    -- Suggested day (0=Mon..6=Sun, nullable = no preference)
    suggested_day_of_week INTEGER
        CHECK (suggested_day_of_week IS NULL OR suggested_day_of_week BETWEEN 0 AND 6),

    -- Whether this session has been placed onto a specific date
    is_placed BOOLEAN NOT NULL DEFAULT false,

    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX idx_qst_plan_week ON quality_session_templates(plan_id, week_number);
CREATE INDEX idx_qst_plan_unplaced ON quality_session_templates(plan_id, is_placed)
    WHERE is_placed = false;

-- RLS
ALTER TABLE quality_session_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own quality templates" ON quality_session_templates
    FOR ALL USING (
        plan_id IN (SELECT id FROM training_plans WHERE user_id = auth.uid()::text)
        OR auth.role() = 'service_role'
    );

-- Updated_at trigger
CREATE TRIGGER quality_session_templates_updated_at
    BEFORE UPDATE ON quality_session_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_scheduled_workouts_updated_at();


-- ============================================================================
-- 2. ADD COLUMNS TO scheduled_workouts
-- ============================================================================

-- source: who placed this workout on this date
ALTER TABLE scheduled_workouts
    ADD COLUMN IF NOT EXISTS source TEXT NOT NULL DEFAULT 'coach_locked'
        CHECK (source IN ('coach_locked', 'athlete_drag', 'easy_fill', 'legacy'));

-- is_movable: can the athlete drag this to another day?
ALTER TABLE scheduled_workouts
    ADD COLUMN IF NOT EXISTS is_movable BOOLEAN NOT NULL DEFAULT false;

-- pool_template_id: links a placed workout back to its quality session template
ALTER TABLE scheduled_workouts
    ADD COLUMN IF NOT EXISTS pool_template_id UUID
        REFERENCES quality_session_templates(id) ON DELETE SET NULL;

-- workout_code: identifier from the workout library (e.g. "RSE_3", "RP_7")
-- (may already exist from a prior migration — IF NOT EXISTS handles it)
ALTER TABLE scheduled_workouts
    ADD COLUMN IF NOT EXISTS workout_code TEXT;

CREATE INDEX IF NOT EXISTS idx_scheduled_workouts_source
    ON scheduled_workouts(source);
CREATE INDEX IF NOT EXISTS idx_scheduled_workouts_pool_template
    ON scheduled_workouts(pool_template_id)
    WHERE pool_template_id IS NOT NULL;


-- ============================================================================
-- 3. MIGRATE EXISTING DATA
-- Tag every existing scheduled_workouts row with the appropriate source.
-- Quality workouts (tempo, intervals, long_run, race, progression) → coach_locked
-- Easy/recovery/rest/strides → easy_fill
-- All existing rows are non-movable by default.
-- ============================================================================

-- Quality workout types → coach_locked
UPDATE scheduled_workouts
SET source = 'coach_locked', is_movable = false
WHERE source = 'legacy'
  AND workout_type IN ('tempo', 'intervals', 'long_run', 'race', 'progression');

-- Easy/recovery types → easy_fill
UPDATE scheduled_workouts
SET source = 'easy_fill', is_movable = false
WHERE source = 'legacy'
  AND workout_type IN ('easy', 'recovery', 'rest', 'strides', 'strength', 'cross_training');

-- Anything still marked legacy (unexpected types) → easy_fill
UPDATE scheduled_workouts
SET source = 'easy_fill', is_movable = false
WHERE source = 'legacy';

-- Backfill quality_session_templates from existing quality workouts.
-- This creates a template row for each quality workout so existing plans
-- integrate with the new pool UI.
INSERT INTO quality_session_templates (
    plan_id, week_number, purpose, workout_type, workout_data,
    target_distance_miles, priority_rank, suggested_day_of_week, is_placed
)
SELECT
    sw.plan_id,
    sw.week_number,
    CASE sw.workout_type
        WHEN 'tempo' THEN 'threshold development'
        WHEN 'intervals' THEN 'speed development'
        WHEN 'long_run' THEN 'long run'
        WHEN 'progression' THEN 'progressive endurance'
        WHEN 'race' THEN 'race'
        ELSE sw.workout_type
    END AS purpose,
    sw.workout_type,
    sw.workout_data,
    CASE
        WHEN sw.workout_data IS NOT NULL AND (sw.workout_data->>'total_distance_km') IS NOT NULL
        THEN (sw.workout_data->>'total_distance_km')::REAL / 1.60934
        ELSE NULL
    END AS target_distance_miles,
    ROW_NUMBER() OVER (
        PARTITION BY sw.plan_id, sw.week_number
        ORDER BY
            CASE sw.workout_type
                WHEN 'long_run' THEN 1
                WHEN 'race' THEN 1
                WHEN 'intervals' THEN 2
                WHEN 'tempo' THEN 3
                WHEN 'progression' THEN 4
                ELSE 5
            END,
            sw.date
    ) AS priority_rank,
    sw.day_of_week - 1 AS suggested_day_of_week,  -- DB is 1-indexed, pool is 0-indexed
    true AS is_placed  -- already on the calendar
FROM scheduled_workouts sw
WHERE sw.workout_type IN ('tempo', 'intervals', 'long_run', 'race', 'progression')
  AND sw.status != 'skipped';

-- Link the placed workouts back to their newly created template rows.
-- Match on (plan_id, week_number, workout_type, date ordering).
WITH ranked_templates AS (
    SELECT id, plan_id, week_number, workout_type,
           ROW_NUMBER() OVER (
               PARTITION BY plan_id, week_number, workout_type
               ORDER BY priority_rank, created_at
           ) AS rn
    FROM quality_session_templates
),
ranked_workouts AS (
    SELECT id, plan_id, week_number, workout_type,
           ROW_NUMBER() OVER (
               PARTITION BY plan_id, week_number, workout_type
               ORDER BY date, session
           ) AS rn
    FROM scheduled_workouts
    WHERE workout_type IN ('tempo', 'intervals', 'long_run', 'race', 'progression')
      AND source = 'coach_locked'
)
UPDATE scheduled_workouts sw
SET pool_template_id = rt.id
FROM ranked_workouts rw
JOIN ranked_templates rt
    ON rt.plan_id = rw.plan_id
    AND rt.week_number = rw.week_number
    AND rt.workout_type = rw.workout_type
    AND rt.rn = rw.rn
WHERE sw.id = rw.id;

-- Change default for new rows: new workouts are 'legacy' until explicitly set
ALTER TABLE scheduled_workouts
    ALTER COLUMN source SET DEFAULT 'legacy';
