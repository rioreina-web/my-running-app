-- ============================================================================
-- Fix fn_enqueue_coachable_moment_evaluation: schema-qualify table refs.
--
-- The function in 20260518100000_coachable_moment_outbox_trigger.sql sets
-- `search_path = pg_catalog, pg_temp` (security hardening for SECURITY
-- DEFINER) but references `coach_athlete_relationships` and
-- `coachable_moment_jobs` unqualified. Postgres resolves them only against
-- pg_catalog/pg_temp, so every fire raises
-- `relation "coach_athlete_relationships" does not exist`, which aborts
-- the parent INSERT on training_logs.
--
-- Visible symptom: Strava sync (strava-test-pull) reports new runs but
-- inserts fail with that error in the errors[] array — no new training_logs
-- rows after 2026-05-15.
--
-- Fix: qualify both table references with `public.`. Keep the locked-down
-- search_path intact.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION fn_enqueue_coachable_moment_evaluation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF NOT EXISTS (
        SELECT 1
          FROM public.coach_athlete_relationships
         WHERE athlete_user_id = NEW.user_id
           AND status = 'active'
    ) THEN
        RETURN NEW;
    END IF;

    INSERT INTO public.coachable_moment_jobs (
        athlete_user_id,
        status,
        attempts,
        next_retry_at,
        last_enqueued_at,
        last_error
    )
    VALUES (NEW.user_id, 'queued', 0, NOW(), NOW(), NULL)
    ON CONFLICT (athlete_user_id) DO UPDATE
        SET status           = 'queued',
            attempts         = 0,
            next_retry_at    = NOW(),
            last_enqueued_at = NOW(),
            last_error       = NULL;

    RETURN NEW;
END;
$$;

COMMIT;
