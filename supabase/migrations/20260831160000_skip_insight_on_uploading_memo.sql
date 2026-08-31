-- Insight trigger: skip insert-first voice rows (2026-08-31).
--
-- The app now inserts the memo row BEFORE uploading its audio (latency
-- Phase 2), so at INSERT time audio_url is NULL and this trigger's existing
-- voice-row skip (audio_url IS NOT NULL) cannot see it's a memo. Without
-- this guard, a memo recorded against a selected run (duration > 0) would
-- enqueue a coach_insight_jobs row and auto-generate an insight — breaking
-- the on-demand rule (2026-06-17 rev3: insights come from the athlete's
-- "Generate AI insight" tap, never automatically).
--
-- processing_status = 'uploading' is that flow's marker. This trigger is
-- INSERT-only, so returning here keeps memo insights on-demand permanently:
-- the later attach UPDATE (audio_url + status 'pending') never re-evaluates
-- it. coach_insight_status stays 'pending', which is what the button surface
-- keys off.

CREATE OR REPLACE FUNCTION public.fn_enqueue_workout_insight()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
    IF NEW.user_id IS NULL THEN
        RETURN NEW;
    END IF;
    -- Insert-first voice row: audio is still uploading, arrives by UPDATE.
    IF NEW.processing_status = 'uploading' THEN
        RETURN NEW;
    END IF;
    IF NEW.workout_duration_minutes IS NULL
       OR NEW.workout_duration_minutes <= 0 THEN
        RETURN NEW;
    END IF;
    IF NEW.audio_url IS NOT NULL THEN
        UPDATE public.training_logs
           SET coach_insight_status = 'skipped'
         WHERE id = NEW.id AND coach_insight_status = 'pending';
        RETURN NEW;
    END IF;
    IF NEW.coach_insight IS NOT NULL
       AND length(trim(NEW.coach_insight)) > 0 THEN
        UPDATE public.training_logs
           SET coach_insight_status = 'generated'
         WHERE id = NEW.id AND coach_insight_status = 'pending';
        RETURN NEW;
    END IF;
    INSERT INTO public.coach_insight_jobs (training_log_id, user_id)
    VALUES (NEW.id, NEW.user_id)
    ON CONFLICT (training_log_id) DO NOTHING;
    RETURN NEW;
END;
$function$;
