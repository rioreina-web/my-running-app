-- ============================================================================
-- Daily biometrics — nocturnal HRV, resting HR, sleep duration from Garmin/Vital
--
-- Landing table for the `daily.data.sleep.*` Junction events the vital-webhook
-- now handles. One row per (athlete, calendar date, source). Device-written
-- only: the webhook writes with the service role (bypasses RLS); athletes read
-- their own. Mirrors the vital_credentials / strava_credentials RLS model
-- (hard rule #4: no client write path to service-ingested data).
--
-- Column choices follow docs/specs/recovery-trend-v2-2026-07-27.md §5. Tier-0
-- fields (sleep stages, sleep efficiency, Garmin Sleep Score, stress rollup) are
-- deliberately NOT captured — they are too noisy to read (v2 §7.4) and storing
-- them invites use. Total sleep time is kept as Tier-3 annotation only.
--
-- user_id is TEXT to match auth.uid()::text — the schema-wide convention.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS daily_biometrics (
    user_id           TEXT NOT NULL,
    date              DATE NOT NULL,          -- sleep.calendar_date (YYYY-MM-DD)
    source            TEXT NOT NULL,          -- 'garmin'

    vital_sleep_id    TEXT,                   -- sleep.id (restatement dedup)
    sleep_state       TEXT,                   -- 'tentative' | 'confirmed'

    hrv_rmssd         NUMERIC,                -- sleep.average_hrv (ms)   — Tier 2
    resting_hr        NUMERIC,                -- sleep.hr_resting (bpm)   — Tier 2
    hr_lowest         NUMERIC,                -- sleep.hr_lowest (bpm)    — context
    sleep_total_min   INTEGER,                -- sleep.total / 60         — Tier 3
    respiratory_rate  NUMERIC,                -- sleep.respiratory_rate   — context

    device_model      TEXT,                   -- drift detection (v2 §3b)
    firmware_version  TEXT,                   -- drift detection
    app_version       TEXT,                   -- drift detection

    created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, date, source)
);

COMMENT ON TABLE daily_biometrics IS
    'Per-night Garmin biometrics via Junction/Vital daily.data.sleep events. '
    'Service-role write (vital-webhook), athlete read-only. Feeds the recovery '
    'ledger Overnight factor (HRV paired with resting HR, weekly-aggregated) and '
    'the C0 card. Tier-0 fields intentionally omitted — see recovery-trend-v2 §7.4.';

-- Baseline queries scan a single athlete's trailing window by date.
CREATE INDEX IF NOT EXISTS daily_biometrics_user_date_idx
    ON daily_biometrics (user_id, date DESC);

ALTER TABLE daily_biometrics ENABLE ROW LEVEL SECURITY;

-- Athletes may READ their own nights. All writes go through the service-role
-- webhook (which bypasses RLS) — no client insert/update/delete path.
CREATE POLICY "athletes read own biometrics"
    ON daily_biometrics
    FOR SELECT
    USING (user_id = (auth.uid())::text);

COMMIT;
