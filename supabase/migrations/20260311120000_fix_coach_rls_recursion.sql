-- ============================================================================
-- Fix RLS infinite recursion in coach_profiles / coach_athlete_relationships.
--
-- Problem: coach_profiles has a policy that queries coach_athlete_relationships,
-- and coach_athlete_relationships has policies that query coach_profiles.
-- This creates infinite recursion.
--
-- Fix: Use a SECURITY DEFINER function to look up the coach's UUID without
-- triggering RLS on coach_profiles.
-- ============================================================================

-- Helper: returns the coach_profiles.id for the current authenticated user,
-- bypassing RLS (SECURITY DEFINER runs as the function owner).
CREATE OR REPLACE FUNCTION current_coach_id()
RETURNS UUID AS $$
    SELECT id FROM coach_profiles WHERE user_id = auth.uid()::text LIMIT 1;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- ============================================================================
-- Drop and recreate policies that caused recursion
-- ============================================================================

-- coach_athlete_relationships: replace coach_id subquery with the helper
DROP POLICY IF EXISTS "Coaches view their athletes" ON coach_athlete_relationships;
CREATE POLICY "Coaches view their athletes" ON coach_athlete_relationships
    FOR SELECT USING (
        coach_id = current_coach_id()
        OR auth.uid() IS NULL
    );

DROP POLICY IF EXISTS "Coaches invite athletes" ON coach_athlete_relationships;
CREATE POLICY "Coaches invite athletes" ON coach_athlete_relationships
    FOR INSERT WITH CHECK (
        coach_id = current_coach_id()
        OR auth.uid() IS NULL
    );

DROP POLICY IF EXISTS "Coaches update their athlete relationships" ON coach_athlete_relationships;
CREATE POLICY "Coaches update their athlete relationships" ON coach_athlete_relationships
    FOR UPDATE USING (
        coach_id = current_coach_id()
        OR auth.uid() IS NULL
    );

-- workout_templates: same fix
DROP POLICY IF EXISTS "Coaches manage own workout templates" ON workout_templates;
CREATE POLICY "Coaches manage own workout templates" ON workout_templates
    FOR ALL USING (
        coach_id = current_coach_id()
        OR auth.uid() IS NULL
    );

DROP POLICY IF EXISTS "Athletes read relevant workout templates" ON workout_templates;
CREATE POLICY "Athletes read relevant workout templates" ON workout_templates
    FOR SELECT USING (
        is_public = true
        OR coach_id IN (
            SELECT car.coach_id FROM coach_athlete_relationships car
            WHERE car.athlete_user_id = auth.uid()::text AND car.status = 'active'
        )
        OR auth.uid() IS NULL
    );

-- plan_templates: same fix
DROP POLICY IF EXISTS "Coaches manage own plan templates" ON plan_templates;
CREATE POLICY "Coaches manage own plan templates" ON plan_templates
    FOR ALL USING (
        coach_id = current_coach_id()
        OR auth.uid() IS NULL
    );
