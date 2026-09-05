-- Memo pipeline latency: make "how long did the memo take" a query, not an
-- archaeology dig.
--
-- 2026-09-04: process-training-memo had been spending 15s per memo on Gemini
-- "thinking" for months. Nothing recorded WHEN a row reached 'completed', so
-- the only sensor was an athlete noticing a spinner; the per-stage timestamps
-- that do exist (structure_parsed_at, rpe_extracted_at, pace_bins_computed_at)
-- are downstream jobs, and backfills have overwritten two of them.
--
-- Two pieces, both DB-side so there is no deploy-order hazard with the edge
-- functions (a PostgREST UPDATE naming a column that does not exist yet fails
-- the whole memo write):
--   1. `processing_completed_at`, stamped by trigger on the pending→completed
--      transition, on training_logs AND workout_notes (the voice row is
--      consumed by merge_voice_orphan_into_run, so the note row is the copy
--      that survives a merge).
--   2. `memo_pipeline_latency`, one row per memo with seconds to each stage.
--      security_invoker + no anon/authenticated grant: an ops view, read with
--      the service role or from the dashboard, never through the app.

alter table public.training_logs  add column if not exists processing_completed_at timestamptz;
alter table public.workout_notes  add column if not exists processing_completed_at timestamptz;

create or replace function public.stamp_processing_completed()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.processing_status = 'completed'
     and old.processing_status is distinct from 'completed' then
    new.processing_completed_at := now();
  end if;
  return new;
end
$$;

drop trigger if exists trg_stamp_processing_completed on public.training_logs;
create trigger trg_stamp_processing_completed
  before update of processing_status on public.training_logs
  for each row execute function public.stamp_processing_completed();

drop trigger if exists trg_stamp_processing_completed on public.workout_notes;
create trigger trg_stamp_processing_completed
  before update of processing_status on public.workout_notes
  for each row execute function public.stamp_processing_completed();

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
  round(extract(epoch from (l.structure_parsed_at - n.created_at))::numeric, 1)  as s_to_structure,
  round(extract(epoch from (l.rpe_extracted_at   - n.created_at))::numeric, 1)   as s_to_rpe,
  round(extract(epoch from (l.last_processing_attempt - n.created_at))::numeric, 1) as s_to_last_attempt,
  l.processing_error
from public.workout_notes n
left join public.training_logs l on l.id = coalesce(n.run_id, n.legacy_log_id);

revoke all on public.memo_pipeline_latency from anon, authenticated;

comment on view public.memo_pipeline_latency is
  'One row per voice memo / typed note with seconds from recording to each pipeline stage. '
  'Healthy 2026-09-04: s_to_completed ≈ 8-9 (words on the row ≈ 6), s_to_rpe ≈ 45-70 (minute cron). '
  'Ops-only: security_invoker, no app-role grant. Example: '
  'select recorded_at, s_to_completed, s_to_rpe, merged_into_run, attempts, status from memo_pipeline_latency order by recorded_at desc limit 20;';
