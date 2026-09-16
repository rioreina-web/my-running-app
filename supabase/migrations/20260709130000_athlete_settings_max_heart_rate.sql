-- athlete_settings — account-scoped max HR for HR-zone scaling
--
-- The iOS workout view scales HR zones to the athlete's max HR. That value has
-- lived only in this device's UserDefaults (@AppStorage "userMaxHR"), so it
-- didn't follow the athlete across devices. This adds the account-scoped home
-- for it: iOS pushes on change (AthleteSettingsService.saveMaxHR) and pulls at
-- launch (syncMaxHRFromServer) into the local cache.
--
-- Nullable: NULL = "not set" → the client falls back to the observed max from
-- the athlete's own lap data (no hardcoded default). Additive column; RLS is
-- unchanged — the existing user-owned athlete_settings policies
-- (20260615210000) already cover every column on the row.
--
-- Append-only migration; deploy via `supabase db push` from a committed SHA.

ALTER TABLE public.athlete_settings
    ADD COLUMN IF NOT EXISTS max_heart_rate INTEGER
        CHECK (max_heart_rate IS NULL OR (max_heart_rate BETWEEN 100 AND 240));

COMMENT ON COLUMN public.athlete_settings.max_heart_rate IS
    'Athlete-set max HR (bpm) driving HR-zone scaling in the workout view. '
    'NULL = use the observed max from the athlete''s lap data. Set from iOS '
    'Settings -> Training; synced across devices via AthleteSettingsService.';
