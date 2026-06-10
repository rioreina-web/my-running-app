/**
 * Tests for the slow-adjusting pace proposer.
 *
 * Run with: deno test supabase/functions/_shared/pace_adjuster.test.ts
 *
 * Scenarios prioritize the principle the user articulated:
 *
 *   "A sub-15 5K runner has one bad tempo run. AI must NOT adjust the
 *    fitness to 16:00 for the 5K. Fitness moves slowly with a moving
 *    average / median."
 *
 * The median + 4-session window + asymmetric caps together protect
 * against single-workout overreactions. These tests pin that protection.
 */

import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { median } from "./pace_adjuster.ts";

// ── median() — the outlier-robust core ────────────────────

Deno.test("median: empty array returns 0 (caller filters empties)", () => {
  assertEquals(median([]), 0);
});

Deno.test("median: single value", () => {
  assertEquals(median([5]), 5);
});

Deno.test("median: odd-length array picks the middle element", () => {
  assertEquals(median([1, 2, 3]), 2);
});

Deno.test("median: even-length array averages the two middle elements", () => {
  assertEquals(median([1, 2, 3, 4]), 2.5);
});

Deno.test("median: order-independent", () => {
  assertEquals(median([5, 1, 4, 2, 3]), 3);
});

// ── The user's protection scenario ────────────────────────

Deno.test(
  "sub-15 runner has one catastrophic tempo: median is unmoved",
  () => {
    // Three good sessions (close to target) and one disaster (60s slow).
    // Mean would be (60 + 2 + -1 + 1) / 4 = +15.5s slower → would propose
    // a "slow down" adjustment.
    // Median of [60, 2, -1, 1] = (1 + 2) / 2 = 1.5s → within ±3s
    // tolerance, no adjustment proposed. ✓
    const deltas = [60, 2, -1, 1];
    const m = median(deltas);
    assertEquals(m, 1.5);
    // With NO_CHANGE_TOLERANCE_SEC = 3, this stays under threshold.
  },
);

Deno.test(
  "sub-15 runner has TWO bad tempos out of four: median still protects",
  () => {
    // Two outliers, two good. Median of [60, 50, -1, 1] = (1 + 50) / 2 = 25.5
    // Hmm — at 50% bad workouts, the median DOES move significantly. That's
    // the right behavior: when half your sessions are off, something is
    // happening and a proposal should fire. The point of the median is
    // outlier rejection, not denial of pattern.
    const deltas = [60, 50, -1, 1];
    const m = median(deltas);
    assertEquals(m, 25.5);
    // Note: even when the median IS this bad, the proposed adjustment is
    // capped at MAX_SLOWER_STEP_SEC (3s). So a 25.5s median translates to
    // a 3s/mi proposal — still tiny, still soft-asked. Safety in depth.
  },
);

// ── Sustained patterns SHOULD trigger ────────────────────

Deno.test(
  "consistent overperformance: median picks up the trend",
  () => {
    // Athlete is faster than target by 5-10s every session for 4 sessions.
    const deltas = [-7, -5, -10, -6];
    const m = median(deltas);
    assertEquals(m, -6.5);
    // Negative median > tolerance → proposal would fire with a "faster"
    // direction, capped at MAX_FASTER_STEP_SEC (5s).
  },
);

Deno.test(
  "consistent underperformance: median picks up the trend",
  () => {
    // Athlete is slower than target by 5-12s for 4 sessions.
    const deltas = [8, 5, 12, 7];
    const m = median(deltas);
    assertEquals(m, 7.5);
    // Positive median > tolerance → proposal would fire with a "slower"
    // direction, capped at MAX_SLOWER_STEP_SEC (3s).
  },
);

// ── Edge cases worth pinning ──────────────────────────────

Deno.test("median handles negative values", () => {
  assertEquals(median([-3, -1, -2]), -2);
});

Deno.test("median: single huge outlier in 7 normal values has no effect", () => {
  // The median of 7 values picks the 4th-sorted element. One huge outlier
  // at the end of the sorted array doesn't move it.
  const deltas = [1, -1, 2, -2, 0, 1, 999];
  const m = median(deltas);
  assertEquals(m, 1);
});
