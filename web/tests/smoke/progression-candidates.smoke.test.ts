// Runtime tests for the deterministic progression-candidate generator
// behind the coach portal's "smart duplicate" flow.
//
// Run: cd web && npm run test:smoke
//
// The invariants pinned here are the safety contract the LLM annotation
// layer relies on (it may only reorder/annotate these candidates):
//   1. +1 rep increments repeats and nothing else.
//   2. Recovery reduction tightens by one notch and respects the floor.
//   3. extend_volume NEVER exceeds +10% of total workout volume.
//   4. The pace zone NEVER changes — on any step, in any candidate.

import { test } from "node:test";
import { strict as assert } from "node:assert";

import {
  generateProgressionCandidates,
  progressionTargetIndex,
  estimatedWorkoutMiles,
  type WorkoutStep,
} from "@/components/coach/workout-helpers";

// ── Fixtures ────────────────────────────────────────────

function intervalWorkout(): WorkoutStep[] {
  // 2 mi wu · 5 × 1km @ 5K w/ 90s easy jog · 2 mi cd
  return [
    { id: "wu", stepType: "warmup", durationType: "distance_miles", durationValue: 2, paceZone: "easy", notes: "" },
    {
      id: "main",
      stepType: "active",
      durationType: "distance_meters",
      durationValue: 1000,
      paceZone: "fiveK",
      notes: "",
      repeats: 5,
      recovery: { durationType: "time_seconds", durationValue: 90, paceZone: "easy" },
    },
    { id: "cd", stepType: "cooldown", durationType: "distance_miles", durationValue: 2, paceZone: "easy", notes: "" },
  ];
}

function continuousWorkout(mainMiles: number): WorkoutStep[] {
  // 2 mi wu · N mi @ MP · 1 mi cd
  return [
    { id: "wu", stepType: "warmup", durationType: "distance_miles", durationValue: 2, paceZone: "easy", notes: "" },
    { id: "main", stepType: "active", durationType: "distance_miles", durationValue: mainMiles, paceZone: "mp", notes: "" },
    { id: "cd", stepType: "cooldown", durationType: "distance_miles", durationValue: 1, paceZone: "easy", notes: "" },
  ];
}

// ── Target selection ────────────────────────────────────

test("progression target is the hardest active step (the rep set, not the warmup)", () => {
  assert.equal(progressionTargetIndex(intervalWorkout()), 1);
});

test("no active steps → no candidates", () => {
  const steps: WorkoutStep[] = [
    { id: "wu", stepType: "warmup", durationType: "distance_miles", durationValue: 2, paceZone: "easy", notes: "" },
  ];
  assert.deepEqual(generateProgressionCandidates(steps), []);
  assert.deepEqual(generateProgressionCandidates([]), []);
});

// ── 1. Rep increment ────────────────────────────────────

test("add-rep: 5×1km becomes 6×1km, everything else untouched", () => {
  const source = intervalWorkout();
  const candidates = generateProgressionCandidates(source);
  const addRep = candidates.find((c) => c.kind === "add_rep");
  assert.ok(addRep, "expected an add_rep candidate for a rep set");
  assert.equal(addRep.id, "add-rep");
  assert.equal(addRep.steps[1].repeats, 6);
  // Rep distance, recovery, and bookends unchanged.
  assert.equal(addRep.steps[1].durationValue, 1000);
  assert.equal(addRep.steps[1].recovery?.durationValue, 90);
  assert.equal(addRep.steps[0].durationValue, 2);
  assert.equal(addRep.steps[2].durationValue, 2);
  // Source not mutated.
  assert.equal(source[1].repeats, 5);
});

test("extend-rep: 1000m steps up the ladder to 1200m", () => {
  const candidates = generateProgressionCandidates(intervalWorkout());
  const extend = candidates.find((c) => c.kind === "extend_rep");
  assert.ok(extend, "expected an extend_rep candidate for an on-ladder rep");
  assert.equal(extend.id, "extend-rep-1200m");
  assert.equal(extend.steps[1].durationValue, 1200);
  assert.equal(extend.steps[1].durationType, "distance_meters");
  assert.equal(extend.steps[1].repeats, 5);
});

test("extend-rep is not offered for off-ladder rep distances", () => {
  const steps = intervalWorkout();
  steps[1].durationValue = 700; // not a ladder rung
  const candidates = generateProgressionCandidates(steps);
  assert.equal(candidates.find((c) => c.kind === "extend_rep"), undefined);
});

// ── 2. Recovery reduction ───────────────────────────────

test("reduce-recovery: 90s jog tightens to 75s", () => {
  const candidates = generateProgressionCandidates(intervalWorkout());
  const reduce = candidates.find((c) => c.kind === "reduce_recovery");
  assert.ok(reduce, "expected a reduce_recovery candidate");
  assert.equal(reduce.steps[1].recovery?.durationValue, 75);
  assert.equal(reduce.steps[1].recovery?.durationType, "time_seconds");
});

test("reduce-recovery: 400m jog tightens to 300m", () => {
  const steps = intervalWorkout();
  steps[1].recovery = { durationType: "distance_meters", durationValue: 400, paceZone: "easy" };
  const candidates = generateProgressionCandidates(steps);
  const reduce = candidates.find((c) => c.kind === "reduce_recovery");
  assert.ok(reduce);
  assert.equal(reduce.steps[1].recovery?.durationValue, 300);
});

test("reduce-recovery respects the floor (30s / 100m) and disappears at it", () => {
  // At 30s the time notch would go below the floor → not offered.
  const atTimeFloor = intervalWorkout();
  atTimeFloor[1].recovery = { durationType: "time_seconds", durationValue: 30, paceZone: "easy" };
  assert.equal(
    generateProgressionCandidates(atTimeFloor).find((c) => c.kind === "reduce_recovery"),
    undefined,
  );
  // 40s → clamps to the 30s floor, not 25s.
  const nearTimeFloor = intervalWorkout();
  nearTimeFloor[1].recovery = { durationType: "time_seconds", durationValue: 40, paceZone: "easy" };
  const clamped = generateProgressionCandidates(nearTimeFloor).find(
    (c) => c.kind === "reduce_recovery",
  );
  assert.ok(clamped);
  assert.equal(clamped.steps[1].recovery?.durationValue, 30);
  // 100m distance recovery is already at the floor → not offered.
  const atDistFloor = intervalWorkout();
  atDistFloor[1].recovery = { durationType: "distance_meters", durationValue: 100, paceZone: "easy" };
  assert.equal(
    generateProgressionCandidates(atDistFloor).find((c) => c.kind === "reduce_recovery"),
    undefined,
  );
});

// ── 3. Volume cap ≤10% ──────────────────────────────────

test("extend-volume candidates never exceed +10% of total workout volume", () => {
  // 2 wu + 7 MP + 1 cd = 10 mi. +0.5 (5%) fits; +1 (10%) sits exactly at
  // the cap and must also fit (epsilon at the boundary).
  const source = continuousWorkout(7);
  const base = estimatedWorkoutMiles(source);
  const candidates = generateProgressionCandidates(source);
  const volumes = candidates.filter((c) => c.kind === "extend_volume");
  assert.ok(volumes.length >= 1, "expected extend_volume candidates for a continuous block");
  for (const c of volumes) {
    const next = estimatedWorkoutMiles(c.steps);
    assert.ok(
      next <= base * 1.10 + 1e-9,
      `${c.id} exceeds the 10% volume cap: ${base} → ${next}`,
    );
  }
  assert.deepEqual(
    volumes.map((c) => c.id).sort(),
    ["extend-volume-0.5mi", "extend-volume-1mi"],
  );
});

test("extend-volume drops the over-cap increment on a short workout", () => {
  // 2 wu + 3 MP + 1 cd = 6 mi total. +0.5 = 8.3% OK; +1 = 16.7% → dropped.
  const candidates = generateProgressionCandidates(continuousWorkout(3));
  const ids = candidates.filter((c) => c.kind === "extend_volume").map((c) => c.id);
  assert.deepEqual(ids, ["extend-volume-0.5mi"]);
});

// ── 4. Zone never changes ───────────────────────────────

test("no candidate ever changes any step's pace zone (or recovery zone)", () => {
  const fixtures: WorkoutStep[][] = [intervalWorkout(), continuousWorkout(7), continuousWorkout(3)];
  for (const source of fixtures) {
    for (const candidate of generateProgressionCandidates(source)) {
      assert.equal(candidate.steps.length, source.length, `${candidate.id} changed step count`);
      for (let i = 0; i < source.length; i++) {
        assert.equal(
          candidate.steps[i].paceZone,
          source[i].paceZone,
          `${candidate.id} changed paceZone on step ${i}`,
        );
        assert.equal(
          candidate.steps[i].recovery?.paceZone,
          source[i].recovery?.paceZone,
          `${candidate.id} changed recovery paceZone on step ${i}`,
        );
        assert.deepEqual(
          candidate.steps[i].paceAdjustment,
          source[i].paceAdjustment,
          `${candidate.id} changed paceAdjustment on step ${i}`,
        );
      }
    }
  }
});

// ── Determinism & shape ─────────────────────────────────

test("generator is deterministic and capped at 4 candidates", () => {
  const a = generateProgressionCandidates(intervalWorkout());
  const b = generateProgressionCandidates(intervalWorkout());
  assert.deepEqual(a, b);
  assert.ok(a.length >= 2 && a.length <= 4, `expected 2–4 candidates, got ${a.length}`);
  // Deterministic order: add_rep · extend_rep · reduce_recovery.
  assert.deepEqual(
    a.map((c) => c.kind),
    ["add_rep", "extend_rep", "reduce_recovery"],
  );
  // Every candidate carries a label and a structure detail line.
  for (const c of a) {
    assert.ok(c.label.length > 0, `${c.id} missing label`);
    assert.ok(c.detail && c.detail.length > 0, `${c.id} missing detail`);
  }
});
