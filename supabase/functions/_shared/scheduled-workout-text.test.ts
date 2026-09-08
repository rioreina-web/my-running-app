/**
 * Tests for scheduled-workout text extraction — see the module doc for why
 * this exists: `session` looked like the text column and is actually an
 * integer, which would have thrown on the first real row.
 *
 * Run: deno test supabase/functions/_shared/scheduled-workout-text.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { summarizeSteps, textForScheduledWorkout } from "./scheduled-workout-text.ts";

Deno.test("summarizes a warmup/reps/cooldown workout into shorthand-ish text", () => {
  const steps = [
    { stepType: "warmup", durationType: "distance_miles", durationValue: 2 },
    { stepType: "active", durationType: "distance_meters", durationValue: 800, paceZone: "fiveK", repeats: 6, recovery: { durationType: "distance_meters", durationValue: 400 } },
    { stepType: "cooldown", durationType: "distance_miles", durationValue: 2 },
  ];
  const text = summarizeSteps({ steps });
  assertEquals(text, "wu 2mi, 6x 800m @ fiveK + 400m jog, cd 2mi");
});

Deno.test("an exact pace renders as a clock time, not the raw seconds", () => {
  const text = summarizeSteps({ steps: [{ durationType: "distance_miles", durationValue: 3, exactPaceSecPerMile: 385 }] });
  assertEquals(text, "3mi @ 6:25");
});

Deno.test("a time-based step renders in minutes", () => {
  const text = summarizeSteps({ steps: [{ durationType: "time_seconds", durationValue: 1200, paceZone: "threshold" }] });
  assertEquals(text, "20' @ threshold");
});

Deno.test("no steps array returns null, not an empty string", () => {
  assertEquals(summarizeSteps(null), null);
  assertEquals(summarizeSteps({}), null);
  assertEquals(summarizeSteps({ steps: [] }), null);
});

Deno.test("never throws on a row shaped nothing like a workout", () => {
  for (const junk of [null, undefined, 42, "x", { steps: "not an array" }, { steps: [null, 1, "x"] }]) {
    assert(summarizeSteps(junk) === null || typeof summarizeSteps(junk) === "string");
  }
});

Deno.test("textForScheduledWorkout prefers notes, then steps, then type, never `session`", () => {
  const withNotes = textForScheduledWorkout({ notes: "  felt great today  ", workout_type: "easy" });
  assertEquals(withNotes, "felt great today");

  const withSteps = textForScheduledWorkout({
    notes: null,
    workout_data: { steps: [{ durationType: "distance_miles", durationValue: 5, paceZone: "easy" }] },
    workout_type: "easy",
  });
  assertEquals(withSteps, "5mi @ easy");

  const fallback = textForScheduledWorkout({ notes: null, workout_data: null, workout_type: "rest" });
  assertEquals(fallback, "rest");

  const nothing = textForScheduledWorkout({});
  assertEquals(nothing, "Workout");
});
