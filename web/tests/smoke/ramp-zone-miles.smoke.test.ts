// Ramp zone-mile aggregation: verifies the helpers that drive the
// pace-colored mileage ramp in the plan builder's Plan-setup section.
//
// Run: cd web && npm run test:smoke
//
// These pin the bucketing behavior ported from
// prototypes/adaptive-plan-builder.html (weekZoneMiles / nearestZoneKey):
//   - named zones bucket into themselves
//   - longRun folds into moderate; recovery keeps its own key
//   - exact-pace steps map to the nearest reference zone
//   - distance and time-based (pace × time) miles both count
//   - rep sets multiply by their repeat count

import { test } from "node:test";
import { strict as assert } from "node:assert";

import {
  weekZoneMiles,
  nearestZoneKey,
  totalZoneMiles,
  REFERENCE_PACE_SEC_PER_MILE,
  PACE_ZONE_COLORS,
  PACE_ZONES,
  type WorkoutStep,
  type PaceZone,
} from "@/components/coach/workout-helpers";

// ── Step builders ────────────────────────────────────────

let idCounter = 0;
function step(partial: Partial<WorkoutStep>): WorkoutStep {
  return {
    id: `s${idCounter++}`,
    stepType: "active",
    durationType: "distance_miles",
    durationValue: 1,
    paceZone: "easy",
    notes: "",
    ...partial,
  };
}

// ── nearestZoneKey ───────────────────────────────────────

test("nearestZoneKey: an exact pace maps to the closest reference zone", () => {
  // 5K reference pace lands exactly on fiveK.
  assert.equal(nearestZoneKey(REFERENCE_PACE_SEC_PER_MILE.fiveK), "fiveK");
  // MP reference pace lands on mp.
  assert.equal(nearestZoneKey(REFERENCE_PACE_SEC_PER_MILE.mp), "mp");
  // A very fast pace (below Mile) still resolves to the fastest zone.
  assert.equal(nearestZoneKey(4 * 60 + 30), "mile");
  // A very slow pace resolves to the slowest zone (recovery).
  assert.equal(nearestZoneKey(12 * 60), "recovery");
});

// ── weekZoneMiles: named zones ───────────────────────────

test("weekZoneMiles: named zones bucket into themselves", () => {
  const zm = weekZoneMiles([
    [step({ paceZone: "threshold", durationType: "distance_miles", durationValue: 6 })],
    [step({ paceZone: "easy", durationType: "distance_miles", durationValue: 8 })],
  ]);
  assert.equal(zm.threshold, 6);
  assert.equal(zm.easy, 8);
  assert.equal(totalZoneMiles(zm), 14);
});

test("weekZoneMiles: longRun folds into moderate, recovery keeps its key", () => {
  const zm = weekZoneMiles([
    [step({ paceZone: "longRun", durationValue: 12 })],
    [step({ paceZone: "recovery", durationValue: 4 })],
  ]);
  assert.equal(zm.moderate, 12, "longRun miles should land in moderate");
  assert.equal(zm.longRun, undefined, "longRun should not be its own bucket");
  assert.equal(zm.recovery, 4);
});

test("weekZoneMiles: a rep set multiplies active miles by repeats", () => {
  // 6 × 800m @ 5K = 6 × 0.4970 mi ≈ 2.98 mi of 5K work.
  const zm = weekZoneMiles([
    [
      step({
        paceZone: "fiveK",
        durationType: "distance_meters",
        durationValue: 800,
        repeats: 6,
      }),
    ],
  ]);
  assert.ok(zm.fiveK && zm.fiveK > 2.9 && zm.fiveK < 3.05, `got ${zm.fiveK}`);
});

test("weekZoneMiles: exact-pace step buckets to its nearest zone", () => {
  const zm = weekZoneMiles([
    [
      step({
        // No named zone intent; pinned to ~10K reference pace.
        exactPaceSecPerMile: REFERENCE_PACE_SEC_PER_MILE.tenK,
        durationType: "distance_miles",
        durationValue: 3,
      }),
    ],
  ]);
  assert.equal(zm.tenK, 3);
});

test("weekZoneMiles: time-based work counts via pace × time", () => {
  // 20 min @ threshold reference pace (7:10/mi = 430s) ≈ 2.79 mi.
  const zm = weekZoneMiles([
    [
      step({
        paceZone: "threshold",
        durationType: "time_seconds",
        durationValue: 20 * 60,
      }),
    ],
  ]);
  assert.ok(zm.threshold && zm.threshold > 2.7 && zm.threshold < 2.9, `got ${zm.threshold}`);
});

test("weekZoneMiles: empty input yields an empty map", () => {
  assert.equal(totalZoneMiles(weekZoneMiles([])), 0);
  assert.equal(totalZoneMiles(weekZoneMiles([[]])), 0);
});

// ── Palette invariants (three-palette rule) ──────────────

test("PACE_ZONE_COLORS: every zone maps to a blue pace token, never mood/coral", () => {
  for (const opt of PACE_ZONES) {
    const color = PACE_ZONE_COLORS[opt.value as PaceZone];
    assert.ok(color, `missing color for ${opt.value}`);
    assert.match(color, /^var\(--color-pace-/, `${opt.value} must use a --color-pace-* token, got ${color}`);
    assert.doesNotMatch(color, /mood|coral/, `${opt.value} must not reference a mood/coral token`);
  }
});
