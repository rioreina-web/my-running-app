-- Coach workout read cache (redesign 2026-07-16, §3 row 9 / §5).
--
-- One AI observation per key session, generated on demand by the
-- `coach-workout-read` edge function and rendered at the foot of the coach
-- WorkoutDrawer. Cached per training_log so a drawer re-open is free and the
-- LLM only runs when the coach taps "generate".
--
-- Follows the coachable_moments pattern (hard rule #4): all inserts go through
-- the service-role edge function — no client INSERT policy. Coaches read their
-- own athletes' rows via current_coach_id() (the SECURITY DEFINER helper from
-- 20260311120000_fix_coach_rls_recursion.sql — never a direct coach_profiles
-- subquery, which recurses).

CREATE TABLE IF NOT EXISTS coach_workout_reads (
    id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    training_log_id   UUID NOT NULL REFERENCES training_logs(id) ON DELETE CASCADE,
    athlete_user_id   TEXT NOT NULL,                                   -- auth.uid()::text of the athlete
    coach_id          UUID NOT NULL REFERENCES coach_profiles(id) ON DELETE CASCADE,
    body              TEXT NOT NULL,                                   -- 3-4 sentence observation
    question          TEXT NOT NULL,                                   -- one soft question
    model             TEXT,                                            -- e.g. 'gemini-2.5-flash'
    prompt_version    TEXT NOT NULL DEFAULT 'coach-workout-read.v1',
    generated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    -- One cached read per session. Re-generation upserts on this key.
    CONSTRAINT coach_workout_reads_training_log_unique UNIQUE (training_log_id)
);

CREATE INDEX IF NOT EXISTS idx_coach_workout_reads_coach
    ON coach_workout_reads(coach_id, generated_at DESC);
CREATE INDEX IF NOT EXISTS idx_coach_workout_reads_athlete
    ON coach_workout_reads(athlete_user_id);

ALTER TABLE coach_workout_reads ENABLE ROW LEVEL SECURITY;

-- Coaches read their own athletes' reads. No `auth.uid() IS NULL` fallback:
-- the anon key ships in the app, so that branch is an anon read hole, not a
-- service-role path (service_role bypasses RLS via BYPASSRLS and does not
-- need a policy branch). Scoped `TO authenticated` so anon is excluded outright.
DROP POLICY IF EXISTS "Coaches view own coach_workout_reads" ON coach_workout_reads;
CREATE POLICY "Coaches view own coach_workout_reads" ON coach_workout_reads
    FOR SELECT TO authenticated
    USING (coach_id = current_coach_id());

-- Service role full access for the edge-function generator (all writes).
DROP POLICY IF EXISTS "Service role full access to coach_workout_reads" ON coach_workout_reads;
CREATE POLICY "Service role full access to coach_workout_reads" ON coach_workout_reads
    FOR ALL USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Note: deliberately no INSERT/UPDATE/DELETE policy for authenticated/anon
-- roles. All writes go through the service-role edge function (hard rule #4).

COMMENT ON TABLE coach_workout_reads IS
    'Cached AI observation per key session for the coach WorkoutDrawer. Written only by the coach-workout-read edge function (service role); coaches SELECT their own via current_coach_id().';
