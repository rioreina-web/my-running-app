-- ============================================================================
-- delete_user_account(target_user_id) — permanent, atomic account erasure
--
-- Powers the in-app "Delete Account" flow (App Store Guideline 5.1.1(v):
-- any app offering account creation MUST offer in-app account deletion).
--
-- WHY CATALOG-DRIVEN (not a hand-written table list):
--   Owner columns are added across many migrations and via ALTER TABLE —
--   e.g. `training_logs.user_id` was NOT in the original CREATE TABLE
--   (20260125), it was added later. A static list rots the moment a new
--   table (or a new owner column) ships. Instead we read the LIVE catalog
--   (information_schema) at call time and delete from every base table in
--   `public` that has a `user_id` / `athlete_user_id` / `athlete_id` TEXT
--   column matching this user. This stays correct as the schema grows.
--
--   Convention this relies on (see CLAUDE.md): auth user IDs are TEXT
--   columns equal to auth.uid()::text, and those three column names are
--   only ever the athlete's own id. Coach-side identity (coach_profiles /
--   coach_athlete_relationships, keyed on a UUID coach_id) is NOT covered
--   here — see the deploy notes for the coach edge case.
--
-- ATOMICITY / FK SAFETY:
--   The whole thing runs in one transaction. Deletes are retried across
--   multiple passes: a delete that fails a foreign-key check (because a
--   child row for this same user hasn't been removed yet) is retried on a
--   later pass once the child is gone. If it can't converge, the function
--   RAISES — which rolls back the entire transaction, so a user is never
--   left half-deleted. Nothing is committed unless everything succeeded.
--
-- SECURITY:
--   SECURITY DEFINER so it can bypass RLS and delete across all athletes'
--   tables. search_path is pinned (mirrors the current_coach_id hardening
--   in 20260609233602). EXECUTE is REVOKED from public/anon/authenticated
--   and GRANTED only to service_role — the ONLY caller is the
--   `delete-account` edge function, which first verifies the JWT and passes
--   the authenticated user's own id. A logged-in user can therefore only
--   ever delete THEIR OWN account.
--
--   Auth identity removal (auth.users, sessions, refresh tokens) is done
--   by the edge function via the Admin API AFTER this returns — not here.
--
-- Append-only (hard rule #5). Reaches prod only via `supabase db push`
-- from a committed SHA (hard rule #9).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_user_account(target_user_id text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
              AND col.data_type IN ('text', 'character varying')
            ORDER BY col.table_name
        LOOP
            BEGIN
                EXECUTE format(
                    'DELETE FROM public.%I WHERE %I = $1',
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
            EXCEPTION WHEN foreign_key_violation THEN
                -- A child row (this same user) still references this row.
                -- Leave it for a later pass once the child is deleted.
                remaining := true;
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
$$;

COMMENT ON FUNCTION public.delete_user_account(text) IS
    'Permanently deletes all rows owned by target_user_id across every '
    'public base table with a user_id/athlete_user_id/athlete_id TEXT '
    'column. Atomic (rolls back on any unresolved FK). service_role only; '
    'called by the delete-account edge function after JWT verification. '
    'Does NOT delete auth.users — the edge function does that via Admin API.';

-- Lock it down: only the service-role edge function may call this.
REVOKE ALL ON FUNCTION public.delete_user_account(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_user_account(text) FROM anon;
REVOKE ALL ON FUNCTION public.delete_user_account(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_account(text) TO service_role;
