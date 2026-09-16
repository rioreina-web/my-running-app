-- ============================================================================
-- Per-athlete consent for sending HealthKit-derived biometrics to an AI model.
--
-- App Review 5.1.3 requires explicit user consent before HealthKit data goes
-- to a third party. The HealthKit permission prompt is consent to READ, not
-- consent to FORWARD, and Apple treats those as different asks.
--
-- SCOPE — read this before building anything on top of it.
--
-- As of 2026-08-24 NO HealthKit-derived biometric reaches a model. Verified,
-- not assumed: `_shared/athlete-state.ts` reads 14 tables and daily_biometrics
-- is not among them; `trends-insights/detectorsC.ts` is a scaffold whose own
-- header says "No daily_biometrics yet → all hidden" and which returns an
-- empty card list; the only live readers are `trends-timeline` (deterministic,
-- no LLM) and the two writers, `vital-webhook` and `ingest-biometrics`.
--
-- So this migration is deliberately AHEAD of the feature. It exists so that
-- when detectorsC is implemented — the one place explicitly waiting on this
-- capture path — the gate is already there and already enforced by
-- `aiBiometricsAllowed()` in `_shared/aiSourcePolicy.ts`, which fails closed
-- on a missing row. The alternative is building the capture path first and
-- remembering to add consent afterwards, which is how this class of thing
-- gets shipped without it.
--
-- No iOS consent UI ships with this, on purpose: a consent sheet for a data
-- flow that does not exist would be asking the athlete to approve nothing.
-- The UI is owed at the same time as detectorsC, not before.
--
-- WITHDRAWAL is why consent is a nullable timestamp rather than a boolean:
-- setting it back to NULL is a complete withdrawal, and the fail-closed
-- helper needs no separate revoked flag to honour it. Garmin's terms require
-- withdrawal to be as easy as granting, and Terra ingestion will inherit that
-- obligation.
-- ============================================================================

BEGIN;

ALTER TABLE athlete_settings
    ADD COLUMN IF NOT EXISTS ai_health_consent_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS ai_health_consent_version TEXT;

-- A version without a timestamp is unattributable, and a timestamp without a
-- version means you cannot tell WHICH disclosure the athlete agreed to when
-- the wording changes. Require them together or not at all.
ALTER TABLE athlete_settings
    DROP CONSTRAINT IF EXISTS athlete_settings_ai_health_consent_paired;
ALTER TABLE athlete_settings
    ADD CONSTRAINT athlete_settings_ai_health_consent_paired
    CHECK ((ai_health_consent_at IS NULL AND ai_health_consent_version IS NULL)
           OR (ai_health_consent_at IS NOT NULL AND ai_health_consent_version IS NOT NULL));

COMMENT ON COLUMN athlete_settings.ai_health_consent_at IS
    'When the athlete consented to HealthKit-derived biometrics being sent to '
    'an AI provider (App Review 5.1.3). NULL = no consent; set back to NULL to '
    'withdraw. Enforced by aiBiometricsAllowed() in _shared/aiSourcePolicy.ts, '
    'which fails closed. No biometric currently reaches a model — this gate is '
    'in place ahead of trends-insights/detectorsC.';
COMMENT ON COLUMN athlete_settings.ai_health_consent_version IS
    'Which disclosure wording was agreed to, so a later reword can re-ask '
    'only the athletes who saw the old one.';

COMMIT;
