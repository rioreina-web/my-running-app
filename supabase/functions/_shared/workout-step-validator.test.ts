/**
 * Tests for the parser-agnostic step validator.
 *
 * This is the last thing standing between a parser and a coach's plan, and the
 * only layer that is fully deterministic once a model is in the pipeline. Each
 * case below is a real defect the August 2026 corpus audit surfaced — the
 * numbers are the actual numbers those bugs produced.
 *
 * Run: deno test supabase/functions/_shared/workout-step-validator.test.ts
 */

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { validateSteps } from "./workout-step-validator.ts";

const ok = {
  stepType: "active",
  durationType: "distance_meters",
  durationValue: 800,
  paceZone: "fiveK",
};

Deno.test("passes a well-formed step through unchanged", () => {
  const r = validateSteps([ok], { source: "test" });
  assertEquals(r.steps.length, 1);
  assertEquals(r.steps[0].paceZone, "fiveK");
  assertEquals(r.steps[0].durationValue, 800);
  assertEquals(r.warnings.length, 0);
});

Deno.test("a null pace is legal and produces a warning, never a guess", () => {
  const r = validateSteps([{ ...ok, paceZone: null }], { source: "test" });
  assertEquals(r.steps.length, 1, "the step still gets built");
  assertEquals(r.steps[0].paceZone, null, "never defaulted to a zone");
  assert(r.steps[0].unresolved, "carries a reason");
  assertEquals(r.warnings.length, 1, "and the coach is told");
});

Deno.test("a pace zone outside the enum is refused, not coerced", () => {
  const r = validateSteps([{ ...ok, paceZone: "sprint" }], { source: "test" });
  assertEquals(r.steps[0].paceZone, null);
  assert(r.warnings.some((w) => w.includes("sprint")), "names the bad value back");
});

Deno.test("rejects an impossible pace (the 2:30/mi rest-read-as-pace bug)", () => {
  const r = validateSteps([{ ...ok, exactPaceSecPerMile: 150 }], { source: "test" });
  assertEquals(r.steps[0].exactPaceSecPerMile, undefined, "stripped");
  assert(r.warnings.some((w) => w.includes("impossible")));
});

Deno.test("rejects an absurd distance (the 155km descending-range bug)", () => {
  const r = validateSteps(
    [{ ...ok, durationType: "distance_km", durationValue: 155 }],
    { source: "test" },
  );
  assertEquals(r.steps.length, 0, "dropped entirely");
  assert(r.warnings.some((w) => w.includes("misread")));
});

Deno.test("drops a step with no usable duration rather than inventing one", () => {
  const r = validateSteps([{ stepType: "active", paceZone: "mp" }], { source: "test" });
  assertEquals(r.steps.length, 0);
  assert(r.warnings.some((w) => w.includes("duration")));
});

Deno.test("caps runaway repeats and says so", () => {
  const r = validateSteps([{ ...ok, repeats: 5000 }], { source: "test" });
  assertEquals(r.steps[0].repeats, 60);
  assert(r.warnings.some((w) => w.includes("capped")));
});

Deno.test("keeps a plausible pace offset, rejects an implausible one", () => {
  const good = validateSteps(
    [{ ...ok, paceAdjustmentType: "seconds_per_mile", paceAdjustmentValue: -10 }],
    { source: "test" },
  );
  assertEquals(good.steps[0].paceAdjustment?.value, -10);

  const bad = validateSteps(
    [{ ...ok, paceAdjustmentType: "seconds_per_mile", paceAdjustmentValue: 9999 }],
    { source: "test" },
  );
  assertEquals(bad.steps[0].paceAdjustment, undefined);
  assert(bad.warnings.some((w) => w.includes("out-of-range")));
});

Deno.test("carries a recovery through, jog vs standing", () => {
  const r = validateSteps(
    [{ ...ok, recoveryDurationType: "time_seconds", recoveryDurationValue: 60, recoveryIsJog: false }],
    { source: "test" },
  );
  assertEquals(r.steps[0].recovery?.durationValue, 60);
  assertEquals(r.steps[0].recovery?.isJog, false);
});

Deno.test("a rest step needs no pace and raises no warning", () => {
  const r = validateSteps(
    [{ stepType: "rest", durationType: "time_seconds", durationValue: 120, paceZone: null }],
    { source: "test" },
  );
  assertEquals(r.steps.length, 1);
  assertEquals(r.warnings.length, 0);
});

Deno.test("never throws on garbage input", () => {
  for (const junk of [null, undefined, 42, "steps", {}, [null], [{}], [[]]]) {
    const r = validateSteps(junk as unknown, { source: "test" });
    assert(Array.isArray(r.steps), `survived ${JSON.stringify(junk)}`);
    assert(Array.isArray(r.warnings));
  }
});

Deno.test("reports when a parser produced nothing at all", () => {
  const r = validateSteps([], { source: "model" });
  assertEquals(r.steps.length, 0);
  assert(r.warnings.some((w) => w.includes("could not build")));
});
