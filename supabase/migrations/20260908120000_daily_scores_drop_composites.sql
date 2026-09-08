-- ============================================================================
-- Daily scores — the 0-100 composites stop being a product surface
--
-- Owner decision 2026-09-08. This is the SECOND time this composite has been
-- cut; the first was 2026-08-24, when `TrendsRecoveryLedger` and its whole
-- surface were deleted from the iOS app. That decision left a written guard
-- ("do not re-propose a composite number, a 0-100 dial, or a single
-- 'recovery' figure without new validation evidence") but the guard was
-- written about Swift, and `compute_daily_scores()` reintroduced the same
-- arithmetic server-side, where it also reached the Daily Read's model
-- context and the coach view.
--
-- The evidence against it (214-day replay, 2026-08-18):
--   - the composite never left a 37-point strip (29-66, mean 48);
--   - it had no relationship with felt_rpe;
--   - it did not separate rest days from run days;
--   - it did not move ahead of the only injury in the window.
-- A single figure CANCELS opposing signals — "sleep fine + load enormous"
-- and "sleep terrible + load tiny" collapse to the same value — and that
-- cancellation is the mechanism behind the flat strip. The recovery half is
-- worse: it is 100-minus-deductions over five signals of which four are
-- routinely silent, so a day where nothing was recorded scores 100, exactly
-- like a day of perfect health.
--
-- WHAT THIS MIGRATION DOES NOT DO: it does not drop `daily_scores.stress` /
-- `.recovery`, and does not change `compute_daily_scores()`. The scorer's
-- component arithmetic still runs, because the per-component POINTS remain
-- useful as an internal "is this row saying anything" flag — the same status
-- `injury-early-warning`'s 0-10 risk score has (a trigger, never a displayed
-- figure). What changes is that no consumer may surface the composites.
--
-- Consumers updated in the same change:
--   - RunningLog/.../StressRecoveryView.swift — no longer selects or models
--     `stress`/`recovery`; plots fitness/fatigue in load units instead.
--   - supabase/functions/coaching-daily-read — no longer puts either number
--     in the model's context.
--   - coach_daily_scores — this migration.
-- ============================================================================

BEGIN;

COMMENT ON COLUMN daily_scores.stress IS
    'RETIRED AS A SURFACE 2026-09-08 — internal only. Sum of the '
    'stress_components points. Never render this, never send it to a model, '
    'never expose it in a view. See the migration header and '
    'project_recovery_score_model for the validation evidence. The '
    'components'' own reason sentences are the shippable artefact.';

COMMENT ON COLUMN daily_scores.recovery IS
    'RETIRED AS A SURFACE 2026-09-08 — internal only. 100 minus the '
    'recovery_components deductions, which means SILENCE SCORES AS HEALTH: '
    'with four of five signals routinely absent this reads 100 on a day '
    'nothing was recorded. Never render, never narrate, never expose. See '
    'the migration header.';

COMMENT ON COLUMN daily_scores.recovery_confidence IS
    'How many recovery signals actually reported: none / low (one) / ok '
    '(two or more). This one IS shippable — it is coverage, not a grade, '
    'and it is what makes silence legible as silence.';

-- The coach view loses both composites and gains the two quantities that are
-- modelled rather than assigned. CREATE OR REPLACE cannot drop columns.
DROP VIEW IF EXISTS coach_daily_scores;

CREATE VIEW coach_daily_scores AS
SELECT
    ds.user_id,
    ds.score_date,
    ds.score_version,
    ds.srpe,
    ds.fitness,
    ds.fatigue,
    ds.stress_components,
    ds.recovery_confidence,
    CASE
        WHEN COALESCE(s.share_stress_with_coach, false) THEN ds.recovery_components
        ELSE (
            SELECT COALESCE(jsonb_agg(c), '[]'::jsonb)
              FROM jsonb_array_elements(ds.recovery_components) c
             WHERE c->>'name' <> 'stress'
        )
    END AS recovery_components,
    ds.computed_at
FROM daily_scores ds
LEFT JOIN athlete_settings s ON s.user_id = ds.user_id
WHERE EXISTS (
    SELECT 1
      FROM coach_athlete_relationships car
     WHERE car.athlete_user_id = ds.user_id
       AND car.coach_id = current_coach_id()
       AND car.status = 'active'
);

COMMENT ON VIEW coach_daily_scores IS
    'Coach-facing read of daily_scores, scoped to the caller''s active '
    'athletes via current_coach_id(). Strips the outside-stress recovery '
    'component server-side unless athlete_settings.share_stress_with_coach. '
    'Deliberately definer-owned (no security_invoker) so it can see through '
    'daily_scores RLS; the WHERE clause is the access control. Coach '
    'surfaces must read this view, never the raw table. '
    'The 0-100 stress/recovery composites are deliberately NOT exposed '
    '(retired 2026-09-08); fitness/fatigue are, in load units, because they '
    'are modelled quantities rather than assigned points. Do not add the '
    'composites back — a coach reading a number the athlete cannot see, and '
    'that failed its own validation, is the worst placement of the two.';

-- Definer-owned; the EXISTS clause above is the access gate.
-- current_coach_id() returns NULL for non-coaches, so athletes and anon
-- callers match no rows even though the view bypasses table RLS.
REVOKE ALL ON coach_daily_scores FROM PUBLIC, anon;
GRANT SELECT ON coach_daily_scores TO authenticated;

COMMIT;

-- ============================================================================
-- Verification (run after applying):
--
-- 1. SELECT column_name FROM information_schema.columns
--     WHERE table_name = 'coach_daily_scores' ORDER BY ordinal_position;
--    Expected: no 'stress', no 'recovery'; fitness and fatigue present.
-- 2. As a coach with an active athlete who has NOT opted in:
--      SELECT recovery_components FROM coach_daily_scores LIMIT 1;
--    Expected: no element with name='stress'.
-- 3. As an athlete (non-coach): SELECT count(*) FROM coach_daily_scores;
--    Expected: 0 (current_coach_id() is null).
-- ============================================================================
