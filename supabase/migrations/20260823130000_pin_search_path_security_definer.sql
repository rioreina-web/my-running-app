-- ============================================================================
-- Pin `search_path` on `increment_subscriber_count`, and stop exposing the
-- maintenance RPCs to anon/authenticated.
--
-- A SECURITY DEFINER function runs as its owner. Without a pinned
-- `search_path` it resolves unqualified names using the CALLER's path.
--
-- The subtlety that makes this more than hygiene: `pg_catalog` is implicitly
-- searched FIRST when it is not named explicitly, so a plain shadow of a
-- built-in does not win. But an EXACT-ARITY function in a schema on the path
-- outranks `pg_catalog`'s VARIADIC match regardless of order. So a definer
-- calling unqualified `jsonb_build_object(...)` can be hijacked by
-- `public.jsonb_build_object(text, text)` — demonstrated on PG16 during this
-- work, exfiltrating a service-role key read from `vault.decrypted_secrets`.
-- Excluding `public` from the path is what closes that; pinning to a path
-- that still contains `public` does not.
--
-- Exploitability today is low: on PG15+ (this project is major_version 17)
-- `CREATE` on `public` is not granted to `PUBLIC`, so an ordinary
-- `authenticated` role cannot create the shadowing object.
--
-- ── WHY THIS MIGRATION IS MUCH SMALLER THAN IT WAS ─────────────────────────
--
-- It used to `CREATE OR REPLACE` five trigger functions, reproducing their
-- bodies "verbatim" from old migrations in this repo, in order to attach the
-- pin. Checked against production on 2026-08-24, that was wrong in every case
-- but one:
--
--   trigger_voice_log_processing     ALREADY pinned (pg_catalog, pg_temp) in
--                                    prod, and prod's BODY IS A DIFFERENT
--                                    ARCHITECTURE. Prod inserts into
--                                    `voice_processing_jobs` for the drain to
--                                    pick up, and handles typed notes
--                                    (kind = 'note') and check-ins. This
--                                    repo's copy predates the outbox: it
--                                    calls net.http_post directly and returns
--                                    early when audio_url IS NULL. Replacing
--                                    prod's body with it would revert the
--                                    queue AND silently stop every typed note
--                                    from being processed.
--
--   fn_trigger_reconcile_log         ALREADY pinned in prod ('public',
--                                    'pg_temp'), body has diverged from this
--                                    repo's.
--
--   trigger_post_run_reconciliation  DOES NOT EXIST in prod. Nor does the
--   fn_trigger_workout_insight       edge function the first one posts to.
--                                    Creating them would add dead code.
--
--   increment_subscriber_count       Genuinely unpinned in prod (proconfig
--                                    IS NULL). This is the one real fix.
--
-- The lesson is the same one the stop notice on this PR draws for the edge
-- functions: this repo is roughly half of production
-- (docs/repo-prod-drift-2026-08-24.md), so "reproduced verbatim from the repo"
-- is not the same as "matches what is deployed". Tightening a pin on a body
-- you have not read is how you ship a regression.
--
-- The two already-pinned functions are left alone. `fn_trigger_reconcile_log`
-- keeping `public` on its path is a real (small) residual — closing it needs
-- its body schema-qualified, which must be done against PROD's body, not this
-- repo's. The report block at the end names anything still outstanding.
-- ============================================================================

BEGIN;

-- ── increment_subscriber_count ──────────────────────────────────────────────
-- Body reproduced from PRODUCTION (read 2026-08-24), not from this repo, with
-- `plan_templates` schema-qualified so the function is correct under a path
-- that excludes `public`. CREATE OR REPLACE preserves the OID.
DO $$
BEGIN
    IF to_regprocedure('public.increment_subscriber_count(uuid)') IS NULL THEN
        RAISE NOTICE 'increment_subscriber_count not present — skipping pin';
        RETURN;
    END IF;

    EXECUTE $fn$
        CREATE OR REPLACE FUNCTION public.increment_subscriber_count(template_id UUID)
        RETURNS void
        LANGUAGE plpgsql
        SECURITY DEFINER
        SET search_path = pg_catalog, pg_temp
        AS $body$
        BEGIN
            UPDATE public.plan_templates
               SET subscriber_count = subscriber_count + 1
             WHERE id = template_id;
        END;
        $body$;
    $fn$;
END $$;

-- ── Maintenance / outbox RPCs: service-role only ────────────────────────────
-- REVOKE must name PUBLIC: a function's default ACL is NULL, i.e. EXECUTE to
-- PUBLIC, so revoking from anon/authenticated alone leaves both reaching it
-- through PUBLIC. Guarded by to_regprocedure because several of these have no
-- definition in this repo — they were applied ad-hoc (see
-- docs/migration-ledger-reconciliation-2026-06-11.md) and are absent from a
-- freshly reset local database.
DO $$
DECLARE
    fn TEXT;
    targets TEXT[] := ARRAY[
        'public.claim_coach_insight_jobs(int)',
        'public.claim_coachable_moment_jobs(int)',
        'public.claim_voice_processing_jobs(int)',
        'public.fn_weekly_plan_rebalance()',
        'public.increment_subscriber_count(uuid)'
    ];
BEGIN
    FOREACH fn IN ARRAY targets LOOP
        IF to_regprocedure(fn) IS NOT NULL THEN
            EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
            EXECUTE format('GRANT  EXECUTE ON FUNCTION %s TO service_role', fn);
        ELSE
            RAISE NOTICE 'Skipping % — not present in this database', fn;
        END IF;
    END LOOP;
END $$;

-- ── Verification ────────────────────────────────────────────────────────────
DO $$
DECLARE
    fn        TEXT;
    role_name TEXT;
    bad       TEXT;
    loose     TEXT;
BEGIN
    -- 1. The one function this migration owns is pinned.
    IF to_regprocedure('public.increment_subscriber_count(uuid)') IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM pg_proc p
            JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public'
              AND p.proname = 'increment_subscriber_count'
              AND 'search_path=pg_catalog, pg_temp' = ANY(COALESCE(p.proconfig, '{}'::text[]))
        ) THEN
            RAISE EXCEPTION 'increment_subscriber_count did not get its search_path pin';
        END IF;
    END IF;

    -- 2. Nothing on the target list is client-callable.
    FOREACH fn IN ARRAY ARRAY[
        'public.claim_coach_insight_jobs(int)',
        'public.claim_coachable_moment_jobs(int)',
        'public.claim_voice_processing_jobs(int)',
        'public.fn_weekly_plan_rebalance()',
        'public.increment_subscriber_count(uuid)'
    ] LOOP
        CONTINUE WHEN to_regprocedure(fn) IS NULL;
        FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            IF has_function_privilege(role_name, fn, 'EXECUTE') THEN
                RAISE EXCEPTION '% can still EXECUTE %', role_name, fn;
            END IF;
        END LOOP;
    END LOOP;

    -- 3. Report-only: SECURITY DEFINER functions with NO pin at all.
    SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND NOT EXISTS (
            SELECT 1 FROM unnest(COALESCE(p.proconfig, '{}'::text[])) cfg
            WHERE cfg LIKE 'search\_path=%');

    IF bad IS NOT NULL THEN
        RAISE WARNING
            'SECURITY DEFINER function(s) with a mutable search_path: %. '
            'Pin with SET search_path = pg_catalog, pg_temp and schema-qualify '
            'the body — against the DEPLOYED body, not this repo''s copy.', bad;
    END IF;

    -- 4. Report-only: pinned, but the path still contains `public`, which is
    --    what the exact-arity-beats-variadic hijack needs. Not failed on:
    --    fixing these means rewriting bodies that live only in production.
    SELECT string_agg(p.proname, ', ' ORDER BY p.proname) INTO loose
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosecdef
      AND EXISTS (
            SELECT 1 FROM unnest(COALESCE(p.proconfig, '{}'::text[])) cfg
            WHERE cfg LIKE 'search\_path=%' AND cfg LIKE '%public%');

    IF loose IS NOT NULL THEN
        RAISE WARNING
            'SECURITY DEFINER function(s) pinned to a path that still includes '
            'public: %. Lower risk than no pin at all, but not closed.', loose;
    END IF;
END $$;

COMMIT;
