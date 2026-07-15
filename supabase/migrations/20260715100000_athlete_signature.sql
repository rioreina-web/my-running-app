-- ============================================================================
-- 20260709120000_athlete_signature.sql
--
-- Athlete Signature — storage for the pattern-mining layer of the AI feedback
-- loop. Spec: outputs/ai-feedback-loop-athlete-signature-addendum-2026-07-07.md
-- Pilot validation: outputs/signature-miner-pilot-rio-2026-07-07.md
--
-- Two tables:
--   athlete_signature_observations — one row per discovered pattern per
--     athlete (unique on user_id + pattern_key). Every row carries its
--     evidence JSONB (n, base/conditional stats, window, example workout ids)
--     so "why does the AI believe this?" is answerable in one query.
--   athlete_signature_events — append-only audit of every status/confidence
--     transition (mirrors athlete_ai_profile_events pattern in the base spec).
--
-- S1 ships DARK: the weekly miner writes rows, nothing surfaces to athletes
-- or prompts until the precision review passes (addendum §9). Hence RLS here
-- is deliberately minimal: athlete SELECT (Model of You reads later),
-- service-role everything else. Coach read/vet policies arrive in S3.
--
-- Hard rules honored: RLS in same migration (#1); athlete ids TEXT matching
-- auth.uid()::text; append-only (#5); prod apply only via `supabase db push`
-- from a committed SHA (#9).
-- ============================================================================

-- ── Observations ─────────────────────────────────────────────────────────────

CREATE TABLE athlete_signature_observations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id     TEXT NOT NULL,

    -- Canonical machine form, e.g. 'rest_day->work_pace@+1d' or
    -- 'heat_oppressive->work_hr@0d'. Unique per athlete: re-detections
    -- UPDATE the row (evidence refresh), never duplicate it.
    pattern_key TEXT NOT NULL,

    category TEXT NOT NULL CHECK (category IN (
        'performance', 'recovery', 'load_response',
        'mood', 'niggle_assoc', 'schedule', 'environment'
    )),

    -- Deterministic template phrasing in S1 (no LLM in the dark run).
    -- S2 replaces this with phrase-signature-observation output.
    statement TEXT NOT NULL,

    -- { n_true, n_false, metric, mean_true, mean_false, effect_sd,
    --   window_start, window_end, example_log_ids: uuid[], last_instance_at }
    evidence JSONB NOT NULL,

    confidence TEXT NOT NULL CHECK (confidence IN ('low', 'medium', 'high')),

    status TEXT NOT NULL DEFAULT 'candidate' CHECK (status IN (
        'candidate',          -- passed gates once; needs re-confirmation
        'active',             -- re-confirmed on a later run with new data
        'fading',             -- active but unsupported for 8+ weeks
        'refuted',            -- counter-evidence; suppressed
        'athlete_dismissed',  -- sticky suppression (Model of You, S2+)
        'coach_confirmed',    -- pinned by coach (S3)
        'coach_dismissed'     -- sticky suppression by coach (S3)
    )),

    coach_id   UUID REFERENCES coach_profiles(id),
    coach_note TEXT,

    first_detected_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_confirmed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (user_id, pattern_key)
);

CREATE INDEX idx_signature_obs_user_status
    ON athlete_signature_observations (user_id, status);

-- The injection query (S2): "active-ish observations for this athlete,
-- strongest first".
CREATE INDEX idx_signature_obs_user_active
    ON athlete_signature_observations (user_id, confidence, last_confirmed_at DESC)
    WHERE status IN ('active', 'coach_confirmed');

-- ── Events (append-only audit) ───────────────────────────────────────────────

CREATE TABLE athlete_signature_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    user_id        TEXT NOT NULL,
    observation_id UUID NOT NULL
        REFERENCES athlete_signature_observations(id) ON DELETE CASCADE,
    pattern_key    TEXT NOT NULL,

    field     TEXT NOT NULL,   -- 'status' | 'confidence' | 'evidence'
    old_value TEXT,
    new_value TEXT,

    source TEXT NOT NULL CHECK (source IN ('miner', 'athlete', 'coach')),
    actor_id TEXT,             -- coach UUID / athlete uid; NULL for miner

    -- Miner transitions: which rule run + counts caused this.
    evidence JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_signature_events_user
    ON athlete_signature_events (user_id, created_at DESC);
CREATE INDEX idx_signature_events_observation
    ON athlete_signature_events (observation_id, created_at DESC);

-- ── updated_at maintenance ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION set_signature_observation_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
    NEW.updated_at := now();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_signature_obs_updated_at
    BEFORE UPDATE ON athlete_signature_observations
    FOR EACH ROW
    EXECUTE FUNCTION set_signature_observation_updated_at();

-- ── RLS ──────────────────────────────────────────────────────────────────────
-- All writes come from the mine-athlete-signature edge function (service
-- role); no client-side INSERT/UPDATE/DELETE. Athlete dismissal (S2) and
-- coach vetting (S3) go through service-role edge functions too, keeping the
-- write path single and auditable.

ALTER TABLE athlete_signature_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE athlete_signature_events       ENABLE ROW LEVEL SECURITY;

-- Athletes read their own signature (Model of You "Patterns I've noticed").
CREATE POLICY "Athletes view own signature observations"
    ON athlete_signature_observations
    FOR SELECT USING (user_id = auth.uid()::text);

CREATE POLICY "Athletes view own signature events"
    ON athlete_signature_events
    FOR SELECT USING (user_id = auth.uid()::text);

-- Service role full access (miner + future dismiss/vet functions).
CREATE POLICY "Service role full access to signature observations"
    ON athlete_signature_observations
    FOR ALL USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "Service role full access to signature events"
    ON athlete_signature_events
    FOR ALL USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- Note: deliberately no coach policies yet — coach read/vet ships in S3 with
-- `coach_id = current_coach_id()` policies (hard rule #6), alongside the
-- portal card. Adding them here would grant reads to a surface that doesn't
-- exist and can't be tested.

COMMENT ON TABLE athlete_signature_observations IS
    'Per-athlete training patterns mined from history (AI feedback loop, athlete-signature layer). S1: dark — written by the weekly miner, not yet surfaced.';
COMMENT ON TABLE athlete_signature_events IS
    'Append-only audit of signature observation transitions. Answers "why did the AI start/stop believing this?"';
