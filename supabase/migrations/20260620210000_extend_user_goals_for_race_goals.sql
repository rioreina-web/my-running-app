-- Extend user_goals into a natural-language race-goal record.
--
-- Context: user_goals previously stored only a free-text goal_title plus a
-- target_date. The goal feature is being reframed (see
-- outputs/race-goals-build-plan-2026-06-20.md) around natural-language entry:
-- an athlete types or speaks a goal in their own words ("stay injury-free and
-- run a BQ at CIM in December"), the app parses it into a structured
-- interpretation, derives a quantitative pace anchor, and asks the athlete to
-- confirm before it counts. This migration makes user_goals the single source
-- of truth for that record.
--
-- Three layers, all on this row:
--   1. raw_statement       — the athlete's verbatim words (quote, never coerce).
--   2. interpretation      — structured facets the parser extracted (JSONB,
--                            free to evolve without schema churn).
--   3. target_race_distance + target_time_seconds — the *derived* quantitative
--                            anchor that pace math (derivePaceTableFromGoal /
--                            build-pace-profile) consumes. Distance is OPEN
--                            free text (athletes target 50k, relays, odd local
--                            races), normalized to a pace key at the app layer
--                            (raceKeyForInput); only recognized distances drive
--                            pace zones, others store fine. The time is an
--                            internal handle — the goal's *framing* ("sub-3",
--                            "BQ") lives in interpretation and is what the coach
--                            actually speaks.
-- Plus a confirmation gate (athlete_confirmed) so an unverified parse never
-- silently drives training — consistent with "AI advises, never acts."
--
-- Append-only and additive. RLS already exists on user_goals (athlete-scoped
-- by user_id via the current FOR ALL policy) and covers the new columns
-- automatically; enable is re-asserted defensively.

-- 1. New columns. All nullable / defaulted so every existing row stays valid.
ALTER TABLE user_goals
  ADD COLUMN IF NOT EXISTS raw_statement        TEXT,
  ADD COLUMN IF NOT EXISTS interpretation       JSONB,
  ADD COLUMN IF NOT EXISTS target_race_distance TEXT,
  ADD COLUMN IF NOT EXISTS target_time_seconds  INTEGER,
  ADD COLUMN IF NOT EXISTS athlete_confirmed    BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS confirmed_at         TIMESTAMPTZ;

COMMENT ON COLUMN user_goals.raw_statement IS
  'The athlete''s goal in their own words (typed or transcribed). Stored verbatim; never coerced.';
COMMENT ON COLUMN user_goals.interpretation IS
  'Structured parse of raw_statement. Evolving shape, e.g. {performance_targets:[{race_distance,target_time_seconds,basis}], constraints:["injury_free"], named_race:{name,event_date,location,race_intel_id}, priority, confidence}. Object or NULL.';
COMMENT ON COLUMN user_goals.target_race_distance IS
  'Open free-text distance as the athlete framed it (e.g. "marathon", "50k", "marathon relay", "backyard ultra"). NOT a closed enum. Normalized to a pace key at the app layer (raceKeyForInput); recognized distances drive pace zones, others are stored but non-derivable. NULL = unset.';
COMMENT ON COLUMN user_goals.target_time_seconds IS
  'Derived goal finish time in seconds — an internal handle, not what the coach speaks (the framing in interpretation, e.g. "sub-3", is). NULL = no time target. Sanity bounds 600..86400.';
COMMENT ON COLUMN user_goals.athlete_confirmed IS
  'TRUE once the athlete has reviewed the parsed interpretation and confirmed it. Unconfirmed goals must not silently drive training context.';

-- 2. Value constraints. NULL allowed throughout so a partial / in-progress
--    goal is valid; interpretation must be a JSON object when present.
DO $$
BEGIN
  -- Distance is intentionally OPEN (no closed enum) so unusual races are
  -- never rejected. Guard only against empty/garbage values; the app layer
  -- normalizes to a pace key and decides what's pace-derivable.
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_goals_target_race_distance_len_check') THEN
    ALTER TABLE user_goals
      ADD CONSTRAINT user_goals_target_race_distance_len_check
      CHECK (
        target_race_distance IS NULL
        OR char_length(btrim(target_race_distance)) BETWEEN 1 AND 64
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_goals_target_time_seconds_check') THEN
    ALTER TABLE user_goals
      ADD CONSTRAINT user_goals_target_time_seconds_check
      CHECK (
        target_time_seconds IS NULL
        OR (target_time_seconds BETWEEN 600 AND 86400)
      );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'user_goals_interpretation_is_object_check') THEN
    ALTER TABLE user_goals
      ADD CONSTRAINT user_goals_interpretation_is_object_check
      CHECK (
        interpretation IS NULL
        OR jsonb_typeof(interpretation) = 'object'
      );
  END IF;
END $$;

-- 3. Fast lookup of an athlete's active, confirmed goal — the path the
--    athlete_state rebuild (Phase 3) uses to pull "the goal that counts".
CREATE INDEX IF NOT EXISTS idx_user_goals_user_active
  ON user_goals (user_id)
  WHERE status = 'active';

-- 4. RLS already enabled and athlete-scoped; re-assert enable defensively.
ALTER TABLE user_goals ENABLE ROW LEVEL SECURITY;
