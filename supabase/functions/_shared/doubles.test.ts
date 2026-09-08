/**
 * Tests for _shared/doubles.ts (Phase 2, coach-assigned doubles).
 *
 * Run: deno test _shared/doubles.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  adaptiveDoublesCount,
  type DoublesConfig,
  type EasyDayInput,
  parseDoublesConfig,
  planDoubles,
  resolveDoublesConfig,
} from "./doubles.ts";

const MIN = 2; // mirrors MIN_EASY_MILES in subscribe-to-plan

function cfg(over: Partial<DoublesConfig> = {}): DoublesConfig {
  return {
    mode: "assigned",
    perWeek: 2,
    rangeMiles: { min: 3, max: 5 },
    distribution: "split",
    eligibleDows: null,
    placement: "easy_only",
    ...over,
  };
}

// A canonical Tue-quality / Sat-long week. Easy days: Mon Wed Thu Fri Sun.
// Mon is pre-quality (Tue), Fri is pre-long (Sat), Sun is post-long recovery.
// Only Wed + Thu should ever be doubled.
const WEEK = {
  easyDays: [
    { dow: 0, amMiles: 6, isRecovery: false }, // Mon — pre-quality
    { dow: 2, amMiles: 9, isRecovery: false }, // Wed
    { dow: 3, amMiles: 9, isRecovery: false }, // Thu
    { dow: 4, amMiles: 6, isRecovery: false }, // Fri — pre-long
    { dow: 6, amMiles: 5, isRecovery: true }, // Sun — recovery
  ] as EasyDayInput[],
  qualityDows: [1],
  longRunDow: 5,
  restDows: [],
};

// ── adaptiveDoublesCount ────────────────────────────────────────────
Deno.test("adaptiveDoublesCount: volume thresholds", () => {
  assertEquals(adaptiveDoublesCount(40), 0);
  assertEquals(adaptiveDoublesCount(54), 0);
  assertEquals(adaptiveDoublesCount(55), 2);
  assertEquals(adaptiveDoublesCount(65), 2);
  assertEquals(adaptiveDoublesCount(70), 3);
  assertEquals(adaptiveDoublesCount(84), 3);
  assertEquals(adaptiveDoublesCount(85), 4);
  assertEquals(adaptiveDoublesCount(100), 4);
});

// ── parseDoublesConfig ──────────────────────────────────────────────
Deno.test("parseDoublesConfig: maps snake_case, drops junk", () => {
  assertEquals(parseDoublesConfig(null), null);
  assertEquals(parseDoublesConfig("nope"), null);
  assertEquals(parseDoublesConfig({}), null); // nothing actionable
  assertEquals(parseDoublesConfig({ foo: 1 }), null);

  const p = parseDoublesConfig({
    mode: "assigned",
    per_week: 2,
    range_miles: { min: 3, max: 5 },
    distribution: "split",
    eligible_dows: [2, 3, 9], // 9 is invalid, dropped
  });
  assertEquals(p, {
    mode: "assigned",
    perWeek: 2,
    rangeMiles: { min: 3, max: 5 },
    distribution: "split",
    eligibleDows: [2, 3],
    placement: "easy_only",
  });
});

// ── resolveDoublesConfig ────────────────────────────────────────────
Deno.test("resolve: coach mode off disables even if athlete opts in", () => {
  const r = resolveDoublesConfig({ mode: "off" }, { mode: "adaptive" }, 80);
  assertEquals(r.mode, "off");
  assertEquals(r.perWeek, 0);
});

Deno.test("resolve: coach assigned count wins", () => {
  const r = resolveDoublesConfig({ mode: "assigned", perWeek: 2 }, null, 65);
  assertEquals(r.mode, "assigned");
  assertEquals(r.perWeek, 2);
});

Deno.test("resolve: coach adaptive derives count from weekly mileage", () => {
  assertEquals(resolveDoublesConfig({ mode: "adaptive" }, null, 65).perWeek, 2);
  assertEquals(resolveDoublesConfig({ mode: "adaptive" }, null, 88).perWeek, 4);
});

Deno.test("resolve: no coach opinion, athlete adaptive is the fallback", () => {
  const r = resolveDoublesConfig(null, { mode: "adaptive" }, 72);
  assertEquals(r.mode, "adaptive");
  assertEquals(r.perWeek, 3);
});

Deno.test("resolve: athlete can dial a coach count down but never up", () => {
  // down
  assertEquals(
    resolveDoublesConfig({ mode: "assigned", perWeek: 3 }, { mode: "assigned", perWeek: 1 }, 65).perWeek,
    1,
  );
  // attempt to raise is ignored
  assertEquals(
    resolveDoublesConfig({ mode: "assigned", perWeek: 1 }, { mode: "assigned", perWeek: 3 }, 65).perWeek,
    1,
  );
  // athlete can switch off
  assertEquals(
    resolveDoublesConfig({ mode: "assigned", perWeek: 3 }, { mode: "off" }, 65).mode,
    "off",
  );
});

Deno.test("resolve: nothing configured is off", () => {
  assertEquals(resolveDoublesConfig(null, null, 90).mode, "off");
});

// ── planDoubles ─────────────────────────────────────────────────────
Deno.test("plan: off mode yields no doubles", () => {
  assertEquals(planDoubles(WEEK, cfg({ mode: "off" }), MIN), []);
});

Deno.test("plan: assigned split picks the two open aerobic days", () => {
  const d = planDoubles(WEEK, cfg({ perWeek: 2 }), MIN);
  // Wed(2) + Thu(3) only; pmMiles = midpoint 4, AM (9) leaves >= floor.
  assertEquals(d, [{ dow: 2, pmMiles: 4 }, { dow: 3, pmMiles: 4 }]);
});

Deno.test("plan: guardrails cap doubles below requested count", () => {
  // Ask for 5, but Mon(pre-quality), Fri(pre-long), Sun(recovery) are all out.
  const d = planDoubles(WEEK, cfg({ perWeek: 5 }), MIN);
  assertEquals(d.map((x) => x.dow), [2, 3]);
});

Deno.test("plan: eligible_dows restricts placement", () => {
  const d = planDoubles(WEEK, cfg({ perWeek: 2, eligibleDows: [2] }), MIN);
  assertEquals(d, [{ dow: 2, pmMiles: 4 }]);
});

Deno.test("plan: split skips days too small for two real runs", () => {
  const week = {
    ...WEEK,
    easyDays: [
      { dow: 2, amMiles: 3, isRecovery: false }, // 3 < 2*MIN(4) → excluded for split
      { dow: 3, amMiles: 9, isRecovery: false },
    ] as EasyDayInput[],
  };
  const d = planDoubles(week, cfg({ perWeek: 2 }), MIN);
  assertEquals(d, [{ dow: 3, pmMiles: 4 }]);
});

Deno.test("plan: split leaves the easy floor on the AM run", () => {
  const week = {
    ...WEEK,
    easyDays: [{ dow: 3, amMiles: 5, isRecovery: false }] as EasyDayInput[],
  };
  // desired 4, but 5 - MIN(2) = 3 → pmMiles clamps to 3, AM keeps 2.
  const d = planDoubles(week, cfg({ perWeek: 1 }), MIN);
  assertEquals(d, [{ dow: 3, pmMiles: 3 }]);
});

Deno.test("plan: add mode allows a short AM day and does not reduce it", () => {
  const week = {
    ...WEEK,
    easyDays: [
      { dow: 2, amMiles: 3, isRecovery: false },
      { dow: 3, amMiles: 9, isRecovery: false },
    ] as EasyDayInput[],
  };
  const d = planDoubles(week, cfg({ perWeek: 2, distribution: "add" }), MIN);
  // Both qualify (AM >= MIN); pmMiles = midpoint 4 with no split reduction.
  assertEquals(d, [{ dow: 2, pmMiles: 4 }, { dow: 3, pmMiles: 4 }]);
});
