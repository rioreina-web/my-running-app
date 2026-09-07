// Natural-language workout parser (Phase 4a). Pins the port of the prototype
// grammar (prototypes/workout-builder.html) + the adapter to the web
// WorkoutStep shape. Covers wu/cd, reps + ranges, recovery (jog vs rest),
// zones + offsets, exact pace, target time, sets flattening, and the v1
// compound-set drop.
//
// Run: cd web && npm run test:smoke

import { test } from "node:test";
import { strict as assert } from "node:assert";

import { parseWorkoutText } from "@/components/coach/workout-nl-parser";
import type { WorkoutStep } from "@/components/coach/workout-helpers";

// ── The canonical example ────────────────────────────────

test("classic: 2mi wu, 6x800 @ 5k w/ 400m jog, 2mi cd", () => {
  const { steps, unparsed } = parseWorkoutText("2mi wu, 6x800 @ 5k w/ 400m jog, 2mi cd");
  assert.equal(unparsed.length, 0, `nothing should be unparsed: ${unparsed.join(" | ")}`);
  assert.equal(steps.length, 3);

  const [wu, main, cd] = steps;
  assert.equal(wu.stepType, "warmup");
  assert.equal(wu.durationType, "distance_miles");
  assert.equal(wu.durationValue, 2);
  assert.equal(wu.paceZone, "easy");

  assert.equal(main.stepType, "active");
  assert.equal(main.durationType, "distance_meters");
  assert.equal(main.durationValue, 800);
  assert.equal(main.repeats, 6);
  assert.equal(main.paceZone, "fiveK");
  assert.ok(main.recovery, "should have a recovery");
  assert.equal(main.recovery!.durationType, "distance_meters");
  assert.equal(main.recovery!.durationValue, 400);
  assert.equal(main.recovery!.paceZone, "easy", "a jog recovery is easy pace");

  assert.equal(cd.stepType, "cooldown");
  assert.equal(cd.durationValue, 2);
});

// ── Zones + offsets ──────────────────────────────────────

test("zone offset: MP-10 → seconds_per_mile -10 (faster)", () => {
  const { steps } = parseWorkoutText("6mi @ MP-10");
  assert.equal(steps.length, 1);
  assert.equal(steps[0].paceZone, "mp");
  assert.deepEqual(steps[0].paceAdjustment, { type: "seconds_per_mile", value: -10 });
});

test("zone offset: percent slower (LT+3%)", () => {
  // The offset + must be attached (LT+3%); a spaced + is a segment separator
  // in the prototype grammar, so "LT +3%" would split into two segments.
  const { steps } = parseWorkoutText("3mi @ LT+3%");
  assert.equal(steps[0].paceZone, "threshold");
  assert.deepEqual(steps[0].paceAdjustment, { type: "percent", value: 3 });
});

test("bare zone word without @ (40 min easy)", () => {
  const { steps } = parseWorkoutText("40 min easy");
  assert.equal(steps.length, 1);
  assert.equal(steps[0].durationType, "time_seconds");
  assert.equal(steps[0].durationValue, 40 * 60);
  assert.equal(steps[0].paceZone, "easy");
});

// ── Exact pace + target time ─────────────────────────────

test("exact pace: @ 5:45 → exactPaceSecPerMile 345", () => {
  const { steps } = parseWorkoutText("5mi @ 5:45");
  assert.equal(steps[0].exactPaceSecPerMile, 345);
  assert.equal(steps[0].paceAdjustment, undefined);
});

test("target time: 800 in 2:30 → exact per-mile pace", () => {
  const { steps } = parseWorkoutText("4 x 800 in 2:30 w/ 90s rest");
  const m = steps[0];
  assert.equal(m.durationValue, 800);
  assert.equal(m.repeats, 4);
  // 150s over 800m (0.4970 mi) ≈ 302 s/mi.
  assert.ok(m.exactPaceSecPerMile && m.exactPaceSecPerMile > 298 && m.exactPaceSecPerMile < 306,
    `got ${m.exactPaceSecPerMile}`);
  assert.equal(m.recovery!.paceZone, undefined, "a rest recovery has no pace zone");
});

// ── Ranges ───────────────────────────────────────────────

test("rep range: 4-6 x 800 → midpoint 5 repeats", () => {
  const { steps } = parseWorkoutText("4-6 x 800 @ 5k");
  assert.equal(steps[0].repeats, 5);
});

test("distance range: 10-12k @ MP → midpoint 11km", () => {
  const { steps } = parseWorkoutText("10-12k @ MP");
  assert.equal(steps[0].durationType, "distance_km");
  assert.equal(steps[0].durationValue, 11);
});

// ── Recovery styles ──────────────────────────────────────

test("jog recovery vs standing rest", () => {
  const jog = parseWorkoutText("5 x 1k @ 5k w/ 2min jog").steps[0];
  assert.equal(jog.recovery!.paceZone, "easy");
  assert.equal(jog.recovery!.durationType, "time_seconds");
  assert.equal(jog.recovery!.durationValue, 120);

  const rest = parseWorkoutText("5 x 1k @ 5k w/ 2min rest").steps[0];
  assert.equal(rest.recovery!.paceZone, undefined);
});

// ── Sets flattening ──────────────────────────────────────

test("sets flatten to total repeats (2 sets of 6 x 400 → 12)", () => {
  const { steps } = parseWorkoutText("2 sets of 6 x 400m @ 3k w/ 200m jog");
  assert.equal(steps[0].repeats, 12, "2 × 6 = 12 total reps in the flat model");
  assert.equal(steps[0].paceZone, "threeK");
});

// ── Standalone rest ──────────────────────────────────────

test("standalone rest step", () => {
  const { steps } = parseWorkoutText("3mi @ MP, 3 min rest, 3mi @ MP");
  assert.equal(steps.length, 3);
  assert.equal(steps[1].stepType, "rest");
  assert.equal(steps[1].durationType, "time_seconds");
  assert.equal(steps[1].durationValue, 180);
});

// ── Compound sets are reported, not silently dropped ─────

// Superseded 2026-08-25. This used to assert that a compound set emitted NO
// steps and was handed back as text. That was never a model limit — `repeats`
// is a compression of the flat format, not the only encoding of it — so the
// set is now written out leg by leg instead of refused.
test("compound set expands leg by leg, alternating in order", () => {
  const { steps, unparsed } = parseWorkoutText("5 x (600 @ 5k / 400 @ 3k)");
  assert.equal(unparsed.length, 0, `should no longer be refused: ${unparsed.join(" | ")}`);
  assert.equal(steps.length, 10, "5 sets x 2 legs");

  // Legs alternate rather than grouping — 600/400/600/400, not 600x5 then 400x5.
  assert.equal(steps[0].durationValue, 600);
  assert.equal(steps[0].paceZone, "fiveK");
  assert.equal(steps[1].durationValue, 400);
  assert.equal(steps[1].paceZone, "threeK");
  assert.equal(steps[2].durationValue, 600);
  assert.equal(steps[9].paceZone, "threeK");
});

test("a rest leg inside a set becomes the preceding rep's recovery", () => {
  const { steps } = parseWorkoutText("3 sets of (1k @ HM - 1' rest - 600m @ 10k - 1' rest)");
  assert.equal(steps.length, 6, "rest legs are recoveries, not steps of their own");
  assert.equal(steps[0].paceZone, "hm");
  assert.equal(steps[0].recovery?.durationValue, 60);
  assert.equal(steps[1].paceZone, "tenK");
  assert.equal(steps[1].recovery?.durationValue, 60);
});

// ── "then" / mixed separators ────────────────────────────

test("segments split on commas and 'then'", () => {
  const { steps } = parseWorkoutText("2mi wu then 4mi @ MP then 1mi cd");
  assert.equal(steps.length, 3);
  assert.equal(steps[0].stepType, "warmup");
  assert.equal(steps[1].paceZone, "mp");
  assert.equal(steps[2].stepType, "cooldown");
});

test("split never breaks an offset's + (MP+15 stays one step)", () => {
  const { steps } = parseWorkoutText("6mi @ MP+15");
  assert.equal(steps.length, 1);
  assert.deepEqual(steps[0].paceAdjustment, { type: "seconds_per_mile", value: 15 });
});

// ── Gibberish is reported, not crashed on ────────────────

test("unparseable fragment is returned in unparsed, not thrown", () => {
  const { steps, unparsed } = parseWorkoutText("2mi wu, xyzzy, 2mi cd");
  assert.equal(steps.length, 2);
  assert.ok(unparsed.some((u) => /xyzzy/.test(u)));
});

test("empty input yields nothing", () => {
  const { steps, unparsed } = parseWorkoutText("");
  assert.equal(steps.length, 0);
  assert.equal(unparsed.length, 0);
});

// ── All emitted steps satisfy the WorkoutStep contract ───

test("every emitted step is a well-formed WorkoutStep", () => {
  const { steps } = parseWorkoutText("2mi wu, 6x800 @ 5k-5 w/ 400m jog, 4mi @ MP, 2mi cd");
  const validTypes = new Set(["distance_miles", "distance_km", "distance_meters", "time_seconds"]);
  for (const s of steps as WorkoutStep[]) {
    assert.ok(typeof s.id === "string" && s.id.length > 0);
    assert.ok(validTypes.has(s.durationType));
    assert.ok(typeof s.durationValue === "number" && s.durationValue > 0);
    assert.ok(typeof s.paceZone === "string" && s.paceZone.length > 0);
    assert.ok(typeof s.notes === "string");
  }
});

// ── Alternations ─────────────────────────────────────────
//
// Six real forms from this coach's corpus, none of which parsed before. The
// failure was the dangerous kind: a complete-looking step list at EASY, with
// nothing in `unparsed` or `warnings` to say the paces had been dropped.

test("alternation: rep count x bare unit (16 x K alternating MP-3% & MP+5%)", () => {
  const { steps, unparsed, warnings, unresolved } = parseWorkoutText(
    "16 x K alternating MP-3% & MP+5%",
  );
  assert.equal(unparsed.length, 0);
  assert.equal(warnings.length, 0);
  assert.equal(Object.keys(unresolved).length, 0, "every leg must carry the pace the coach wrote");
  assert.equal(steps.length, 16);
  for (const s of steps) {
    assert.equal(s.durationType, "distance_km");
    assert.equal(s.durationValue, 1);
    assert.equal(s.paceZone, "mp");
  }
  // Fast legs on the odds, float on the evens — the order as written.
  assert.deepEqual(steps[0].paceAdjustment, { type: "percent", value: -3 });
  assert.deepEqual(steps[1].paceAdjustment, { type: "percent", value: 5 });
  assert.deepEqual(steps[15].paceAdjustment, { type: "percent", value: 5 });
});

test("alternation: the word can be left out (16 x K @ MP-3% & MP+5%)", () => {
  const { steps, unresolved } = parseWorkoutText("16 x K @ MP-3% & MP+5%");
  assert.equal(steps.length, 16);
  assert.equal(Object.keys(unresolved).length, 0);
  assert.deepEqual(steps[0].paceAdjustment, { type: "percent", value: -3 });
  assert.deepEqual(steps[1].paceAdjustment, { type: "percent", value: 5 });
});

test("alternation: leading number is TOTAL distance, legs are 1 mile", () => {
  // "8-12m" collapses to its midpoint, 10 — so ten 1-mile legs, not ten pairs.
  const { steps } = parseWorkoutText("8-12m alternations (MP-10/MP+30)");
  assert.equal(steps.length, 10);
  assert.equal(steps[0].durationType, "distance_miles");
  assert.equal(steps[0].durationValue, 1);
  assert.deepEqual(steps[0].paceAdjustment, { type: "seconds_per_mile", value: -10 });
  assert.deepEqual(steps[1].paceAdjustment, { type: "seconds_per_mile", value: 30 });
});

test("alternation: an odd total keeps its odd leg (7mi = 4 fast, 3 float)", () => {
  // 7 miles of 1-mile alternation is seven legs. Rounding to eight would add a
  // mile the coach never wrote; rounding to six would drop one.
  const { steps } = parseWorkoutText("7mi alternations ( 1m at MP-10/1mi at MP +20)");
  assert.equal(steps.length, 7);
  const fast = steps.filter((s) => s.paceAdjustment?.value === -10);
  const float = steps.filter((s) => s.paceAdjustment?.value === 20);
  assert.equal(fast.length, 4);
  assert.equal(float.length, 3);
});

test("alternation: parenthesised legs run the whole distance, not one pair", () => {
  // Regression: this parsed as a 2-mile session — the two legs, once — and
  // reported no warning while doing it.
  const { steps } = parseWorkoutText("10 mi Alternations- (1 mi at MP-10/ 1 mi at MP+30)");
  assert.equal(steps.length, 10);
});

test("alternation with no paces stays a question, not a guess", () => {
  const { steps, unresolved } = parseWorkoutText("6 miles of alternations");
  assert.equal(steps.length, 1);
  assert.equal(Object.values(unresolved)[0], "no_pace_written");
});

// A slash after a pace usually introduces a RECOVERY. None of these may be
// read as a second work pace.
test("alternation guard: a jog/float recovery is never eaten as a leg", () => {
  for (const input of [
    "6x800 @ 5k / 400 jog",
    "3x1600 @ 10K pace / 400 jog",
    "6 x mile @ HM pace /400m float",
  ]) {
    const { steps } = parseWorkoutText(input);
    assert.equal(steps.length, 1, `${input} must stay one repeated step`);
    assert.ok(steps[0].recovery, `${input} must keep its recovery`);
  }
});

test("offset pace written without an @ (16 x 1k MP-3%)", () => {
  const { steps, unresolved } = parseWorkoutText("16 x 1k MP-3%");
  assert.equal(steps.length, 1);
  assert.equal(steps[0].repeats, 16);
  assert.equal(steps[0].paceZone, "mp");
  assert.deepEqual(steps[0].paceAdjustment, { type: "percent", value: -3 });
  assert.equal(Object.keys(unresolved).length, 0);
});
