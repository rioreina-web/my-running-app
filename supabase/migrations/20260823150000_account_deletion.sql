-- ============================================================================
-- Account deletion: the audit tombstone.
--
-- WHAT THIS MIGRATION USED TO DO, AND WHY IT NO LONGER DOES
--
-- It used to `CREATE OR REPLACE public.delete_user_account(text)` to fix a
-- live erasure bug: the function's catalog-driven loop filtered
--
--     AND col.data_type IN ('text', 'character varying')
--
-- so seven tables typing `user_id` as `uuid` were skipped silently while the
-- function still reported success — `conversation_messages` among them.
--
-- THAT BUG WAS FIXED IN PRODUCTION ON 2026-08-24 AT 19:00Z, by ledger
-- migration `20260824190000_delete_user_account_uuid_columns`, which does not
-- originate from this repo. Verified against prod the same evening: the
-- discovery query now reads `data_type IN ('text','character varying','uuid')`
-- and uuid columns delete via `%I = $1::uuid`. 59 user-linked tables covered,
-- 0 uncovered.
--
-- That fix is BETTER than the one this migration carried. Both cover uuid,
-- but they differ on which side of the comparison gets cast:
--
--     this repo's version   DELETE ... WHERE %I::text = $1      -- casts COLUMN
--     production's version  DELETE ... WHERE %I = $1::uuid      -- casts PARAM
--
-- Casting the column defeats any index on it; casting the parameter does not.
-- For a one-off erasure that difference is small, but it is real, and there is
-- no reason to trade down.
--
-- So the function definition is GONE from this migration. Re-asserting it here
-- would overwrite the better implementation with the worse one — the same
-- mistake, in SQL, that the stop notice at the top of this PR describes for the
-- edge functions. When the repo is reconciled against production (see
-- docs/repo-prod-drift-2026-08-24.md), the authoritative definition should come
-- from prod, not from here.
--
-- What remains is the one thing production does NOT have: the tombstone table
-- that `delete-account` writes to after a successful erasure.
-- ============================================================================

BEGIN;

-- ── Tombstone ───────────────────────────────────────────────────────────────
-- Holds NO personal data: a hash of the user id, when it happened, and
-- per-table counts. Enough to answer "was this account deleted, and when",
-- which the privacy policy's 30-day completion claim needs, without keeping
-- an identifier for someone who asked to be forgotten.
CREATE TABLE IF NOT EXISTS public.deleted_accounts (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id_hash  TEXT        NOT NULL,
    deleted_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    row_counts    JSONB       NOT NULL DEFAULT '{}'::jsonb,
    storage_note  TEXT
);

COMMENT ON TABLE public.deleted_accounts IS
    'Audit tombstone for completed account deletions. Contains no personal '
    'data — user_id_hash is sha256(user_id), not reversible to an identity.';

-- Hard rule #1: RLS in the same migration. No client policy — operator only.
ALTER TABLE public.deleted_accounts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.deleted_accounts FROM PUBLIC, anon, authenticated;

-- ── Verification ────────────────────────────────────────────────────────────
DO $$
DECLARE
    fn        CONSTANT TEXT := 'public.delete_user_account(text)';
    def       TEXT;
    uncovered TEXT;
BEGIN
    IF has_table_privilege('anon', 'public.deleted_accounts', 'SELECT')
       OR has_table_privilege('authenticated', 'public.deleted_accounts', 'SELECT') THEN
        RAISE EXCEPTION 'deleted_accounts must not be client-readable';
    END IF;

    -- Report on delete_user_account WITHOUT redefining it. The function has no
    -- definition in this repo (it arrived via prod-only ledger version
    -- 20260720120000), so on a fresh local database it simply is not there.
    IF to_regprocedure(fn) IS NULL THEN
        RAISE NOTICE
            'delete_user_account is not present in this database. It exists in '
            'production only; delete-account will fail here until the repo is '
            'reconciled. See docs/repo-prod-drift-2026-08-24.md.';
        RETURN;
    END IF;

    SELECT pg_get_functiondef(to_regprocedure(fn)) INTO def;

    -- The uuid-coverage regression check. Warn rather than fail: this
    -- migration no longer owns the function, so it must not abort a deploy
    -- over an implementation it deliberately declines to overwrite.
    SELECT string_agg(col.table_name, ', ' ORDER BY col.table_name)
    INTO uncovered
    FROM information_schema.columns col
    JOIN information_schema.tables tb
      ON tb.table_schema = col.table_schema
     AND tb.table_name   = col.table_name
     AND tb.table_type   = 'BASE TABLE'
    WHERE col.table_schema = 'public'
      AND col.column_name IN ('user_id', 'athlete_user_id', 'athlete_id')
      AND col.data_type NOT IN ('text', 'character varying', 'uuid')
      AND col.table_name <> 'deleted_accounts';

    IF uncovered IS NOT NULL THEN
        RAISE WARNING
            'delete_user_account may not erase these tables (user column is '
            'neither text nor uuid): %', uncovered;
    END IF;

    IF def !~ 'uuid' THEN
        RAISE WARNING
            'delete_user_account appears not to handle uuid-typed user columns. '
            'Production fixed this in ledger version 20260824190000; if this '
            'database predates that, erasure is silently incomplete.';
    END IF;
END $$;

COMMIT;
