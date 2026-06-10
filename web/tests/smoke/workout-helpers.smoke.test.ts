// Runtime smoke test for the editor's data path.
//
// Run: cd web && npm run test:smoke
//
// What this catches that the contract tests cannot:
//   1. Module-load errors. The TDZ regression (May 2026) where a
//      dev-mode assertion was placed above a `const` it transitively
//      depended on broke the dev server. A `node --test` import here
//      would have failed at module load. Contract-text tests didn't
//      execute the module so they passed cleanly even while the dev
//      server crashed.
//   2. NaN propagation. Workouts with missing `paceZone` used to
//      render `NaN:NaN-NaN:NaN/mi` in the library. The smoke test
//      runs the safe formatters with the same broken inputs and
//      asserts the output is `null`, not a NaN string.
//   3. Cross-zone math. `paceRangeLabel("mp", ...)` and the
//      `trainingZoneRange` family run against canonical fixtures
//      and pin the numbers that show up on screen.

import { test } from "node:test";
import { strict as assert } from "node:assert";

import {
  paceRangeLabel,
  safePaceLabel,
  safePaceRangeLabel,
  trainingZoneRange,
  groupStepsIntoSections,
  derivePaceTableFromGoal,
  estimatedWorkoutMiles,
  PACE_ZONES,
  TRAINING_MP_SPEED_RANGE,
  type WorkoutStep,
} from "@/components/coach/workout-helpers";

// ── Module load ─────────────────────────────────────────
// If this file gets imported at all, the module evaluated cleanly.
// A TDZ at module load would crash before any test runs. We still
// add an explicit test so the harness reports it as a positive.

test("workout-helpers module loads without throwing", () => {
  assert.ok(typeof paceRangeLabel === "function");
  assert.ok(Array.isArray(PACE_ZONES));
  assert.ok(PACE_ZONES.length > 0);
});

// ── NaN guards ──────────────────────────────────────────

test("safePaceLabel returns null for undefined zone", () => {
  const r = safePaceLabel(undefined, undefined, undefined);
  assert.equal(r, null);
});

test("safePaceLabel returns null for unknown zone string", () => {
  const r = safePaceLabel("vo2max_pace_zone_that_does_not_exist", undefined, undefined);
  assert.equal(r, null);
});

test("safePaceLabel surfaces exact pace when given (even without zone)", () => {
  const r = safePaceLabel(undefined, undefined, 345);
  assert.equal(r, "5:45/mi");
});

test("safePaceRangeLabel never returns a string containing NaN", () => {
  // The bug we're guarding: paceRangeLabel used to do arithmetic against
  // an undefined REFERENCE_PACE_SEC_PER_MILE[undefined], producing
  // "NaN:NaN-NaN:NaN/mi" in the library card.
  const inputs: Array<[string | undefined, number?]> = [
    [undefined, undefined],
    [undefined, 0],
    ["bogus_zone", undefined],
  ];
  for (const [zone, exact] of inputs) {
    const r = safePaceRangeLabel(zone, undefined, exact);
    if (r !== null) {
      assert.ok(!r.includes("NaN"), `safePaceRangeLabel produced NaN output: ${r}`);
    }
  }
});

// ── Pace math contracts ─────────────────────────────────

test("paceRangeLabel: MP +20s/mi for 6:00 marathoner = 6:20/mi", () => {
  const r = paceRangeLabel("mp", { type: "seconds_per_mile", value: 20 }, undefined, { mp: 360 });
  assert.equal(r, "6:20/mi");
});

test("paceRangeLabel: easy renders as MP% band, NOT a tolerance window", () => {
  // For MP 5:32 (332s), easy band is 80–70% MP speed.
  // fast = 332 / 0.80 = 415s = 6:55
  // slow = 332 / 0.70 = 474.3s ≈ 7:54
  const r = paceRangeLabel("easy", undefined, undefined, { mp: 332 });
  assert.equal(r, "6:55–7:54/mi");
});

test("trainingZoneRange returns null for race zones", () => {
  for (const zone of ["mp", "hm", "threshold", "tenK", "fiveK", "threeK", "mile"] as const) {
    assert.equal(trainingZoneRange(zone, 332), null, `expected null for race zone ${zone}`);
  }
});

test("trainingZoneRange returns band for all four core aerobic zones", () => {
  for (const zone of ["steady", "moderate", "easy", "recovery"] as const) {
    const band = trainingZoneRange(zone, 332);
    assert.ok(band !== null, `expected band for ${zone}`);
    assert.ok(band!.fastSec > 0 && band!.slowSec > band!.fastSec);
    assert.ok(band!.bandLabel.includes("% MP"));
  }
});

// ── derivePaceTableFromGoal: LT is not collapsed to HM ─

test("derivePaceTableFromGoal: threshold (LT) is separate from HM", () => {
  // 2:25 marathon goal → MP 5:32, HM ~5:18. LT should sit between
  // 10K and HM (a slow runner whose 10K > 1hr would have LT = 10K
  // pace; our 2:25 athlete is fast so LT interpolates).
  const goalSecPerMile = 8700 / 26.21875;
  const table = derivePaceTableFromGoal(goalSecPerMile, "marathon");
  assert.ok(table.threshold !== table.hm, "LT should not equal HM");
  assert.ok(table.threshold > table.tenK, "LT should be slower than 10K");
  assert.ok(table.threshold < table.hm, "LT should be faster than HM");
});

// ── PACE_ZONES regressions ─────────────────────────────

test("PACE_ZONES does not include the retired longRun", () => {
  const values = PACE_ZONES.map((z) => z.value);
  assert.ok(!values.includes("longRun" as never), "longRun pace zone was retired");
});

test("TRAINING_MP_SPEED_RANGE covers the four core zones", () => {
  for (const k of ["steady", "moderate", "easy", "recovery"] as const) {
    const band = TRAINING_MP_SPEED_RANGE[k];
    assert.ok(band, `missing band for ${k}`);
    // Convention: ratios are fractions of MP speed. Larger ratio = closer
    // to MP speed = faster pace. So fastRatio > slowRatio.
    assert.ok(
      band.fastRatio > band.slowRatio && band.slowRatio > 0,
      `${k}: expected fastRatio (${band.fastRatio}) > slowRatio (${band.slowRatio}) > 0`,
    );
    assert.ok(band.bandLabel.includes("% MP"));
  }
});

// ── groupStepsIntoSections — production algorithm path ─

test("groupStepsIntoSections collapses the 6 × 800m flat pattern", () => {
  const steps: WorkoutStep[] = [
    { id: "1", stepType: "warmup",   durationType: "distance_miles",  durationValue: 2,   paceZone: "easy", notes: "" },
    { id: "2", stepType: "active",   durationType: "distance_meters", durationValue: 800, paceZone: "fiveK", notes: "" },
    { id: "3", stepType: "recovery", durationType: "time_seconds",    durationValue: 120, paceZone: "easy", notes: "" },
    { id: "4", stepType: "active",   durationType: "distance_meters", durationValue: 800, paceZone: "fiveK", notes: "" },
    { id: "5", stepType: "recovery", durationType: "time_seconds",    durationValue: 120, paceZone: "easy", notes: "" },
    { id: "6", stepType: "active",   durationType: "distance_meters", durationValue: 800, paceZone: "fiveK", notes: "" },
    { id: "7", stepType: "recovery", durationType: "time_seconds",    durationValue: 120, paceZone: "easy", notes: "" },
    { id: "8", stepType: "active",   durationType: "distance_meters", durationValue: 800, paceZone: "fiveK", notes: "" },
    { id: "9", stepType: "cooldown", durationType: "distance_miles",  durationValue: 1,   paceZone: "easy", notes: "" },
  ];
  const sections = groupStepsIntoSections(steps);
  assert.equal(sections.warmup.length, 1);
  assert.equal(sections.cooldown.length, 1);
  assert.equal(sections.blocks.length, 1);
  assert.equal(sections.blocks[0].kind, "reps");
  assert.equal(sections.blocks[0].repeats, 4);
});

test("groupStepsIntoSections guards against warmup being treated as a recovery gap", () => {
  // Pathological data: two identical Active reps with a Warmup
  // accidentally sitting between them. The grouper must NOT collapse
  // them with the warmup as the recovery row.
  const steps: WorkoutStep[] = [
    { id: "1", stepType: "active", durationType: "distance_miles", durationValue: 1, paceZone: "fiveK", notes: "" },
    { id: "2", stepType: "warmup", durationType: "distance_miles", durationValue: 1, paceZone: "easy",  notes: "" },
    { id: "3", stepType: "active", durationType: "distance_miles", durationValue: 1, paceZone: "fiveK", notes: "" },
  ];
  const sections = groupStepsIntoSections(steps);
  // Three single blocks, not one rep block of 2.
  assert.equal(sections.warmup.length, 0); // mid-stream warmup isn't a prefix
  assert.equal(sections.blocks.length, 3);
  assert.equal(sections.blocks[0].kind, "single");
  assert.equal(sections.blocks[1].kind, "single");
  assert.equal(sections.blocks[2].kind, "single");
});

// ── estimatedWorkoutMiles — exercises the standing-rest path ─

test("estimatedWorkoutMiles handles standing-rest recovery (no pace) cleanly", () => {
  // 6 × 800m @ 5K + 90s standing rest. The standing rest should
  // contribute 0 miles to the total (you're not moving), but the
  // function must not throw or return NaN.
  const steps: WorkoutStep[] = [
    {
      id: "1",
      stepType: "active",
      durationType: "distance_meters",
      durationValue: 800,
      paceZone: "fiveK",
      notes: "",
      repeats: 6,
      recovery: {
        durationType: "time_seconds",
        durationValue: 90,
        // No paceZone — this is standing rest.
      },
    },
  ];
  const miles = estimatedWorkoutMiles(steps, { fiveK: 295 });
  assert.ok(Number.isFinite(miles), "miles must be finite");
  // 6 × 0.497 mi (800m) = ~2.98 mi. Standing rest adds 0.
  assert.ok(miles > 2.9 && miles < 3.1, `expected ~2.98, got ${miles}`);
});
