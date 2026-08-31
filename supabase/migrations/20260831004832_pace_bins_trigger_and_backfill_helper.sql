-- Recompute bins whenever the inputs change. Wrapped in an exception block:
-- a binning failure must never stop a workout from saving.
CREATE OR REPLACE FUNCTION public.fn_recompute_pace_bins()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
BEGIN
    BEGIN
        PERFORM compute_pace_bins(NEW.id);
    EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'compute_pace_bins failed for %: %', NEW.id, SQLERRM;
    END;
    RETURN NULL;
END;
$function$;

DROP TRIGGER IF EXISTS trg_recompute_pace_bins ON public.training_logs;

-- UPDATE OF <cols> fires only when those columns are in the SET list, so the
-- pace_bins_* writeback inside compute_pace_bins() cannot re-enter this trigger.
CREATE TRIGGER trg_recompute_pace_bins
AFTER INSERT OR UPDATE OF external_streams, pace_segments,
                          workout_distance_miles, workout_duration_minutes
ON public.training_logs
FOR EACH ROW
EXECUTE FUNCTION public.fn_recompute_pace_bins();

-- Chunked backfill so a single call stays well inside statement timeouts.
CREATE OR REPLACE FUNCTION public.backfill_pace_bins(p_limit integer DEFAULT 25)
RETURNS TABLE (processed integer, remaining bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $function$
DECLARE
    r      record;
    v_done integer := 0;
BEGIN
    FOR r IN
        SELECT id FROM training_logs
         WHERE pace_bins_computed_at IS NULL
         ORDER BY workout_date DESC
         LIMIT p_limit
    LOOP
        BEGIN
            PERFORM compute_pace_bins(r.id);
        EXCEPTION WHEN OTHERS THEN
            RAISE WARNING 'backfill failed for %: %', r.id, SQLERRM;
            UPDATE training_logs
               SET pace_bins_source = 'none', pace_bins_miles = 0, pace_bins_computed_at = now()
             WHERE id = r.id;
        END;
        v_done := v_done + 1;
    END LOOP;

    RETURN QUERY
    SELECT v_done, (SELECT COUNT(*) FROM training_logs WHERE pace_bins_computed_at IS NULL);
END;
$function$;

REVOKE ALL ON FUNCTION public.backfill_pace_bins(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.backfill_pace_bins(integer) TO service_role;;
