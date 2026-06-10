-- ============================================================================
-- 20260528140000_user_preferences_and_pace_view.sql
--
-- User-controllable toggle for default pace view (raw / adjusted / auto).
--
-- Three states:
--   raw       — always show what the watch said
--   adjusted  — always show heat-adjusted neutral-equivalent
--   auto      — system picks based on climate exposure (default)
--
-- The UI calls effective_pace_view(uid) and gets back 'raw' or 'adjusted'
-- (auto resolves to one or the other on read). Athletes can override
-- explicitly from settings; default for new users is 'auto', which means
-- Texas/Florida/etc. users get adjusted-first without configuring anything,
-- and PNW/Boston/etc. users get raw-first without configuring anything.
-- ============================================================================

-- ── Generic user_preferences key/value store ────────────────────────────────
-- Lightweight settings table. NOT a substitute for the future user_profiles
-- consolidation (Phase 5 of Maya's roadmap) — that work owns identity,
-- demographics, and health data. This table owns transient app preferences.

CREATE TABLE user_preferences (
    user_id    TEXT NOT NULL,
    key        TEXT NOT NULL,
    value      JSONB NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    PRIMARY KEY (user_id, key)
);

COMMENT ON TABLE user_preferences IS
    'Lightweight key/value app preferences. Keys are namespaced strings '
    '(e.g. ''pace_view_default''). Values are JSONB so structured settings '
    'are possible later without schema churn.';

CREATE INDEX idx_user_preferences_user
    ON user_preferences (user_id);

ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY;

CREATE POLICY "rls_user_preferences_all" ON user_preferences
    FOR ALL USING (user_id = auth.uid()::text)
    WITH CHECK (user_id = auth.uid()::text);

-- ── Effective pace view resolver ────────────────────────────────────────────
-- Returns 'raw' or 'adjusted' for a given user, resolving 'auto' against
-- their recent climate exposure. Stable function — same input gives same
-- output within a transaction.

CREATE OR REPLACE FUNCTION effective_pace_view(uid TEXT)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    pref      TEXT;
    hot_share NUMERIC;
BEGIN
    -- 1. Explicit preference, if set
    SELECT value #>> '{}' INTO pref
    FROM user_preferences
    WHERE user_id = uid AND key = 'pace_view_default';

    IF pref = 'raw' OR pref = 'adjusted' THEN
        RETURN pref;
    END IF;

    -- 2. Auto (or unset) — compute from last 60 days of lap weather.
    -- Threshold: >30% of recent laps in 'hot' or above → default 'adjusted'.
    -- Athletes who train in genuinely hot climates land on adjusted; those
    -- with occasional summer warmth still see raw.
    SELECT COALESCE(
        COUNT(*) FILTER (WHERE heat_category IN ('hot','very_hot','dangerous'))::numeric
            / NULLIF(COUNT(*), 0),
        0
    ) INTO hot_share
    FROM running_workout_laps
    WHERE user_id = uid
      AND lap_start_at >= NOW() - INTERVAL '60 days'
      AND heat_category IS NOT NULL;

    IF hot_share > 0.30 THEN
        RETURN 'adjusted';
    ELSE
        RETURN 'raw';
    END IF;
END;
$$;

COMMENT ON FUNCTION effective_pace_view(TEXT) IS
    'Resolves the user''s effective pace view. Returns ''raw'' or ''adjusted''. '
    'If the user has set ''pace_view_default'' to one of those values explicitly, '
    'returns that. Otherwise (auto / unset), returns ''adjusted'' if >30% of the '
    'user''s last 60 days of laps were in a hot+ category, else ''raw''.';

-- ── Convenience setter (lets app code just call set_pace_view_default) ──────

CREATE OR REPLACE FUNCTION set_pace_view_default(new_value TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
BEGIN
    IF new_value NOT IN ('raw', 'adjusted', 'auto') THEN
        RAISE EXCEPTION 'pace_view_default must be one of: raw, adjusted, auto';
    END IF;

    INSERT INTO user_preferences (user_id, key, value)
    VALUES (auth.uid()::text, 'pace_view_default', to_jsonb(new_value))
    ON CONFLICT (user_id, key) DO UPDATE
        SET value = EXCLUDED.value,
            updated_at = now();
END;
$$;

COMMENT ON FUNCTION set_pace_view_default(TEXT) IS
    'Upserts the calling user''s pace_view_default preference. '
    'Accepts ''raw'', ''adjusted'', or ''auto''. RLS-safe via auth.uid().';
