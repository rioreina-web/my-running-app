-- ============================================================================
-- coachable_moments — V1 of the real-time coach attention surface.
--
-- A row represents a single piece of attention a coach should give to one
-- athlete, right now. Created by the evaluate-coachable-moment edge function
-- when V1 trigger rules match. Coach handles or dismisses from the dashboard.
--
-- Spec: docs/specs/coachable_moment.md
--
-- V1 invariants:
--   - One athlete per row (no multi-athlete patterns)
--   - Templated summary (no LLM-generated text)
--   - No athlete-facing surface (coach-only)
--   - No expiration / snooze / re-fire suppression
-- ============================================================================

CREATE TABLE IF NOT EXISTS coachable_moments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Subjects
    athlete_user_id TEXT NOT NULL,                              -- auth.uid()::text of the athlete
    coach_id UUID NOT NULL REFERENCES coach_profiles(id) ON DELETE CASCADE,

    -- When and why
    triggered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    rule_id TEXT NOT NULL,                                      -- e.g. 'load_spike_plus_injury'

    -- What
    severity TEXT NOT NULL
        CHECK (severity IN ('low', 'med', 'high')),
    action_type TEXT NOT NULL
        CHECK (action_type IN ('send_check_in', 'suggest_deload', 'recommend_evaluation', 'monitor')),
    summary TEXT NOT NULL,                                      -- templated, ~2 sentences
    source_log_ids UUID[] NOT NULL DEFAULT ARRAY[]::UUID[],     -- training_log ids cited as evidence

    -- Lifecycle
    status TEXT NOT NULL DEFAULT 'open'
        CHECK (status IN ('open', 'handled', 'dismissed')),
    handled_at TIMESTAMPTZ,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============================================================================
-- Indexes
-- ============================================================================

-- Primary read path: coach inbox sorted by recency, filtered by status
CREATE INDEX IF NOT EXISTS idx_coachable_moments_coach_status
    ON coachable_moments(coach_id, status, triggered_at DESC);

-- Athlete detail lookup
CREATE INDEX IF NOT EXISTS idx_coachable_moments_athlete
    ON coachable_moments(athlete_user_id, triggered_at DESC);

-- Rule-firing analytics (which rules fire / get dismissed)
CREATE INDEX IF NOT EXISTS idx_coachable_moments_rule
    ON coachable_moments(rule_id, status, triggered_at DESC);

-- ============================================================================
-- Lifecycle trigger: stamp handled_at when status leaves 'open'
-- ============================================================================

CREATE OR REPLACE FUNCTION set_coachable_moment_handled_at()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.status <> 'open' AND OLD.status = 'open' THEN
        NEW.handled_at := now();
    ELSIF NEW.status = 'open' THEN
        NEW.handled_at := NULL;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS coachable_moments_handled_at ON coachable_moments;
CREATE TRIGGER coachable_moments_handled_at
    BEFORE UPDATE OF status ON coachable_moments
    FOR EACH ROW
    EXECUTE FUNCTION set_coachable_moment_handled_at();

-- ============================================================================
-- RLS — coach-only in V1.
--
-- Reads use the existing current_coach_id() SECURITY DEFINER helper
-- (created in 20260311120000_fix_coach_rls_recursion.sql) to avoid recursion
-- through coach_profiles.
--
-- Writes (INSERTs) come from the evaluate-coachable-moment edge function
-- using the service role; no client-side INSERT policy is granted.
-- ============================================================================

ALTER TABLE coachable_moments ENABLE ROW LEVEL SECURITY;

-- Coaches see their own athletes' moments
DROP POLICY IF EXISTS "Coaches view own coachable_moments" ON coachable_moments;
CREATE POLICY "Coaches view own coachable_moments" ON coachable_moments
    FOR SELECT USING (
        coach_id = current_coach_id()
        OR auth.uid() IS NULL
    );

-- Coaches update status (handle / dismiss) on their own moments
DROP POLICY IF EXISTS "Coaches update own coachable_moments" ON coachable_moments;
CREATE POLICY "Coaches update own coachable_moments" ON coachable_moments
    FOR UPDATE USING (
        coach_id = current_coach_id()
        OR auth.uid() IS NULL
    );

-- Service role full access for the edge function evaluator
DROP POLICY IF EXISTS "Service role full access to coachable_moments" ON coachable_moments;
CREATE POLICY "Service role full access to coachable_moments" ON coachable_moments
    FOR ALL USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Note: deliberately no INSERT or DELETE policy for authenticated/anon roles.
-- All inserts go through the service-role edge function.
-- Note: deliberately no athlete-side policy. Athlete UI is V2.
