-- Merge an orphan voice_log row into a telemetry-carrying run row.
--
-- Background: when a voice memo is recorded for a run that Strava/HealthKit
-- hasn't synced yet, iOS falls back to inserting a standalone `voice_log`
-- training_logs row with no vital_workout_id and no telemetry (see
-- VoiceLogViewModel.saveVoiceMemo insert path). When the run later syncs it
-- lands as a SEPARATE row with the GPS/laps/stream. The two never reconcile
-- (dedupe_recent_training_logs deliberately never touches voice_log rows), so
-- the athlete taps the voice row and the workout-detail sheet shows the
-- "Logged without GPS" empty state while the real run sits on the other row.
--
-- strava-sync calls this function after it writes a run row to fold a matching
-- orphan back in: the run row stays canonical (keeps its GPS, laps, streams,
-- pace_segments) and inherits the voice memo's subjective content. Voice-owned
-- fields win for the note/mood/RPE columns; the run's Strava activity *title*
-- (cleaned_notes = a.name) must NOT shadow the athlete's real reflection —
-- hence coalesce(voice, run) for cleaned_notes, not the other way around.
--
-- Niggle data derived from the memo (body_mentions, niggle_resolutions) is
-- REAL user content and is repointed to the surviving run. GPS-superseded or
-- transient children of the orphan (workout_features from a no-GPS parse, the
-- orphan's own coach_insight_jobs / voice_processing_jobs /
-- workout_reconciliations) are dropped — the run has, or will get, its own.
--
-- SECURITY DEFINER + locked search_path: strava-sync runs as the service role,
-- but this keeps the merge atomic and callable from one place.

create or replace function public.merge_voice_orphan_into_run(
  p_orphan uuid,
  p_run    uuid
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user   text;
  r_user   text;
begin
  -- Defensive guards: the orphan must be a telemetry-less row and the run must
  -- belong to the same athlete. Never merge across users; never clobber a row
  -- that already carries streams by treating it as the orphan.
  select user_id into v_user
    from training_logs
   where id = p_orphan and external_streams is null and audio_url is not null;
  select user_id into r_user
    from training_logs
   where id = p_run and external_streams is not null;

  if v_user is null or r_user is null or v_user <> r_user then
    return;  -- nothing to do / mismatched — leave both rows untouched
  end if;

  -- 1) Fold the voice memo's subjective content onto the run row. Voice wins
  --    for the note/mood/RPE columns (the run's cleaned_notes is just the
  --    Strava activity title); telemetry columns are never touched here.
  update training_logs r set
    mood             = coalesce(v.mood, r.mood),
    cleaned_notes    = coalesce(v.cleaned_notes, r.cleaned_notes),
    workout_notes    = coalesce(v.workout_notes, r.workout_notes),
    extracted_data   = coalesce(v.extracted_data, r.extracted_data),
    audio_url        = coalesce(r.audio_url, v.audio_url),
    transcript_url   = coalesce(r.transcript_url, v.transcript_url),
    felt_rpe         = coalesce(r.felt_rpe, v.felt_rpe),
    rpe_tags         = coalesce(r.rpe_tags, v.rpe_tags),
    planned_rpe      = coalesce(r.planned_rpe, v.planned_rpe),
    rpe_pull_quote   = coalesce(r.rpe_pull_quote, v.rpe_pull_quote),
    rpe_extracted_at = coalesce(r.rpe_extracted_at, v.rpe_extracted_at),
    workout_type     = coalesce(r.workout_type, v.workout_type)
  from training_logs v
  where r.id = p_run and v.id = p_orphan;

  -- 2) Repoint real memo-derived data onto the surviving run.
  update body_mentions     set training_log_id = p_run where training_log_id = p_orphan;
  update niggle_resolutions set training_log_id = p_run where training_log_id = p_orphan;

  -- 3) Drop the orphan's GPS-superseded / transient children. The run has (or
  --    will regenerate) its own from real telemetry.
  delete from workout_features       where training_log_id = p_orphan;
  delete from coach_insight_jobs      where training_log_id = p_orphan;
  delete from voice_processing_jobs   where training_log_id = p_orphan;
  delete from workout_reconciliations where training_log_id = p_orphan;

  -- 4) Remove the now-empty orphan row.
  delete from training_logs where id = p_orphan;
end;
$$;

comment on function public.merge_voice_orphan_into_run(uuid, uuid) is
  'Folds an orphan voice_log training_logs row (no telemetry) into a synced run row, preserving the run''s GPS/laps and inheriting the memo''s subjective content + niggles. Called by strava-sync after a run row is written.';
