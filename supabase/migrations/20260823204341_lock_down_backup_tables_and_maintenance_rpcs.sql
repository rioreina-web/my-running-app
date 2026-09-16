-- RECONCILED 2026-08-24. Original file:
--   supabase/migrations/20260823140000_lock_down_backup_tables_and_maintenance_rpcs.sql
--   on branch origin/claude/security-priorities-500-users-18s28k, commit bbf899e.
--
-- That branch is not merged into design/ds-sync, and the migration reached prod
-- via MCP `apply_migration` (contrary to hard rule #9), which stamped it with
-- its own timestamp 20260823204341 rather than the file's 20260823140000. The
-- result was a remote ledger entry with no local file, which blocked
-- `supabase db push` outright.
--
-- Content below is byte-identical to bbf899e; only the filename version was
-- changed, to the version prod actually recorded. When the security branch
-- merges, its 20260823140000 copy will arrive as a duplicate — that is safe to
-- apply (every statement is guarded by to_regclass/to_regprocedure existence
-- checks and REVOKE/GRANT are idempotent) but the duplicate file should be
-- deleted at merge time.

-- ============================================================================
-- Close live anon-reachable exposures found in the production advisors on
-- 2026-08-23. None of these objects exist in this repo's migration history —
-- they were created ad-hoc against prod — so nothing here could have been
-- caught by reading the repo alone.
--
-- Three groups:
--
--   1. Ad-hoc BACKUP TABLES sitting in `public` with RLS disabled. Two of them
--      are whole-row copies of `training_logs` — user_id, cleaned_notes, mood,
--      coach_insight, audio_url, transcript_url, rpe_pull_quote. `anon` holds
--      SELECT, and the anon key ships publicly in the iOS binary and the web
--      bundle, so these were readable with a single unauthenticated GET
--      against /rest/v1/. Verified in prod: RLS off, anon SELECT true.
--
--   2. MAINTENANCE RPCs executable by `anon`. The worst is
--      `dedupe_recent_training_logs(p_days)`: SECURITY DEFINER, no auth.uid()
--      check, and it MERGES AND DELETES rows across every athlete. An
--      unauthenticated caller could pass a large p_days and run a global
--      dedupe. `merge_voice_orphan_into_run` likewise deletes a row (it does
--      refuse cross-user merges, so it needs two ids from one athlete).
--      `backfill_workout_insights` and `enqueue_weekly_reads` enqueue LLM work
--      — unauthenticated spend.
--
--   3. SECURITY DEFINER VIEWS readable by `anon`. `race_prs` has no auth.uid()
--      filter, so it exposed every athlete's race results regardless of RLS on
--      the underlying tables. The four spend views leak operational cost data.
--
-- Deliberately NON-DESTRUCTIVE: the backup tables are locked down, not
-- dropped. Whether they are still needed is a data-retention decision for a
-- human — and dropping the only copy of a merge/dedupe backup is not something
-- to do inside a security fix. Once confirmed unneeded they should be dropped
-- (or moved to a schema PostgREST does not expose), because a locked-down copy
-- of athlete health data is still a copy.
--
-- `create_mcp_access_token` is intentionally left available to `authenticated`
-- — it derives its subject from auth.uid() and raises without one, so the anon
-- grant was never usable. Only the anon grant is removed.
--
-- Everything is guarded on existence so this applies cleanly to a freshly
-- reset local database, where none of these prod-only objects exist.
-- ============================================================================

BEGIN;

-- ── 1. Backup tables ────────────────────────────────────────────────────────
DO $$
DECLARE
    t TEXT;
    backup_tables TEXT[] := ARRAY[
        'training_logs_dedupe_backup',
        '_heat_backfill_backup_20260805',
        '_dup_cleanup_backup_20260803',
        '_backup_voice_dupe_merge_20260805',
        '_backup_features_20260817',
        '_backup_load_20260817',
        '_backup_snapshot_row_20260817'
    ];
BEGIN
    FOREACH t IN ARRAY backup_tables LOOP
        IF to_regclass('public.' || quote_ident(t)) IS NULL THEN
            RAISE NOTICE 'Skipping % — not present in this database', t;
            CONTINUE;
        END IF;

        -- RLS with no policy = deny-all for anon/authenticated. service_role
        -- and the table owner bypass RLS, so restores still work.
        EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

        -- Belt and braces: drop the grants too, so exposure doesn't depend on
        -- RLS alone (a future FORCE/owner change shouldn't reopen this).
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated', t);
    END LOOP;
END $$;

-- ── 2. Maintenance RPCs ─────────────────────────────────────────────────────
-- REVOKE must name PUBLIC: a function's default ACL is NULL, meaning EXECUTE
-- to PUBLIC, so revoking only from anon/authenticated leaves both reaching it
-- through PUBLIC. Revoking PUBLIC also strips service_role, hence the re-grant.
DO $$
DECLARE
    fn TEXT;
    service_only TEXT[] := ARRAY[
        'public.dedupe_recent_training_logs(integer)',
        'public.merge_voice_orphan_into_run(uuid, uuid)',
        'public.backfill_workout_insights(integer)',
        'public.enqueue_weekly_reads()',
        'public.fn_weekly_plan_rebalance()',
        'public.increment_subscriber_count(uuid)'
    ];
BEGIN
    FOREACH fn IN ARRAY service_only LOOP
        IF to_regprocedure(fn) IS NULL THEN
            RAISE NOTICE 'Skipping % — not present in this database', fn;
            CONTINUE;
        END IF;
        EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
        EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
    END LOOP;

    -- Athlete-facing: keeps `authenticated`, loses `anon`.
    IF to_regprocedure('public.create_mcp_access_token(text)') IS NOT NULL THEN
        REVOKE EXECUTE ON FUNCTION public.create_mcp_access_token(text) FROM PUBLIC, anon;
        GRANT  EXECUTE ON FUNCTION public.create_mcp_access_token(text) TO authenticated, service_role;
    END IF;
END $$;

-- ── 3. SECURITY DEFINER views ───────────────────────────────────────────────
DO $$
DECLARE
    v TEXT;
    ops_views TEXT[] := ARRAY[
        'daily_usage', 'daily_cost_estimate', 'llm_spend_today', 'yesterday_llm_spend'
    ];
BEGIN
    -- Operational cost views: no athlete-facing caller, so no client grant.
    FOREACH v IN ARRAY ops_views LOOP
        IF to_regclass('public.' || quote_ident(v)) IS NULL THEN
            RAISE NOTICE 'Skipping view % — not present in this database', v;
            CONTINUE;
        END IF;
        EXECUTE format('REVOKE ALL ON TABLE public.%I FROM PUBLIC, anon, authenticated', v);
    END LOOP;

    -- race_prs is athlete data. security_invoker makes the view run as the
    -- CALLER, so RLS on the underlying tables applies per athlete instead of
    -- being bypassed by the view's definer. Requires PG15+; prod is 17.
    -- anon loses SELECT outright — there is no signed-out use for it.
    IF to_regclass('public.race_prs') IS NOT NULL THEN
        EXECUTE 'ALTER VIEW public.race_prs SET (security_invoker = true)';
        EXECUTE 'REVOKE ALL ON TABLE public.race_prs FROM PUBLIC, anon';
    END IF;
END $$;

-- ── Verification ────────────────────────────────────────────────────────────
DO $$
DECLARE
    obj TEXT;
    bad TEXT := '';
BEGIN
    -- No backup table may be anon/authenticated readable, and each must have RLS.
    FOREACH obj IN ARRAY ARRAY[
        'training_logs_dedupe_backup', '_heat_backfill_backup_20260805',
        '_dup_cleanup_backup_20260803', '_backup_voice_dupe_merge_20260805',
        '_backup_features_20260817', '_backup_load_20260817',
        '_backup_snapshot_row_20260817'
    ] LOOP
        CONTINUE WHEN to_regclass('public.' || quote_ident(obj)) IS NULL;

        IF has_table_privilege('anon', 'public.' || quote_ident(obj), 'SELECT')
           OR has_table_privilege('authenticated', 'public.' || quote_ident(obj), 'SELECT') THEN
            bad := bad || format(' %s(still readable)', obj);
        END IF;

        IF NOT (SELECT relrowsecurity FROM pg_class
                 WHERE oid = to_regclass('public.' || quote_ident(obj))) THEN
            bad := bad || format(' %s(RLS off)', obj);
        END IF;
    END LOOP;

    -- No maintenance RPC may be anon-executable.
    FOREACH obj IN ARRAY ARRAY[
        'public.dedupe_recent_training_logs(integer)',
        'public.merge_voice_orphan_into_run(uuid, uuid)',
        'public.backfill_workout_insights(integer)',
        'public.enqueue_weekly_reads()',
        'public.fn_weekly_plan_rebalance()',
        'public.increment_subscriber_count(uuid)',
        'public.create_mcp_access_token(text)'
    ] LOOP
        CONTINUE WHEN to_regprocedure(obj) IS NULL;
        IF has_function_privilege('anon', obj, 'EXECUTE') THEN
            bad := bad || format(' %s(anon EXECUTE)', obj);
        END IF;
    END LOOP;

    -- Views must not be anon-readable.
    FOREACH obj IN ARRAY ARRAY[
        'race_prs', 'daily_usage', 'daily_cost_estimate',
        'llm_spend_today', 'yesterday_llm_spend'
    ] LOOP
        CONTINUE WHEN to_regclass('public.' || quote_ident(obj)) IS NULL;
        IF has_table_privilege('anon', 'public.' || quote_ident(obj), 'SELECT') THEN
            bad := bad || format(' %s(anon SELECT)', obj);
        END IF;
    END LOOP;

    IF bad <> '' THEN
        RAISE EXCEPTION 'Lockdown incomplete:%', bad;
    END IF;
END $$;

COMMIT;
