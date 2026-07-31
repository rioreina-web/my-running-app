-- Add an optional athlete-authored title to journal entries.
--
-- The journal entry header has always been the derived day-of-week
-- (e.g. "Wednesday"). Athletes asked to name entries themselves
-- ("Long run — felt strong"), so this adds a free-text `title` that the
-- entry detail shows as the header when set, falling back to the day/date
-- when empty. Purely additive: nullable, no default, no backfill — every
-- existing row keeps rendering the day-of-week header until a title is set.
--
-- RLS: training_logs already enforces per-user row security; a new column is
-- covered by the existing row policies, so no policy change is needed
-- (see docs/conventions/rls-checklist.md — column adds inherit table RLS).

ALTER TABLE public.training_logs
    ADD COLUMN IF NOT EXISTS title text;

COMMENT ON COLUMN public.training_logs.title IS
    'Optional athlete-authored entry title. Shown as the journal entry header when set; entry falls back to the day-of-week/date when null or empty.';
