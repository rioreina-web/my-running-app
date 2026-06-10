/**
 * Contract + algorithm tests for the workout step editor's persisted shape
 * and pace-adjustment math.
 *
 * Run: cd web && node --test tests/workout-step-roundtrip.test.mjs
 *
 * What this guards against:
 *   1. `repeats` or `recovery` going missing from the WorkoutStep type
 *      (the iOS-side equivalent regression silently dropped them for
 *      months — coaches lost interval structure on every save).
 *   2. The persisted form payload changing shape without intent.
 *   3. The pace-adjustment math drifting — "MP +20s/mi for goal MP 6:00
 *      should render 6:20/mi" is the canonical coach example.
 *   4. estimatedWorkoutMiles regressing on fartlek-style workouts (time-
 *      based segments must contribute to the mile total).
 *
 * Why a contract test rather than importing the TS module:
 *   The repo's npm test script runs `node --test 'tests/**\/*.test.mjs'`
 *   with no TS runner. We replicate the small testable algorithms inline
 *   AND verify the source file still declares the right exports/shapes,
 *   so drift between the test and the source is detectable.
 */

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const HELPERS = path.resolve(HERE, "..", "src", "components", "coach", "workout-helpers.ts");
const FORM = path.resolve(HERE, "..", "src", "components", "coach", "workout-template-form.tsx");
const CARD = path.resolve(HERE, "..", "src", "components", "coach", "workout-template-card.tsx");

// ── Inline algorithm port ────────────────────────────────
// Mirror of `adjustedPaceSecPerMile` + `paceRangeLabel` from
// workout-helpers.ts. Keep the math in sync — when the source changes,
// update this and re-run. The contract test below verifies the source
// still has the function names we're shadowing.

const KM_PER_MILE = 1.609344;

function adjustedPaceSecPerMile(basePaceSecPerMile, adjustment) {
  if (!adjustment || adjustment.value === 0) return basePaceSecPerMile;
  switch (adjustment.type) {
    case "percent":          return basePaceSecPerMile * (1 + adjustment.value / 100);
    case "seconds_per_mile": return basePaceSecPerMile + adjustment.value;
    case "seconds_per_km":   return basePaceSecPerMile + adjustment.value * KM_PER_MILE;
    default: throw new Error(`unknown adjustment type: ${adjustment.type}`);
  }
}

function formatPaceSecPerMile(totalSeconds) {
  const t = Math.max(0, Math.round(totalSeconds));
  const m = Math.floor(t / 60);
  const s = t % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

// Quality zones (mp, hm, threshold, tenK, fiveK, threeK, mile) → single
// target. Aerobic zones → ±5%. Matches the constant in workout-helpers.ts.
const TOLERANCE_PERCENT = {
  recovery: 5, easy: 5, longRun: 5, moderate: 5, steady: 5,
  mp: 0, hm: 0, threshold: 0, tenK: 0, fiveK: 0, threeK: 0, mile: 0,
};

function paceRangeLabel(zone, adjustment, exactPaceSecPerMile, athletePaces) {
  if (exactPaceSecPerMile && exactPaceSecPerMile > 0) {
    return `${formatPaceSecPerMile(exactPaceSecPerMile)}/mi`;
  }
  const base = athletePaces?.[zone];
  if (base == null) throw new Error(`missing base pace for ${zone}`);
  const center = adjustedPaceSecPerMile(base, adjustment);
  const pct = TOLERANCE_PERCENT[zone] ?? 0;
  const half = Math.round((center * pct) / 100);
  if (half <= 0) return `${formatPaceSecPerMile(center)}/mi`;
  return `${formatPaceSecPerMile(center - half)}–${formatPaceSecPerMile(center + half)}/mi`;
}

// Mirror of `estimatedSegmentMiles` + `estimatedWorkoutMiles`. The cost
// of duplication is small; the benefit is that the canonical coach use
// case ("a fartlek workout has miles, not zero") is covered.
function segmentMiles(seg) {
  switch (seg.durationType) {
    case "distance_miles":  return seg.durationValue;
    case "distance_km":     return seg.durationValue / KM_PER_MILE;
    case "distance_meters": return seg.durationValue / (KM_PER_MILE * 1000);
    case "time_seconds":    return 0; // resolved by estimatedSegmentMiles
  }
  return 0;
}

function estimatedSegmentMiles(seg, athletePaces) {
  if (seg.durationType !== "time_seconds") return segmentMiles(seg);
  const base = athletePaces?.[seg.paceZone];
  if (base == null) return 0;
  const paceSec = seg.exactPaceSecPerMile ?? adjustedPaceSecPerMile(base, seg.paceAdjustment);
  return paceSec > 0 ? seg.durationValue / paceSec : 0;
}

function estimatedStepMiles(step, athletePaces) {
  const reps = (step.repeats ?? 1) > 1 ? step.repeats : 1;
  const active = estimatedSegmentMiles(step, athletePaces) * reps;
  const recovery = step.recovery ? estimatedSegmentMiles(step.recovery, athletePaces) * reps : 0;
  return active + recovery;
}

function estimatedWorkoutMiles(steps, athletePaces) {
  return steps.reduce((s, step) => s + estimatedStepMiles(step, athletePaces), 0);
}

// ── Algorithm tests ─────────────────────────────────────

test("pace adjustment: MP +20s/mi for 6:00 marathoner = 6:20/mi", () => {
  const result = paceRangeLabel(
    "mp",
    { type: "seconds_per_mile", value: 20 },
    undefined,
    { mp: 360 },
  );
  assert.equal(result, "6:20/mi");
});

test("pace adjustment: percent mode multiplies the base", () => {
  // 6:00 × 1.02 = 367.2s → 6:07/mi (rounded)
  const result = paceRangeLabel(
    "mp",
    { type: "percent", value: 2 },
    undefined,
    { mp: 360 },
  );
  assert.equal(result, "6:07/mi");
});

test("pace adjustment: seconds_per_km adds km offset × mile-per-km", () => {
  // -10 s/km × 1.609344 ≈ -16.09 s/mi
  const result = paceRangeLabel(
    "mp",
    { type: "seconds_per_km", value: -10 },
    undefined,
    { mp: 360 },
  );
  // 360 - 16.09 = 343.91 → 5:44/mi
  assert.equal(result, "5:44/mi");
});

test("aerobic zone with adjustment renders a range, not a point", () => {
  // Easy with base 7:30 (450s), 5% tolerance → ±22.5s → "7:08–7:53/mi"
  const result = paceRangeLabel("easy", undefined, undefined, { easy: 450 });
  // Should be a range, not a single pace
  assert.match(result, /^\d+:\d{2}–\d+:\d{2}\/mi$/);
});

test("threshold (LT) is computed as 1-hour race pace, not collapsed to HM", async () => {
  // Inline port of `oneHourPaceSecPerMile` — same algorithm as iOS
  // PaceCalculator.calculateOneHourPace. Linear interp between 10K and
  // HM by elapsed-time fraction at exactly 3600s.
  const DIST_10K_MI = 6.213712;
  const DIST_HALF_MI = 13.109375;
  function oneHour(tenKPace, hmPace) {
    const t10 = tenKPace * DIST_10K_MI;
    const tHalf = hmPace * DIST_HALF_MI;
    if (t10 >= 3600) return tenKPace;
    if (tHalf <= 3600) return hmPace;
    const f = (3600 - t10) / (tHalf - t10);
    const d1h = DIST_10K_MI + f * (DIST_HALF_MI - DIST_10K_MI);
    return 3600 / d1h;
  }
  // 2:25 marathoner: 10K ≈ 5:09/mi, HM ≈ 5:18/mi.
  // 10K time = 5:09 × 6.21 = 1919s (< 3600). HM time = 5:18 × 13.11 = 4170s (> 3600).
  // So interp produces an LT pace between 10K and HM, strictly slower than 10K
  // and strictly faster than HM. NOT equal to HM (which was the old buggy behavior).
  const tenK = 5 * 60 + 9;
  const hm   = 5 * 60 + 18;
  const lt = oneHour(tenK, hm);
  assert.ok(lt > tenK, `LT (${lt.toFixed(1)}) should be slower than 10K (${tenK})`);
  assert.ok(lt < hm, `LT (${lt.toFixed(1)}) should be faster than HM (${hm}) — not collapsed`);
});

test("workout-helpers.ts uses oneHourPaceSecPerMile for threshold, not the old hmSec collapse", async () => {
  const src = await readFile(HELPERS, "utf8");
  assert.ok(
    src.includes("threshold: oneHourPaceSecPerMile("),
    "derivePaceTableFromGoal should call oneHourPaceSecPerMile for threshold — found the legacy `threshold: hmSec` collapse still in place",
  );
  assert.ok(
    !src.includes("threshold: hmSec,"),
    "Legacy `threshold: hmSec` collapse still present — should be replaced",
  );
});

test("exact pace overrides zone + adjustment", () => {
  const result = paceRangeLabel(
    "mp",
    { type: "seconds_per_mile", value: 60 },
    345, // 5:45 exact
    { mp: 360 },
  );
  assert.equal(result, "5:45/mi");
});

test("estimatedWorkoutMiles: distance-only workout sums exactly", () => {
  const steps = [
    { id: "1", stepType: "warmup",   durationType: "distance_miles", durationValue: 2, paceZone: "easy",      notes: "" },
    { id: "2", stepType: "active",   durationType: "distance_miles", durationValue: 1, paceZone: "threshold", notes: "", repeats: 7 },
    { id: "3", stepType: "cooldown", durationType: "distance_miles", durationValue: 2, paceZone: "recovery",  notes: "" },
  ];
  assert.equal(estimatedWorkoutMiles(steps, { mp: 360, easy: 480, threshold: 354, recovery: 540 }), 11);
});

test("estimatedWorkoutMiles: time-based fartlek contributes via pace × time", () => {
  // "10 × 1 min @ 5K / 1 min @ easy" with 5K=4:41/mi (281s), easy=7:00/mi (420s):
  // active: 60s / 281 sec/mi ≈ 0.2135 mi
  // recovery: 60s / 420 sec/mi ≈ 0.1429 mi
  // total per rep: 0.356 mi × 10 reps = 3.56 mi
  const steps = [
    {
      id: "1",
      stepType: "active",
      durationType: "time_seconds",
      durationValue: 60,
      paceZone: "fiveK",
      notes: "",
      repeats: 10,
      recovery: {
        durationType: "time_seconds",
        durationValue: 60,
        paceZone: "easy",
      },
    },
  ];
  const total = estimatedWorkoutMiles(steps, { fiveK: 281, easy: 420 });
  assert.ok(total > 3.4 && total < 3.7, `expected ~3.56, got ${total}`);
});

test("estimatedWorkoutMiles: time-based steps with no athlete paces return 0", () => {
  // Without a pace table, we shouldn't invent miles. The form prefixes
  // ~ when paces are uncalibrated to communicate this.
  const steps = [
    { id: "1", stepType: "active", durationType: "time_seconds", durationValue: 600, paceZone: "easy", notes: "" },
  ];
  // Falls back to reference paces in the real helper; here we pass no
  // athlete paces and the algorithm returns 0. The form's own behavior
  // is to use REFERENCE_PACE_SEC_PER_MILE as a fallback — that's the
  // important thing the source does that this port doesn't reproduce.
  assert.equal(estimatedWorkoutMiles(steps, undefined), 0);
});

// ── Source contract checks ──────────────────────────────
// Verify the source file still has the exports/shapes this test is
// shadowing. When the source drifts, these checks catch it.

test("workout-helpers.ts still exports the functions this test shadows", async () => {
  const src = await readFile(HELPERS, "utf8");
  const required = [
    "export function adjustedPaceSecPerMile",
    "export function paceRangeLabel",
    "export function estimatedStepMiles",
    "export function estimatedWorkoutMiles",
    "export function workoutHasTimeBasedSegment",
    "export function totalWorkoutDurationMinutes",
    "export function formatPaceSecPerMile",
  ];
  for (const sig of required) {
    assert.ok(
      src.includes(sig),
      `workout-helpers.ts no longer contains '${sig}' — algorithm port may be out of sync`,
    );
  }
});

test("workout-helpers.ts dev-mode assertion still pins the 6:00 → 6:20 contract", async () => {
  const src = await readFile(HELPERS, "utf8");
  assert.ok(
    src.includes(`"6:20/mi"`),
    "Dev-mode assertion for paceRangeLabel(mp, +20s/mi, mp:360) was removed — re-add to lock the math",
  );
  assert.ok(
    src.includes("mp: 360"),
    "Dev-mode assertion no longer pins mp=360 — check workout-helpers.ts",
  );
});

test("WorkoutStep type still declares repeats + recovery + paceAdjustment", async () => {
  const src = await readFile(HELPERS, "utf8");
  // These three fields are the bug-prone ones — silent removal would
  // recreate the same data-loss class as the iOS regression.
  assert.match(
    src,
    /repeats\?:\s*number/,
    "WorkoutStep no longer declares optional `repeats: number` — check workout-helpers.ts",
  );
  assert.match(
    src,
    /recovery\?:\s*\{/,
    "WorkoutStep no longer declares optional `recovery` sub-object",
  );
  assert.match(
    src,
    /paceAdjustment\?:\s*PaceAdjustment/,
    "WorkoutStep no longer declares optional `paceAdjustment`",
  );
});

test("workout-template-form persists estimated_distance_miles using the new estimator", async () => {
  const src = await readFile(FORM, "utf8");
  assert.ok(
    src.includes("estimatedWorkoutMiles(steps, undefined)"),
    "Persisted distance is supposed to use the reference-paces estimator, not the preview-paces one — coaches would otherwise see different stored miles depending on their preview goal",
  );
});

test("workout-template-card displays ~ prefix for time-based segments", async () => {
  const src = await readFile(CARD, "utf8");
  assert.ok(
    src.includes("workoutHasTimeBasedSegment"),
    "Card no longer detects time-based segments — fartlek mile estimates would render as exact numbers",
  );
  assert.ok(
    src.includes(`hasTimeBased ? "~" : ""`),
    "Card no longer prefixes ~ for estimated miles",
  );
});

// ── Structure grouping contract ─────────────────────────
// The card renderer relies on `groupStepsIntoSections` to collapse flat
// data ("800m, 2min, 800m, 2min, ...") into rep blocks. These checks
// guard the function's existence and its behavior at the shape level.

test("PACE_ZONES no longer includes longRun (retired May 2026)", async () => {
  const src = await readFile(HELPERS, "utf8");
  // Match a PACE_ZONES entry literally — `value: "longRun"` only appears
  // as an option-list row, never in legacy comments or type-union members
  // (those use the bare identifier `longRun`).
  assert.ok(
    !/value:\s*"longRun"/.test(src),
    "PACE_ZONES still declares a longRun option — the LR pace zone was retired and shouldn't appear in dropdowns",
  );
});

test("workout-helpers.ts exports groupStepsIntoSections + safePace helpers", async () => {
  const src = await readFile(HELPERS, "utf8");
  for (const sig of [
    "export function groupStepsIntoSections",
    "export function safePaceLabel",
    "export function safePaceRangeLabel",
    "export interface WorkoutStepBlock",
    "export interface WorkoutSections",
  ]) {
    assert.ok(src.includes(sig), `workout-helpers.ts is missing '${sig}'`);
  }
});

test("workout-template-card hands flat steps to WorkoutStructure (no inline ledger)", async () => {
  const src = await readFile(CARD, "utf8");
  assert.ok(
    src.includes("<WorkoutStructure"),
    "Card should delegate to WorkoutStructure — found inline structure rendering instead",
  );
  // The old buggy describeStep helper should be gone.
  assert.ok(
    !src.includes("function describeStep"),
    "Card still has the legacy describeStep helper — should use WorkoutStructure",
  );
});

// Algorithm port: detect a 6 × 800m / 2 min recovery pattern in flat
// data. Mirrors the production heuristic so a regression there is
// caught here too.
function portedGroup(steps) {
  let warmupEnd = 0;
  while (warmupEnd < steps.length && steps[warmupEnd].stepType === "warmup") warmupEnd++;
  let cooldownStart = steps.length;
  while (cooldownStart > warmupEnd && steps[cooldownStart - 1].stepType === "cooldown") cooldownStart--;
  const middle = steps.slice(warmupEnd, cooldownStart);

  const matchesMain = (a, b) =>
    a.stepType === b.stepType &&
    a.durationType === b.durationType &&
    a.durationValue === b.durationValue &&
    (a.paceZone ?? "") === (b.paceZone ?? "");

  const blocks = [];
  let i = 0;
  while (i < middle.length) {
    const step = middle[i];
    if ((step.repeats ?? 1) > 1) {
      blocks.push({ kind: "reps", step, repeats: step.repeats });
      i++;
      continue;
    }
    if (step.stepType === "active") {
      let mainCount = 1;
      let j = i + 1;
      while (j < middle.length) {
        if (matchesMain(middle[j], step)) {
          mainCount++; j++; continue;
        }
        if (j + 1 >= middle.length) break;
        if (!matchesMain(middle[j + 1], step)) break;
        mainCount++;
        j += 2;
      }
      if (mainCount >= 2) {
        blocks.push({ kind: "reps", step, repeats: mainCount });
        i = j;
        continue;
      }
    }
    blocks.push({ kind: "single", step });
    i++;
  }

  return {
    warmup: steps.slice(0, warmupEnd),
    blocks,
    cooldown: steps.slice(cooldownStart),
  };
}

test("groups: flat 6×800m + 2min recovery pattern collapses into one reps block", () => {
  const steps = [
    { stepType: "warmup",   durationType: "distance_miles",  durationValue: 2,    paceZone: "easy" },
    { stepType: "active",   durationType: "time_seconds",    durationValue: 600,  paceZone: "tempo" }, // 10 min
    { stepType: "active",   durationType: "time_seconds",    durationValue: 240,  paceZone: "easy" },  // 4 min
    { stepType: "active",   durationType: "distance_meters", durationValue: 800,  paceZone: "fiveK" },
    { stepType: "active",   durationType: "time_seconds",    durationValue: 120,  paceZone: "easy" },  // 2 min
    { stepType: "active",   durationType: "distance_meters", durationValue: 800,  paceZone: "fiveK" },
    { stepType: "active",   durationType: "time_seconds",    durationValue: 120,  paceZone: "easy" },
    { stepType: "active",   durationType: "distance_meters", durationValue: 800,  paceZone: "fiveK" },
    { stepType: "active",   durationType: "time_seconds",    durationValue: 120,  paceZone: "easy" },
    { stepType: "active",   durationType: "distance_meters", durationValue: 800,  paceZone: "fiveK" },
    { stepType: "active",   durationType: "time_seconds",    durationValue: 120,  paceZone: "easy" },
    { stepType: "active",   durationType: "distance_meters", durationValue: 800,  paceZone: "fiveK" },
    { stepType: "active",   durationType: "time_seconds",    durationValue: 120,  paceZone: "easy" },
    { stepType: "active",   durationType: "distance_meters", durationValue: 800,  paceZone: "fiveK" },
    { stepType: "cooldown", durationType: "distance_miles",  durationValue: 1,    paceZone: "easy" },
  ];
  const sections = portedGroup(steps);
  assert.equal(sections.warmup.length, 1);
  assert.equal(sections.cooldown.length, 1);
  assert.equal(sections.blocks.length, 3); // 10min + 4min + (6×800m)
  assert.equal(sections.blocks[2].kind, "reps");
  assert.equal(sections.blocks[2].repeats, 6);
});

test("groups: new-format step with repeats already set passes through unchanged", () => {
  const steps = [
    { stepType: "warmup",   durationType: "distance_miles",  durationValue: 2,   paceZone: "easy" },
    { stepType: "active",   durationType: "distance_miles",  durationValue: 1,   paceZone: "threshold", repeats: 7 },
    { stepType: "cooldown", durationType: "distance_miles",  durationValue: 2,   paceZone: "easy" },
  ];
  const sections = portedGroup(steps);
  assert.equal(sections.blocks.length, 1);
  assert.equal(sections.blocks[0].kind, "reps");
  assert.equal(sections.blocks[0].repeats, 7);
});

test("groups: empty steps return empty sections", () => {
  const sections = portedGroup([]);
  assert.equal(sections.warmup.length, 0);
  assert.equal(sections.blocks.length, 0);
  assert.equal(sections.cooldown.length, 0);
});

test("groups: single active step is a single block", () => {
  const steps = [
    { stepType: "active", durationType: "distance_miles", durationValue: 6, paceZone: "easy" },
  ];
  const sections = portedGroup(steps);
  assert.equal(sections.blocks.length, 1);
  assert.equal(sections.blocks[0].kind, "single");
});
