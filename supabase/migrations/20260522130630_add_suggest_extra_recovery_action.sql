-- ============================================================================
-- Add 'suggest_extra_recovery' to the coachable_moments.action_type enum.
--
-- Used by the new `weather_impacted_quality` rule to recommend protecting
-- the recovery window after a heat-affected quality session.
--
-- Distinct from `suggest_deload`:
--   - suggest_deload         → multi-day pull-back in training load
--   - suggest_extra_recovery → protect the next 24-72h post-workout
--                              (defer next quality, keep easy days truly easy)
--
-- Spec: docs/specs/coachable_moment.md
-- ============================================================================

ALTER TABLE coachable_moments
    DROP CONSTRAINT IF EXISTS coachable_moments_action_type_check;

ALTER TABLE coachable_moments
    ADD CONSTRAINT coachable_moments_action_type_check
    CHECK (action_type IN (
        'send_check_in',
        'suggest_deload',
        'recommend_evaluation',
        'monitor',
        'suggest_extra_recovery'
    ));
