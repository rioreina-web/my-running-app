-- Schema-qualify athlete_state in the training_logs invalidation trigger.
--
-- invalidate_athlete_state_on_training_log() is NOT security-definer and had no
-- search_path set, so it ran with the caller's search_path and used an
-- UNQUALIFIED `UPDATE athlete_state`. Direct client inserts into training_logs
-- (the `authenticated` role, whose search_path does not reliably include
-- `public`) therefore failed with 42P01 "relation athlete_state does not
-- exist". Service-role writes (Strava sync, edge functions) were unaffected
-- because `public` is in their path.
--
-- This surfaced 2026-06-16 once voice-memo uploads started reaching the
-- training_logs INSERT again (the storage upload had been failing before it,
-- masking the trigger). Qualify the table and pin the function's search_path so
-- it resolves regardless of caller context. CREATE OR REPLACE only — no data
-- change, and the existing trigger already points at this function.

CREATE OR REPLACE FUNCTION public.invalidate_athlete_state_on_training_log()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $function$
DECLARE
    affected_user_id text;
BEGIN
    affected_user_id := COALESCE(NEW.user_id, OLD.user_id);

    IF affected_user_id IS NOT NULL THEN
        UPDATE public.athlete_state
        SET last_updated_at = '1970-01-01'::timestamptz,
            last_updated_by = 'invalidated:training_log_' || TG_OP
        WHERE user_id = affected_user_id;
    END IF;

    RETURN COALESCE(NEW, OLD);
END;
$function$;
