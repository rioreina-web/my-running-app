// 10-zone workout labels, zone-dot tags, and the mono estimated line.
// Pins the helpers that replace legacy "tempo/intervals" copy on library
// cards with pace-zone shorthand (workoutZoneLabel / stepZones /
// describeWorkoutLine), ported in intent from prototypes/workout-builder.html.
//
// Run: cd web && npm run test:smoke

import { test } from "node:test";
import { strict as assert } from "node:assert";

import {
  workoutZoneLabel,
  describeWorkoutLine,
  stepZones,
  zoneForStep,
  zoneLabelShort,
  type WorkoutStep,
} from "@/components/coach/workout-helpers";

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

// A classic interval workout: 2mi wu · 6×800m @ 5K (200m jog) · 2mi cd.
function intervalWorkout(): WorkoutStep[] {
  return [
    step({ stepType: "warmup", durationType: "distance_miles", durationValue: 2, paceZone: "easy" }),
    step({
      stepType: "active",
      durationType: "distance_meters",
      durationValue: 800,
      paceZone: "fiveK",
      repeats: 6,
      recovery: { durationType: "distance_meters", durationValue: 200, paceZone: "easy" },
    }),
    step({ stepType: "cooldown", durationType: "distance_miles", durationValue: 2, paceZone: "easy" }),
  ];
}

// ── workoutZoneLabel ─────────────────────────────────────

test("workoutZoneLabel: a tempo run reads as its zone + distance", () => {
  const steps = [step({ paceZone: "threshold", durationType: "distance_miles", durationValue: 6 })];
  assert.equal(workoutZoneLabel(steps), "LT 6 mi");
});

test("workoutZoneLabel: a marathon-pace block reads as MP + distance", () => {
  const steps = [
    step({ stepType: "warmup", durationValue: 2 }),
    step({ paceZone: "mp", durationType: "distance_miles", durationValue: 7 }),
  ];
  // Headline is the MP block (7 mi), not the whole workout (9 mi).
  assert.equal(workoutZoneLabel(steps), "MP 7 mi");
});

test("workoutZoneLabel: an interval set reads as reps × distance", () => {
  assert.equal(workoutZoneLabel(intervalWorkout()), "5K 6×800m");
});

test("workoutZoneLabel: 1000m reps render as km", () => {
  const steps = [
    step({ stepType: "active", durationType: "distance_meters", durationValue: 1000, paceZone: "fiveK", repeats: 5 }),
  ];
  assert.equal(workoutZoneLabel(steps), "5K 5×1km");
});

test("workoutZoneLabel: a long run uses the structural Long label", () => {
  const steps = [step({ paceZone: "longRun" as WorkoutStep["paceZone"], durationValue: 16 })];
  assert.equal(zoneForStep(steps[0]), "longRun");
  assert.equal(workoutZoneLabel(steps), "Long 16 mi");
});

test("workoutZoneLabel: empty workout returns null (caller falls back)", () => {
  assert.equal(workoutZoneLabel([]), null);
});

// ── stepZones (dots) ─────────────────────────────────────

test("stepZones: lists distinct quality zones, skips easy/warmup/cooldown", () => {
  assert.deepEqual(stepZones(intervalWorkout()), ["fiveK"]);
});

test("stepZones: a pure easy run has no quality dots", () => {
  const steps = [step({ paceZone: "easy", durationValue: 8 })];
  assert.deepEqual(stepZones(steps), []);
});

test("stepZones: a mixed session lists zones in order, deduped", () => {
  const steps = [
    step({ stepType: "warmup", durationValue: 2 }),
    step({ paceZone: "mp", durationType: "distance_miles", durationValue: 4 }),
    step({ paceZone: "threshold", durationType: "distance_miles", durationValue: 2 }),
    step({ paceZone: "mp", durationType: "distance_miles", durationValue: 4 }),
  ];
  assert.deepEqual(stepZones(steps), ["mp", "threshold"]);
});

// ── describeWorkoutLine ──────────────────────────────────

test("describeWorkoutLine: warmup · reps @ zone · cooldown", () => {
  assert.equal(describeWorkoutLine(intervalWorkout()), "2 wu · 6 × 800m @ 5K · 2 cd");
});

test("describeWorkoutLine: a single tempo block with wu/cd", () => {
  const steps = [
    step({ stepType: "warmup", durationValue: 1 }),
    step({ paceZone: "threshold", durationType: "distance_miles", durationValue: 6 }),
    step({ stepType: "cooldown", durationValue: 1 }),
  ];
  assert.equal(describeWorkoutLine(steps), "1 wu · 6 mi @ LT · 1 cd");
});

test("describeWorkoutLine: an exact pinned pace shows the clock, not a zone", () => {
  const steps = [step({ exactPaceSecPerMile: 345, durationType: "distance_miles", durationValue: 5 })];
  assert.equal(describeWorkoutLine(steps), "5 mi @ 5:45/mi");
});

// ── zoneLabelShort ───────────────────────────────────────

test("zoneLabelShort: longRun is Long, others use canonical short names", () => {
  assert.equal(zoneLabelShort("longRun"), "Long");
  assert.equal(zoneLabelShort("threshold"), "LT");
  assert.equal(zoneLabelShort("fiveK"), "5K");
  assert.equal(zoneLabelShort("mp"), "MP");
});
