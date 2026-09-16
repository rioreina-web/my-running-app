-- Harden merge_voice_orphan_into_run: never overwrite a memo the run already has.
--
-- The merge folds voice-owned columns onto the run with the VOICE side winning
-- (`coalesce(v.cleaned_notes, r.cleaned_notes)`) — correct when the run's
-- cleaned_notes is just the Strava activity title, catastrophic when the run
-- already carries the athlete's own words from a different recording: those
-- words are silently replaced and the orphan row is then deleted, so the
-- overwritten reflection is gone with no copy anywhere.
--
-- Not hypothetical. The 2026-08-24 orphan audit surfaced two NULL-dated memos.
-- One (a 10 mi memo beside that morning's Strava 10.01) targets a run whose
-- note is the placeholder "Morning Run" — a clean merge. The other (a 7.5 mi
-- memo written 2026-08-22 00:37) matches on time and distance to the 7.47 mi
-- run of 2026-08-21, which ALREADY holds its own memo ("I'm still feeling a bit
-- sick, but managed an easy..."). Distance + time said merge; doing so would
-- have destroyed that text. The matcher cannot tell these apart — only the
-- target's contents can — so the guard belongs here, at the write.
--
-- This mattered little while the merge could only fire from strava-sync in the
-- seconds after a run row was written (a fresh run has no memo yet). It matters
-- now: reconciliation also runs from the memo side, where the target run may be
-- hours old and already spoken for.
--
-- Behaviour on refusal: return without touching either row, exactly like the
-- existing user/telemetry guards. The orphan survives for a human to look at,
-- which is the right failure direction — a stranded memo is recoverable, an
-- overwritten one is not.

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
  v_user       text;
  r_user       text;
  v_audio      text;
  r_audio      text;
  r_notes      text;
begin
  -- Defensive guards: the orphan must be a telemetry-less row and the run must
  -- belong to the same athlete. Never merge across users; never clobber a row
  -- that already carries streams by treating it as the orphan.
  select user_id, audio_url into v_user, v_audio
    from training_logs
   where id = p_orphan and external_streams is null and audio_url is not null;
  select user_id, audio_url, cleaned_notes into r_user, r_audio, r_notes
    from training_logs
   where id = p_run and external_streams is not null;

  if v_user is null or r_user is null or v_user <> r_user then
    return;  -- nothing to do / mismatched — leave both rows untouched
  end if;

  -- The run already has a voice memo of its OWN (different recording): refuse.
  if r_audio is not null and r_audio is distinct from v_audio then
    raise notice 'merge_voice_orphan_into_run: run % already has its own memo; refusing to overwrite', p_run;
    return;
  end if;

  -- The run already carries real athlete words (not a Strava auto-title):
  -- refuse. Covers typed notes and memos whose audio_url was cleared.
  if r_notes is not null
     and length(btrim(r_notes)) > 0
     and not public.is_strava_placeholder_note(r_notes) then
    raise notice 'merge_voice_orphan_into_run: run % already has athlete notes; refusing to overwrite', p_run;
    return;
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
  update body_mentions      set training_log_id = p_run where training_log_id = p_orphan;
  update niggle_resolutions set training_log_id = p_run where training_log_id = p_orphan;

  -- 2b) Repoint the memo record itself. `workout_notes.run_id` is refreshed by
  --     the mirror trigger on the UPDATE above (it locates the row by
  --     audio_url), but `legacy_log_id` still points at the orphan — and it
  --     carries NO foreign key, so the delete below leaves it dangling at a
  --     row id that no longer exists rather than nulling it.
  update workout_notes
     set run_id        = coalesce(run_id, p_run),
         legacy_log_id = p_run,
         updated_at    = now()
   where legacy_log_id = p_orphan;

  -- 3) Drop the orphan's GPS-superseded / transient children. The run has (or
  --    will regenerate) its own from real telemetry.
  delete from workout_features        where training_log_id = p_orphan;
  delete from coach_insight_jobs      where training_log_id = p_orphan;
  delete from voice_processing_jobs   where training_log_id = p_orphan;
  delete from workout_reconciliations where training_log_id = p_orphan;

  -- 4) Remove the now-empty orphan row.
  delete from training_logs where id = p_orphan;
end;
$$;

comment on function public.merge_voice_orphan_into_run(uuid, uuid) is
  'Folds an orphan voice_log training_logs row (no telemetry) into a synced run row, preserving the run''s GPS/laps and inheriting the memo''s subjective content + niggles. Refuses when the run already carries its own memo or athlete-written notes. Called by strava-sync after a run row is written, and by process-training-memo when a memo lands after its run.';
