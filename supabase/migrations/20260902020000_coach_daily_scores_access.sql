-- ============================================================================
-- Daily scores — coach read access (step 4 of the drip-scores handoff)
--
-- Coaches read their athletes' stress/recovery scores. The handoff asked for
-- a raw RLS SELECT policy on daily_scores plus "strip the stress element in
-- the coach UI when share_stress_with_coach is false". That client-side-only
-- strip is the exact defect pattern this repo has already shipped once
-- (niggles v2 extractor junk, defended client-side only), and no coach
-- scores UI exists yet to do the stripping — so the strip lives server-side:
--
--   - NO coach policy on the raw table. Athletes keep their own-rows SELECT
--     policy; service role keeps writes. A coach selecting daily_scores
--     directly gets nothing.
--   - coach_daily_scores view (SECURITY DEFINER semantics: owned by
--     postgres, security_invoker stays off deliberately) scopes rows to the
--     caller's active athletes via current_coach_id() and removes the
--     'stress' element from recovery_components unless the athlete opted in
--     via athlete_settings.share_stress_with_coach.
--
-- Any future coach surface (web portal, coach read prompt context) reads
-- the view and cannot leak what the view never returns.
-- ============================================================================

BEGIN;

CREATE OR REPLACE VIEW coach_daily_scores AS
SELECT
    ds.user_id,
    ds.score_date,
    ds.score_version,
    ds.srpe,
    ds.stress,
    ds.stress_components,
    ds.recovery,
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
    'surfaces must read this view, never the raw table. Note: fitness/'
    'fatigue/sessions are deliberately not exposed to coaches.';

-- Deliberately definer-owned; the EXISTS clause above is the access gate.
-- current_coach_id() returns NULL for non-coaches, so athletes and anon
-- callers match no rows even though the view bypasses table RLS.
REVOKE ALL ON coach_daily_scores FROM PUBLIC, anon;
GRANT SELECT ON coach_daily_scores TO authenticated;

COMMIT;

-- ============================================================================
-- Verification (run after applying):
--
-- 1. As a coach with an active athlete who has NOT opted in:
--      SELECT recovery_components FROM coach_daily_scores LIMIT 1;
--    Expected: no element with name='stress'.
-- 2. As an athlete (non-coach): SELECT count(*) FROM coach_daily_scores;
--    Expected: 0 (current_coach_id() is null).
-- 3. Raw-table check: as a coach, SELECT count(*) FROM daily_scores for an
--    athlete's user_id. Expected: 0 rows (no coach policy on the table).
-- ============================================================================
