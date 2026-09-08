-- athlete_state.niggle_recurrence — missing satellite column (v2 Phase C).
--
-- The Phase C builder writes a `niggle_recurrence` block (12-month niggle
-- recurrence from body_mentions), but the column was never added — it was
-- omitted from 20260612120000_athlete_state_v2_satellites.sql. Because the
-- rebuild upserts the whole AthleteState object, the unknown column made
-- PostgREST reject the entire upsert, so NO satellite data persisted (the
-- function still returned 200; the write silently failed).
--
-- Idempotent (IF NOT EXISTS) so it reconciles cleanly whether applied via
-- db push or already present.

ALTER TABLE public.athlete_state
  ADD COLUMN IF NOT EXISTS niggle_recurrence jsonb,
  -- PRE-EXISTING bug: the AthleteState interface and the rebuild have written
  -- `pace_zone_ranges` since before the v2 work, but the column never existed.
  -- Because rebuildAthleteState() doesn't check the upsert error, the FULL
  -- state write has been failing silently on this column for a long time —
  -- which is why athlete_state was stuck thin. Add it so the save succeeds.
  ADD COLUMN IF NOT EXISTS pace_zone_ranges jsonb;

COMMENT ON COLUMN public.athlete_state.niggle_recurrence IS
  'Durable 12-month niggle recurrence assembled from body_mentions (per body area: occurrences, first/last seen, worst severity).';
COMMENT ON COLUMN public.athlete_state.pace_zone_ranges IS
  'Engine pace-zone ranges (easy/moderate/steady/hmp) — coach-style bands, not midpoints.';
