-- ============================================================================
-- Account deletion: erase every row belonging to one athlete, plus a tombstone
-- for the audit trail.
--
-- Why this exists: `docs/legal/privacy-policy.md` promises twice that an
-- athlete "can delete your account and your data any time" and points at
-- in-app settings — and no deletion path existed anywhere in the codebase.
-- Apple App Store 5.1.1(v) also requires in-app account deletion for any app
-- that offers account creation.
--
-- Why the table list is DISCOVERED rather than hardcoded:
-- production carries user-linked tables that have no definition in this repo
-- (body_mentions, and the ad-hoc _backup_* / _dup_cleanup_* copies of
-- training_logs). A list written from the migration history would silently
-- skip exactly the tables most likely to be forgotten — which is the failure
-- mode that makes an erasure promise untrue. So the function reads
-- pg_catalog at run time and covers whatever is actually there, including
-- tables added ad-hoc after this migration ships.
--
-- Storage is NOT handled here. Deleting rows from `storage.objects` leaves the
-- underlying file in the object store; only the Storage API removes bytes. The
-- `delete-account` edge function does that part before calling this function.
--
-- Scope note: this deletes the athlete's own rows. Rows that belong to a coach
-- ABOUT this athlete (coach_notes.athlete_user_id, coachable_moments, the
-- relationship row) carry the athlete's user id and are therefore matched and
-- deleted too, which is the correct reading of an erasure request.
-- ============================================================================

BEGIN;

-- ── Tombstone ───────────────────────────────────────────────────────────────
-- Deliberately holds NO personal data: a salted hash of the user id, when it
-- happened, and per-table row counts. Enough to answer "was this account
-- deleted, and when", which the policy's 30-day completion claim needs, without
-- keeping an identifier for someone who asked to be forgotten.
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

-- Hard rule #1: RLS in the same migration. No client policy at all — this is
-- service-role/operator only.
ALTER TABLE public.deleted_accounts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.deleted_accounts FROM PUBLIC, anon, authenticated;

-- ── delete_user_data ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_user_data(p_user_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
    rec         RECORD;
    counts      JSONB := '{}'::jsonb;
    deleted     BIGINT;
    pending     INT;
    progressed  BOOLEAN;
    pass        INT := 0;
    remaining   TEXT[] := '{}';
BEGIN
    IF p_user_id IS NULL OR btrim(p_user_id) = '' THEN
        RAISE EXCEPTION 'delete_user_data requires a user id'
            USING ERRCODE = '22023';
    END IF;

    -- Discover every public table with a column naming the subject user.
    -- Both spellings are used in this schema, and the column is `text` on most
    -- tables but `uuid` on a handful (athlete_pace_profiles, conversation_
    -- messages, plan_adjustments, training_blocks, usage_tracking, user_tiers,
    -- workout_reconciliations), so the comparison casts to text.
    CREATE TEMP TABLE _targets ON COMMIT DROP AS
    SELECT c.relname::text AS tbl, a.attname::text AS col
    FROM pg_class c
    JOIN pg_namespace n ON n.oid = c.relnamespace
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
    WHERE n.nspname = 'public'
      AND c.relkind = 'r'
      AND a.attname IN ('user_id', 'athlete_user_id')
      AND c.relname <> 'deleted_accounts';

    -- Foreign keys between these tables mean order matters, and the order
    -- isn't known ahead of time on a schema that drifts. Rather than topo-sort,
    -- retry: each pass deletes what it can and records what it couldn't. A
    -- table blocked by a child this pass succeeds once that child is gone.
    -- Bounded so a genuine cycle can't spin forever.
    LOOP
        pass := pass + 1;
        progressed := false;
        pending := 0;
        remaining := '{}';

        FOR rec IN SELECT tbl, col FROM _targets LOOP
            BEGIN
                EXECUTE format(
                    'DELETE FROM public.%I WHERE %I::text = $1', rec.tbl, rec.col
                ) USING p_user_id;
                GET DIAGNOSTICS deleted = ROW_COUNT;

                IF deleted > 0 THEN
                    counts := counts || jsonb_build_object(rec.tbl, deleted);
                    progressed := true;
                END IF;

                DELETE FROM _targets t WHERE t.tbl = rec.tbl;
            EXCEPTION
                WHEN foreign_key_violation THEN
                    -- Blocked by a child row that a later pass will remove.
                    pending := pending + 1;
                    remaining := remaining || rec.tbl;
            END;
        END LOOP;

        EXIT WHEN pending = 0;

        IF NOT progressed OR pass >= 10 THEN
            RAISE EXCEPTION
                'delete_user_data could not resolve foreign keys for: %',
                array_to_string(remaining, ', ')
                USING ERRCODE = '23503';
        END IF;
    END LOOP;

    RETURN counts;
END;
$fn$;

COMMENT ON FUNCTION public.delete_user_data(TEXT) IS
    'Deletes every row for one athlete across all public tables carrying '
    'user_id/athlete_user_id, discovered from pg_catalog at run time. Returns '
    'per-table counts. Does NOT touch storage — the delete-account edge '
    'function removes objects via the Storage API first.';

-- Service-role only. REVOKE must name PUBLIC: a function's default ACL is
-- NULL, i.e. EXECUTE to PUBLIC, so revoking from anon/authenticated alone
-- leaves both reaching it through PUBLIC.
REVOKE EXECUTE ON FUNCTION public.delete_user_data(TEXT) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.delete_user_data(TEXT) TO service_role;

-- ── Verification ────────────────────────────────────────────────────────────
DO $$
BEGIN
    IF has_function_privilege('anon', 'public.delete_user_data(text)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.delete_user_data(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'delete_user_data must not be callable by anon/authenticated';
    END IF;

    IF NOT has_function_privilege('service_role', 'public.delete_user_data(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'service_role must retain EXECUTE on delete_user_data';
    END IF;

    IF has_table_privilege('anon', 'public.deleted_accounts', 'SELECT')
       OR has_table_privilege('authenticated', 'public.deleted_accounts', 'SELECT') THEN
        RAISE EXCEPTION 'deleted_accounts must not be client-readable';
    END IF;
END $$;

COMMIT;
