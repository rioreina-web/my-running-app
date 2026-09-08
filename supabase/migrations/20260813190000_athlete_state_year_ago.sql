-- athlete_state.year_ago — the column the rebuild has been writing since the
-- "this time last year" line landed, and which was never added to the table.
--
-- Why this is a P0 (found 2026-08-13)
-- ───────────────────────────────────
-- `rebuildAthleteState` builds one `state` object and spreads it straight into
--   supabase.from("athlete_state").upsert(state, { onConflict: "user_id" })
-- so a single key with no matching column fails the WHOLE upsert, not just
-- that field. `year_ago` (athlete-state.ts:1922) is that key. Every rebuild
-- since has logged
--   [AthleteState] state upsert FAILED (rebuild not persisted):
--   Could not find the 'year_ago' column of 'athlete_state' in the schema cache
-- and thrown its work away.
--
-- The visible damage: the served state is frozen at the last successful
-- rebuild. `last_updated_at` sat at the epoch (1970-01-01) with
-- `last_updated_by = 'invalidated:training_log_UPDATE'` — invalidated, then
-- never rebuilt. Every surface reading athlete_state (the recovery read's
-- hard-session count and spacing, load trend, fitness prediction, the coach's
-- context) has been serving a stale snapshot, which is what "the readiness
-- stats are wrong" turned out to mean.
--
-- Shape mirrors the TS type at athlete-state.ts:304 —
--   { weekly_avg_miles: number; mood_summary: string | null } | null
--
-- Nullable and additive: a rebuild that has no 52-week-old data writes null,
-- which is the same thing the type already says.

ALTER TABLE public.athlete_state
  ADD COLUMN IF NOT EXISTS year_ago jsonb;

COMMENT ON COLUMN public.athlete_state.year_ago IS
  'This time last year: { weekly_avg_miles, mood_summary }. Written by rebuildAthleteState; null when there is no 52-week-old data.';
