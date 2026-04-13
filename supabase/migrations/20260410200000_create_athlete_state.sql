-- Athlete State: The Dynamic Context Object (DCO)
--
-- Single source of truth for "who is this runner right now." Every AI function
-- reads from this instead of independently querying 6-8 tables. Updated by
-- events (log run, check-in, workout sync, injury report, fitness snapshot).
--
-- The state is a living document — stale after ~24 hours if no events fire,
-- but always represents the last-known state of the athlete.

CREATE TABLE IF NOT EXISTS athlete_state (
    user_id TEXT PRIMARY KEY,

    -- ── Identity & Phase ──────────────────────────────────
    experience_level TEXT,                -- beginner / intermediate / advanced / elite
    current_phase TEXT,                   -- base / build / peak / taper / recovery / off_season
    active_plan_id UUID,                  -- FK to training_plans (nullable if no plan)
    goal_race TEXT,                       -- "Boston Marathon 2026-04-20" or null
    goal_time_seconds INTEGER,            -- target finish time

    -- ── Load & Fitness (rolling metrics) ──────────────────
    acwr DOUBLE PRECISION,               -- acute:chronic workload ratio (7d / 28d)
    monotony_7d DOUBLE PRECISION,         -- training monotony (last 7 days)
    strain_7d DOUBLE PRECISION,           -- training strain (last 7 days)
    rolling_7d_miles DOUBLE PRECISION,    -- total miles last 7 days
    rolling_28d_miles DOUBLE PRECISION,   -- total miles last 28 days
    weekly_avg_miles DOUBLE PRECISION,    -- 4-week rolling average
    hard_sessions_7d INTEGER DEFAULT 0,   -- tempo/interval/long_run count last 7 days
    easy_sessions_7d INTEGER DEFAULT 0,   -- easy/recovery count last 7 days
    runs_last_7d INTEGER DEFAULT 0,       -- total runs last 7 days
    longest_run_14d DOUBLE PRECISION,     -- longest single run in last 14 days

    -- ── Fitness Trajectory ────────────────────────────────
    predicted_5k_seconds INTEGER,
    predicted_10k_seconds INTEGER,
    predicted_half_seconds INTEGER,
    predicted_marathon_seconds INTEGER,
    fitness_trend TEXT,                   -- improving / maintaining / declining
    fitness_snapshot_id UUID,             -- FK to the snapshot these came from
    fitness_snapshot_at TIMESTAMPTZ,

    -- ── Recent Vibe (from check-ins & logs) ───────────────
    last_mood TEXT,                       -- energized/positive/neutral/tired/struggling/injured
    last_readiness_score INTEGER,         -- 1-10 from most recent check-in
    mood_trend TEXT,                      -- improving / stable / declining (last 5 entries)
    last_check_in_at TIMESTAMPTZ,

    -- ── Injury & Risk ─────────────────────────────────────
    active_injuries JSONB DEFAULT '[]',   -- [{body_area, severity, status, first_reported_at}]
    injury_risk_score DOUBLE PRECISION,   -- 0-10 from injury-early-warning
    injury_risk_signals JSONB DEFAULT '[]', -- [{signal, level, detail}]

    -- ── Pace Zones (from latest fitness snapshot) ─────────
    pace_zones JSONB DEFAULT '{}',        -- {easy: 540, longRun: 510, mp: 420, hm: 405, ...} sec/mi

    -- ── Recent Training Summary (for prompt context) ──────
    recent_training_summary TEXT,          -- compressed 2-week narrative for AI prompts
    recent_workouts JSONB DEFAULT '[]',    -- last 7 workouts: [{date, type, miles, pace, mood}]

    -- ── Scheduled Context ─────────────────────────────────
    today_workout JSONB,                  -- today's scheduled workout (if any)
    upcoming_workouts JSONB DEFAULT '[]', -- next 5 scheduled workouts
    week_compliance_pct DOUBLE PRECISION, -- % of scheduled workouts completed this week

    -- ── Metadata ──────────────────────────────────────────
    last_updated_at TIMESTAMPTZ DEFAULT now(),
    last_updated_by TEXT,                 -- which function triggered the update
    version INTEGER DEFAULT 1             -- for optimistic concurrency
);

CREATE INDEX IF NOT EXISTS idx_athlete_state_updated ON athlete_state(last_updated_at);

ALTER TABLE athlete_state ENABLE ROW LEVEL SECURITY;

-- Users can read their own state
CREATE POLICY "Users read own athlete state" ON athlete_state
    FOR SELECT USING (user_id = auth.uid()::text);

-- Service role (edge functions) has full access
CREATE POLICY "Service role full access to athlete_state" ON athlete_state
    FOR ALL USING (auth.role() = 'service_role');
