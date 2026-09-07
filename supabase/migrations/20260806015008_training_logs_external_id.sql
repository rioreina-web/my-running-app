-- Phase 1 of docs/specs/runs-and-notes-split.md
--
-- Gives every training_logs row a source identity so that re-importing the
-- same activity is impossible at the database level rather than by convention.
--
-- Context: the ONLY uniqueness the table enforced was a partial unique index on
-- vital_workout_id. Any row with that column NULL was exempt, so every writer
-- had to defend itself with its own fuzzy same-day/similar-distance matching.
-- Six such implementations exist and they disagree with each other (see the
-- spec). This is the first step in removing all of them.
--
-- NOT a fix for the voice-memo duplicate class (a memo written as a run row).
-- That is closed by Phase 2 (workout_notes), because a memo legitimately has no
-- source activity id and so cannot be caught by a uniqueness rule here.
--
-- Append-only migration; deploy via `supabase db push` from a committed SHA.

-- 1. Column, nullable for now.
ALTER TABLE public.training_logs
  ADD COLUMN IF NOT EXISTS external_id text;

-- 2. Backfill. Real device ids where we have them; a synthetic per-row id
--    otherwise, so legacy rows satisfy the constraint without being merged.
UPDATE public.training_logs
   SET external_id = coalesce(
         nullif(vital_workout_id, ''),
         coalesce(source, 'unknown') || '_' || id::text
       )
 WHERE external_id IS NULL;

-- 3. Guarantee it going forward WITHOUT requiring every writer to change.
--    Five writers insert runs (strava-sync, vital-webhook, strava-test-pull,
--    ingest-manual-workout, and the iOS client). Making NOT NULL depend on all
--    five being updated first would mean a window where an insert can fail and
--    an athlete silently loses a run. The trigger removes that window: a writer
--    that forgets still produces a valid, unique row.
CREATE OR REPLACE FUNCTION public.training_logs_ensure_external_id()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.external_id IS NULL OR NEW.external_id = '' THEN
    NEW.external_id := coalesce(
      nullif(NEW.vital_workout_id, ''),
      coalesce(NEW.source, 'unknown') || '_' || NEW.id::text
    );
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_training_logs_ensure_external_id ON public.training_logs;
CREATE TRIGGER trg_training_logs_ensure_external_id
  BEFORE INSERT OR UPDATE ON public.training_logs
  FOR EACH ROW EXECUTE FUNCTION public.training_logs_ensure_external_id();

-- 4. The actual guarantee.
CREATE UNIQUE INDEX IF NOT EXISTS training_logs_user_external_uniq
  ON public.training_logs (user_id, external_id);

ALTER TABLE public.training_logs
  ALTER COLUMN external_id SET NOT NULL;

COMMENT ON COLUMN public.training_logs.external_id IS
  'Source identity for this activity: strava_<id> | <vital id> | <source>_<row uuid> for rows with no device id. Unique per user. Filled automatically by trg_training_logs_ensure_external_id when a writer omits it.';
