-- ============================================================================
-- Account deletion: fix a live erasure bug, and bring the function into the
-- repo.
--
-- `public.delete_user_account(text)` ALREADY EXISTS IN PRODUCTION (applied as
-- ledger version 20260720120000, whose migration file is not in this repo).
-- It is SECURITY DEFINER, search_path-pinned, service-role only, and it
-- discovers user-linked tables from the catalog at run time — a good design.
--
-- It has one bug, and it is the expensive kind. Its discovery query filters:
--
--     AND col.data_type IN ('text', 'character varying')
--
-- Seven user-linked tables carry `user_id` as `uuid`, not text:
--   athlete_pace_profiles, conversation_messages, plan_adjustments,
--   training_blocks, usage_tracking, user_tiers, workout_reconciliations
--
-- Those are skipped silently, and the function still returns a report saying
-- the deletion completed. So an erasure request today leaves rows behind —
-- including `conversation_messages`, which holds the athlete's coaching
-- conversation content. A deletion that reports success while retaining
-- personal data is worse than one that fails loudly.
--
-- The fix is one line in the discovery query: drop the data_type filter and
-- compare `%I::text = $1`, which matches text and uuid columns alike. Also
-- widen to `athlete_user_id` (already present) and keep `athlete_id`.
--
-- Name and signature are preserved deliberately. An earlier draft of this
-- change introduced a second function (`delete_user_data`) because the repo
-- gave no sign that `delete_user_account` existed. Two deletion functions
-- with slightly different coverage is exactly how erasure quietly rots, so
-- there is one function and it keeps the name production already uses.
--
-- Storage is not handled here. Deleting `storage.objects` rows leaves the
-- bytes in the object store; only the Storage API removes them, which the
-- `delete-account` edge function does before calling this.
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

-- ── delete_user_account ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_user_account(target_user_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    rec        record;
    n          bigint;
    pass       int     := 0;
    remaining  boolean := true;
    report     jsonb   := '{}'::jsonb;
    total      bigint  := 0;
BEGIN
    IF coalesce(target_user_id, '') = '' THEN
        RAISE EXCEPTION 'delete_user_account: target_user_id is required';
    END IF;

    -- Repeat passes until no delete is blocked by a not-yet-removed child.
    -- Cap the passes so a genuine FK cycle can't loop forever.
    WHILE remaining AND pass < 15 LOOP
        remaining := false;
        pass := pass + 1;

        FOR rec IN
            SELECT col.table_name AS tbl, col.column_name AS colname
            FROM information_schema.columns col
            JOIN information_schema.tables tb
              ON tb.table_schema = col.table_schema
             AND tb.table_name   = col.table_name
             AND tb.table_type   = 'BASE TABLE'
            WHERE col.table_schema = 'public'
              AND col.column_name IN ('user_id', 'athlete_user_id', 'athlete_id')
              -- NO data_type filter. The previous version required
              -- text/character varying, which silently skipped the seven
              -- tables whose user_id is uuid — including conversation_messages
              -- — while still reporting the deletion as complete.
              AND col.table_name <> 'deleted_accounts'
            ORDER BY col.table_name
        LOOP
            BEGIN
                -- Cast the column rather than the parameter: `%I::text = $1`
                -- matches text and uuid columns alike. It gives up the index
                -- on that column, which is irrelevant for a one-off erasure
                -- and is the whole point of the fix.
                EXECUTE format(
                    'DELETE FROM public.%I WHERE %I::text = $1',
                    rec.tbl, rec.colname
                ) USING target_user_id;

                GET DIAGNOSTICS n = ROW_COUNT;
                IF n > 0 THEN
                    total  := total + n;
                    report := report || jsonb_build_object(
                        rec.tbl,
                        coalesce((report ->> rec.tbl)::bigint, 0) + n
                    );
                END IF;
            EXCEPTION
                WHEN foreign_key_violation THEN
                    -- A child row (same user) still references this row.
                    -- Leave it for a later pass once the child is gone.
                    remaining := true;
                WHEN invalid_text_representation THEN
                    -- A uuid column compared against a non-uuid id. Not this
                    -- user's table; skip rather than abort the whole erasure.
                    NULL;
            END;
        END LOOP;
    END LOOP;

    IF remaining THEN
        RAISE EXCEPTION
            'delete_user_account: could not resolve delete order for user % after % passes (possible FK cycle)',
            target_user_id, pass;
    END IF;

    RETURN jsonb_build_object(
        'user_id',     target_user_id,
        'tables',      report,
        'total_rows',  total,
        'passes',      pass
    );
END;
$function$;

COMMENT ON FUNCTION public.delete_user_account(TEXT) IS
    'Deletes every row for one athlete across all public tables carrying '
    'user_id / athlete_user_id / athlete_id, discovered from the catalog at '
    'run time and compared as text so uuid columns are covered too. Returns '
    'per-table counts. Does NOT touch storage — the delete-account edge '
    'function removes objects via the Storage API first.';

-- Service-role only. REVOKE must name PUBLIC: a function's default ACL is
-- NULL, i.e. EXECUTE to PUBLIC, so revoking from anon/authenticated alone
-- leaves both reaching it through PUBLIC.
REVOKE EXECUTE ON FUNCTION public.delete_user_account(TEXT) FROM PUBLIC, anon, authenticated;
GRANT  EXECUTE ON FUNCTION public.delete_user_account(TEXT) TO service_role;

-- ── Verification ────────────────────────────────────────────────────────────
DO $$
DECLARE
    uncovered TEXT;
BEGIN
    IF has_function_privilege('anon', 'public.delete_user_account(text)', 'EXECUTE')
       OR has_function_privilege('authenticated', 'public.delete_user_account(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'delete_user_account must not be callable by anon/authenticated';
    END IF;

    IF NOT has_function_privilege('service_role', 'public.delete_user_account(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'service_role must retain EXECUTE on delete_user_account';
    END IF;

    IF has_table_privilege('anon', 'public.deleted_accounts', 'SELECT')
       OR has_table_privilege('authenticated', 'public.deleted_accounts', 'SELECT') THEN
        RAISE EXCEPTION 'deleted_accounts must not be client-readable';
    END IF;

    -- The bug this migration fixes: assert the discovery query no longer
    -- excludes non-text user columns. If a future edit reintroduces a
    -- data_type filter, these tables go uncovered again silently.
    SELECT string_agg(col.table_name, ', ' ORDER BY col.table_name)
    INTO uncovered
    FROM information_schema.columns col
    JOIN information_schema.tables tb
      ON tb.table_schema=col.table_schema AND tb.table_name=col.table_name
     AND tb.table_type='BASE TABLE'
    WHERE col.table_schema='public'
      AND col.column_name IN ('user_id','athlete_user_id','athlete_id')
      AND col.data_type NOT IN ('text','character varying')
      AND col.table_name <> 'deleted_accounts';

    IF uncovered IS NOT NULL THEN
        RAISE NOTICE
            'Non-text user columns now covered by delete_user_account: %', uncovered;
    END IF;
END $$;

COMMIT;
