-- ============================================================================
-- mcp_access_tokens — the athlete's key to their own Claude.
--
-- WHY THIS EXISTS (2026-08-19)
--
-- The Ask registry answers ~50 athlete questions with real math over real
-- rows. Every one of those answers is currently reachable only from inside
-- the app. `supabase/functions/mcp` exposes the SAME registry over the Model
-- Context Protocol, so an athlete can connect their own Claude account and
-- ask their training data questions there — with the compute paid for by
-- their Claude subscription, not ours.
--
-- The connector needs to know WHICH athlete is calling. Claude's custom-
-- connector UI cannot send a custom `Authorization` header (anthropics/
-- claude-ai-mcp#112), and it does not speak Supabase JWTs, so the credential
-- travels in the URL path the athlete pastes:
--
--     https://<ref>.supabase.co/functions/v1/mcp/prd_<43 url-safe chars>
--
-- That makes this row a BEARER CREDENTIAL, and the posture follows from it:
--
--   * The plaintext is returned EXACTLY ONCE, by `create_mcp_access_token`,
--     and is never stored. We keep `sha256(token)` and a display prefix.
--     A database dump therefore leaks no working connector URL.
--   * Revoking is a DELETE, not an UPDATE. There is no `revoked_at` to flip
--     back — an athlete who thinks a token leaked should be able to make it
--     permanently dead in one statement, and an UPDATE policy broad enough
--     to set `revoked_at` is also broad enough to unset it.
--   * Tokens expire. 180 days by default, extended on nothing. A connector
--     nobody uses should stop working on its own.
--   * Five active tokens per athlete, enforced in the minting function. The
--     ceiling is not a scarcity measure; it is so a compromised session
--     cannot quietly mint a hundred backdoors.
--
-- WHAT THE TOKEN CAN DO: read. The MCP function runs analyzers, and hard
-- rule "Ask reads" applies there exactly as it does in `ask` — no
-- `coachable_moments`, no `plan_adjustments`, no plan mutation, no writes of
-- any kind beyond the `analysis_queries` audit row. A leaked token exposes
-- the athlete's own training analysis. It cannot change their plan.
--
-- user_id is TEXT to match auth.uid()::text — the schema-wide convention.
-- ============================================================================

BEGIN;

-- gen_random_bytes / digest. Supabase provisions pgcrypto into `extensions`;
-- this is a no-op on a normal project and makes the migration self-contained
-- for a fresh `supabase db reset`.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE TABLE IF NOT EXISTS mcp_access_tokens (
    id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id      TEXT NOT NULL,

    -- Athlete-facing label, so a person with two connectors can tell them
    -- apart ("laptop Claude", "phone").
    name         TEXT NOT NULL DEFAULT 'Claude',

    -- sha256 of the plaintext, lowercase hex. The plaintext is not stored.
    token_hash   TEXT NOT NULL UNIQUE,

    -- First 12 chars of the plaintext ("prd_A7bQ2x"), for display in a
    -- settings list. Not enough to authenticate with; enough to recognise.
    token_prefix TEXT NOT NULL,

    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- Written best-effort by the MCP function on each authenticated call.
    -- This is the athlete's own abuse signal: a token they have not used in
    -- a month that shows traffic is a token to delete.
    last_used_at TIMESTAMPTZ,
    expires_at   TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '180 days'),

    CONSTRAINT mcp_access_tokens_hash_chk
        CHECK (token_hash ~ '^[0-9a-f]{64}$'),
    CONSTRAINT mcp_access_tokens_name_chk
        CHECK (char_length(name) BETWEEN 1 AND 60)
);

COMMENT ON TABLE mcp_access_tokens IS
    'Bearer credentials for the MCP connector (supabase/functions/mcp). Hash '
    'only — the plaintext is returned once by create_mcp_access_token() and '
    'never persisted. Read-only scope: the token grants the analyzer registry '
    'and nothing that writes.';

COMMENT ON COLUMN mcp_access_tokens.token_hash IS
    'sha256(plaintext) as lowercase hex. The MCP function hashes the path '
    'segment and looks it up here; there is no reverse path to the token.';

-- The hot path is exactly one query: hash → row, then an expiry check in the
-- predicate. The UNIQUE constraint on `token_hash` already provides that
-- index, so there is no second one to build. (A partial index predicated on
-- `expires_at > now()` would be the obvious optimisation and Postgres will
-- reject it — index predicates must be IMMUTABLE, and `now()` is not.)

CREATE INDEX IF NOT EXISTS idx_mcp_access_tokens_user
    ON mcp_access_tokens (user_id, created_at DESC);

-- ── RLS ─────────────────────────────────────────────────────────────────
--
-- Athletes read and delete their own rows. They do NOT insert directly —
-- minting goes through the SECURITY DEFINER function below, which is what
-- guarantees the token was generated with `gen_random_bytes` and not chosen
-- by the client. There is deliberately no UPDATE policy.

ALTER TABLE mcp_access_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Athletes read own mcp tokens" ON mcp_access_tokens
    FOR SELECT
    USING (user_id = auth.uid()::text);

CREATE POLICY "Athletes delete own mcp tokens" ON mcp_access_tokens
    FOR DELETE
    USING (user_id = auth.uid()::text);

CREATE POLICY "Service role full access to mcp_access_tokens" ON mcp_access_tokens
    FOR ALL
    USING (auth.jwt() ->> 'role' = 'service_role')
    WITH CHECK (auth.jwt() ->> 'role' = 'service_role');

-- ── Minting ─────────────────────────────────────────────────────────────

/**
 * Mint one connector token for the calling athlete and return the plaintext.
 *
 * THIS IS THE ONLY TIME THE PLAINTEXT EXISTS. The caller must show it to the
 * athlete immediately (as the full connector URL) and must not persist it.
 * Losing it means deleting the row and minting again — which is the correct
 * cost, because the alternative is a recoverable secret.
 *
 * Returns (id, token, expires_at). `token` is `prd_` + 43 url-safe base64
 * characters over 32 random bytes — 256 bits, which is not guessable and is
 * short enough to survive being pasted into a settings field by hand.
 */
CREATE OR REPLACE FUNCTION create_mcp_access_token(p_name TEXT DEFAULT 'Claude')
RETURNS TABLE (id UUID, token TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
-- Pinned search_path: a SECURITY DEFINER function that resolves `digest` or
-- `mcp_access_tokens` through a caller-controlled path is a privilege
-- escalation, not a convenience.
SET search_path = public, extensions
AS $$
DECLARE
    v_user   TEXT := auth.uid()::text;
    v_token  TEXT;
    v_active INTEGER;
    v_name   TEXT := COALESCE(NULLIF(btrim(p_name), ''), 'Claude');
BEGIN
    IF v_user IS NULL THEN
        RAISE EXCEPTION 'create_mcp_access_token requires an authenticated athlete'
            USING ERRCODE = '28000';
    END IF;

    -- Expired rows are dead weight and they hide the real count. Reap the
    -- athlete's own before enforcing the ceiling.
    DELETE FROM mcp_access_tokens t
     WHERE t.user_id = v_user AND t.expires_at <= now();

    SELECT count(*) INTO v_active
      FROM mcp_access_tokens t
     WHERE t.user_id = v_user;

    IF v_active >= 5 THEN
        RAISE EXCEPTION 'Connector limit reached (5). Delete an existing connector first.'
            USING ERRCODE = '54000';
    END IF;

    -- url-safe base64 over 32 bytes, no padding. `encode` wraps at 76 chars
    -- for longer inputs; 32 bytes is 44 so there is nothing to wrap, but the
    -- newline strip stays as a guard against a future length change.
    v_token := 'prd_' || rtrim(
        translate(
            replace(encode(extensions.gen_random_bytes(32), 'base64'), E'\n', ''),
            '+/', '-_'
        ),
        '='
    );

    RETURN QUERY
    INSERT INTO mcp_access_tokens (user_id, name, token_hash, token_prefix)
    VALUES (
        v_user,
        v_name,
        encode(extensions.digest(v_token, 'sha256'), 'hex'),
        left(v_token, 12)
    )
    RETURNING mcp_access_tokens.id, v_token, mcp_access_tokens.expires_at;
END;
$$;

COMMENT ON FUNCTION create_mcp_access_token(TEXT) IS
    'Mint an MCP connector token for the calling athlete. Returns the '
    'plaintext ONCE — it is stored only as sha256. Max 5 active per athlete.';

REVOKE ALL ON FUNCTION create_mcp_access_token(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_mcp_access_token(TEXT) TO authenticated;

-- ── Audit ───────────────────────────────────────────────────────────────
--
-- The MCP function logs to `analysis_queries` exactly as `ask` does, so
-- "what do people actually ask?" stays one query rather than two. Questions
-- arriving over the connector are a fourth source.
--
-- `mode` needs no change: a connector call always resolves to a named tool,
-- so it is always 'analyzed'. There is no Layer-0 router and therefore no
-- 'prose' or 'ambiguous' outcome to record.
--
-- `annotated` is always FALSE for these rows and that is not a bug: Layer 2
-- happens inside the athlete's Claude, where `narration-guard.ts` cannot
-- reach it. A connector row means "these facts were served"; it makes no
-- claim about what was said over them. Keep that in mind before reading
-- `guard_tripped` rates across sources — the denominator is app rows only.

ALTER TABLE analysis_queries
    DROP CONSTRAINT IF EXISTS analysis_queries_source_chk;

ALTER TABLE analysis_queries
    ADD CONSTRAINT analysis_queries_source_chk
    CHECK (source IN ('chip', 'text', 'followup', 'mcp'));

COMMIT;
