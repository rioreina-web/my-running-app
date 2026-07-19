/**
 * Tests for heat pace adjustment + rep-length scaling.
 * Run: deno test _shared/pace-heat-adjustment.test.ts
 */
import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  adjustPace,
  heatAdjustmentPct,
  heatSurfacing,
  repLengthFactor,
} from "./pace-heat-adjustment.ts";

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
  // Hadley example: 74°F air + 71°F dew (~145 sum) → ~3% continuous.
  const a = adjustPace(450, 74, 71); // 7:30/mi, no distance = continuous
  assertEquals(a.repLengthFactor, 1.0);
  assertAlmostEquals(a.effectiveAdjustmentPercent, a.adjustmentPercent, 1e-9);
  assert(a.adjustmentPercent > 0.025 && a.adjustmentPercent < 0.035, `got ${a.adjustmentPercent}`);
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
