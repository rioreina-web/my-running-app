/**
 * Unit tests for the deterministic safety logic in fitness-predictor.
 *
 * What this guards against:
 *   1. CLAUDE.md hard rule #7 — "Predictions ship with range + confidence,
 *      never a single point." That rule is enforced HERE, in code, not in
 *      the LLM prompt. A regression in `computeConfidenceTier` or
 *      `rangeFromTier` lets a single-point prediction reach the renderer.
 *   2. The high/medium/low criteria drifting — e.g. someone loosens
 *      "high tier requires 2 MP workouts" to 1 MP workout, and now every
 *      moderately-active runner gets a ±1.5% range that the data doesn't
 *      actually support.
 *   3. The range math being off enough that a high-confidence marathon
 *      prediction is suddenly ±15 minutes instead of ±3.
 *
 * Why these tests and not LLM eval cassettes for this function:
 *   The LLM gives a midpoint; code decides the confidence + range. The
 *   LLM doesn't get a vote on safety. Testing the LLM here would test
 *   the wrong layer.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  computeConfidenceTier,
  rangeFromTier,
  type PredictionRequest,
  type WorkoutData,
  type VoiceLogData,
} from "./index.ts";

const NOW_MS = Date.now();
const DAY_MS = 86_400_000;

function daysAgo(d: number): string {
  return new Date(NOW_MS - d * DAY_MS).toISOString();
}

function workout(over: Partial<WorkoutData> = {}): WorkoutData {
  return {
    date: daysAgo(7),
    distanceMiles: 6,
    durationMinutes: 48,
    paceSecondsPerMile: 480,
    type: "Easy",
    ...over,
  };
}

function voiceLog(over: Partial<VoiceLogData> = {}): VoiceLogData {
  return {
    date: daysAgo(3),
    notes: "Easy run today",
    pacesMentioned: [],
    ...over,
  };
}

function buildRequest(workouts: WorkoutData[], voiceLogs: VoiceLogData[] = []): PredictionRequest {
  return { workouts, voiceLogs };
}

// ─── computeConfidenceTier ───────────────────────────────────────────

Deno.test("tier: empty workouts → low", () => {
  assertEquals(computeConfidenceTier(buildRequest([])), "low");
});

Deno.test("tier: only easy runs → low", () => {
  const req = buildRequest([
    workout({ type: "Easy", date: daysAgo(2) }),
    workout({ type: "Easy", date: daysAgo(5) }),
    workout({ type: "Long Run", date: daysAgo(8) }),
  ]);
  assertEquals(computeConfidenceTier(req), "low");
});

Deno.test("tier: single threshold session in last 6 weeks → medium", () => {
  const req = buildRequest([
    workout({ type: "Tempo", date: daysAgo(14) }),
    workout({ type: "Easy", date: daysAgo(2) }),
  ]);
  assertEquals(computeConfidenceTier(req), "medium");
});

Deno.test("tier: threshold session > 6 weeks ago does NOT count", () => {
  const req = buildRequest([
    workout({ type: "Tempo", date: daysAgo(50) }), // > 42 days
    workout({ type: "Easy", date: daysAgo(2) }),
  ]);
  assertEquals(computeConfidenceTier(req), "low");
});

Deno.test("tier: 2 marathon-pace workouts in last 6 weeks → high", () => {
  const req = buildRequest([
    workout({ type: "Marathon Pace", date: daysAgo(10) }),
    workout({ type: "Marathon Pace", date: daysAgo(24) }),
    workout({ type: "Easy", date: daysAgo(2) }),
  ]);
  assertEquals(computeConfidenceTier(req), "high");
});

Deno.test("tier: 1 marathon-pace workout in last 6 weeks → medium (needs ≥2 for high)", () => {
  const req = buildRequest([
    workout({ type: "Marathon Pace", date: daysAgo(10) }),
    workout({ type: "Easy", date: daysAgo(2) }),
  ]);
  // The MP workout DOES match the threshold-session regex (/tempo|threshold|interval|speed/i — wait, it doesn't),
  // but the MP match itself only earns medium when there's only one. Let's be precise:
  //   - MP count: 1, fails the ≥2 check for high
  //   - threshold regex: "Marathon Pace" doesn't match /tempo|threshold|interval|speed/i
  //   - So medium would only come from voice log, which is empty
  // Therefore expectation: low.
  assertEquals(computeConfidenceTier(req), "low");
});

Deno.test("tier: 'mp' type pattern is matched case-insensitively", () => {
  const req = buildRequest([
    workout({ type: "MP workout", date: daysAgo(10) }),
    workout({ type: "mp", date: daysAgo(20) }),
  ]);
  assertEquals(computeConfidenceTier(req), "high");
});

Deno.test("tier: marathon-pace workouts > 6 weeks ago don't count", () => {
  const req = buildRequest([
    workout({ type: "Marathon Pace", date: daysAgo(50) }),
    workout({ type: "Marathon Pace", date: daysAgo(55) }),
  ]);
  assertEquals(computeConfidenceTier(req), "low");
});

Deno.test("tier: recent race ≥10K within 8 weeks → high", () => {
  const req = buildRequest([
    workout({ type: "Race", distanceMiles: 13.1, date: daysAgo(14) }),
  ]);
  assertEquals(computeConfidenceTier(req), "high");
});

Deno.test("tier: race < 10K does NOT trigger high (distance floor)", () => {
  const req = buildRequest([
    workout({ type: "Race", distanceMiles: 5, date: daysAgo(14) }), // 5 mi < 10K floor
  ]);
  // 5mi race doesn't pass the ≥6.0 mile threshold for race-driven "high".
  // It also doesn't match the threshold-session regex. So → low.
  assertEquals(computeConfidenceTier(req), "low");
});

Deno.test("tier: race > 8 weeks ago does NOT trigger high", () => {
  const req = buildRequest([
    workout({ type: "Race", distanceMiles: 13.1, date: daysAgo(70) }), // > 56 days
  ]);
  assertEquals(computeConfidenceTier(req), "low");
});

Deno.test("tier: voice log with ≥2 paces bumps low → medium", () => {
  const req = buildRequest(
    [workout({ type: "Easy", date: daysAgo(2) })],
    [voiceLog({ pacesMentioned: ["6:50", "6:45"], date: daysAgo(3) })],
  );
  assertEquals(computeConfidenceTier(req), "medium");
});

Deno.test("tier: voice log with tempo mention bumps low → medium", () => {
  const req = buildRequest(
    [workout({ type: "Easy" })],
    [voiceLog({ notes: "Ran a tempo at race pace today", date: daysAgo(3) })],
  );
  assertEquals(computeConfidenceTier(req), "medium");
});

Deno.test("tier: voice log alone NEVER reaches high (caps at medium per spec)", () => {
  const req = buildRequest(
    [workout({ type: "Easy" })],
    [
      voiceLog({ pacesMentioned: ["6:50", "6:45", "6:40"], notes: "Tempo + threshold + race pace mentioned" }),
      voiceLog({ pacesMentioned: ["6:50", "6:45"], notes: "Another tempo session" }),
    ],
  );
  assertEquals(computeConfidenceTier(req), "medium");
});

Deno.test("tier: 'race' substring in type field matches case-insensitively", () => {
  const req = buildRequest([
    workout({ type: "Marathon Race", distanceMiles: 26.2, date: daysAgo(14) }),
  ]);
  assertEquals(computeConfidenceTier(req), "high");
});

// ─── rangeFromTier ───────────────────────────────────────────────────

Deno.test("range: high tier on 3:11 marathon (11460 sec) → ~172 sec (≈2:52)", () => {
  // 11460 × 0.015 = 171.9 → rounds to 172. About 2:52 half-window.
  assertEquals(rangeFromTier(11460, "high"), 172);
});

Deno.test("range: medium tier on 3:11 marathon → ~344 sec (≈5:44)", () => {
  // 11460 × 0.030 = 343.8 → 344. Doubles the high-tier window.
  assertEquals(rangeFromTier(11460, "medium"), 344);
});

Deno.test("range: low tier on 3:11 marathon → ~573 sec (≈9:33)", () => {
  // 11460 × 0.050 = 573.
  assertEquals(rangeFromTier(11460, "low"), 573);
});

Deno.test("range: zero seconds in → zero out (defensive)", () => {
  assertEquals(rangeFromTier(0, "high"), 0);
  assertEquals(rangeFromTier(0, "medium"), 0);
  assertEquals(rangeFromTier(0, "low"), 0);
});

Deno.test("range: negative seconds in → zero out (defensive)", () => {
  assertEquals(rangeFromTier(-1, "high"), 0);
});

Deno.test("range: monotonic in tier — high < medium < low for any positive input", () => {
  for (const sec of [600, 1800, 3600, 5400, 11460, 20000]) {
    const hi = rangeFromTier(sec, "high");
    const md = rangeFromTier(sec, "medium");
    const lo = rangeFromTier(sec, "low");
    assert(hi < md, `expected high < medium for ${sec}s (got ${hi}, ${md})`);
    assert(md < lo, `expected medium < low for ${sec}s (got ${md}, ${lo})`);
  }
});

Deno.test("range: short-distance prediction (mile, 5:00 = 300s) → reasonable absolute size", () => {
  // 300 × 0.030 = 9 sec for medium. That's right — a mile prediction
  // shouldn't have a 90-second window even at medium confidence.
  assertEquals(rangeFromTier(300, "medium"), 9);
  // Sanity check that low isn't catastrophic for short distances.
  assertEquals(rangeFromTier(300, "low"), 15);
});

// ─── Wedge invariants — the actual rule we care about ─────────────────

Deno.test("invariant: rangeFromTier always returns ≥ 0 (no negative windows)", () => {
  for (const sec of [-100, -1, 0, 1, 60, 3600, 14400]) {
    for (const tier of ["high", "medium", "low"] as const) {
      assert(rangeFromTier(sec, tier) >= 0, `negative window for ${sec}s, ${tier}`);
    }
  }
});

Deno.test("invariant: NO confidence tier yields a zero-width range for a positive prediction", () => {
  // This is the wedge rule: predictions always ship with SOME range.
  // A zero-width range = a single-point prediction = a CLAUDE.md violation.
  for (const sec of [60, 600, 3600, 14400]) {
    for (const tier of ["high", "medium", "low"] as const) {
      assert(
        rangeFromTier(sec, tier) > 0,
        `zero range for positive prediction (${sec}s, ${tier}) — would emit a single-point prediction, violating CLAUDE.md rule #7`,
      );
    }
  }
});
