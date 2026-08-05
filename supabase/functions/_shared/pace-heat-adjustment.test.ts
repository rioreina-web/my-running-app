/**
 * Tests for heat pace adjustment + rep-length scaling.
 * Run: deno test _shared/pace-heat-adjustment.test.ts
 */
import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  adjustPace,
  BEYOND_CHART_SCORE,
  compositeScore,
  dewPointMultiplier,
  heatAdjustmentPct,
  heatSurfacing,
  isBeyondChart,
  repLengthFactor,
} from "./pace-heat-adjustment.ts";

// ── The spreadsheet is the source of truth ─────────────────────────
// "Dew Point Calculator Emy" v2. These pin the port to the sheet's own cells;
// if one of these fails, the code has drifted from the calibration.

Deno.test("SHEET REFERENCE: 5:15/mi at 78°F / 75°F dew → 5:33/mi", () => {
  const a = adjustPace(315, 78, 75);           // continuous, no rep scaling
  assertAlmostEquals(a.multiplier, 1.132994901, 1e-9);        // sheet B8
  assertAlmostEquals(a.compositeScore, 162.9746176, 1e-6);    // sheet B9
  assertAlmostEquals(a.adjustmentPercent, 0.05594923511, 1e-9); // sheet B10
  assertEquals(Math.round(a.adjustedPaceSeconds), 333);       // sheet B11 → 5:33
});

Deno.test("dew multiplier: flat 1.01 to the 65°F pivot, exponential above", () => {
  assertEquals(dewPointMultiplier(45), 1.01);
  assertEquals(dewPointMultiplier(55), 1.01);
  assertEquals(dewPointMultiplier(65), 1.01);   // pivot itself is flat
  assertAlmostEquals(dewPointMultiplier(70), 1.0697312, 1e-6);
  assertAlmostEquals(dewPointMultiplier(75), 1.1329949, 1e-6);
  assertAlmostEquals(dewPointMultiplier(80), 1.2000000, 1e-6);
  // Strictly increasing above the pivot — no flat spots, no inversions.
  for (let d = 66; d <= 90; d++) {
    assert(dewPointMultiplier(d) > dewPointMultiplier(d - 1), `flat/inverted at ${d}`);
  }
});

Deno.test("dew point outweighs temperature at equal composite pressure", () => {
  // The whole point of the exponential: a saturated 78/75 morning must not read
  // easier than a dry 96/67 afternoon just because the air is cooler.
  const humid = adjustPace(315, 78, 75);
  const dry = adjustPace(315, 96, 67);
  assert(humid.adjustmentPercent > 0.05, `humid ${humid.adjustmentPercent}`);
  // 18 degrees hotter but 8 degrees drier lands within a point of each other,
  // where a plain temp+dew sum would rate the dry day far harder.
  assert(Math.abs(humid.adjustmentPercent - dry.adjustmentPercent) < 0.01,
    `humid ${humid.adjustmentPercent} vs dry ${dry.adjustmentPercent}`);
});

Deno.test("past composite 185 the chart refuses rather than prescribes", () => {
  const a = adjustPace(315, 100, 80);
  assert(a.compositeScore > BEYOND_CHART_SCORE, `score ${a.compositeScore}`);
  assertEquals(a.beyondChart, true);
  assertEquals(isBeyondChart(100, 80), true);
  // Still returns a usable (clamped) number so no caller has to handle null.
  assertEquals(a.adjustmentPercent, 0.100);
  // Ordinary hot conditions are NOT beyond the chart.
  assertEquals(adjustPace(315, 78, 75).beyondChart, false);
  assertEquals(adjustPace(315, 92, 71).beyondChart, false);
});

Deno.test("compositeScore helper agrees with adjustPace", () => {
  assertAlmostEquals(compositeScore(78, 75), adjustPace(315, 78, 75).compositeScore, 1e-12);
});

Deno.test("repLengthFactor: half ≤0.75mi, ramp to full at 1.5mi", () => {
  assertEquals(repLengthFactor(0.4), 0.5);     // 400m rep
  assertEquals(repLengthFactor(0.75), 0.5);    // boundary
  assertAlmostEquals(repLengthFactor(1.125), 0.75, 1e-9); // midpoint of ramp
  assertEquals(repLengthFactor(1.5), 1.0);     // boundary
  assertEquals(repLengthFactor(3.0), 1.0);     // long continuous
  assertEquals(repLengthFactor(null), 1.0);    // unknown → full (continuous)
  assertEquals(repLengthFactor(undefined), 1.0);
});

Deno.test("continuous run gets the full table adjustment", () => {
  // 74°F air + 71°F dew → composite ~150.8 → ~3.5% continuous.
  const a = adjustPace(450, 74, 71); // 7:30/mi, no distance = continuous
  assertEquals(a.repLengthFactor, 1.0);
  assertAlmostEquals(a.effectiveAdjustmentPercent, a.adjustmentPercent, 1e-9);
  assert(a.adjustmentPercent > 0.030 && a.adjustmentPercent < 0.040, `got ${a.adjustmentPercent}`);
});

Deno.test("a short interval rep gets HALF the heat penalty", () => {
  const continuous = adjustPace(300, 80, 70, 2.0);   // 2mi
  const rep600 = adjustPace(300, 80, 70, 0.37);      // 600m rep
  assertEquals(rep600.repLengthFactor, 0.5);
  assertAlmostEquals(
    rep600.effectiveAdjustmentPercent,
    continuous.effectiveAdjustmentPercent * 0.5,
    1e-9,
  );
  // The 600m rep is adjusted by half the seconds the continuous bout would be.
  assertAlmostEquals(
    rep600.adjustmentSecondsPerMile,
    continuous.adjustmentSecondsPerMile * 0.5,
    1e-6,
  );
});

Deno.test("a 1-mile rep sits partway up the ramp (~0.667)", () => {
  const a = adjustPace(300, 80, 70, 1.0);
  assertAlmostEquals(a.repLengthFactor, 0.6667, 1e-3);
});

Deno.test("ideal conditions → no adjustment regardless of distance", () => {
  const a = adjustPace(450, 50, 45, 0.4);
  assertEquals(a.adjustmentPercent, 0);
  assertEquals(a.adjustmentSecondsPerMile, 0);
  assertEquals(a.heatCategory, "ideal");
});

Deno.test("heatAdjustmentPct matches adjustPace's raw (continuous) pct", () => {
  const pct = heatAdjustmentPct(85, 72);
  const a = adjustPace(450, 85, 72);
  assertAlmostEquals(pct, a.adjustmentPercent, 1e-9);
});

Deno.test("heatSurfacing: apply at 68+ dew, mention when mildly humid, else none", () => {
  // 68°F+ dew point → apply (Rio's primary rule).
  assertEquals(heatSurfacing(75, 68), "apply");
  assertEquals(heatSurfacing(76, 72), "apply");
  // Mildly humid (60–67 dew) → mention only, no pace change.
  assertEquals(heatSurfacing(70, 62), "mention");
  assertEquals(heatSurfacing(68, 60), "mention");
  // Cool & dry → say nothing.
  assertEquals(heatSurfacing(55, 50), "none");
  assertEquals(heatSurfacing(60, 45), "none");
  // Backstop: hot, dry day still surfaces even with a moderate dew point.
  assertEquals(heatSurfacing(95, 55), "apply");
});

Deno.test("neutral-equivalent is FASTER than actual and inverts the penalty", () => {
  // A pace run in the heat is worth a faster pace in neutral conditions —
  // this is what the completed-workout HEAT-ADJ toggle displays (credit).
  const a = adjustPace(450, 85, 72); // 7:30/mi in hot/humid
  assert(a.adjustedPaceSeconds > a.originalPaceSeconds, "prescriptive stays slower");
  assert(a.neutralEquivalentPaceSeconds < a.originalPaceSeconds,
    `neutral-eq should be faster than 450, got ${a.neutralEquivalentPaceSeconds}`);
  // It's the exact inverse of the effective penalty.
  assertAlmostEquals(
    a.neutralEquivalentPaceSeconds * (1 + a.effectiveAdjustmentPercent),
    a.originalPaceSeconds,
    1e-6,
  );
});

Deno.test("ideal conditions → neutral-equivalent equals actual", () => {
  const a = adjustPace(450, 50, 45);
  assertEquals(a.neutralEquivalentPaceSeconds, 450);
});

Deno.test("Austin-this-morning ballpark: warm/hot, continuous easy run", () => {
  // ~76°F air, ~72°F dew (typical Austin June dawn).
  const a = adjustPace(450, 76, 72); // 7:30/mi continuous
  // Composite lands in the 'hot'/'very_hot' band with a meaningful penalty.
  assert(a.compositeScore > 148 && a.compositeScore < 160, `score ${a.compositeScore}`);
  assert(a.adjustmentSecondsPerMile > 10 && a.adjustmentSecondsPerMile < 25,
    `+${a.adjustmentSecondsPerMile}s/mi`);
});
