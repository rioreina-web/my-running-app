-- Minimal stand-ins for the parts of the real schema the migrations touch.
-- Enough to make Postgres parse, plan and execute them; not a replica.
CREATE ROLE service_role;
CREATE ROLE anon;
CREATE ROLE authenticated;

CREATE SCHEMA vault;
CREATE TABLE vault.decrypted_secrets (name text, decrypted_secret text);
INSERT INTO vault.decrypted_secrets VALUES
  ('supabase_url', 'https://example.supabase.co'),
  ('service_role_key', 'stub-key');

CREATE SCHEMA net;
CREATE FUNCTION net.http_post(url text, headers jsonb DEFAULT '{}', body jsonb DEFAULT '{}')
RETURNS bigint LANGUAGE sql AS $$ SELECT 1::bigint $$;

CREATE TABLE public.training_logs (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id text,
    source text,
    workout_date date,
    created_at timestamptz DEFAULT now(),
    audio_url text,
    transcript_url text,
    notes text,
    cleaned_notes text,
    workout_notes text,
    mood text,
    felt_rpe numeric,
    rpe_tags jsonb,
    extracted_data jsonb,
    processing_status text,
    external_streams jsonb,
    parsed_structure jsonb,
    structure_parsed_at timestamptz,
    rpe_extracted_at timestamptz,
    stress_load numeric
);

CREATE TABLE public.workout_notes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id text,
    run_id uuid,
    recorded_at timestamptz,
    audio_url text,
    transcript_url text,
    raw_transcript text,
    cleaned_text text,
    mood text,
    felt_rpe numeric,
    rpe_tags jsonb,
    extracted_data jsonb,
    processing_status text,
    legacy_log_id uuid
);

CREATE TABLE public.workout_parse_jobs (
    training_log_id uuid PRIMARY KEY,
    user_id text NOT NULL,
    attempts smallint NOT NULL DEFAULT 0,
    last_attempt_at timestamptz,
    last_error text,
    force boolean NOT NULL DEFAULT false,
    reason text NOT NULL DEFAULT 'created',
    priority smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.rpe_extraction_jobs (
    training_log_id uuid PRIMARY KEY,
    user_id text NOT NULL,
    attempts smallint NOT NULL DEFAULT 0,
    last_attempt_at timestamptz,
    last_error text,
    priority smallint NOT NULL DEFAULT 0,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.llm_model_pricing (
    model text PRIMARY KEY,
    input_per_1m_usd numeric,
    output_per_1m_usd numeric
);

CREATE FUNCTION public.is_strava_placeholder_note(_t text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$ SELECT false $$;

-- The real body, verbatim from prod, so the trigger re-registration in
-- migration 1 is exercised against the function it actually points at.
CREATE FUNCTION public.mirror_training_log_to_workout_notes()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp AS $$
DECLARE
  v_is_note   boolean;
  v_is_run    boolean;
  v_clean     text;
  v_raw       text;
  v_existing  uuid;
BEGIN
  IF NEW.user_id IS NULL THEN RETURN NEW; END IF;
  v_is_note := NEW.source IN ('voice_log', 'check_in') OR NEW.audio_url IS NOT NULL;
  IF NOT v_is_note THEN RETURN NEW; END IF;
  v_is_run := NEW.source IN ('strava', 'auto_sync', 'strava_backfill');
  v_clean := CASE WHEN public.is_strava_placeholder_note(NEW.cleaned_notes)
                  THEN NULL ELSE NEW.cleaned_notes END;
  v_raw   := CASE WHEN NEW.source IN ('voice_log', 'check_in') THEN NEW.notes END;
  SELECT id INTO v_existing FROM public.workout_notes
   WHERE user_id = NEW.user_id AND NEW.audio_url IS NOT NULL AND audio_url = NEW.audio_url LIMIT 1;
  IF v_existing IS NULL THEN
    SELECT id INTO v_existing FROM public.workout_notes WHERE legacy_log_id = NEW.id LIMIT 1;
  END IF;
  IF v_existing IS NULL THEN
    INSERT INTO public.workout_notes (
      user_id, run_id, recorded_at, audio_url, transcript_url,
      raw_transcript, cleaned_text, mood, felt_rpe, rpe_tags,
      extracted_data, processing_status, legacy_log_id
    ) VALUES (
      NEW.user_id, CASE WHEN v_is_run THEN NEW.id END,
      COALESCE(NEW.workout_date, NEW.created_at, now()),
      NEW.audio_url, NEW.transcript_url, v_raw, v_clean, NEW.mood, NEW.felt_rpe,
      NEW.rpe_tags, NEW.extracted_data, NEW.processing_status, NEW.id);
  ELSE
    UPDATE public.workout_notes n SET
      run_id            = COALESCE(n.run_id, CASE WHEN v_is_run THEN NEW.id END),
      audio_url         = COALESCE(NEW.audio_url, n.audio_url),
      transcript_url    = COALESCE(NEW.transcript_url, n.transcript_url),
      raw_transcript    = COALESCE(v_raw, n.raw_transcript),
      cleaned_text      = COALESCE(v_clean, n.cleaned_text),
      mood              = COALESCE(NEW.mood, n.mood),
      felt_rpe          = COALESCE(NEW.felt_rpe, n.felt_rpe),
      rpe_tags          = COALESCE(NEW.rpe_tags, n.rpe_tags),
      extracted_data    = COALESCE(NEW.extracted_data, n.extracted_data),
      processing_status = COALESCE(NEW.processing_status, n.processing_status),
      legacy_log_id     = COALESCE(n.legacy_log_id, NEW.id)
    WHERE n.id = v_existing;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_mirror_training_log_to_notes
    AFTER INSERT OR UPDATE ON public.training_logs
    FOR EACH ROW EXECUTE FUNCTION public.mirror_training_log_to_workout_notes();

-- Pre-fix versions of the two enqueue triggers, so the "before" behaviour is
-- reproducible and the fix is demonstrably a change.
CREATE FUNCTION public.enqueue_workout_parse_from_note()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp AS $$
BEGIN
    IF NEW.run_id IS NULL THEN RETURN NEW; END IF;
    IF COALESCE(btrim(NEW.cleaned_text), '') = ''
       AND COALESCE(btrim(NEW.raw_transcript), '') = '' THEN RETURN NEW; END IF;
    IF NEW.user_id IS NULL OR NEW.user_id = '' THEN RETURN NEW; END IF;
    INSERT INTO public.workout_parse_jobs
        (training_log_id, user_id, reason, force, priority, created_at)
    VALUES (NEW.run_id, NEW.user_id, 'notes_edited', true, 0, now())
    ON CONFLICT (training_log_id) DO UPDATE
        SET reason='notes_edited', force=true, attempts=0, last_error=NULL,
            last_attempt_at=NULL, priority=0, created_at=now();
    RETURN NEW;
END; $$;

CREATE TRIGGER trg_enqueue_workout_parse_from_note
    AFTER INSERT OR UPDATE OF cleaned_text, raw_transcript, run_id
    ON public.workout_notes
    FOR EACH ROW EXECUTE FUNCTION public.enqueue_workout_parse_from_note();

CREATE FUNCTION public.enqueue_workout_parse()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp AS $$
DECLARE _notes_changed BOOLEAN := false; _has_material BOOLEAN; _reason TEXT; _force BOOLEAN;
BEGIN
    IF NEW.user_id IS NULL OR NEW.user_id = '' THEN RETURN NEW; END IF;
    _has_material := COALESCE(btrim(NEW.workout_notes),'') <> ''
        OR COALESCE(btrim(NEW.cleaned_notes),'') <> ''
        OR COALESCE(btrim(NEW.notes),'') <> ''
        OR NEW.external_streams IS NOT NULL;
    IF NOT _has_material THEN RETURN NEW; END IF;
    IF TG_OP = 'UPDATE' THEN
        _notes_changed := NEW.workout_notes IS DISTINCT FROM OLD.workout_notes
            OR NEW.cleaned_notes IS DISTINCT FROM OLD.cleaned_notes
            OR NEW.notes IS DISTINCT FROM OLD.notes;
    END IF;
    IF TG_OP = 'INSERT' THEN _reason := 'created'; _force := false;
    ELSIF _notes_changed THEN _reason := 'notes_edited'; _force := true;
    ELSE _reason := 'stream_arrived'; _force := false; END IF;
    INSERT INTO public.workout_parse_jobs
        (training_log_id, user_id, reason, force, priority, created_at)
    VALUES (NEW.id, NEW.user_id, _reason, _force, 0, now())
    ON CONFLICT (training_log_id) DO UPDATE
        SET reason=EXCLUDED.reason, force=public.workout_parse_jobs.force OR EXCLUDED.force,
            attempts=0, last_error=NULL, last_attempt_at=NULL, priority=0, created_at=now();
    RETURN NEW;
END; $$;

CREATE TRIGGER trg_enqueue_workout_parse
    AFTER INSERT OR UPDATE OF workout_notes, cleaned_notes, notes, external_streams
    ON public.training_logs
    FOR EACH ROW EXECUTE FUNCTION public.enqueue_workout_parse();
