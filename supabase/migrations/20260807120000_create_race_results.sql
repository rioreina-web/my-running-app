-- ============================================================================
-- race_results — a first-class home for races and personal bests
--
-- Until now a "race" was a `race_result` JSONB blob hanging off a
-- `training_logs` row, rolled up into the derived `athlete_state.confirmed_races`
-- array. That shape has three problems, and this table fixes each:
--
--   1. NO PLACE FOR THE OFFICIAL TIME. The blob stores one number, taken from
--      the activity — which is moving time. An athlete whose chip time was
--      2:23:30 has 2:22:43 on file, 47 seconds fast, because the watch stopped
--      and the race clock didn't. A PR is an OFFICIAL result; the recording is
--      evidence. Both are stored here, separately, and neither overwrites the
--      other.
--   2. NO RACE WITHOUT AN ACTIVITY. A PR from 2019, a race run on a borrowed
--      watch, a result read off a results page — none of these have a
--      `training_logs` row to hang off, so none could be recorded at all.
--      `training_log_id` is nullable here.
--   3. DELETING A RUN DELETED A RACE. The blob lived on the log, so cleaning up
--      a duplicate activity silently destroyed the result. The FK is
--      ON DELETE SET NULL: the race outlives its recording.
--
-- PRs ARE DERIVED, NEVER STORED. There is no `is_pr` column on purpose — a
-- stored flag goes stale the moment a faster race lands, and then two rows
-- disagree about the truth. `race_prs` (below) computes it at read time.
--
-- PROVENANCE. `training_log_id` links to the activity, which already carries
-- `source` ('strava' | 'strava_backfill' | 'voice_log' | …) and `external_id`.
-- `external_ref` copies that id here so the trail to the original Garmin or
-- Strava upload survives even if the log row is later removed. Note that
-- backfilled activities carry a synthetic id (`strava_backfill_<uuid>`) rather
-- than a real Strava activity number, so not every race can be linked back to
-- a clickable upload — `external_ref` records what we have, honestly.
--
-- user_id is TEXT to match auth.uid()::text — the schema-wide convention.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS race_results (
    id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id                TEXT NOT NULL,

    -- The activity this race was run as, when there is one. Nullable by design
    -- (a race predating the app, or one never recorded), and SET NULL on delete
    -- so removing a duplicate activity never destroys the result.
    training_log_id        UUID REFERENCES training_logs(id) ON DELETE SET NULL,
    -- The upload's own id, copied so provenance survives the log row.
    external_ref           TEXT,

    race_date              DATE NOT NULL,
    -- Closed vocabulary, mirroring `paces.ts` race keys. `other` carries its
    -- own distance so an odd race (a 4-miler, a 50K) is still recordable
    -- without polluting the equivalence table.
    distance_key           TEXT NOT NULL,
    distance_meters        NUMERIC,

    -- THE RESULT. What the clock at the finish line said.
    official_time_seconds  INTEGER,
    -- What the watch recorded. Kept alongside, never merged: the gap between
    -- them is real information (stopped watch, long tangents, late start).
    recorded_time_seconds  INTEGER,

    event_name             TEXT,
    location               TEXT,
    bib                    TEXT,
    finish_place           INTEGER,
    conditions             TEXT,
    notes                  TEXT,

    -- How this row got here. 'detected' = inferred from an activity;
    -- 'athlete' = entered or corrected by the athlete; 'official' = reconciled
    -- against a published result. Precedence for anchoring runs in that order.
    source                 TEXT NOT NULL DEFAULT 'athlete',
    -- The athlete has looked at this row and affirmed it. An un-affirmed
    -- detected race should never silently become a PR the product quotes back.
    confirmed_at           TIMESTAMPTZ,

    created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT race_results_distance_chk CHECK (
        distance_key IN ('mile','3k','5k','8k','10k','12k','15k','10mile',
                         'half','marathon','50k','other')
    ),
    CONSTRAINT race_results_source_chk CHECK (
        source IN ('detected','athlete','official')
    ),
    -- A race with neither time is not a result.
    CONSTRAINT race_results_has_a_time_chk CHECK (
        official_time_seconds IS NOT NULL OR recorded_time_seconds IS NOT NULL
    ),
    -- Sanity bounds: 2 minutes to 24 hours. Catches a milliseconds-vs-seconds
    -- unit slip at write time rather than at read time.
    CONSTRAINT race_results_official_range_chk CHECK (
        official_time_seconds IS NULL
        OR (official_time_seconds BETWEEN 120 AND 86400)
    ),
    CONSTRAINT race_results_recorded_range_chk CHECK (
        recorded_time_seconds IS NULL
        OR (recorded_time_seconds BETWEEN 120 AND 86400)
    ),
    -- `other` must say how far it actually was, or it can't be compared.
    CONSTRAINT race_results_other_needs_distance_chk CHECK (
        distance_key <> 'other' OR distance_meters IS NOT NULL
    )
);

COMMENT ON TABLE race_results IS
    'Race results and personal bests. One row per race. official_time_seconds '
    'is the finish-line clock and is what a PR is measured on; '
    'recorded_time_seconds is what the watch said. PRs are derived at read '
    'time via the race_prs view, never stored as a flag.';

COMMENT ON COLUMN race_results.official_time_seconds IS
    'The finish-line result. Authoritative for PRs and for pace anchoring.';
COMMENT ON COLUMN race_results.recorded_time_seconds IS
    'What the recording device captured (moving time). Usually faster than the '
    'official clock. Never overwrites the official time.';
COMMENT ON COLUMN race_results.external_ref IS
    'The source upload id copied from training_logs.external_id, so the trail '
    'to Garmin/Strava survives deletion of the log. Backfilled activities carry '
    'a synthetic id and cannot be linked to a real upload.';

-- One race per athlete per day per distance. Re-running the backfill, or a
-- duplicate activity being detected twice, updates rather than multiplies.
CREATE UNIQUE INDEX IF NOT EXISTS race_results_unique_race_idx
    ON race_results (user_id, race_date, distance_key);

CREATE INDEX IF NOT EXISTS race_results_user_date_idx
    ON race_results (user_id, race_date DESC);

CREATE INDEX IF NOT EXISTS race_results_user_distance_idx
    ON race_results (user_id, distance_key, race_date DESC);

CREATE INDEX IF NOT EXISTS race_results_training_log_idx
    ON race_results (training_log_id)
    WHERE training_log_id IS NOT NULL;

-- ── The PR view ─────────────────────────────────────────────────────────────
-- Fastest result per athlete per distance. Prefers the official time and falls
-- back to the recorded one, because a race with only a watch time is still a
-- race — it is just less authoritative, which `time_is_official` reports.
CREATE OR REPLACE VIEW race_prs AS
SELECT DISTINCT ON (user_id, distance_key)
    user_id,
    distance_key,
    id                AS race_result_id,
    race_date,
    COALESCE(official_time_seconds, recorded_time_seconds) AS pr_seconds,
    (official_time_seconds IS NOT NULL)                    AS time_is_official,
    official_time_seconds,
    recorded_time_seconds,
    event_name,
    training_log_id,
    external_ref,
    source,
    confirmed_at
FROM race_results
ORDER BY
    user_id,
    distance_key,
    COALESCE(official_time_seconds, recorded_time_seconds) ASC,
    race_date DESC;

COMMENT ON VIEW race_prs IS
    'Derived personal bests: the fastest race per athlete per distance. '
    'Computed at read time so a new faster race can never leave a stale flag '
    'behind. time_is_official = false means the PR rests on a watch time.';

-- ── RLS (hard rule #1: same migration as the table) ─────────────────────────
ALTER TABLE race_results ENABLE ROW LEVEL SECURITY;

CREATE POLICY "athletes read own races"
    ON race_results FOR SELECT
    USING (user_id = (auth.uid())::text);

-- Races ARE athlete-owned in a way niggles are not: the athlete is the
-- authority on what they ran. Direct write is allowed, unlike body_mentions.
CREATE POLICY "athletes write own races"
    ON race_results FOR INSERT
    WITH CHECK (user_id = (auth.uid())::text);

CREATE POLICY "athletes update own races"
    ON race_results FOR UPDATE
    USING (user_id = (auth.uid())::text)
    WITH CHECK (user_id = (auth.uid())::text);

CREATE POLICY "athletes delete own races"
    ON race_results FOR DELETE
    USING (user_id = (auth.uid())::text);

-- ── Backfill ────────────────────────────────────────────────────────────────
-- Lift every race already inferred from an activity. These land as 'detected'
-- with the activity's time in `recorded_time_seconds` and `official_time_seconds`
-- left NULL — because that is the truth: nobody has ever confirmed the official
-- result. `confirmed_at` stays null so the UI can ask the athlete to check them,
-- which is exactly how the 47-second discrepancy gets corrected.
INSERT INTO race_results (
    user_id, training_log_id, external_ref, race_date, distance_key,
    recorded_time_seconds, source, confirmed_at
)
SELECT
    t.user_id,
    t.id,
    t.external_id,
    (t.workout_date AT TIME ZONE 'UTC')::date,
    CASE lower(t.race_result->>'distance')
        WHEN 'mile'     THEN 'mile'
        WHEN '3k'       THEN '3k'
        WHEN '5k'       THEN '5k'
        WHEN '8k'       THEN '8k'
        WHEN '10k'      THEN '10k'
        WHEN '12k'      THEN '12k'
        WHEN '15k'      THEN '15k'
        WHEN '10mile'   THEN '10mile'
        WHEN '10 mile'  THEN '10mile'
        WHEN 'half'     THEN 'half'
        WHEN 'half marathon' THEN 'half'
        WHEN 'marathon' THEN 'marathon'
        WHEN '50k'      THEN '50k'
        ELSE 'other'
    END,
    NULLIF(t.race_result->>'finish_time_seconds','')::integer,
    'detected',
    NULL
FROM training_logs t
WHERE t.race_result IS NOT NULL
  AND t.user_id IS NOT NULL
  AND NULLIF(t.race_result->>'finish_time_seconds','')::integer BETWEEN 120 AND 86400
  -- 'other' needs a distance we don't have from the blob, so skip rather than
  -- violate the constraint. Those get entered by hand.
  AND lower(t.race_result->>'distance') IN (
        'mile','3k','5k','8k','10k','12k','15k','10mile','10 mile',
        'half','half marathon','marathon','50k')
ON CONFLICT (user_id, race_date, distance_key) DO NOTHING;

COMMIT;
