-- ============================================================================
-- delete_user_account(): also erase tables whose user_id is typed UUID.
--
-- Finding (privacy audit 2026-08-24): the catalog-driven loop filtered
--
--     AND col.data_type IN ('text', 'character varying')
--
-- so every table typing `user_id` as `uuid` was silently skipped. Seven tables
-- do. Only `athlete_pace_profiles` carries an FK to auth.users with
-- ON DELETE CASCADE, so it was cleaned up incidentally when delete-account
-- removed the auth identity at its step 3. The other six have NO FK to
-- auth.users and simply survived account deletion:
--
--     conversation_messages     <- the athlete's coaching chat history
--     workout_reconciliations
--     usage_tracking
--     plan_adjustments
--     training_blocks
--     user_tiers
--
-- And the function returned a success report either way, so the in-app
-- "Delete My Account" told the athlete their data was gone while their
-- conversations with the coach remained. That contradicts both the App Store
-- 5.1.1(v) commitment the endpoint exists to satisfy and the erasure promise
-- in docs/legal/privacy-policy.md.
--
-- Fix: drop the data_type filter and branch the predicate on the column type.
-- UUID columns compare `%I = $1::uuid` rather than `%I::text = $1` — casting
-- the PARAMETER, not the column, because uuid input parsing is
-- case-insensitive while `uuid::text` is always lowercase. That sidesteps the
-- uppercase-.uuidString-vs-lowercase-DB class of bug that broke voice memos
-- once already.
--
-- If target_user_id is not a parseable UUID we skip the uuid-typed tables
-- rather than abort the whole erasure, so a non-UUID id (should not happen
-- via delete-account, which reads auth.uid()) still clears everything it can.
--
-- Verified against the live catalog before writing: all seven uuid-typed
-- columns are named `user_id`. No `athlete_id` / `athlete_user_id` column is
-- uuid-typed, so this widens coverage without newly targeting any column
-- whose semantics differ from "the owning athlete".
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_user_account(target_user_id text)
 RETURNS jsonb
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
    uuid_ok    boolean := true;
    skipped    text[]  := '{}';
BEGIN
    IF coalesce(target_user_id, '') = '' THEN
        RAISE EXCEPTION 'delete_user_account: target_user_id is required';
    END IF;

    -- Can this id even address a uuid-typed column?
    BEGIN
        PERFORM target_user_id::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        uuid_ok := false;
    END;

    -- Repeat passes until no delete is blocked by a not-yet-removed child.
    -- Cap the passes so a genuine FK cycle can't loop forever.
    WHILE remaining AND pass < 15 LOOP
        remaining := false;
        pass := pass + 1;

        FOR rec IN
            SELECT col.table_name AS tbl,
                   col.column_name AS colname,
                   col.data_type   AS coltype
            FROM information_schema.columns col
            JOIN information_schema.tables tb
              ON tb.table_schema = col.table_schema
             AND tb.table_name   = col.table_name
             AND tb.table_type   = 'BASE TABLE'
            WHERE col.table_schema = 'public'
              AND col.column_name IN ('user_id', 'athlete_user_id', 'athlete_id')
              AND col.data_type IN ('text', 'character varying', 'uuid')
            ORDER BY col.table_name
        LOOP
            IF rec.coltype = 'uuid' AND NOT uuid_ok THEN
                IF pass = 1 THEN
                    skipped := skipped || rec.tbl;
                END IF;
                CONTINUE;
            END IF;

            BEGIN
                IF rec.coltype = 'uuid' THEN
                    EXECUTE format(
                        'DELETE FROM public.%I WHERE %I = $1::uuid',
                        rec.tbl, rec.colname
                    ) USING target_user_id;
                ELSE
                    EXECUTE format(
                        'DELETE FROM public.%I WHERE %I = $1',
                        rec.tbl, rec.colname
                    ) USING target_user_id;
                END IF;

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
        'user_id',       target_user_id,
        'tables',        report,
        'total_rows',    total,
        'passes',        pass,
        -- Non-empty only when target_user_id is not a parseable UUID. Surfaced
        -- so a partial erasure can never look like a complete one.
        'skipped_uuid_tables', to_jsonb(skipped)
    );
END;
$function$;
