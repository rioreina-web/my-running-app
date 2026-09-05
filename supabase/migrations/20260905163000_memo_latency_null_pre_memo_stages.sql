-- memo_pipeline_latency: never print a negative stage delta.
--
-- Found immediately after 20260904210000 went live (2026-09-05): merged memos
-- showed s_to_rpe of -43s, -115s, -10127s. The arithmetic was right and the
-- pairing was wrong. After merge_voice_orphan_into_run, workout_notes.run_id
-- points at the RUN row, and the RPC keeps the run's own
-- `rpe_extracted_at` (coalesce(r..., v...)). That timestamp belongs to the
-- run's pipeline, which for a memo recorded hours after the run had already
-- finished — so subtracting the memo's recorded_at yields a negative number
-- that reads like a latency measurement and is not one.
--
-- Stage columns sourced from training_logs are therefore NULL whenever the
-- stage predates the recording. `s_to_completed` is unaffected: it prefers
-- workout_notes.processing_completed_at, which the note row carries through a
-- merge (the note is repointed, never deleted) and which is stamped by
-- trg_stamp_processing_completed on the note's own status transition.
create or replace view public.memo_pipeline_latency
with (security_invoker = true)
as
select
  n.id                                   as memo_id,
  n.user_id,
  n.created_at                           as recorded_at,
  n.run_id is not null                   as merged_into_run,
  l.id                                   as log_id,
  l.source                               as log_source,
  coalesce(n.processing_status, l.processing_status) as status,
  l.processing_attempts                  as attempts,
  round(extract(epoch from (coalesce(n.processing_completed_at, l.processing_completed_at) - n.created_at))::numeric, 1) as s_to_completed,
  -- nullif(..., true) on the guard: only forward-looking deltas survive.
  case when l.structure_parsed_at     >= n.created_at
       then round(extract(epoch from (l.structure_parsed_at     - n.created_at))::numeric, 1) end as s_to_structure,
  case when l.rpe_extracted_at        >= n.created_at
       then round(extract(epoch from (l.rpe_extracted_at        - n.created_at))::numeric, 1) end as s_to_rpe,
  case when l.last_processing_attempt >= n.created_at
       then round(extract(epoch from (l.last_processing_attempt - n.created_at))::numeric, 1) end as s_to_last_attempt,
  l.processing_error
from public.workout_notes n
left join public.training_logs l on l.id = coalesce(n.run_id, n.legacy_log_id);

revoke all on public.memo_pipeline_latency from anon, authenticated;

comment on view public.memo_pipeline_latency is
  'One row per voice memo / typed note with seconds from recording to each pipeline stage. '
  'Healthy 2026-09-05: s_to_completed ~8-9 (words on the row ~6), s_to_rpe ~45-70 (minute cron). '
  's_to_completed is stamped by trigger from 2026-09-05 forward and is NULL for older rows. '
  'The other stage columns are NULL when the stage predates the recording — after a merge they '
  'belong to the run pipeline, not this memo. Ops-only: security_invoker, no app-role grant.';
