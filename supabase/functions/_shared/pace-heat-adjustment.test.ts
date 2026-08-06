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
  heatCategory,
  heatSurfacing,
  INTENSITY_FLOOR,
  intensityFactor,
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

Deno.test("a perfect morning is labelled ideal, not warm", () => {
  // 55°F with a 45°F dew point — composite 100.45, a hair over the adjustment
  // table's zero knot. This used to read "warm" (sun icon + tinted card on the
  // iOS pace chart) over a 0.02% time cost, because the label boundary and the
  // table's zero were both pinned at 100. They're decoupled now: the cost claim
  // stays at 100, the label runs to 110.
  const a = adjustPace(360, 55, 45);
  assert(a.compositeScore > 100, `expected just over the knot, got ${a.compositeScore}`);
  assert(a.adjustmentPercent < 0.001, `cost should be negligible, got ${a.adjustmentPercent}`);
  assertEquals(a.heatCategory, "ideal");
});

Deno.test("the ideal→warm line sits at 110, and warm still means something", () => {
  assertEquals(heatCategory(109.9), "ideal");
  assertEquals(heatCategory(110), "warm");
  // At the new line the cost is ~0.5% — the point where a day is a factor.
  assertAlmostEquals(heatAdjustmentPct(60, 50), 0.005, 0.0005);
  // The bands above are untouched.
  assertEquals(heatCategory(129.9), "warm");
  assertEquals(heatCategory(130), "hot");
  assertEquals(heatCategory(150), "very_hot");
  assertEquals(heatCategory(170), "dangerous");
});

Deno.test("surfacing is unaffected by the label move — it gates on dew point", () => {
  // The label and the act/mention decision are separate systems; widening
  // "ideal" must not quietly silence or trigger a coaching mention.
  assertEquals(heatSurfacing(55, 45), "none");
  assertEquals(heatSurfacing(60, 50), "none");
  assertEquals(heatSurfacing(75, 62), "mention");
  assertEquals(heatSurfacing(85, 72), "apply");
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

// ── Intensity scaling (2026-08-05) ─────────────────────────────────
// The table is a quality-work chart, so the CREDIT is scaled down at easy
// intensity. The PRESCRIPTION never is. See the module header for why, and for
// why the 0.75 floor is a coaching judgment rather than a fitted parameter.

Deno.test("intensityFactor: floor at recovery, full at LT and faster", () => {
  const lt = 380;                              // 6:20/mi threshold
  assertEquals(intensityFactor(380, lt), 1.0);        // at LT
  assertEquals(intensityFactor(340, lt), 1.0);        // faster than LT
  assertEquals(intensityFactor(400, lt), 1.0);        // ratio 0.95 — still full
  assertEquals(intensityFactor(560, lt), INTENSITY_FLOOR); // ratio 0.68 — floor
  // Midway up the ramp: ratio 0.865 sits ~half of the 0.78→0.95 span.
  assertAlmostEquals(intensityFactor(439.3, lt), 0.875, 0.01);
});

Deno.test("intensityFactor: no threshold anchor → chart as published", () => {
  assertEquals(intensityFactor(464, null), 1.0);
  assertEquals(intensityFactor(464, undefined), 1.0);
  assertEquals(intensityFactor(464, 0), 1.0);        // nonsense anchor
  assertEquals(intensityFactor(464, NaN), 1.0);
});

Deno.test("REGRESSION: the Aug 5 easy run is credited ~19s/mi, not 25", () => {
  // The real run: 6.01mi @ 7:44/mi, 78°F / 75°F dew. Continuous, so no rep
  // scaling. Threshold 322 s/mi is this athlete's actual LT, interpolated from
  // their stored zones (10K 310, HM 324) by the 1-hour rule.
  const a = adjustPace(464, 78, 75, null, 322);
  // 322/464 = 0.694 — comfortably into recovery territory, so the floor.
  assertEquals(a.intensityFactor, INTENSITY_FLOOR);
  const credit = a.originalPaceSeconds - a.neutralEquivalentPaceSeconds;
  assert(credit > 18 && credit < 20, `credit ${credit}s/mi`);
  // The unscaled chart credited 25s/mi — that's the number this change exists
  // to walk back, and it must stay walked back.
  const unscaled = adjustPace(464, 78, 75);
  assertEquals(
    Math.round(unscaled.originalPaceSeconds - unscaled.neutralEquivalentPaceSeconds),
    25,
  );
});

Deno.test("prescription is NOT intensity-scaled; credit is", () => {
  const easy = adjustPace(464, 78, 75, null, 380);
  const unscaled = adjustPace(464, 78, 75);
  // Same prescriptive target either way — effort held constant, full slowdown.
  assertAlmostEquals(easy.adjustedPaceSeconds, unscaled.adjustedPaceSeconds, 1e-9);
  assertAlmostEquals(
    easy.effectiveAdjustmentPercent, unscaled.effectiveAdjustmentPercent, 1e-9);
  // But the credit is strictly smaller.
  assert(easy.creditAdjustmentPercent < easy.effectiveAdjustmentPercent);
  assert(easy.neutralEquivalentPaceSeconds > unscaled.neutralEquivalentPaceSeconds,
    "intensity-scaled credit must be the more conservative (slower) equivalent");
});

Deno.test("at LT and faster, credit and prescription stay exact inverses", () => {
  const a = adjustPace(380, 78, 75, null, 380);
  assertEquals(a.intensityFactor, 1.0);
  assertAlmostEquals(
    a.neutralEquivalentPaceSeconds * (1 + a.effectiveAdjustmentPercent),
    a.originalPaceSeconds,
    1e-6,
  );
});

Deno.test("rep-length and intensity scaling compose on the credit", () => {
  // A 1km rep (0.62mi → 0.5×) jogged at recovery pace: both discounts stack.
  const a = adjustPace(464, 78, 75, 0.62, 322);
  assertEquals(a.repLengthFactor, 0.5);
  assertEquals(a.intensityFactor, INTENSITY_FLOOR);
  assertAlmostEquals(
    a.creditAdjustmentPercent, a.adjustmentPercent * 0.5 * INTENSITY_FLOOR, 1e-12);
  // Rep-length still applies to the PRESCRIPTION; intensity still doesn't.
  assertAlmostEquals(
    a.effectiveAdjustmentPercent, a.adjustmentPercent * 0.5, 1e-12);
});
