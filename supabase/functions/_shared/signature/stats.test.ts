/**
 * Unit tests for the signature statistics core.
 *
 * Run: deno test --allow-none _shared/signature/stats.test.ts
 */

import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { continuousEffect, mean, rate, rateEffect, splitHalf, stdev } from "./stats.ts";

Deno.test("mean / stdev / rate basics", () => {
  assertAlmostEquals(mean([1, 2, 3, 4]), 2.5);
  // population SD of [2,4,4,4,5,5,7,9] is 2
  assertAlmostEquals(stdev([2, 4, 4, 4, 5, 5, 7, 9]), 2, 1e-9);
  assertAlmostEquals(rate([true, false, true, true]), 0.75);
});

Deno.test("continuousEffect is signed and in personal-SD units", () => {
  const exposed = [6, 6, 6, 6];
  const baseline = [4, 4, 4, 4];
  const all = [...exposed, ...baseline];
  const e = continuousEffect(exposed, baseline, all);
  // personalSd of four 6s and four 4s = 1.0, diff = +2 → effect +2.0
  assertAlmostEquals(e.personalSd, 1, 1e-9);
  assertAlmostEquals(e.effect, 2, 1e-9);
});

Deno.test("rateEffect is the difference in event rates", () => {
  const e = rateEffect([true, true, true, false], [false, false, false, false]);
  assertAlmostEquals(e.effect, 0.75);
});

Deno.test("splitHalf flags a consistent effect and rejects a one-sided fluke", () => {
  // Consistent: exposed always ~+2 above baseline, across both halves.
  const consistent = [
    ...[0, 1, 2, 3].map((i) => ({ x: 6, exposed: true, order: `2025-01-0${i + 1}` })),
    ...[0, 1, 2, 3].map((i) => ({ x: 4, exposed: false, order: `2025-01-1${i + 1}` })),
    ...[0, 1, 2, 3].map((i) => ({ x: 6, exposed: true, order: `2025-06-0${i + 1}` })),
    ...[0, 1, 2, 3].map((i) => ({ x: 4, exposed: false, order: `2025-06-1${i + 1}` })),
  ];
  const good = splitHalf(consistent, "continuous", 3, 0.3, 1);
  assert(good.consistent, "genuine effect should hold in both halves");

  // Fluke: the whole gap lives in the first half; second half is flat.
  const fluke = [
    ...[1, 2, 3, 4].map((i) => ({ x: 8, exposed: true, order: `2025-01-0${i}` })),
    ...[1, 2, 3, 4].map((i) => ({ x: 4, exposed: false, order: `2025-02-0${i}` })),
    ...[1, 2, 3, 4].map((i) => ({ x: 5, exposed: true, order: `2025-08-0${i}` })),
    ...[1, 2, 3, 4].map((i) => ({ x: 5, exposed: false, order: `2025-09-0${i}` })),
  ];
  const bad = splitHalf(fluke, "continuous", 3, 0.3, 1);
  assertEquals(bad.consistent, false, "a one-sided fluke must fail split-half");
});
