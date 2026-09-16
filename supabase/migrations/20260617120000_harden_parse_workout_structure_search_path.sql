-- Pin search_path on trigger_parse_workout_structure().
--
-- Hygiene follow-up to 20260616233000 (which fixed the sibling
-- invalidate_athlete_state_on_training_log 42P01). This function fires on the
-- same client-written training_logs INSERT/UPDATE path but is SECURITY DEFINER
-- with no SET search_path. It is NOT currently failing — its only external
-- reference, net.http_post, is already schema-qualified — but:
--   1. It is the only training_logs trigger function lacking a pinned path;
--      every sibling (fn_enqueue_*, trigger_voice_log_processing,
--      sync_workout_laps_from_streams, fn_trigger_reconcile_log) already sets one.
--   2. A SECURITY DEFINER function with an unpinned search_path is a standard
--      Supabase security-advisor finding (search_path injection surface).
--
-- Pin to `public, pg_temp` for consistency and to close the advisor finding.
-- CREATE OR REPLACE only — no behavior change, no data change, existing trigger
-- already points at this function.

CREATE OR REPLACE FUNCTION public.trigger_parse_workout_structure()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
  _supabase_url TEXT;
  _service_key TEXT;
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.parsed_structure IS NOT NULL
     AND NEW.workout_notes IS NOT DISTINCT FROM OLD.workout_notes
     AND NEW.cleaned_notes IS NOT DISTINCT FROM OLD.cleaned_notes
     AND NEW.notes IS NOT DISTINCT FROM OLD.notes
     AND NEW.external_streams IS NOT DISTINCT FROM OLD.external_streams THEN
    RETURN NEW;
  END IF;

  IF NEW.workout_notes IS NULL AND NEW.cleaned_notes IS NULL
     AND NEW.notes IS NULL AND NEW.external_streams IS NULL THEN
    RETURN NEW;
  END IF;

  _supabase_url := current_setting('app.settings.supabase_url', true);
  _service_key := current_setting('app.settings.service_role_key', true);
  IF _supabase_url IS NULL OR _supabase_url = '' OR _service_key IS NULL OR _service_key = '' THEN
    RAISE WARNING 'parse-workout-structure trigger: app.settings not configured';
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := _supabase_url || '/functions/v1/parse-workout-structure',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || _service_key,
      'apikey', _service_key
    ),
    body := jsonb_build_object('training_log_id', NEW.id::text)
  );

  RETURN NEW;
END;
$function$;
