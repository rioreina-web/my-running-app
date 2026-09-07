-- Weekly memory-consolidation cron (long-term memory, plan Step 4).
--
-- Fans out one fire-and-forget http_post to the consolidate-memories edge
-- function per athlete who has any active memory. The function merges
-- near-duplicates, archives expired transients + year-stale low-importance
-- rows, and caps each category — keeping the store the size a coach actually
-- carries (~30 things, not 3,000). Idempotent: re-running is a no-op.
--
-- Mirrors the nightly-fitness-snapshot cron pattern exactly (dynamic Vault
-- secrets at run time, async net.http_post fan-out). Archiving is reversible
-- (status → 'archived'); DELETE stays an athlete-only action (Model of You).
--
-- Firing: Sundays 04:30 UTC — a quiet weekly "sleep" pass, after the nightly
-- rebuilds. Each invocation consolidates ONE athlete, well within edge limits.
--
-- Prerequisites: consolidate-memories edge function deployed; Vault secrets
-- supabase_url + service_role_key present (same ones the other crons use).

DO $$
DECLARE
    _job_id INTEGER;
BEGIN
    BEGIN
        PERFORM cron.unschedule('weekly-consolidate-memories');
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    SELECT cron.schedule(
        'weekly-consolidate-memories',
        '30 4 * * 0',  -- Sundays 04:30 UTC
        $cron$
        DO $inner$
        DECLARE
            _supabase_url TEXT;
            _service_key  TEXT;
            _athlete      RECORD;
        BEGIN
            _supabase_url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'supabase_url' LIMIT 1);
            _service_key  := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1);

            IF _supabase_url IS NULL OR _supabase_url = ''
               OR _service_key IS NULL OR _service_key = '' THEN
                RAISE NOTICE 'weekly-consolidate-memories skipped — vault secrets missing';
                RETURN;
            END IF;

            FOR _athlete IN
                SELECT DISTINCT user_id
                FROM user_memories
                WHERE user_id IS NOT NULL
                  AND btrim(user_id) <> ''
                  AND status = 'active'
            LOOP
                PERFORM net.http_post(
                    url := _supabase_url || '/functions/v1/consolidate-memories',
                    headers := jsonb_build_object(
                        'Content-Type', 'application/json',
                        'Authorization', 'Bearer ' || _service_key,
                        'apikey', _service_key
                    ),
                    body := jsonb_build_object('user_id', _athlete.user_id)
                );
            END LOOP;

            RAISE NOTICE 'weekly-consolidate-memories dispatched';
        END
        $inner$;
        $cron$
    ) INTO _job_id;

    RAISE NOTICE 'weekly-consolidate-memories cron scheduled (job id %)', _job_id;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'pg_cron not available — weekly-consolidate-memories not scheduled';
END;
$$;
