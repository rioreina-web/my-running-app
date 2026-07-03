-- training_logs.stats_excluded — the athlete's explicit include/exclude
-- decision for analytics, overriding the server-side plausibility heuristic
-- used by trends-timeline.
--
--   NULL  → undecided. The heuristic applies: implausible runs (watch left
--           running etc.) are auto-excluded from stats AND surfaced as
--           "flagged" for the athlete to review.
--   true  → athlete TRIMMED it. Always excluded from stats.
--   false → athlete KEPT it. Always counted, even if the heuristic flagged it.
--
-- No new RLS policy is needed: owner UPDATE is already covered by
-- `auth_update_own_logs` and service-role by its full-access policy. RLS is
-- row-level, so the existing policies govern this new column too.
--
-- Append-only + idempotent (IF NOT EXISTS) per the migration conventions.

alter table public.training_logs
  add column if not exists stats_excluded boolean;

comment on column public.training_logs.stats_excluded is
  'Athlete include/exclude decision for analytics. NULL = auto (plausibility heuristic in trends-timeline), true = trimmed/excluded, false = kept/counted.';
