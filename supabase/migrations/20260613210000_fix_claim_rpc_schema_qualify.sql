-- ============================================================================
-- WS0 follow-up: schema-qualify table refs in the claim RPCs
--
-- `claim_coach_insight_jobs` and `claim_coachable_moment_jobs` run with a
-- hardened `search_path = pg_catalog, pg_temp` (a security pass) but reference
-- their tables UNQUALIFIED, so under that search_path the table is invisible:
--   ERROR: relation "coach_insight_jobs" does not exist
-- The functions threw, the drains returned 500, and the queues never drained.
-- `claim_voice_processing_jobs` was already qualified (public.…) and worked —
-- the hardening pass simply missed these two.
--
-- This surfaced only after the drain-cron auth fix (the drains used to 403 at
-- the gateway and never executed their body / called these RPCs). Fix: qualify
-- every table reference with `public.`. Logic is otherwise byte-for-byte the
-- prior definition. Append-only; CREATE OR REPLACE is idempotent.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.claim_coach_insight_jobs(batch_size integer DEFAULT 20)
 RETURNS TABLE(id bigint, training_log_id uuid, user_id text, attempts integer, max_attempts integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
    RETURN QUERY
    WITH next_batch AS (
        SELECT j.id
          FROM public.coach_insight_jobs j
         WHERE j.status = 'queued'
           AND j.next_retry_at <= NOW()
         ORDER BY j.next_retry_at, j.id
         LIMIT GREATEST(1, LEAST(100, COALESCE(batch_size, 20)))
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.coach_insight_jobs j
       SET status = 'in_progress',
           attempts = j.attempts + 1,
           last_attempted_at = NOW()
      FROM next_batch nb
     WHERE j.id = nb.id
    RETURNING j.id, j.training_log_id, j.user_id, j.attempts, j.max_attempts;
END;
$function$;

CREATE OR REPLACE FUNCTION public.claim_coachable_moment_jobs(batch_size integer DEFAULT 20)
 RETURNS TABLE(athlete_user_id text, attempts integer, max_attempts integer, version timestamp with time zone)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pg_temp'
AS $function$
BEGIN
    RETURN QUERY
    WITH next_batch AS (
        SELECT j.athlete_user_id
          FROM public.coachable_moment_jobs j
         WHERE j.status = 'queued'
           AND j.next_retry_at <= NOW()
         ORDER BY j.next_retry_at, j.athlete_user_id
         LIMIT GREATEST(1, LEAST(100, COALESCE(batch_size, 20)))
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.coachable_moment_jobs j
       SET status = 'in_progress',
           attempts = j.attempts + 1,
           last_attempted_at = NOW()
      FROM next_batch nb
     WHERE j.athlete_user_id = nb.athlete_user_id
    RETURNING j.athlete_user_id, j.attempts, j.max_attempts, j.last_enqueued_at;
END;
$function$;
