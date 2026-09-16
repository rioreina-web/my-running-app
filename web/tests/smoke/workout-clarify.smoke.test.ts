// Clarification questions — the layer that turns "I didn't understand this"
// into something the coach can close with a tap.
//
// The behaviour that matters: ask ONCE per distinct thing, offer only real
// answers, and apply the answer without re-parsing (so hand edits survive and
// the parse cannot drift on a second pass).
//
// Run: cd web && npm run test:smoke

import { test } from "node:test";
import { strict as assert } from "node:assert";

import { parseWorkoutText } from "@/components/coach/workout-nl-parser";
import { buildClarifications, applyClarification, describeStep } from "@/components/coach/workout-clarify";
import { PACE_ZONES } from "@/components/coach/workout-helpers";

test("a missing pace becomes a question, not a warning", () => {
  const r = parseWorkoutText("10-12 x K");
  const qs = buildClarifications(r.steps, r.unresolved);

  assert.equal(qs.length, 1, "one thing is unknown, so one question");
  assert.match(qs[0].question, /pace/i);
  assert.match(qs[0].question, /11 × 1km/, "names the step it is about");
  assert.equal(qs[0].reason, "no_pace_written");
});

test("every offered answer is a real pace zone", () => {
  const r = parseWorkoutText("10-12 x K");
  const [q] = buildClarifications(r.steps, r.unresolved);
  const valid = new Set(PACE_ZONES.map((z) => z.value));
  assert.ok(q.options.length > 0);
  for (const o of q.options) {
    assert.ok(valid.has(o.value as never), `${o.value} is not a pace zone`);
  }
});

test("answering sets the pace and retires the question", () => {
  const r = parseWorkoutText("10-12 x K");
  const [q] = buildClarifications(r.steps, r.unresolved);

  const after = applyClarification(r.steps, q, "tenK");
  assert.equal(after[0].paceZone, "tenK");
  assert.equal(r.steps[0].paceZone, "easy", "the original array is not mutated");
});

test("identical unresolved legs are asked about once, then all resolve together", () => {
  // Six sets of two legs; neither leg names a pace.
  const r = parseWorkoutText("6 sets of (1k / 600m)");
  const qs = buildClarifications(r.steps, r.unresolved);

  assert.ok(r.steps.length >= 12, `expected an expansion, got ${r.steps.length}`);
  assert.equal(qs.length, 2, "one question per distinct leg, not per rep");

  const kmQuestion = qs.find((q) => q.question.includes("1km"));
  assert.ok(kmQuestion, "should ask about the 1km legs");
  assert.equal(kmQuestion!.stepIds.length, 6, "covers all six 1km legs");

  const after = applyClarification(r.steps, kmQuestion!, "hm");
  const kmSteps = after.filter((s) => s.durationType === "distance_km");
  assert.equal(kmSteps.length, 6);
  assert.ok(kmSteps.every((s) => s.paceZone === "hm"), "one answer resolved all six");
});

test("a cooldown before any warmup is queried, never silently corrected", () => {
  // The real typo from this coach's sheet: CD written at both ends.
  const r = parseWorkoutText("2mi CD + 6x800 @ 5k w/ 400m jog + 2mi CD");
  const qs = buildClarifications(r.steps, r.unresolved);

  const typo = qs.find((q) => q.reason === "cooldown_at_start");
  assert.ok(typo, "should ask about the opening cooldown");
  assert.match(typo!.question, /warm-up/i);
  assert.equal(r.steps[0].stepType, "cooldown", "unchanged until the coach answers");

  const fixed = applyClarification(r.steps, typo!, "warmup");
  assert.equal(fixed[0].stepType, "warmup");
});

test("declining the typo question leaves the step alone", () => {
  const r = parseWorkoutText("2mi CD + 6x800 @ 5k w/ 400m jog + 2mi CD");
  const [typo] = buildClarifications(r.steps, r.unresolved).filter((q) => q.reason === "cooldown_at_start");
  const kept = applyClarification(r.steps, typo, "cooldown");
  assert.equal(kept[0].stepType, "cooldown");
});

test("a fully-understood workout asks nothing", () => {
  const r = parseWorkoutText("2mi wu, 6x800 @ 5k w/ 400m jog, 2mi cd");
  assert.deepEqual(buildClarifications(r.steps, r.unresolved), []);
});

test("describeStep reads the way a coach writes", () => {
  const r = parseWorkoutText("6x800 @ 5k");
  assert.equal(describeStep(r.steps[0]), "6 × 800m");
  assert.equal(describeStep(parseWorkoutText("20 min @ LT").steps[0]), "20'");
  assert.equal(describeStep(parseWorkoutText("2mi @ MP").steps[0]), "2mi");
});
