/**
 * CONTRACT TEST — heat adjustment is a FRACTION, not a percent.
 *
 * `adjustPaceForHeat().adjustmentPercent` and the persisted
 * `running_workout_laps.heat_adjustment_pct` it feeds are FRACTIONS
 * (0.02 == 2%). The field name says "pct" but the value is a fraction — that
 * mismatch caused the June 2026 "every run shows 0% heat" bug: athlete-state
 * read the fraction as a percent and filtered `>= 2` (always false), so the
 * Read's conditions block was permanently empty.
 *
 * Any consumer that DISPLAYS a percent must ×100. If you change the producer
 * to emit percent, this test breaks — fix every consumer in lockstep
 * (athlete-state.ts environment block + the iOS workout-detail toggle).
 *
 * Run: deno test _shared/pace-heat.contract.test.ts
 */
import { assert, assertAlmostEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { adjustPaceForHeat } from "./pace-heat.ts";

Deno.test("heat adjustment is a fraction in [0,1), not a percent", () => {
  const cool = adjustPaceForHeat(420, 50, 45); // composite < 100 → 0
  assertAlmostEquals(cool.adjustmentPercent, 0.0, 0.005);

  const warm = adjustPaceForHeat(420, 72, 62); // ~1.8%
  assert(
    warm.adjustmentPercent > 0.01 && warm.adjustmentPercent < 0.03,
    `warm should be a ~0.018 fraction, got ${warm.adjustmentPercent}`,
  );

  const hot = adjustPaceForHeat(420, 85, 72); // ~5.5%
  assert(
    hot.adjustmentPercent > 0.04 && hot.adjustmentPercent < 0.07,
    `hot should be a ~0.055 fraction, got ${hot.adjustmentPercent}`,
  );
  // The cardinal guard: a fraction, never an already-multiplied percent.
  assert(hot.adjustmentPercent < 1, "heat adjustment must be a fraction (<1), not a percent");
});

Deno.test("fraction → percent for display reproduces golden athlete May 19/20", () => {
  // Goldens for user 03857bf3…: May 20 (67°F/67°dew), May 19 (85°F/71°dew).
  //
  // RECALIBRATED 2026-08-05: these moved when the model was ported to "Dew Point
  // Calculator Emy" v2 (1.9% → 1.7%, 4.3% → 5.4%). That is expected — the old
  // linear multiplier under-corrected humid conditions. What this test actually
  // guards is the FRACTION-vs-PERCENT contract, not the calibration; the numbers
  // are here to make an accidental ×100 obvious.
  const pct = (f: number) => Math.round(f * 1000) / 10;

  const may20 = adjustPaceForHeat(307, 67, 67);
  assert(
    pct(may20.adjustmentPercent) >= 1.2 && pct(may20.adjustmentPercent) <= 2.2,
    `May 20 percent should be ~1.7, got ${pct(may20.adjustmentPercent)}`,
  );
  // ~5 s/mi slower on a 307 s/mi rep.
  const slowdown = 307 * may20.adjustmentPercent;
  assert(slowdown >= 3 && slowdown <= 8, `May 20 slowdown should be ~5 s/mi, got ${slowdown}`);

  const may19 = adjustPaceForHeat(307, 85, 71);
  assert(
    pct(may19.adjustmentPercent) >= 4.5 && pct(may19.adjustmentPercent) <= 6.5,
    `May 19 percent should be ~5.4, got ${pct(may19.adjustmentPercent)}`,
  );

  // The surfacing threshold lives in PERCENT space: a 1.9% run must clear the
  // athlete-state "notable heat" bar (>= 1.5), which the old fraction never did.
  assert(pct(may20.adjustmentPercent) >= 1.5, "1.9% must be notable in percent space");
});
