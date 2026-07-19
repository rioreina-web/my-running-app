import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildReadiness, type ReadinessInput } from "./buildReadiness.ts";
import type { LifeContext } from "./buildLifeContext.ts";

// Minimal LifeContext with everything "quiet"; override the fields under test.
function lc(over: Partial<LifeContext> = {}): LifeContext {
  return {
    sleep: { poor_mentions_7d: 0, mentions_28d: 0, last: null },
    fatigue: [],
    effort: [],
    hard_7d: 0,
    stress: { work_high_7d: 0, life_high_7d: 0, any_high_28d: 0, last_mention: null },
    illness: { active: false, detail: null, date: null },
    travel: { recent: false, detail: null, date: null },
    motivation: { low_7d: 0, last: null },
    felt_vs_looked: [],
    avg_rpe_7d: null,
    summary: null,
    ...over,
  };
}

function input(over: Partial<ReadinessInput> = {}): ReadinessInput {
  return { lifeContext: null, acwr: null, monotony7d: null, moodTrend: null, lastMood: null, ...over };
}

Deno.test("no signal at all → null (no fabricated opinion)", () => {
  assertEquals(buildReadiness(input()), null);
  assertEquals(buildReadiness(input({ lifeContext: lc() })), null); // all-quiet life context
});

Deno.test("stacked recovery drags → pull", () => {
  const r = buildReadiness(input({
    lifeContext: lc({
      sleep: { poor_mentions_7d: 2, mentions_28d: 4, last: { date: "2026-07-02", quality: "poor", hours: 5 } },
      felt_vs_looked: [{ date: "2026-07-02", value: "harder than it looks" }, { date: "2026-07-01", value: "harder than it looks" }],
      fatigue: [{ date: "2026-07-02", label: "wiped" }],
    }),
    lastMood: "tired",
  }));
  assert(r !== null);
  assertEquals(r!.verdict, "pull");
  assertEquals(r!.confidence, "high"); // ≥3 independent signals
  assert(r!.score <= -3, `score ${r!.score}`);
  assert(r!.drivers.length > 0);
  assert(!/rest|stop|take a day|ice|treat/i.test(r!.read), "read must not prescribe rest/treatment");
});

Deno.test("load spike alone contributes toward pull", () => {
  const r = buildReadiness(input({ acwr: 1.7, monotony7d: 2.4, lastMood: "tired" }));
  assert(r !== null);
  // ACWR>1.5 (-2) + monotony>2 (-1) + tired (-1) = -4 → pull
  assertEquals(r!.verdict, "pull");
  assert(r!.drivers.some((d) => d.includes("ACWR")));
});

Deno.test("all green → push", () => {
  const r = buildReadiness(input({
    lifeContext: lc({ felt_vs_looked: [{ date: "2026-07-02", value: "easier than it looks" }] }),
    acwr: 1.0,
    lastMood: "energized",
    moodTrend: "improving",
  }));
  assert(r !== null);
  // easier(+1) + acwr healthy(+1) + energized(+1) + improving(+1) = +4 → push
  assertEquals(r!.verdict, "push");
  // On push, drivers reflect the positives.
  assert(r!.drivers.length > 0);
  assert(r!.read.length > 0);
});

Deno.test("mixed signal → hold", () => {
  const r = buildReadiness(input({
    lifeContext: lc({ sleep: { poor_mentions_7d: 1, mentions_28d: 2, last: null } }), // -1
    acwr: 1.0, // +1
  }));
  assert(r !== null);
  assertEquals(r!.verdict, "hold"); // net 0
});

Deno.test("confidence scales with number of independent signals", () => {
  const one = buildReadiness(input({ lastMood: "tired" }))!; // 1 signal
  assertEquals(one.confidence, "low");
  const two = buildReadiness(input({ lastMood: "tired", acwr: 1.4 }))!; // 2 signals
  assertEquals(two.confidence, "medium");
});

Deno.test("conservative bias: it takes more to say push than to say pull", () => {
  // A single strong positive should NOT reach push on its own (needs ≥+2).
  const r = buildReadiness(input({ lastMood: "positive" }))!;
  assertEquals(r.verdict, "hold");
});
