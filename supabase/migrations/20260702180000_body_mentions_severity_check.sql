-- body_mentions hygiene — niggle-classifier rewrite (audit fix #2, 2026-07-02)
--
-- The niggle classifier now writes body_mentions from two paths (the memo
-- pipeline `memo_llm` and the regex backfill `notes_scan`), both sourcing
-- severity from the CLOSED vocabulary in _shared/bodyVocabulary.ts:
-- tight | sore | pain | sharp. This migration pins that closed vocabulary
-- at the database level so a future writer can't silently widen it.
--
-- Append-only (hard rule #5). No new columns: `side` and `source` already
-- exist (migration 20260612130000) — `side` is populated by the new
-- writers, historical rows stay NULL and group as "unspecified".
--
-- Safe to apply against existing data: any legacy row whose severity_hint
-- falls outside the closed set (or is NULL) is first normalized to 'sore'
-- — the honest floor for "a body part was named" — so the CHECK cannot
-- fail on backfill.

begin;

-- 1. Normalize any out-of-vocabulary / NULL severity_hint before constraining.
update public.body_mentions
   set severity_hint = 'sore'
 where severity_hint is null
    or severity_hint not in ('tight', 'sore', 'pain', 'sharp');

-- 2. Add the closed-vocabulary CHECK, idempotently (constraints have no
--    IF NOT EXISTS, so guard on pg_constraint).
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'body_mentions_severity_hint_check'
      and conrelid = 'public.body_mentions'::regclass
  ) then
    alter table public.body_mentions
      add constraint body_mentions_severity_hint_check
      check (severity_hint in ('tight', 'sore', 'pain', 'sharp'));
  end if;
end $$;

-- 3. Document the two columns the rewrite gives real meaning to.
comment on column public.body_mentions.side is
  'Laterality when known: left | right. NULL = unspecified or bilateral — groups separately from sided mentions in niggle recurrence, never folded into a sided count.';

comment on column public.body_mentions.source is
  'Writer provenance: memo_llm (primary — the voice-memo niggle classifier, closed vocabulary + verbatim words + side) | notes_scan (regex backfill for TYPED manual notes and imported run descriptions; skips voice rows).';

commit;
