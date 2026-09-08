-- Manual (user-confirmed) fitness anchor on athlete_pace_profiles.
--
-- When the auto-derived projection is far off, the athlete (or their coach)
-- states a recent effort — a distance + time — and the pace engine derives the
-- whole zone ladder from it via race-equivalence, at the TOP of the precedence
-- chain (above the auto race/snapshot-derived columns). See
-- _shared/pace-engine.ts resolveRaceAnchors (source: "manual").
--
-- Additive + nullable: no behavior change for anyone until a value is set, so
-- existing pace zones are untouched. build-pace-profile writes only the auto
-- `*_pace_seconds` columns and must leave these alone, so the manual anchor
-- survives profile rebuilds until explicitly changed or cleared.
--
-- Append-only per hard rule #5; reaches prod via `supabase db push` from a
-- committed SHA (hard rule #9), never a dashboard/MCP apply.

ALTER TABLE athlete_pace_profiles
  ADD COLUMN IF NOT EXISTS manual_anchor_distance     TEXT,
  ADD COLUMN IF NOT EXISTS manual_anchor_time_seconds INTEGER,
  ADD COLUMN IF NOT EXISTS manual_anchor_date         DATE,
  ADD COLUMN IF NOT EXISTS manual_anchor_set_by       TEXT,
  ADD COLUMN IF NOT EXISTS manual_anchor_updated_at   TIMESTAMPTZ;

-- Distance must be one of the race-equivalence keys the engine understands
-- (raceKeyForInput). Null distance = no manual anchor.
ALTER TABLE athlete_pace_profiles
  ADD CONSTRAINT athlete_pace_profiles_manual_anchor_distance_check
  CHECK (
    manual_anchor_distance IS NULL
    OR manual_anchor_distance IN ('marathon','half','tenK','tenMi','fiveK','threeK','1500m','mile')
  );

-- Sanity rail on the effort time (30s–10h) — guards against bad input.
ALTER TABLE athlete_pace_profiles
  ADD CONSTRAINT athlete_pace_profiles_manual_anchor_time_check
  CHECK (
    manual_anchor_time_seconds IS NULL
    OR (manual_anchor_time_seconds >= 30 AND manual_anchor_time_seconds <= 36000)
  );
