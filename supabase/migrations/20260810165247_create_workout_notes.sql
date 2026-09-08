-- Phase 2 of docs/specs/runs-and-notes-split.md — create `workout_notes`,
-- backfill it, and start dual-writing. NOTHING READS THIS TABLE YET.
--
-- The problem this closes:
--
--   `training_logs` stores two different kinds of thing in one table — a RUN
--   (measured, from Strava/HealthKit, owns laps and streams) and a NOTE
--   (recorded by the athlete, owns audio, transcript, mood, RPE). Because they
--   share a table, nothing in the schema says "these two rows are the same
--   workout", so six separate pieces of code guess at it with six different
--   thresholds, and they disagree. See the spec's table for the full list.
--
--   The visible symptom is that a voice memo does not attach to its run. It
--   lives on its own. What looks like attachment today is
--   `dedupe_recent_training_logs()` PHOTOCOPYING the memo's words and audio
--   onto the run row and deleting the note — and only within the last 3 days.
--   86 of this athlete's 88 voice logs are attached to nothing at all.
--
-- The invariant this table exists to hold:
--
--   One recorded reflection = one row in `workout_notes`, never deleted, never
--   merged, optionally pointing at a run via `run_id`.
--
-- `run_id` is NULLABLE ON PURPOSE. It carries the case that started all of
-- this: a memo recorded before the run has synced. Today that becomes a fake
-- run-shaped row in `training_logs` (which is why the duplicates exist). Here
-- it is simply a note with no run yet — a valid, complete, displayable journal
-- entry. When the run arrives, one function (`linkNoteToRun`, reusing
-- voiceOrphanMatch.ts's ±4h / max(0.5mi, 8%) thresholds) fills `run_id` in.
-- That function may ONLY ever set `run_id`. It may never decide whether a run
-- exists, and it may never delete anything.
--
-- NAMING. There is already a COLUMN `training_logs.workout_notes` holding the
-- prescription/description text. A table and a column may share a name in
-- Postgres, and PostgREST disambiguates an embed by its parentheses
-- (`workout_notes(*)`), so this should be legal — but it is a genuine trip
-- hazard for the Phase 3 readers, and it is UNVERIFIED against this project's
-- PostgREST until a reader actually embeds. Test the embed FIRST in Phase 3,
-- before writing any query against it. If it bites, rename the COLUMN (it
-- holds a prescription, not notes) rather than this table, which the spec names
-- and which the iOS/edge code will by then be writing to.
--
-- Append-only migration; deploy via `supabase db push` from a committed SHA.

CREATE TABLE IF NOT EXISTS public.workout_notes (
    id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id           text NOT NULL,

    -- The run this reflection is about. NULL = recorded before the run synced,
    -- or a rest-day / check-in note that is about no run at all.
    -- ON DELETE SET NULL, never CASCADE: deleting a run must never destroy the
    -- athlete's words. That asymmetry is the whole point of the split.
    run_id            uuid REFERENCES public.training_logs(id) ON DELETE SET NULL,

    recorded_at       timestamptz NOT NULL,

    audio_url         text,
    transcript_url    text,
    raw_transcript    text,
    cleaned_text      text,
    mood              text,
    felt_rpe          smallint,
    rpe_tags          text[],
    extracted_data    jsonb,
    processing_status text,

    -- Provenance for the backfill. Not in the spec; added so this migration is
    -- re-runnable and so Phase 3 can prove old row → new row for every note
    -- before any reader moves over. Also the key the iOS dual-write upserts on.
    -- Drop it in Phase 4 once `training_logs` no longer carries notes.
    legacy_log_id     uuid UNIQUE,

    created_at        timestamptz NOT NULL DEFAULT now(),
    updated_at        timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.workout_notes IS
  'One recorded reflection per row — never deleted, never merged, optionally '
  'pointing at a run via run_id. Phase 2 of docs/specs/runs-and-notes-split.md. '
  'Nothing reads this yet; the iOS client dual-writes here and to training_logs.';
COMMENT ON COLUMN public.workout_notes.run_id IS
  'The run this note is about, or NULL when the run has not synced yet. Only '
  'linkNoteToRun() may set this. ON DELETE SET NULL — deleting a run must never '
  'destroy the athlete''s words.';
COMMENT ON COLUMN public.workout_notes.legacy_log_id IS
  'The training_logs row this note was backfilled from / is dual-written with. '
  'Provenance only. Dropped in Phase 4.';

CREATE INDEX IF NOT EXISTS idx_workout_notes_user_recorded
    ON public.workout_notes(user_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_workout_notes_run
    ON public.workout_notes(run_id) WHERE run_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.touch_workout_notes_updated_at()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, pg_temp
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_workout_notes_touch ON public.workout_notes;
CREATE TRIGGER trg_workout_notes_touch
    BEFORE UPDATE ON public.workout_notes
    FOR EACH ROW EXECUTE FUNCTION public.touch_workout_notes_updated_at();

ALTER TABLE public.workout_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role full access to workout_notes" ON public.workout_notes;
CREATE POLICY "Service role full access to workout_notes" ON public.workout_notes
    FOR ALL USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

DROP POLICY IF EXISTS auth_read_own_notes ON public.workout_notes;
CREATE POLICY auth_read_own_notes ON public.workout_notes
    FOR SELECT USING (user_id = (auth.uid())::text);

DROP POLICY IF EXISTS auth_insert_own_notes ON public.workout_notes;
CREATE POLICY auth_insert_own_notes ON public.workout_notes
    FOR INSERT WITH CHECK (user_id = (auth.uid())::text);

DROP POLICY IF EXISTS auth_update_own_notes ON public.workout_notes;
CREATE POLICY auth_update_own_notes ON public.workout_notes
    FOR UPDATE USING (user_id = (auth.uid())::text);

DROP POLICY IF EXISTS auth_delete_own_notes ON public.workout_notes;
CREATE POLICY auth_delete_own_notes ON public.workout_notes
    FOR DELETE USING (user_id = (auth.uid())::text);

INSERT INTO public.workout_notes (
    user_id, run_id, recorded_at,
    audio_url, transcript_url, raw_transcript, cleaned_text,
    mood, felt_rpe, rpe_tags, extracted_data, processing_status,
    legacy_log_id, created_at
)
SELECT
    t.user_id,
    CASE WHEN t.source IN ('strava', 'auto_sync', 'strava_backfill')
         THEN t.id END                                   AS run_id,
    COALESCE(t.workout_date, t.created_at, now())        AS recorded_at,
    t.audio_url,
    t.transcript_url,
    CASE WHEN t.source IN ('voice_log', 'check_in')
         THEN t.notes END                                AS raw_transcript,
    CASE WHEN public.is_strava_placeholder_note(t.cleaned_notes)
         THEN NULL ELSE t.cleaned_notes END              AS cleaned_text,
    t.mood,
    t.felt_rpe,
    t.rpe_tags,
    t.extracted_data,
    t.processing_status,
    t.id,
    COALESCE(t.created_at, now())
FROM public.training_logs t
WHERE t.user_id IS NOT NULL
  AND (t.source IN ('voice_log', 'check_in') OR t.audio_url IS NOT NULL)
ON CONFLICT (legacy_log_id) DO NOTHING;