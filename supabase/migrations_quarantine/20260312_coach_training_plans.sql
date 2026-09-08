-- ============================================================================
-- Coach Training Plans Feature
-- Enables human coaches to build reusable workout templates and 12-16 week
-- plan templates that athletes can subscribe to (via join code or direct assign).
-- ============================================================================

-- ============================================================================
-- 1. COACH PROFILES
-- One row per coach user. Coaches opt in (not all users are coaches).
-- ============================================================================

CREATE TABLE IF NOT EXISTS coach_profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id TEXT NOT NULL UNIQUE,   -- matches auth.uid()::text
    display_name TEXT NOT NULL,
    bio TEXT,
    specializations TEXT[] DEFAULT '{}',  -- e.g. ['marathon', 'trail', '5k']
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_coach_profiles_user ON coach_profiles(user_id);

ALTER TABLE coach_profiles ENABLE ROW LEVEL SECURITY;

-- Coaches manage their own profile
CREATE POLICY "Coaches manage own profile" ON coach_profiles
    FOR ALL USING (auth.uid()::text = user_id OR auth.uid() IS NULL);

-- Service role for edge functions
CREATE POLICY "Service role full access to coach_profiles" ON coach_profiles
    FOR ALL USING (auth.role() = 'service_role');

-- NOTE: "Athletes read linked coaches" policy added after coach_athlete_relationships table is created (below)


-- ============================================================================
-- 2. WORKOUT TEMPLATES
-- Reusable workout blueprints per coach (e.g., "10 x 1K", "Long Run Progression").
-- workout_data stores a full PlannedWorkout JSON blob.
-- ============================================================================

CREATE TABLE IF NOT EXISTS workout_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID NOT NULL REFERENCES coach_profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    workout_type TEXT NOT NULL DEFAULT 'easy',
        -- values match ScheduledWorkoutType: rest/easy/tempo/intervals/long_run/recovery/race/progression/strides
    description TEXT,
    tags TEXT[] DEFAULT '{}',        -- e.g. ['track', 'vo2max', 'threshold']
    workout_data JSONB NOT NULL,     -- serialized PlannedWorkout
    estimated_distance_miles FLOAT,
    estimated_duration_minutes INTEGER,
    is_public BOOLEAN NOT NULL DEFAULT false,
    use_count INTEGER NOT NULL DEFAULT 0,  -- incremented when added to a plan
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_workout_templates_coach ON workout_templates(coach_id);
CREATE INDEX idx_workout_templates_type ON workout_templates(coach_id, workout_type);

ALTER TABLE workout_templates ENABLE ROW LEVEL SECURITY;

-- Coaches manage their own templates
CREATE POLICY "Coaches manage own workout templates" ON workout_templates
    FOR ALL USING (
        coach_id IN (SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text)
        OR auth.uid() IS NULL
    );

-- NOTE: "Athletes read relevant workout templates" policy added after coach_athlete_relationships table is created (below)

CREATE POLICY "Service role full access to workout_templates" ON workout_templates
    FOR ALL USING (auth.role() = 'service_role');

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_workout_templates_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER workout_templates_updated_at
    BEFORE UPDATE ON workout_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_workout_templates_timestamp();


-- ============================================================================
-- 3. PLAN TEMPLATES
-- A 12-16 week training plan blueprint created by a coach.
-- The weeks column stores the full week/workout structure as JSONB.
--
-- weeks JSONB shape:
-- [
--   {
--     "weekNumber": 1,
--     "theme": "Base Building",
--     "notes": "Focus on easy aerobic work",
--     "workouts": [
--       {
--         "dayOfWeek": 0,          -- 0=Mon, 6=Sun
--         "workoutTemplateId": "uuid | null",
--         "workoutType": "easy",
--         "workoutData": { ... },  -- PlannedWorkout JSON (may be null if templateId set)
--         "notes": ""
--       },
--       ...
--     ]
--   },
--   ...
-- ]
-- ============================================================================

CREATE TABLE IF NOT EXISTS plan_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID NOT NULL REFERENCES coach_profiles(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    target_distance TEXT NOT NULL DEFAULT 'marathon',
        -- 'marathon' | 'half_marathon' | '10k' | '5k'
    duration_weeks INTEGER NOT NULL DEFAULT 16
        CHECK (duration_weeks BETWEEN 8 AND 24),
    weeks JSONB NOT NULL DEFAULT '[]',
    join_code TEXT UNIQUE,          -- 6-char alphanumeric, null until published
    is_published BOOLEAN NOT NULL DEFAULT false,
    subscriber_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_plan_templates_coach ON plan_templates(coach_id);
CREATE INDEX idx_plan_templates_join_code ON plan_templates(join_code) WHERE join_code IS NOT NULL;

ALTER TABLE plan_templates ENABLE ROW LEVEL SECURITY;

-- Coaches manage their own plan templates
CREATE POLICY "Coaches manage own plan templates" ON plan_templates
    FOR ALL USING (
        coach_id IN (SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text)
        OR auth.uid() IS NULL
    );

-- Any authenticated user can browse published plans (for join code discovery)
CREATE POLICY "Anyone reads published plan templates" ON plan_templates
    FOR SELECT USING (is_published = true OR auth.uid() IS NULL);

CREATE POLICY "Service role full access to plan_templates" ON plan_templates
    FOR ALL USING (auth.role() = 'service_role');

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_plan_templates_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER plan_templates_updated_at
    BEFORE UPDATE ON plan_templates
    FOR EACH ROW
    EXECUTE FUNCTION update_plan_templates_timestamp();


-- ============================================================================
-- 4. COACH-ATHLETE RELATIONSHIPS
-- Tracks which athletes are under which coach.
-- ============================================================================

CREATE TABLE IF NOT EXISTS coach_athlete_relationships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    coach_id UUID NOT NULL REFERENCES coach_profiles(id) ON DELETE CASCADE,
    athlete_user_id TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'active', 'inactive')),
    invited_at TIMESTAMPTZ DEFAULT now(),
    accepted_at TIMESTAMPTZ,
    UNIQUE (coach_id, athlete_user_id)
);

CREATE INDEX idx_coach_athlete_coach ON coach_athlete_relationships(coach_id);
CREATE INDEX idx_coach_athlete_athlete ON coach_athlete_relationships(athlete_user_id);

ALTER TABLE coach_athlete_relationships ENABLE ROW LEVEL SECURITY;

-- Coaches see their own athletes
CREATE POLICY "Coaches view their athletes" ON coach_athlete_relationships
    FOR SELECT USING (
        coach_id IN (SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text)
        OR auth.uid() IS NULL
    );

-- Coaches insert new relationships (inviting athletes)
CREATE POLICY "Coaches invite athletes" ON coach_athlete_relationships
    FOR INSERT WITH CHECK (
        coach_id IN (SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text)
        OR auth.uid() IS NULL
    );

-- Coaches update (deactivate athletes)
CREATE POLICY "Coaches update their athlete relationships" ON coach_athlete_relationships
    FOR UPDATE USING (
        coach_id IN (SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text)
        OR auth.uid() IS NULL
    );

-- Athletes view their own coach relationships
CREATE POLICY "Athletes view their coaches" ON coach_athlete_relationships
    FOR SELECT USING (
        athlete_user_id = auth.uid()::text
        OR auth.uid() IS NULL
    );

-- Athletes accept invites (update status to 'active')
CREATE POLICY "Athletes accept their invites" ON coach_athlete_relationships
    FOR UPDATE USING (
        athlete_user_id = auth.uid()::text
        OR auth.uid() IS NULL
    );

CREATE POLICY "Service role full access to coach_athlete_relationships" ON coach_athlete_relationships
    FOR ALL USING (auth.role() = 'service_role');

-- Deferred policies that reference coach_athlete_relationships
CREATE POLICY "Athletes read linked coaches" ON coach_profiles
    FOR SELECT USING (
        id IN (
            SELECT coach_id FROM coach_athlete_relationships
            WHERE athlete_user_id = auth.uid()::text
        )
        OR auth.uid() IS NULL
    );

CREATE POLICY "Athletes read relevant workout templates" ON workout_templates
    FOR SELECT USING (
        is_public = true
        OR coach_id IN (
            SELECT cp.id FROM coach_profiles cp
            JOIN coach_athlete_relationships car ON car.coach_id = cp.id
            WHERE car.athlete_user_id = auth.uid()::text AND car.status = 'active'
        )
        OR auth.uid() IS NULL
    );


-- ============================================================================
-- 5. ATHLETE PLAN SUBSCRIPTIONS
-- When an athlete subscribes to a plan template, this table records it and
-- links to the generated training_plan record in the existing training_plans table.
-- ============================================================================

CREATE TABLE IF NOT EXISTS athlete_plan_subscriptions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_template_id UUID NOT NULL REFERENCES plan_templates(id) ON DELETE RESTRICT,
    athlete_user_id TEXT NOT NULL,
    training_plan_id UUID REFERENCES training_plans(id) ON DELETE SET NULL,
        -- the actual generated training_plans row for this athlete
    start_date DATE NOT NULL,
    status TEXT NOT NULL DEFAULT 'active'
        CHECK (status IN ('active', 'paused', 'completed', 'dropped')),
    created_at TIMESTAMPTZ DEFAULT now(),
    UNIQUE (plan_template_id, athlete_user_id)
);

CREATE INDEX idx_athlete_subs_athlete ON athlete_plan_subscriptions(athlete_user_id);
CREATE INDEX idx_athlete_subs_plan ON athlete_plan_subscriptions(plan_template_id);

ALTER TABLE athlete_plan_subscriptions ENABLE ROW LEVEL SECURITY;

-- Athletes see their own subscriptions
CREATE POLICY "Athletes view own subscriptions" ON athlete_plan_subscriptions
    FOR SELECT USING (
        athlete_user_id = auth.uid()::text
        OR auth.uid() IS NULL
    );

-- Athletes can insert (subscribe via join code)
CREATE POLICY "Athletes subscribe to plans" ON athlete_plan_subscriptions
    FOR INSERT WITH CHECK (
        athlete_user_id = auth.uid()::text
        OR auth.uid() IS NULL
    );

-- Athletes can update their own (pause/drop)
CREATE POLICY "Athletes update own subscriptions" ON athlete_plan_subscriptions
    FOR UPDATE USING (
        athlete_user_id = auth.uid()::text
        OR auth.uid() IS NULL
    );

-- Coaches see subscriptions to their plans
CREATE POLICY "Coaches view subscriptions to their plans" ON athlete_plan_subscriptions
    FOR SELECT USING (
        plan_template_id IN (
            SELECT id FROM plan_templates
            WHERE coach_id IN (SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text)
        )
        OR auth.uid() IS NULL
    );

CREATE POLICY "Service role full access to athlete_plan_subscriptions" ON athlete_plan_subscriptions
    FOR ALL USING (auth.role() = 'service_role');


-- ============================================================================
-- 6. ADD coach_id TO training_plans (optional link back to template)
-- Lets the app show "Coached by X" when a plan was generated from a template.
-- ============================================================================

ALTER TABLE training_plans
    ADD COLUMN IF NOT EXISTS coach_id UUID REFERENCES coach_profiles(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS plan_template_id UUID REFERENCES plan_templates(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_training_plans_coach ON training_plans(coach_id) WHERE coach_id IS NOT NULL;

-- ============================================================================
-- 7. HELPER FUNCTION — increment_subscriber_count
-- Called by the subscribe-to-plan edge function after successful subscription.
-- ============================================================================

CREATE OR REPLACE FUNCTION increment_subscriber_count(template_id UUID)
RETURNS void AS $$
BEGIN
    UPDATE plan_templates
    SET subscriber_count = subscriber_count + 1
    WHERE id = template_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
