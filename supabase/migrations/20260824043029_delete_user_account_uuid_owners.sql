-- ============================================================================
-- delete_user_account() — cover UUID owner columns and whole-row backups
--
-- WHY (bug, found 2026-08-24 by auditing the RPC against live prod):
--   The catalog scan in 20260720120000 matched owner columns only when
--   `data_type IN ('text','character varying')`. That mirrors the CLAUDE.md
--   convention ("auth user IDs are TEXT columns equal to auth.uid()::text"),
--   but prod does not uniformly follow it: SEVEN public base tables carry a
--   `user_id` of type `uuid` and were therefore skipped ENTIRELY by account
--   deletion —
--       athlete_pace_profiles, conversation_messages, plan_adjustments,
--       training_blocks, usage_tracking, user_tiers, workout_reconciliations
--
--   Three of those are rescued today by an ON DELETE CASCADE from a
--   TEXT-owned parent (conversation_messages ← conversations,
--   plan_adjustments ← training_plans, workout_reconciliations ←
--   training_logs). That rescue is incidental, not designed: it disappears
--   the moment a cascade is dropped or a row is written with a NULL parent
--   FK. The remaining four have no such path and leak outright — at audit
--   time usage_tracking held 185 rows across 2 users and
--   athlete_pace_profiles 1 row; user_tiers and training_blocks are empty
--   now but will fill.
--
--   Consequence: "Delete My Account" reported success while leaving the
--   athlete's rows behind. That is an erasure-completeness bug in the path
--   that exists specifically to satisfy App Store Guideline 5.1.1(v) and
--   GDPR/CCPA deletion requests.
--
-- WHAT CHANGES
--   1. The catalog scan now also matches `uuid` owner columns and compares
--      against `target_user_id::uuid`. The cast is computed ONCE up front
--      and guarded: a target that is not a valid UUID simply skips the uuid
--      pass rather than raising, so a legacy non-UUID id can still be
--      deleted from the TEXT tables.
--   2. An explicit sweep for whole-row backup tables that keep the owner id
--      INSIDE a JSONB payload and have no owner column of their own. Today
--      that is `training_logs_dedupe_backup.row_data` (rows copied out of
--      training_logs before a dedupe, owner id living at row_data->>'user_id').
--
--      This is an ALLOWLIST on purpose. A generic "any table with a JSONB
--      column" sweep was considered and REJECTED: coaching_documents,
--      plan_templates, quality_session_templates and workout_templates all
--      carry JSONB and no owner column, and are shared/library content. A
--      blanket sweep keyed on an embedded user_id could delete a template
--      other athletes depend on. Deleting someone else's data is a worse
--      failure than retaining a backup row, so new backup tables must be
--      added here deliberately — see the audit function below, which exists
--      to make that omission visible instead of silent.
--
-- WHAT THIS DOES NOT FIX
--   `_heat_backfill_backup_20260805` (1436 rows) carries no owner reference
--   at all — only `id` plus derived heat/pace metrics. It cannot be scoped
--   to a user, so it cannot be swept. It is a spent one-off backup from the
--   2026-08-05 heat backfill; the correct disposal is DROP TABLE once the
--   team confirms the backfill is settled. Deliberately not dropped here:
--   destroying 1436 rows of derived data is the team's call, not a
--   migration's side effect.
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
    target_uuid uuid;
BEGIN
    IF coalesce(target_user_id, '') = '' THEN
        RAISE EXCEPTION 'delete_user_account: target_user_id is required';
    END IF;

    -- Auth ids are UUIDs rendered as text (auth.uid()::text), so this
    -- normally succeeds. If it doesn't, leave target_uuid NULL and skip the
    -- uuid-typed tables rather than failing the whole erasure.
    BEGIN
        target_uuid := target_user_id::uuid;
    EXCEPTION WHEN invalid_text_representation THEN
        target_uuid := NULL;
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
            -- A uuid-typed owner column needs a uuid comparand; if the
            -- target isn't a valid uuid there is nothing to match there.
            CONTINUE WHEN rec.coltype = 'uuid' AND target_uuid IS NULL;

            BEGIN
                IF rec.coltype = 'uuid' THEN
                    EXECUTE format(
                        'DELETE FROM public.%I WHERE %I = $1',
                        rec.tbl, rec.colname
                    ) USING target_uuid;
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

        -- Whole-row backup tables: owner id lives inside a JSONB payload.
        -- Allowlisted (see header) — never a blanket JSONB sweep.
        FOR rec IN
            SELECT * FROM (VALUES
                ('training_logs_dedupe_backup', 'row_data')
            ) AS t(tbl, jcol)
        LOOP
            CONTINUE WHEN to_regclass('public.' || quote_ident(rec.tbl)) IS NULL;

            BEGIN
                EXECUTE format(
                    'DELETE FROM public.%I
                      WHERE %I ->> ''user_id''         = $1
                         OR %I ->> ''athlete_user_id'' = $1
                         OR %I ->> ''athlete_id''      = $1',
                    rec.tbl, rec.jcol, rec.jcol, rec.jcol
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
    'public base table with a user_id/athlete_user_id/athlete_id column of '
    'type TEXT, VARCHAR or UUID, plus allowlisted whole-row backup tables '
    'that hold the owner id inside a JSONB payload. Atomic (rolls back on '
    'any unresolved FK). service_role only; called by the delete-account '
    'edge function after JWT verification. Does NOT delete auth.users — '
    'the edge function does that via the Admin API.';

REVOKE ALL ON FUNCTION public.delete_user_account(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_user_account(text) FROM anon;
REVOKE ALL ON FUNCTION public.delete_user_account(text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.delete_user_account(text) TO service_role;


-- ============================================================================
-- account_deletion_coverage_report() — make erasure gaps visible
--
-- The bug above was silent for a month because nothing reported which
-- tables account deletion could not reach. This returns every public base
-- table with NO recognised owner column and NO allowlisted JSONB payload,
-- along with its row count, so a new table that quietly falls outside the
-- erasure path shows up as a row here instead of as a compliance incident.
--
-- Read-only. Intended for an operator or a periodic ops check, not for the
-- request path. Reference-data tables (llm_model_pricing, blog_posts, …)
-- legitimately appear — the point is that the list is short enough to read
-- and each entry is a conscious decision.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.account_deletion_coverage_report()
RETURNS TABLE (table_name text, row_count bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    rec record;
    n   bigint;
BEGIN
    FOR rec IN
        SELECT tb.table_name AS tbl
        FROM information_schema.tables tb
        WHERE tb.table_schema = 'public'
          AND tb.table_type   = 'BASE TABLE'
          AND NOT EXISTS (
              SELECT 1 FROM information_schema.columns col
              WHERE col.table_schema = 'public'
                AND col.table_name   = tb.table_name
                AND col.column_name IN ('user_id','athlete_user_id','athlete_id')
                AND col.data_type IN ('text','character varying','uuid')
          )
          AND tb.table_name NOT IN ('training_logs_dedupe_backup')
        ORDER BY tb.table_name
    LOOP
        EXECUTE format('SELECT count(*) FROM public.%I', rec.tbl) INTO n;
        table_name := rec.tbl;
        row_count  := n;
        RETURN NEXT;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.account_deletion_coverage_report() IS
    'Lists public base tables that delete_user_account() cannot scope to a '
    'user (no TEXT/VARCHAR/UUID owner column, not an allowlisted JSONB '
    'backup table), with row counts. Operator audit surface for erasure '
    'completeness. Read-only; service_role only.';

REVOKE ALL ON FUNCTION public.account_deletion_coverage_report() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.account_deletion_coverage_report() FROM anon;
REVOKE ALL ON FUNCTION public.account_deletion_coverage_report() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.account_deletion_coverage_report() TO service_role;
