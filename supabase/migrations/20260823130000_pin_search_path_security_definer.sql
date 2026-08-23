-- ============================================================================
-- Pin `search_path` on the remaining SECURITY DEFINER functions, and stop
-- exposing `increment_subscriber_count` to anon/authenticated.
--
-- A SECURITY DEFINER function runs as its owner. Without a pinned
-- `search_path` it resolves unqualified names using the CALLER's path — so
-- whoever can get an object onto that path decides what the definer executes.
--
-- What raises this above hygiene here: four of these five functions read
-- `vault.decrypted_secrets` to pull `service_role_key`, then pass it to
-- `net.http_post` as a bearer token. The service-role key bypasses RLS for
-- every user, so a successful shadow of `vault` or `net` in one of these
-- would disclose it. They are trigger functions on `training_logs`, firing as
-- the definer on any athlete's own INSERT.
--
-- Exploitability today is low: on PG15+ (this project is major_version 17)
-- `CREATE` on `public` is not granted to `PUBLIC`, so an ordinary
-- `authenticated` role cannot create the shadowing object. This migration
-- removes the dependency on that being and staying true — the fix is free and
-- changes no behaviour.
--
-- `pg_catalog, pg_temp` matches the convention already set by
-- 20260609233602_harden_current_coach_id_search_path.sql and
-- 20260611140000_backfill_workout_insights_via_outbox.sql. Because that path
-- excludes `public`, every table reference below is schema-qualified.
--
-- Bodies are otherwise reproduced verbatim from:
--   trigger_voice_log_processing    — 20260410100000_auto_process_voice_logs.sql
--   trigger_post_run_reconciliation — 20260416400000_adaptive_triggers.sql
--   fn_trigger_reconcile_log        — 20260417500000_trigger_reconcile_log.sql
--   fn_trigger_workout_insight      — 20260428110000_trigger_workout_insight.sql
--   increment_subscriber_count      — 20260312_coach_training_plans.sql
--
-- CREATE OR REPLACE preserves each function's OID, so the existing triggers
-- keep pointing at it — no trigger is dropped or recreated here.
--
-- Already hardened, deliberately not touched: current_coach_id (20260609233602),
-- backfill_workout_insights (20260611140000), fn_enqueue_workout_insight.
-- ============================================================================

BEGIN;

-- ── trigger_voice_log_processing ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION trigger_voice_log_processing()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  _function_name TEXT;
  _supabase_url TEXT;
  _service_key TEXT;
  _payload JSONB;
BEGIN
  -- Only fire for new rows with audio that need processing
  IF NEW.audio_url IS NULL OR NEW.processing_status != 'pending' THEN
    RETURN NEW;
  END IF;

  -- Pick the right edge function based on source
  IF NEW.source = 'check_in' THEN
    _function_name := 'process-check-in';
  ELSE
    _function_name := 'process-training-memo';
  END IF;

  -- Build the payload the edge functions expect
  _payload := jsonb_build_object(
    'record', jsonb_build_object(
      'id', NEW.id::text,
      'audio_url', NEW.audio_url
    )
  );

  _supabase_url := current_setting('app.settings.supabase_url', true);
  _service_key := current_setting('app.settings.service_role_key', true);

  -- Require app.settings to be configured — no hardcoded fallback
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    RAISE WARNING 'app.settings.supabase_url is not configured — skipping voice log auto-processing';
    RETURN NEW;
  END IF;

  -- Use pg_net to make an async HTTP POST to the edge function.
  -- This runs outside the transaction so it doesn't block the INSERT.
  IF _service_key IS NOT NULL AND _service_key != '' THEN
    PERFORM net.http_post(
      url := _supabase_url || '/functions/v1/' || _function_name,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || _service_key,
        'apikey', _service_key
      ),
      body := _payload
    );
  END IF;

  RETURN NEW;
END;
$fn$;

-- ── trigger_post_run_reconciliation ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION trigger_post_run_reconciliation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
  _supabase_url TEXT;
  _service_key TEXT;
  _payload JSONB;
BEGIN
  -- Only fire for rows with actual workout data (not voice-only logs)
  IF NEW.workout_date IS NULL THEN
    RETURN NEW;
  END IF;

  IF COALESCE(NEW.workout_distance_miles, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  -- Build payload
  _payload := jsonb_build_object(
    'training_log_id', NEW.id::text,
    'user_id', NEW.user_id
  );

  _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
  _service_key := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    RAISE WARNING 'app.settings.supabase_url not configured — skipping post-run reconciliation';
    RETURN NEW;
  END IF;

  IF _service_key IS NOT NULL AND _service_key != '' THEN
    PERFORM net.http_post(
      url := _supabase_url || '/functions/v1/post-run-reconciliation',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || _service_key,
        'apikey', _service_key
      ),
      body := _payload
    );
  END IF;

  RETURN NEW;
END;
$fn$;

-- ── fn_trigger_reconcile_log ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_trigger_reconcile_log()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
    _payload      JSONB;
BEGIN
    -- Guards: skip rows that don't represent an actual workout.
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.workout_duration_minutes IS NULL
       OR NEW.workout_duration_minutes <= 0 THEN
        RETURN NEW;
    END IF;

    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE WARNING
            'app.settings.supabase_url / service_role_key not configured — skipping reconcile-log';
        RETURN NEW;
    END IF;

    _payload := jsonb_build_object('training_log_id', NEW.id::text);

    PERFORM net.http_post(
        url := _supabase_url || '/functions/v1/reconcile-log',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || _service_key,
            'apikey', _service_key
        ),
        body := _payload
    );

    RETURN NEW;
END;
$fn$;

-- ── fn_trigger_workout_insight ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_trigger_workout_insight()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
DECLARE
    _supabase_url TEXT;
    _service_key  TEXT;
BEGIN
    -- Guards
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NEW.workout_duration_minutes IS NULL
       OR NEW.workout_duration_minutes <= 0 THEN
        RETURN NEW;
    END IF;

    -- Skip voice logs — process-training-memo handles those.
    IF NEW.audio_url IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Skip rows that already have an insight (e.g. coach manually wrote one).
    IF NEW.coach_insight IS NOT NULL AND length(trim(NEW.coach_insight)) > 0 THEN
        RETURN NEW;
    END IF;

    _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
    _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

    IF _supabase_url IS NULL OR _supabase_url = ''
       OR _service_key IS NULL OR _service_key = '' THEN
        RAISE WARNING
            'app.settings.supabase_url / service_role_key not configured — '
            'skipping generate-workout-insight';
        RETURN NEW;
    END IF;

    PERFORM net.http_post(
        url := _supabase_url || '/functions/v1/generate-workout-insight',
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || _service_key,
            'apikey', _service_key
        ),
        body := jsonb_build_object('training_log_id', NEW.id::text)
    );

    RETURN NEW;
END;
$fn$;

-- ── increment_subscriber_count ──────────────────────────────────────────────
-- `plan_templates` was unqualified; with `public` off the path it must be
-- `public.plan_templates`.
CREATE OR REPLACE FUNCTION increment_subscriber_count(template_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $fn$
BEGIN
    UPDATE public.plan_templates
    SET subscriber_count = subscriber_count + 1
    WHERE id = template_id;
END;
$fn$;

-- This one RETURNS void rather than TRIGGER, so unlike the four above
-- PostgREST exposes it at /rest/v1/rpc/increment_subscriber_count. Any
-- anon-key holder could therefore inflate any template's subscriber_count.
-- Its only caller is the subscribe-to-plan edge function, which uses the
-- service-role client.
--
-- REVOKE must name PUBLIC. A function's default ACL is NULL, which means
-- "EXECUTE to PUBLIC" — so revoking from `anon, authenticated` alone leaves
-- both roles executing it through PUBLIC. Verified on PG16:
--   default                          -> has_function_privilege(authenticated) = true
--   REVOKE FROM anon, authenticated  -> still true
--   REVOKE FROM PUBLIC               -> false
-- Revoking PUBLIC also strips service_role, so it is granted back explicitly.
REVOKE EXECUTE ON FUNCTION public.increment_subscriber_count(UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.increment_subscriber_count(UUID) TO service_role;

-- ── Re-apply the outbox RPC revokes from 20260610230628 ─────────────────────
-- That migration used `REVOKE EXECUTE ... FROM anon, authenticated` without
-- naming PUBLIC, and its comment asserts the opposite of the behaviour
-- measured above. On the default ACL that revoke is a no-op, so these four
-- are most likely still callable by any anon-key holder via
-- /rest/v1/rpc/. Redone here correctly.
--
-- Guarded by to_regprocedure because fn_weekly_plan_rebalance has no
-- definition in this repo — it was applied ad-hoc and only ever appears as a
-- REVOKE (see docs/migration-ledger-reconciliation-2026-06-11.md), so it does
-- not exist in a freshly reset local database.
DO $$
DECLARE
    fn TEXT;
    targets TEXT[] := ARRAY[
        'public.claim_coach_insight_jobs(int)',
        'public.claim_coachable_moment_jobs(int)',
        'public.claim_voice_processing_jobs(int)',
        'public.fn_weekly_plan_rebalance()'
    ];
BEGIN
    FOREACH fn IN ARRAY targets LOOP
        IF to_regprocedure(fn) IS NOT NULL THEN
            EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', fn);
            EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', fn);
        ELSE
            RAISE NOTICE 'Skipping % — not present in this database', fn;
        END IF;
    END LOOP;
END $$;

-- ── Verification ────────────────────────────────────────────────────────────
DO $$
DECLARE
    owned TEXT[] := ARRAY[
        'trigger_voice_log_processing',
        'trigger_post_run_reconciliation',
        'fn_trigger_reconcile_log',
        'fn_trigger_workout_insight',
        'increment_subscriber_count'
    ];
    bad TEXT;
    fn TEXT;
    role_name TEXT;
BEGIN
    -- 1. Hard assert: everything THIS migration redefined is pinned.
    SELECT string_agg(p.proname, ', ' ORDER BY p.proname)
    INTO bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(owned)
      AND p.prosecdef
      AND NOT EXISTS (
            SELECT 1 FROM unnest(COALESCE(p.proconfig, '{}'::text[])) cfg
            WHERE cfg LIKE 'search\_path=%'
          );

    IF bad IS NOT NULL THEN
        RAISE EXCEPTION 'Still have a mutable search_path after this migration: %', bad;
    END IF;

    -- 2. Hard assert: neither anon nor authenticated can reach the
    --    RPC-exposed functions any more.
    FOREACH fn IN ARRAY ARRAY[
        'public.increment_subscriber_count(uuid)',
        'public.claim_coach_insight_jobs(int)',
        'public.claim_coachable_moment_jobs(int)',
        'public.claim_voice_processing_jobs(int)',
        'public.fn_weekly_plan_rebalance()'
    ] LOOP
        CONTINUE WHEN to_regprocedure(fn) IS NULL;
        FOREACH role_name IN ARRAY ARRAY['anon', 'authenticated'] LOOP
            IF has_function_privilege(role_name, fn, 'EXECUTE') THEN
                RAISE EXCEPTION '% can still EXECUTE %', role_name, fn;
            END IF;
        END LOOP;
    END LOOP;

    -- 3. Report-only: any OTHER SECURITY DEFINER function in public still
    --    carrying a mutable search_path. Deliberately a warning, not a
    --    failure — this migration shouldn't abort over a function whose
    --    definition doesn't live in this repo and which it therefore can't
    --    fix (fn_weekly_plan_rebalance is exactly that case).
    SELECT string_agg(p.proname, ', ' ORDER BY p.proname)
    INTO bad
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND NOT (p.proname = ANY(owned))
      AND p.prosecdef
      AND NOT EXISTS (
            SELECT 1 FROM unnest(COALESCE(p.proconfig, '{}'::text[])) cfg
            WHERE cfg LIKE 'search\_path=%'
          );

    IF bad IS NOT NULL THEN
        RAISE WARNING
            'Other SECURITY DEFINER function(s) still have a mutable search_path: %. '
            'Pin them with SET search_path = pg_catalog, pg_temp and schema-qualify their bodies.',
            bad;
    END IF;
END $$;

COMMIT;
