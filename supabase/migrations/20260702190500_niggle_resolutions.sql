-- niggle_resolutions — the "it's better now" watermark (2026-07-02)
--
-- A niggle in `body_mentions` never closes on its own: an ache from two
-- months ago would otherwise haunt the recurrence view forever. This table
-- records an ATHLETE-OWNED all-clear per body_area (+ side). Recurrence
-- then only counts mentions AFTER the latest resolution — so a resolved
-- niggle drops out of active analysis, and a NEW mention after that date
-- brings it straight back ("unless it comes back up").
--
-- It's a watermark, not a delete: history stays intact, so a recurrence
-- months later is still recognizable as a repeat, not a first-time thing.
--
-- Two writers, mirroring the niggle classifier:
--   • memo_llm — the voice path. The athlete says "my knee feels fine now";
--     process-training-memo records it (service role).
--   • manual  — the explicit "mark resolved" tap, via the resolve-niggle
--     edge function (service role). No client INSERT policy, same as
--     body_mentions (hard rule #4 spirit): athlete actions are mediated by
--     an authenticated edge function, not a raw client write.
--
-- Detection-not-diagnosis is preserved: body_area is the closed vocabulary,
-- verbatim_quote is the athlete's own words. Nothing here interprets.

create table if not exists public.niggle_resolutions (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  -- The memo the all-clear came from. NULL for a manual tap.
  training_log_id uuid,
  -- Closed body-part vocabulary (enforced in code: _shared/bodyVocabulary.ts).
  body_area text not null,
  -- 'left' | 'right' | NULL. Matches how niggle recurrence groups mentions,
  -- so a "left knee is fine" resolution clears the left knee, not the right.
  side text,
  resolved_at date not null,
  -- 'memo_llm' | 'manual'.
  source text,
  -- The athlete's own all-clear words (voice path). NULL for a manual tap.
  verbatim_quote text,
  created_at timestamptz not null default now()
);

-- One resolution per (athlete, source memo, body area) — re-processing a
-- memo upserts in place instead of duplicating. Manual taps have a NULL
-- training_log_id (Postgres treats NULLs as distinct), so an athlete can
-- resolve the same area again after it recurs — exactly what we want, since
-- the LATEST resolution date is the watermark.
create unique index if not exists niggle_resolutions_unique_per_log
  on public.niggle_resolutions (user_id, training_log_id, body_area);

-- Recurrence looks up "latest resolution for this area+side".
create index if not exists niggle_resolutions_lookup
  on public.niggle_resolutions (user_id, body_area, side, resolved_at desc);

alter table public.niggle_resolutions enable row level security;

create policy "Service role full access to niggle_resolutions"
  on public.niggle_resolutions
  for all
  using (auth.role() = 'service_role');

create policy "Users read own niggle resolutions"
  on public.niggle_resolutions
  for select
  using (user_id = (auth.uid())::text);
