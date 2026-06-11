-- ============================================================================
-- Add 'journey_comparison' to the coachable_moments.action_type enum.
--
-- Used by the new `build_vs_last_cycle` rule (Phase 2 sub-task F) — the
-- first race-aware coachable moment. A journey_comparison is a pure
-- pattern observation (current build measured against the athlete's
-- prior race cycle) with no operational ask attached.
--
-- Distinct from `monitor`:
--   - monitor            → operational: coach should keep an eye on a
--                          developing situation
--   - journey_comparison → observational: a narrative data point for the
--                          athlete's journey (Coach Read context); per the
--                          Q17 follow-up decision, pattern observations may
--                          surface directly to self-coached athletes
--
-- Spec: outputs/phase-2-race-anchoring-plan-2026-06-04.md sub-task F;
--       docs/specs/coachable_moment.md
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
        'suggest_extra_recovery',
        'journey_comparison'
    ));
