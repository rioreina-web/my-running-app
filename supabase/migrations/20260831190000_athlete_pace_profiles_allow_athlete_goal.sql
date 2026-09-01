-- Allow 'athlete_goal' as a pace-confidence tier on athlete_pace_profiles.
--
-- Context: GOAL-IA-APPLY.md / GOAL-ELEMENT-APPLY.md §5 rail 6. The goal
-- editor (GoalAndPacesCard, the onboarding sheet) saves through
-- update-plan-goal, which writes 'athlete_goal' into these six
-- *_confidence columns to mark a pace as goal-derived (aspirational)
-- rather than measured. The columns were still constrained to
-- ('high','medium','low'), so that upsert has been failing with a
-- Postgres CHECK violation in production (verified 2026-08-24, one
-- athlete_pace_profiles row, all 'high') — the athlete-only goal-save
-- path 500s.
--
-- Widening the constraint alone would make every future goal save
-- silently overwrite a fitness-derived pace with an aspirational one
-- (the rail 6 rule: "the goal never sets a pace the athlete trains at").
-- The demotion half of that fix lives in update-plan-goal/index.ts,
-- which now only upserts a pace column here when the existing row's
-- confidence for that column isn't already a measured tier
-- ('high'/'medium'/'low'). This migration and that function change ship
-- together — see 20260417100000_athlete_pace_profiles.sql for the
-- original constraints.

ALTER TABLE athlete_pace_profiles DROP CONSTRAINT IF EXISTS athlete_pace_profiles_easy_pace_confidence_check;
ALTER TABLE athlete_pace_profiles
  ADD CONSTRAINT athlete_pace_profiles_easy_pace_confidence_check
  CHECK (easy_pace_confidence IN ('high', 'medium', 'low', 'athlete_goal'));

ALTER TABLE athlete_pace_profiles DROP CONSTRAINT IF EXISTS athlete_pace_profiles_marathon_pace_confidence_check;
ALTER TABLE athlete_pace_profiles
  ADD CONSTRAINT athlete_pace_profiles_marathon_pace_confidence_check
  CHECK (marathon_pace_confidence IN ('high', 'medium', 'low', 'athlete_goal'));

ALTER TABLE athlete_pace_profiles DROP CONSTRAINT IF EXISTS athlete_pace_profiles_half_pace_confidence_check;
ALTER TABLE athlete_pace_profiles
  ADD CONSTRAINT athlete_pace_profiles_half_pace_confidence_check
  CHECK (half_pace_confidence IN ('high', 'medium', 'low', 'athlete_goal'));

ALTER TABLE athlete_pace_profiles DROP CONSTRAINT IF EXISTS athlete_pace_profiles_ten_k_pace_confidence_check;
ALTER TABLE athlete_pace_profiles
  ADD CONSTRAINT athlete_pace_profiles_ten_k_pace_confidence_check
  CHECK (ten_k_pace_confidence IN ('high', 'medium', 'low', 'athlete_goal'));

ALTER TABLE athlete_pace_profiles DROP CONSTRAINT IF EXISTS athlete_pace_profiles_five_k_pace_confidence_check;
ALTER TABLE athlete_pace_profiles
  ADD CONSTRAINT athlete_pace_profiles_five_k_pace_confidence_check
  CHECK (five_k_pace_confidence IN ('high', 'medium', 'low', 'athlete_goal'));

ALTER TABLE athlete_pace_profiles DROP CONSTRAINT IF EXISTS athlete_pace_profiles_mile_pace_confidence_check;
ALTER TABLE athlete_pace_profiles
  ADD CONSTRAINT athlete_pace_profiles_mile_pace_confidence_check
  CHECK (mile_pace_confidence IN ('high', 'medium', 'low', 'athlete_goal'));
