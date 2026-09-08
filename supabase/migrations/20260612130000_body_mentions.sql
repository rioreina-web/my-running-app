-- body_mentions — durable niggle store (athlete_state v2, Phase C)
--
-- The Niggles surface (CLAUDE.md) is supposed to live in a body_mentions
-- table, but the table never existed in prod — niggles were re-derived by
-- regex on every athlete_state rebuild, so a mention could appear one day
-- and vanish the next. This table makes them persistent, enabling a real
-- recurrence timeline ("left knee, 3× over 6 weeks").
--
-- Detection-not-diagnosis is preserved: rows store the athlete's VERBATIM
-- words, a closed-vocabulary body_area, and a closed severity_hint. Nothing
-- here interprets, diagnoses, or recommends — that contract lives in the
-- code that reads this table.
--
-- RLS mirrors athlete_state exactly: service-role writes (the rebuild runs
-- under service role on the cron/trigger path), owner reads. No client
-- INSERT policy.

create table if not exists public.body_mentions (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  -- The training_logs row the mention was detected in. Nullable so future
  -- non-log sources (e.g. a standalone check-in) can still record mentions.
  training_log_id uuid,
  -- Closed body-part vocabulary (≈30 entries). Enforced in code, not here,
  -- so the list can evolve without a migration.
  body_area text not null,
  side text,
  -- The athlete's own words — never coerced to a number or a diagnosis.
  verbatim_quote text not null,
  -- Closed severity vocabulary: tight | sore | pain | sharp.
  severity_hint text not null,
  mentioned_at date not null,
  -- e.g. "2wk volume +40% before mention (32 → 45mi)".
  volume_context text,
  source text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- One mention per (athlete, source log, body area) — re-scans upsert in
-- place instead of duplicating.
create unique index if not exists body_mentions_unique_per_log
  on public.body_mentions (user_id, training_log_id, body_area);

create index if not exists body_mentions_user_date
  on public.body_mentions (user_id, mentioned_at desc);

alter table public.body_mentions enable row level security;

create policy "Service role full access to body_mentions"
  on public.body_mentions
  for all
  using (auth.role() = 'service_role');

create policy "Users read own body mentions"
  on public.body_mentions
  for select
  using (user_id = (auth.uid())::text);
