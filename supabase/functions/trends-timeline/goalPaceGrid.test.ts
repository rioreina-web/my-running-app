/**
 * Tests for the block-level goal-pace grid.
 *
 * `boundary values land in the correct row` exists SPECIFICALLY because the
 * HTML prototype this module replaces had a backwards threshold search: it
 * iterated ascending-value thresholds and returned on first match, so any
 * value from 75% up to 115% collapsed into the single 75% row. Every "two hot
 * rows" reading taken from that prototype was describing a chart where nearly
 * the whole dataset had been miscategorized into one bucket. This test checks
 * every band boundary explicitly rather than a few representative examples,
 * because "a few examples happened to look right" is exactly what let the
 * original bug ship unnoticed through two rounds of screenshot review.
 *
 * Run: deno test trends-timeline/goalPaceGrid.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildGoalPaceGrid,
  PACE_ROW_LABELS,
  paceRowOf,
  type GoalPaceGridLog,
} from "./goalPaceGrid.ts";

const GOAL = {
  race_key: "marathon",
  time_seconds: 8400,
  pace_sec_per_mile: 8400 / 26.2188, // ≈320.4 → 5:20/mi
  source: "active_goal",
  race_date: "2026-12-06",
};

Deno.test("boundary values land in the correct row, not the first-scanned one", () => {
  // [input pct, expected row index]. Row 0 = "115%+" ... row 9 = "<75%".
  const cases: Array<[number, number]> = [
    [130, 0], [115, 0],       // 115%+
    [114.9, 1], [110, 1],     // 110–115
    [109.9, 2], [105, 2],     // 105–110
    [104.9, 3], [100, 3],     // 100–105  (exactly goal pace)
    [99.9, 4], [95, 4],       // 95–100
    [94.9, 5], [90, 5],       // 90–95    — the value that exposed the bug
    [89.9, 6], [85, 6],       // 85–90
    [84.9, 7], [80, 7],       // 80–85
    [79.9, 8], [75, 8],       // 75–80
    [74.9, 9], [0, 9],        // <75%
  ];
  for (const [pct, expected] of cases) {
    assertEquals(paceRowOf(pct), expected, `${pct}% should land in row ${expected}`);
  }
});

Deno.test("row labels line up 1:1 with the thresholds", () => {
  assertEquals(PACE_ROW_LABELS.length, 10);
  // Sampling every row via paceRowOf must never exceed the label array.
  for (let i = 0; i < 10; i++) assert(PACE_ROW_LABELS[i] !== undefined);
});

const wo = (id: string, date: string, type: string) => ({
  id, workout_date: date, workout_type: type,
} as GoalPaceGridLog);

Deno.test("a 2mi WU + 16mi @ MP + 2mi CD deposits into TWO rows, never one average", () => {
  const blocks = [
    { role: "warmup", distance_miles: 2, avg_pace_per_mile: "7:30" },
    { role: "work_rep", distance_miles: 16, avg_pace_per_mile: "5:20" }, // exactly goal
    { role: "cooldown", distance_miles: 2, avg_pace_per_mile: "7:30" },
  ];
  const out = buildGoalPaceGrid(
    [wo("a", "2026-08-01", "long_wo")],
    new Map([["a", blocks]]),
    GOAL,
  )!;
  assertEquals(out.deposits.length, 3, "warmup, work, cooldown are three deposits");
  const mpDeposit = out.deposits.find((d) => d.miles === 16)!;
  assertEquals(mpDeposit.pace_row, 3, "16mi at exactly goal pace lands in the 100–105 row");
  const wuMiles = out.deposits.filter((d) => d.miles === 2).reduce((a, d) => a + d.miles, 0);
  assertEquals(wuMiles, 4, "both warmup and cooldown counted — nothing stripped");
  assertEquals(out.summary.total_miles, 20);
});

Deno.test("`steady`-role blocks are counted — the bug that dropped whole sessions", () => {
  // The session-level model excluded `steady` blocks from continuous-mile
  // totals, so a workout with only a steady block (a 14mi steady threshold
  // run, or a race with no work_rep at all) vanished from the surface
  // entirely. This module has no such gate.
  const out = buildGoalPaceGrid(
    [wo("a", "2026-03-21", "threshold")],
    new Map([["a", [{ role: "steady", distance_miles: 14, avg_pace_per_mile: "5:46" }]]]),
    GOAL,
  )!;
  assertEquals(out.deposits.length, 1);
  assertEquals(out.deposits[0].miles, 14);
});

Deno.test("recovery blocks DO deposit — they are real miles at a real pace", () => {
  // Reversed 2026-09-01. Excluding recovery jogs under-reported this
  // athlete's volume by ~61 miles over 27 weeks. They belong in the slow
  // bands, not nowhere. The only block-level exclusion left is the noise floor.
  const out = buildGoalPaceGrid(
    [wo("a", "2026-07-21", "threshold")],
    new Map([["a", [
      { role: "work_rep", distance_miles: 1, avg_pace_per_mile: "5:27" },
      { role: "recovery", distance_miles: 0.26, avg_pace_per_mile: "6:22" },
    ]]]),
    GOAL,
  )!;
  assertEquals(out.deposits.length, 2);
  assertEquals(out.summary.total_miles, 1.26);
});

Deno.test("sub-0.05mi blocks are still dropped as recording noise", () => {
  const out = buildGoalPaceGrid(
    [wo("a", "2026-07-21", "threshold")],
    new Map([["a", [
      { role: "work_rep", distance_miles: 1, avg_pace_per_mile: "5:27" },
      { role: "recovery", distance_miles: 0.02, avg_pace_per_mile: "55:45" },
    ]]]),
    GOAL,
  )!;
  assertEquals(out.deposits.length, 1);
  assertEquals(out.deposits[0].miles, 1);
});

Deno.test("a log with no blocks still deposits its whole-session miles", () => {
  // The ~100 miles that used to vanish: runs the structure pass never
  // produced blocks for. Distance + duration is enough to place them.
  const out = buildGoalPaceGrid(
    [{
      id: "a",
      workout_date: "2026-07-21",
      workout_type: "easy",
      workout_distance_miles: 8,
      workout_duration_minutes: 60, // 7:30/mi
    }],
    new Map(),
    GOAL,
  )!;
  assertEquals(out.deposits.length, 1);
  assertEquals(out.deposits[0].miles, 8);
  assertEquals(out.deposits[0].pace_sec, 450);
});

Deno.test("no distance or no duration invents nothing", () => {
  const out = buildGoalPaceGrid(
    [{
      id: "a",
      workout_date: "2026-07-21",
      workout_type: "easy",
      workout_distance_miles: 8,
      workout_duration_minutes: null,
    }],
    new Map(),
    GOAL,
  );
  assertEquals(out, null);
});

Deno.test("plain long_run is included but flagged is_long, not is_key", () => {
  const out = buildGoalPaceGrid(
    [wo("a", "2026-08-22", "long_run")],
    new Map([["a", [{ role: "work_rep", distance_miles: 16, avg_pace_per_mile: "6:38" }]]]),
    GOAL,
  )!;
  assertEquals(out.deposits[0].is_long, true);
  assertEquals(out.deposits[0].is_key, false);
});

Deno.test("long_wo is BOTH is_key and is_long", () => {
  const out = buildGoalPaceGrid(
    [wo("a", "2026-08-29", "long_wo")],
    new Map([["a", [{ role: "work_rep", distance_miles: 3, avg_pace_per_mile: "5:37" }]]]),
    GOAL,
  )!;
  assertEquals(out.deposits[0].is_key, true);
  assertEquals(out.deposits[0].is_long, true);
});

Deno.test("a session outside both filters (e.g. `steady` type) still appears under 'all'", () => {
  const out = buildGoalPaceGrid(
    [wo("a", "2026-05-29", "steady")],
    new Map([["a", [{ role: "work_rep", distance_miles: 12, avg_pace_per_mile: "7:30" }]]]),
    GOAL,
  );
  // "steady" is not isQuality and not long_run/long_wo, but there is no
  // candidate-session gate any more — every logged session deposits. It just
  // carries neither filter flag, so Key/Long slice it out while "all" keeps it.
  assertEquals(out?.deposits.length, 1);
  assertEquals(out?.deposits[0].is_key, false);
  assertEquals(out?.deposits[0].is_long, false);
});

Deno.test("heat: raw is never replaced, goal never moves", () => {
  const blocks = [{ role: "work_rep", distance_miles: 13.69, avg_pace_per_mile: "6:22" }];
  const wx = new Map([["a", { temp_f: 88, dew_point_f: 76 }]]);
  const hot = buildGoalPaceGrid([wo("a", "2026-08-01", "long_wo")], new Map([["a", blocks]]), GOAL, wx)!;
  const cool = buildGoalPaceGrid([wo("a", "2026-08-01", "long_wo")], new Map([["a", blocks]]), GOAL)!;
  const dh = hot.deposits[0], dc = cool.deposits[0];
  assertEquals(dh.pace_sec, dc.pace_sec, "raw pace untouched by weather");
  assert(dh.pace_sec_heat_adj < dh.pace_sec, "a hot session credits faster");
  assertEquals(hot.goal.pace_sec_per_mile, GOAL.pace_sec_per_mile, "goal never adjusts");
});

Deno.test("no weather still yields a grid; heat fields equal raw", () => {
  const out = buildGoalPaceGrid(
    [wo("a", "2026-08-01", "long_wo")],
    new Map([["a", [{ role: "work_rep", distance_miles: 5, avg_pace_per_mile: "5:40" }]]]),
    GOAL,
  )!;
  assertEquals(out.deposits[0].pace_sec_heat_adj, out.deposits[0].pace_sec);
  assertEquals(out.deposits[0].pct_of_goal_heat_adj, out.deposits[0].pct_of_goal);
});

Deno.test("no goal, no grid", () => {
  const out = buildGoalPaceGrid(
    [wo("a", "2026-08-01", "long_wo")],
    new Map([["a", [{ role: "work_rep", distance_miles: 5, avg_pace_per_mile: "5:40" }]]]),
    { ...GOAL, pace_sec_per_mile: 0 },
  );
  assertEquals(out, null);
});

Deno.test("workouts with no blocks are skipped, not zeroed", () => {
  const out = buildGoalPaceGrid(
    [wo("a", "2026-08-01", "long_wo"), wo("z", "2026-08-02", "threshold")],
    new Map([["a", [{ role: "work_rep", distance_miles: 5, avg_pace_per_mile: "5:40" }]]]),
    GOAL,
  )!;
  assertEquals(out.deposits.length, 1);
  assertEquals(out.deposits[0].workout_id, "a");
});

Deno.test("summary totals match a hand check", () => {
  const out = buildGoalPaceGrid(
    [wo("a", "2026-08-01", "long_wo"), wo("b", "2026-08-18", "intervals"),
     wo("c", "2026-08-22", "long_run")],
    new Map([
      ["a", [{ role: "work_rep", distance_miles: 3, avg_pace_per_mile: "5:20" }]],   // key+long, 100%
      ["b", [{ role: "work_rep", distance_miles: 6, avg_pace_per_mile: "5:20" }]],   // key only, 100%
      ["c", [{ role: "work_rep", distance_miles: 16, avg_pace_per_mile: "6:38" }]],  // long only, ~80%
    ]),
    GOAL,
  )!;
  assertEquals(out.summary.total_miles, 25);
  assertEquals(out.summary.key_miles, 9);   // a (3) + b (6)
  assertEquals(out.summary.long_miles, 19); // a (3) + c (16)
  assertEquals(out.summary.near_goal_miles, 9); // a + b, both at 100%
});
