-- ============================================================================
-- workout_type: authority ladder + provenance
--
-- WHY
-- ---
-- `training_logs.workout_type` had five independent writers and three mutually
-- incompatible conflict policies:
--
--   WorkoutSyncService.classifyWorkout (iOS, lapless pace heuristic)  last-wins
--   process-training-memo              (the athlete's own words)      last-wins
--   WorkoutLapsService.setType         (iOS pickers)                  last-wins
--   compute-workout-features           (server lap geometry)          only-if-NULL
--   merge_voice_orphan_into_run        (orphan fold)                  coalesce(run, memo)
--
-- Nothing recorded WHO wrote a value or how much evidence stood behind it, and
-- there was no CHECK constraint — the column accepted any string. So the winner
-- was decided by arrival order, and 133 files read the result.
--
-- 2026-08-26 is the worked example. An 8.22 mi run at 7:51/mi (easy anchor:
-- 7:03/mi) was written by the iOS device heuristic as `tempo`, because
-- classifyWorkout used an absolute `pace < 480 -> tempo` cutoff. strava-sync
-- then promoted that row to source='strava' in place; the promote clears every
-- other field derived from the lapless copy (parsed_structure, coach_insight)
-- but not workout_type. The voice memo — which said, in the athlete's own
-- words, "I did an easy 8-miler today" and extracted workout_type='easy' —
-- merged in afterwards under `coalesce(r.workout_type, v.workout_type)` and
-- lost to the machine guess. The server's geometry classifier, which reads
-- actual laps against the athlete's real pace zones and would have returned
-- `easy`, was forbidden from correcting it by the only-if-NULL guard.
-- WorkoutLabel.display then folded legacy `tempo` -> "Threshold", and the
-- athlete's easy run showed up as a quality session.
--
-- Across 311 logs, 19 runs are labelled harder than they were run, all of them
-- from the heuristic writers (voice_log 12, auto_sync 4, strava_backfill 3).
-- The Strava path, which has real lap geometry, disagreed with the geometry
-- classifier twice in 207 rows.
--
-- WHAT
-- ----
-- The same shape the repo already solved twice — stress_load/stress_source and
-- effort_load/density_baseline_source, both "several tiers estimate the same
-- quantity, record which tier won". Here the tiers are ranked by how much
-- evidence stands behind them, and a weaker writer may never overwrite a
-- stronger one:
--
--   athlete  50  explicit pick in a picker
--   plan     40  reconciled scheduled workout
--   memo     30  the athlete's own spoken/typed words
--   geometry 20  server segmentation from real laps vs the athlete's zones
--   device   10  lapless pace heuristic
--   unknown   0  a writer that did not declare itself
--
-- Enforcement is a BEFORE trigger, not caller discipline. Callers declare a
-- source by going through set_workout_type(); anything writing the column
-- directly is demoted to `unknown` and can therefore only fill a NULL. That
-- covers writers this migration does not touch — including
-- merge_voice_orphan_into_run, whose hardened rewrite is still queued in
-- 20260824213000 and must not be pushed as a side effect of this change.
--
-- NOTE ON `display` vs `signal`: this column is the EDITORIAL LABEL — the word
-- on screen. It is not a fitness signal. Consumers that gate real behaviour off
-- it (fitnessPrediction.qualifyingTypes, adaptation-rules.QUALITY,
-- fn_enqueue_daily_read_workout_rerender) should read parsed_structure /
-- workout_features instead; that repoint is deliberately NOT in this migration.
-- ============================================================================

-- ── 1. Provenance column ────────────────────────────────────────────────────

ALTER TABLE public.training_logs
  ADD COLUMN IF NOT EXISTS workout_type_source text;

COMMENT ON COLUMN public.training_logs.workout_type_source IS
  'Which tier last set workout_type: athlete | plan | memo | geometry | device | unknown. '
  'Enforced by trg_workout_type_authority; a weaker tier can never overwrite a stronger one. '
  'NULL exactly when workout_type is NULL.';

-- ── 2. Canonical spelling (the SQL twin of WorkoutLabel.normalize) ──────────
-- Folds spellings of the SAME concept only. It never reinterprets a workout,
-- and anything unrecognised passes through lowercased and untouched — never
-- invent a type the athlete did not choose.

CREATE OR REPLACE FUNCTION public.normalize_workout_type(p_type text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE lower(btrim(coalesce(p_type, '')))
    WHEN ''                 THEN NULL
    WHEN 'interval'         THEN 'intervals'
    WHEN 'tempo'            THEN 'threshold'   -- retired 2026-08-10
    WHEN 'longrun'          THEN 'long_run'
    WHEN 'long'             THEN 'long_run'
    WHEN 'longwo'           THEN 'long_wo'
    WHEN 'cross_training'   THEN 'cross_train'
    WHEN 'crosstraining'    THEN 'cross_train'
    WHEN 'crosstrain'       THEN 'cross_train'
    ELSE lower(btrim(p_type))
  END;
$$;

COMMENT ON FUNCTION public.normalize_workout_type(text) IS
  'Fold a workout_type key to its canonical spelling. SQL twin of WorkoutLabel.normalize (iOS).';

-- ── 3. The ladder ───────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.workout_type_authority(p_source text)
RETURNS integer
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE lower(btrim(coalesce(p_source, '')))
    WHEN 'athlete'  THEN 50
    WHEN 'plan'     THEN 40
    WHEN 'memo'     THEN 30
    WHEN 'geometry' THEN 20
    WHEN 'device'   THEN 10
    ELSE 0                       -- 'unknown', '', NULL, anything unrecognised
  END;
$$;

COMMENT ON FUNCTION public.workout_type_authority(text) IS
  'Rank of a workout_type writer. Higher outranks lower; a writer may only set the column when its rank >= the incumbent''s.';

-- ── 4. Backfill, BEFORE the trigger exists ─────────────────────────────────
-- Order matters: the trigger below pins workout_type_source against drift, so
-- the historical assignment has to land first.
--
-- Every pre-existing row is recorded as `unknown` (rank 0) rather than guessed
-- at. That is the honest reading — we cannot recover which writer won a race
-- that happened months ago — and it is also the useful one: rank 0 means the
-- memo, the geometry classifier and the athlete can all now correct history
-- simply by running, with no data archaeology and no destructive repair pass.

UPDATE public.training_logs
   SET workout_type = public.normalize_workout_type(workout_type)
 WHERE workout_type IS DISTINCT FROM public.normalize_workout_type(workout_type);

UPDATE public.training_logs
   SET workout_type_source = 'unknown'
 WHERE workout_type IS NOT NULL
   AND workout_type_source IS NULL;

UPDATE public.training_logs
   SET workout_type_source = NULL
 WHERE workout_type IS NULL
   AND workout_type_source IS NOT NULL;

-- ── 5. Enforcement ─────────────────────────────────────────────────────────
-- A caller declares itself by setting the transaction-local GUC
-- `app.workout_type_source` (set_workout_type does this). A direct write that
-- declares nothing reads back as 'unknown' and can therefore only fill a NULL.
--
-- The GUC is transaction-scoped (set_config(..., is_local => true)), so it
-- cannot leak across requests on a pooled connection. This is NOT the
-- `ALTER DATABASE SET app.settings.*` pattern that is permission-denied on
-- Supabase and left auto_parse_workout_structure dead — that is a
-- database-level setting; this is a per-transaction one, and it is verified
-- working on this project.

CREATE OR REPLACE FUNCTION public.enforce_workout_type_authority()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  claimed text := coalesce(nullif(current_setting('app.workout_type_source', true), ''), 'unknown');
BEGIN
  NEW.workout_type := public.normalize_workout_type(NEW.workout_type);

  IF TG_OP = 'INSERT' THEN
    NEW.workout_type_source := CASE WHEN NEW.workout_type IS NULL THEN NULL ELSE claimed END;
    RETURN NEW;
  END IF;

  -- Same value: nothing to arbitrate, but let a STRONGER writer restate it and
  -- take ownership. An athlete re-picking the type it already had is a
  -- confirmation, and it should stop the geometry pass from ever revisiting it.
  IF NEW.workout_type IS NOT DISTINCT FROM OLD.workout_type THEN
    IF public.workout_type_authority(claimed)
       > public.workout_type_authority(OLD.workout_type_source)
       AND NEW.workout_type IS NOT NULL THEN
      NEW.workout_type_source := claimed;
    ELSE
      NEW.workout_type_source := OLD.workout_type_source;
    END IF;
    RETURN NEW;
  END IF;

  -- A real change — including a clear to NULL, which is how strava-sync drops
  -- a device guess when it promotes a HealthKit twin. Same rule either way: a
  -- re-sync must never be able to wipe an athlete's manual label.
  IF public.workout_type_authority(claimed)
     < public.workout_type_authority(OLD.workout_type_source) THEN
    NEW.workout_type        := OLD.workout_type;
    NEW.workout_type_source := OLD.workout_type_source;
    RETURN NEW;
  END IF;

  NEW.workout_type_source := CASE WHEN NEW.workout_type IS NULL THEN NULL ELSE claimed END;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_workout_type_authority() IS
  'Arbitrates every write to training_logs.workout_type by the authority ladder. Undeclared writers are demoted to `unknown` and can only fill a NULL.';

DROP TRIGGER IF EXISTS trg_workout_type_authority ON public.training_logs;
CREATE TRIGGER trg_workout_type_authority
  BEFORE INSERT OR UPDATE OF workout_type, workout_type_source
  ON public.training_logs
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_workout_type_authority();

-- ── 6. The sanctioned write path ───────────────────────────────────────────
-- SECURITY INVOKER on purpose. The existing RLS on training_logs
-- (auth_update_own_logs: user_id = auth.uid()::text, plus service-role full
-- access) is exactly the right rule, so this reuses it rather than re-deriving
-- ownership inside a SECURITY DEFINER body — which is where an IDOR would come
-- from. A caller can only retype a log it could already update.

CREATE OR REPLACE FUNCTION public.set_workout_type(
  p_log    uuid,
  p_type   text,
  p_source text
)
RETURNS text
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_result text;
BEGIN
  IF public.workout_type_authority(p_source) = 0 THEN
    RAISE EXCEPTION 'set_workout_type: refusing an undeclared or unrecognised source (%)', p_source
      USING HINT = 'Use one of: athlete, plan, memo, geometry, device.';
  END IF;

  PERFORM set_config('app.workout_type_source', lower(btrim(p_source)), true);

  UPDATE public.training_logs
     SET workout_type = p_type
   WHERE id = p_log
  RETURNING workout_type INTO v_result;

  -- Clear it again so an unrelated later write in the same transaction cannot
  -- inherit this call's authority.
  PERFORM set_config('app.workout_type_source', '', true);

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.set_workout_type(uuid, text, text) IS
  'The sanctioned way to write training_logs.workout_type. Declares the writer to the authority ladder; returns the value actually stored, which is the OLD one when the ladder refused the write. RLS-scoped (SECURITY INVOKER).';

REVOKE ALL ON FUNCTION public.set_workout_type(uuid, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_workout_type(uuid, text, text) TO authenticated, service_role;

-- ── 7. Close the vocabulary ────────────────────────────────────────────────
-- Step 4 already folded every stored value through normalize_workout_type, and
-- the trigger folds every future one, so this cannot reject a live row. The
-- retired pace-zone keys (mp/hmp/lt/10k/...) and the legacy hills/strides/other
-- stay ADMITTED but are not offered by any picker: WorkoutLabel.display still
-- renders them and options(including:) still preserves them on edit, so
-- rejecting them here would break editing an old row.

ALTER TABLE public.training_logs
  DROP CONSTRAINT IF EXISTS training_logs_workout_type_vocabulary;

ALTER TABLE public.training_logs
  ADD CONSTRAINT training_logs_workout_type_vocabulary CHECK (
    workout_type IS NULL OR workout_type IN (
      -- canonical, offered by the pickers
      'easy', 'moderate', 'steady', 'recovery',
      'long_run', 'long_wo',
      'threshold', 'intervals', 'fartlek', 'progression', 'race',
      -- structural
      'rest', 'cross_train', 'strength',
      -- retired but still stored on historical rows
      'mp', 'hmp', 'lt', '10k', '5k', '3k', 'mile',
      'hills', 'strides', 'other'
    )
  ) NOT VALID;

ALTER TABLE public.training_logs
  VALIDATE CONSTRAINT training_logs_workout_type_vocabulary;

ALTER TABLE public.training_logs
  DROP CONSTRAINT IF EXISTS training_logs_workout_type_source_vocabulary;

ALTER TABLE public.training_logs
  ADD CONSTRAINT training_logs_workout_type_source_vocabulary CHECK (
    workout_type_source IS NULL OR workout_type_source IN
      ('athlete', 'plan', 'memo', 'geometry', 'device', 'unknown')
  );
