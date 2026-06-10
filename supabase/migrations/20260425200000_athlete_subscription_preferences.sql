-- ============================================================================
-- Athlete subscription preferences
--
-- The `athlete_plan_subscriptions` table is the per-subscription customization
-- layer. The plan template holds coach defaults; the subscription holds the
-- athlete's overrides. The `subscribe-to-plan` materializer reads both and
-- the athlete's overrides win.
--
-- See athlete-onboarding-redesign.md for the full design + open questions
-- (resolved 2026-04-25).
--
-- All columns are nullable / default empty so the migration is backwards-
-- compatible: existing subscriptions don't break, and the materializer
-- treats missing values as "use coach's defaults."
-- ============================================================================

BEGIN;

ALTER TABLE athlete_plan_subscriptions
    -- Multi-day rest. Empty array = no forced rest day. Athlete decides;
    -- no nudge, no recommendation. Some athletes rest Mon+Thu, some rest
    -- only Sunday, some rest never. All valid.
    ADD COLUMN IF NOT EXISTS rest_dows INTEGER[] NOT NULL DEFAULT '{}'::INTEGER[],

    -- Days the athlete WANTS quality workouts on. Defaults to coach's
    -- pattern (typically Tue/Thu/Sat). Athlete picks exactly the days they
    -- can hit hard sessions (e.g., Tue+Sat for an athlete with a track
    -- group + Saturday long run).
    ADD COLUMN IF NOT EXISTS preferred_quality_dows INTEGER[],

    -- Day the long run lands on. Separate from quality_dows because
    -- it's typically the same day every week and benefits from being
    -- explicit (Saturday for most marathoners; Sunday for athletes with
    -- weekend race commitments).
    ADD COLUMN IF NOT EXISTS long_run_dow INTEGER
        CHECK (long_run_dow IS NULL OR (long_run_dow BETWEEN 0 AND 6)),

    -- Volume ramp config. Controls how starting weekly mileage transitions
    -- from the athlete's current baseline to the coach's prescribed range.
    -- Shape: { start_mileage, ramp_to_coach_target, ramp_weeks }
    ADD COLUMN IF NOT EXISTS volume_ramp JSONB,

    -- Shape preferences (strides_pre_quality, recovery_after_long,
    -- doubles_on_easy_days). Athlete's overrides win over the template's
    -- shape_prefs which win over hardcoded fallbacks.
    ADD COLUMN IF NOT EXISTS shape_prefs JSONB,

    -- Athlete-reported baseline at subscribe time. Pre-filled from logs
    -- when available (last 4-week rolling average); athlete can override
    -- or answer directly when no log history exists. Drives volume_ramp
    -- start.
    ADD COLUMN IF NOT EXISTS current_weekly_mileage NUMERIC(5,1)
        CHECK (current_weekly_mileage IS NULL OR (current_weekly_mileage >= 0 AND current_weekly_mileage <= 200));

-- Element-level check on rest_dows array — each entry must be a valid dow.
-- Postgres doesn't natively check element types in array CHECK constraints
-- the way it does for scalar columns, so we use the array containment
-- operator: rest_dows must be a subset of {0,1,2,3,4,5,6}.
ALTER TABLE athlete_plan_subscriptions
    ADD CONSTRAINT athlete_plan_subscriptions_rest_dows_valid
        CHECK (rest_dows <@ ARRAY[0,1,2,3,4,5,6]);

-- Same containment check for preferred_quality_dows when set.
ALTER TABLE athlete_plan_subscriptions
    ADD CONSTRAINT athlete_plan_subscriptions_quality_dows_valid
        CHECK (preferred_quality_dows IS NULL
               OR preferred_quality_dows <@ ARRAY[0,1,2,3,4,5,6]);


-- ----------------------------------------------------------------------------
-- Column comments for self-documentation
-- ----------------------------------------------------------------------------

COMMENT ON COLUMN athlete_plan_subscriptions.rest_dows IS
    'Athlete-chosen rest days (0=Mon..6=Sun). Empty array = no forced rest. '
    'Multi-day allowed. Resolved Q3 in athlete-onboarding-redesign.md: '
    'athlete decided, no nudge.';

COMMENT ON COLUMN athlete_plan_subscriptions.preferred_quality_dows IS
    'Days the athlete wants quality workouts. NULL = use coach''s pattern. '
    'Materializer respects the selection — coach''s 2 quality sessions land '
    'on the athlete''s picked days, not a default Tue/Thu/Sat.';

COMMENT ON COLUMN athlete_plan_subscriptions.long_run_dow IS
    'Long run day (0=Mon..6=Sun). NULL = use coach''s pattern (typically '
    'whichever quality day has the most miles).';

COMMENT ON COLUMN athlete_plan_subscriptions.volume_ramp IS
    'JSON: { start_mileage: number, ramp_to_coach_target: bool, ramp_weeks: int }. '
    'NULL = no ramp; use coach''s targetMilesMin/Max as-is from week 1.';

COMMENT ON COLUMN athlete_plan_subscriptions.shape_prefs IS
    'JSON: { strides_pre_quality: bool, recovery_after_long: bool, '
    'doubles_on_easy_days: bool }. NULL or missing keys fall back to '
    'template defaults, which fall back to hardcoded defaults.';

COMMENT ON COLUMN athlete_plan_subscriptions.current_weekly_mileage IS
    'Athlete-reported or log-derived weekly mileage at subscribe time. '
    'Drives the volume ramp start (volume_ramp.start_mileage). Refreshed '
    'when the athlete reopens the subscription edit sheet (Phase 5 of '
    'onboarding redesign).';


COMMIT;
