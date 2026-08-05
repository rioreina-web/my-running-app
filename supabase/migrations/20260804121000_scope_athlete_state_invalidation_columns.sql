-- Voice-memo latency, Phase 2.1 — and a global cache-correctness fix.
--
-- trg_invalidate_athlete_state (20260420200000, function body last revised in
-- 20260616233000) fires on ANY INSERT/UPDATE/DELETE on training_logs with no
-- column scoping. The voice pipeline's own bookkeeping UPDATEs
-- (processing_status/processing_attempts/last_processing_attempt via
-- updateProcessingStatus) therefore wiped the athlete_state cache on every
-- memo — before the pipeline itself called getOrBuildAthleteState. The
-- 60-minute freshness check could never pass, so EVERY athlete-state consumer
-- (Daily Read, coaching agent, memo analysis, workout insight) was paying the
-- full ~13-query rebuild on every call. Confirmed in prod 2026-08-04: all
-- athlete_state rows sat at last_updated_at = 1970-01-01,
-- last_updated_by = 'invalidated:training_log_UPDATE'.
--
-- Fix: keep the trigger's contract (any *athlete-relevant* write invalidates;
-- writers stay state-unaware) but scope the UPDATE arm to the columns that can
-- actually change derived state. INSERT and DELETE still always invalidate.
-- Bookkeeping columns — processing_status, processing_error,
-- processing_attempts, last_processing_attempt, coach_insight,
-- coach_insight_status, transcript_url, audio_url, title — no longer wipe the
-- cache. The memo pipeline's final content UPDATE (cleaned_notes, mood, ...)
-- still invalidates, correctly.
--
-- The function body is unchanged (same one from 20260616233000, schema-
-- qualified + pinned search_path). Append-only migration per hard rule #5;
-- CREATE OR REPLACE + trigger re-create, no data change.

DROP TRIGGER IF EXISTS trg_invalidate_athlete_state ON public.training_logs;

CREATE TRIGGER trg_invalidate_athlete_state
    AFTER INSERT OR DELETE OR UPDATE OF
        user_id,
        workout_date,
        workout_distance_miles,
        workout_duration_minutes,
        workout_type,
        workout_pace_per_mile,
        mood,
        notes,
        cleaned_notes,
        workout_notes,
        pace_segments,
        parsed_structure,
        external_streams,
        extracted_data,
        felt_rpe,
        stress_load,
        source,
        vital_workout_id
    ON public.training_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.invalidate_athlete_state_on_training_log();

-- Verification (SQL editor):
--   1. Trigger is column-scoped:
--      SELECT pg_get_triggerdef(oid) FROM pg_trigger
--       WHERE tgname = 'trg_invalidate_athlete_state';
--   2. Bookkeeping writes no longer invalidate: after a memo completes, check
--      SELECT user_id, last_updated_at, last_updated_by FROM athlete_state;
--      last_updated_at should be recent (the content UPDATE), and stay put
--      when only processing_status changes.
--
-- NOTE (UPDATE OF semantics): the UPDATE arm fires when a listed column
-- appears in the SET clause, whether or not the value changed. That matches
-- the old behavior for content writes; it only stops firing for statements
-- that touch none of the listed columns — exactly the bookkeeping UPDATEs.
