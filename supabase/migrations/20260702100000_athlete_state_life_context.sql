-- athlete_state — life_context satellite (qualitative voice-memo signal)
--
-- See outputs/athlete-state-knowledge-audit-2026-07-02.md hole #1 and
-- outputs/life-context-implementation-plan-2026-07-02.md.
--
-- Adds one more JSONB "satellite" block to the existing athlete_state row, in
-- the same append-only style as 20260615000000_athlete_state_fitness_signal.sql.
-- Assembled by rebuildAthleteState() from training_logs.extracted_data (the
-- structured qualitative fields the voice-memo pipeline already extracts:
-- sleep, work/life stress, fatigue, illness, travel, motivation,
-- felt_vs_looked, rpe) via _shared/builders/buildLifeContext.ts.
--
-- The slice stores the athlete's own labels verbatim (never reinterpreted,
-- never diagnostic — hard rule #2) as small recency-first rollups the Read
-- can reference ("feeling before data").
--
-- Nullable, no default beyond NULL, so existing rows and the existing rebuild
-- path are unaffected until the builder populates it. RLS on athlete_state
-- already covers this column (same row, existing policies) — no policy change
-- is required.

ALTER TABLE public.athlete_state
  ADD COLUMN IF NOT EXISTS life_context jsonb;

COMMENT ON COLUMN public.athlete_state.life_context IS
  'Qualitative life signal rolled up from voice-memo extracted_data: sleep, work/life stress, fatigue trail, illness, travel, motivation, felt_vs_looked, avg RPE. Athlete''s own labels, verbatim; surface, never diagnose. Built by _shared/builders/buildLifeContext.ts.';
