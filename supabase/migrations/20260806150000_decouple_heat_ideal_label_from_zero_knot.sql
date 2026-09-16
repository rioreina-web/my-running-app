-- Heat LABEL boundary decoupled from the adjustment table's zero knot.
--
-- WHY
-- ---
-- `heat_category_for()` (20260528222217) put "ideal" below composite 100 —
-- the same number the adjustment table uses as its zero knot. That was a
-- collision, not a decision.
--
-- Below the 65F dew pivot the dew multiplier is flat (1.01), so the composite
-- is essentially `temp + dew`. That put the ideal/warm line at `temp + dew ~ 99`
-- and dropped a 55F morning with a 45F dew point -- composite 100.45, one of
-- the better days of the year to run -- into 'warm'. iOS renders that as a sun
-- icon, the word "Warm", and a warm-tinted card (PaceChartView.swift). The time
-- cost being flagged: 0.0225%. A fifth of a second per mile.
--
-- The table's zero at 100 is a physical claim (below it, heat costs no time)
-- and is UNCHANGED by this migration. The label answers a different question --
-- "was this day a factor" -- so 'ideal' now runs to 110, where the cost first
-- reaches ~0.5%.
--
-- Four implementations share this ladder; all four move together:
--   supabase/functions/_shared/pace-heat-adjustment.ts  heatCategory()
--   supabase/functions/_shared/pace-heat.ts             heatCategoryFromScore()
--   RunningLog/RunningLog/Workouts/PaceCalculator.swift heatCategory
--   this function
--
-- No enum/CHECK change: the constraint already allows all five labels
-- ('ideal','warm','hot','very_hot','dangerous') and no new value is introduced.
-- Existing rows are re-stamped below so stored labels match the new ladder;
-- only rows in the 100..110 band change, and only their label -- no pace,
-- percentage, or composite score is touched.

CREATE OR REPLACE FUNCTION heat_category_for(score NUMERIC)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
    SELECT CASE
        WHEN score IS NULL THEN NULL
        WHEN score <  110 THEN 'ideal'
        WHEN score <  130 THEN 'warm'
        WHEN score <  150 THEN 'hot'
        WHEN score <  170 THEN 'very_hot'
        ELSE                   'dangerous'
    END;
$$;

COMMENT ON FUNCTION heat_category_for(NUMERIC) IS
  'Heat LABEL from composite score. ''ideal'' runs to 110, deliberately NOT to '
  'the adjustment table''s zero knot at 100 -- the two answer different '
  'questions. Mirrored in pace-heat-adjustment.ts, pace-heat.ts, and '
  'PaceCalculator.swift; change all four together.';

-- Re-stamp the label on the affected band only (composite 100..110, previously
-- 'warm', now 'ideal'). Guarded so it is a no-op on a fresh database.
UPDATE running_workout_laps
SET    heat_category = heat_category_for(heat_composite_score)
WHERE  heat_composite_score IS NOT NULL
  AND  heat_composite_score >= 100
  AND  heat_composite_score <  110
  AND  heat_category IS DISTINCT FROM heat_category_for(heat_composite_score);
