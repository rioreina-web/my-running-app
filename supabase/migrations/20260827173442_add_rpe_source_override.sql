-- Athlete override provenance for `training_logs.felt_rpe`.
--
-- Why this column has to exist before the workout-detail RPE slider ships:
-- `extract-rpe` is idempotent *by design* — its header states that re-running
-- "overwrites felt_rpe/pull_quote/tags and bumps rpe_extracted_at". It is
-- invoked from four places (client post-memo, service-role backfill, the
-- `dispatch_rpe_extraction` cron, and a DB webhook on cleaned_notes UPDATE),
-- so any hand-set value would be silently clobbered the next time any of them
-- fired. This column is the marker the function checks before it writes.
--
--   NULL       — never set, or predates this column
--   'llm'      — written by extract-rpe, read out of the voice memo
--   'athlete'  — set by hand on the slider; extract-rpe must NOT touch felt_rpe
--
-- Deliberately only on `training_logs`: that is where extract-rpe writes and
-- where iOS reads RPE from (`RPERow.fetchRecent`). The dual-write trigger
-- mirrors `felt_rpe` into `workout_notes` on its own; adding provenance there
-- too would mean editing `mirror_training_log_to_workout_notes()`, which is a
-- larger blast radius for no reader.

alter table public.training_logs
  add column if not exists rpe_source text;

-- Idempotent: this migration must be safe to re-run against a live DB that
-- already has the column from a partial apply.
alter table public.training_logs
  drop constraint if exists training_logs_rpe_source_check;

alter table public.training_logs
  add constraint training_logs_rpe_source_check
  check (rpe_source is null or rpe_source in ('llm', 'athlete'));

comment on column public.training_logs.rpe_source is
  'Provenance of felt_rpe: ''llm'' (extract-rpe, from the voice memo) or '
  '''athlete'' (set on the workout-detail slider). extract-rpe must not '
  'overwrite felt_rpe when this is ''athlete''. NULL = unset.';

-- Every existing non-null felt_rpe came from extract-rpe — there has never
-- been a client write path for this column (verified: zero insert/update/upsert
-- sites for felt_rpe across the Swift target). So they are all 'llm', and the
-- athlete keeps a clean slate of values they can override.
update public.training_logs
   set rpe_source = 'llm'
 where felt_rpe is not null
   and rpe_source is null;
