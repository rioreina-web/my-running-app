/**
 * Tests for the goal-pace convergence block.
 *
 * Fixtures are REAL `parsed_structure.blocks` from the calibration athlete,
 * trimmed to the fields the block reads. The 1 Aug session is the important
 * one: it is a structured long run that every earlier reading reported as flat
 * aerobic volume, and it is the case that proves floats have to count.
 *
 * Run: deno test trends-timeline/goalPace.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildGoalPace, type GoalPaceLog } from "./goalPace.ts";

const MP = 338; // athlete_pace_profiles.marathon_pace_seconds — 5:38/mi
const GOAL = {
  race_key: "marathon",
  time_seconds: 8400, // sub 2:20 at CIM
  pace_sec_per_mile: 8400 / 26.2188, // 320.4 → 5:20/mi
  source: "active_goal",
};

const w = (mi: number, s: number, p: string) => ({
  role: "work_rep", distance_miles: mi, duration_s: s, avg_pace_per_mile: p,
});
const r = (mi: number, s: number, p: string, style = "jog") => ({
  role: "recovery", distance_miles: mi, duration_s: s, avg_pace_per_mile: p,
  recovery_style: style,
});

// 1 Aug 2026 — a long-run WORKOUT (`long_wo`, the real row's type): eight
// segments with short floats between them. A plain `long_run` is not a key
// session and is deliberately excluded.
const AUG_01 = [
  w(1, 360, "6:00"), r(0.25, 109, "7:16"), w(2, 761, "6:21"), r(0.24, 110, "7:30"),
  w(1, 359, "5:59"), r(0.25, 108, "7:05"), w(2, 763, "6:22"), r(0.25, 112, "7:29"),
  w(1, 362, "6:02"), r(0.25, 105, "6:57"), w(2, 751, "6:16"), r(0.20, 91, "7:45"),
  w(1, 356, "5:56"), r(0.25, 115, "7:44"), w(2, 765, "6:23"),
];

// 18 Aug 2026 — 3×2mi with genuine jog rest. Not a float session.
const AUG_18 = [
  w(2.02, 662, "5:28"), r(0.10, 146, "23:27"),
  w(2.01, 658, "5:27"), r(0.08, 150, "32:11"),
  w(2.01, 667, "5:32"),
];

const log = (id: string, date: string, type: string): GoalPaceLog => ({
  id, workout_date: date, workout_type: type, workout_distance_miles: null,
});

Deno.test("bands come from the library, not from a plan", () => {
  const out = buildGoalPace(
    [log("a", "2026-08-01", "long_wo")],
    new Map([["a", AUG_01]]),
    GOAL,
    MP,
  )!;
  assertEquals(out.bands.map((b) => b.pct), [80, 85, 90, 95, 100]);
  // 100% is goal pace itself; 80% is goal pace / 0.80.
  assertEquals(out.bands.find((b) => b.pct === 100)!.pace_sec, 320);
  assertEquals(out.bands.find((b) => b.pct === 80)!.pace_sec, 400); // 320.39/0.80
});

Deno.test("1 Aug reads as 13.69 continuous miles, not 12 miles of reps", () => {
  const out = buildGoalPace(
    [log("a", "2026-08-01", "long_wo")],
    new Map([["a", AUG_01]]),
    GOAL,
    MP,
  )!;
  const s = out.sessions[0];
  assert(s.is_float_session, "float legs must be recognised as aerobic support");
  assertEquals(s.continuous_miles, 13.69);
  assertEquals(s.pace_sec, 382); // aggregate over the whole span, 6:22
  assertEquals(s.fast_pace_sec, 373); // the segments alone, 6:13
  assertEquals(s.cycles, 8);
  // 320.4 / 382 = 83.9% of goal speed.
  assert(s.pct_of_goal > 83 && s.pct_of_goal < 85, `got ${s.pct_of_goal}%`);
  assert(!s.at_or_above_specific, "84% is aerobic support, not specific work");
});

Deno.test("a rep session with jog rest is not a float session", () => {
  const out = buildGoalPace(
    [log("b", "2026-08-18", "intervals")],
    new Map([["b", AUG_18]]),
    GOAL,
    MP,
  )!;
  const s = out.sessions[0];
  assert(!s.is_float_session, "23:27 and 32:11 jogs are rest, not floats");
  assertEquals(s.continuous_miles, 6.04); // work only — the jogs are excluded
  assertEquals(s.cycles, 3);
  assert(s.pct_of_goal > 96 && s.pct_of_goal < 99, `got ${s.pct_of_goal}%`);
});

Deno.test("summary reports the convergence number", () => {
  const out = buildGoalPace(
    [log("a", "2026-08-01", "long_wo"), log("b", "2026-08-18", "intervals")],
    new Map([["a", AUG_01], ["b", AUG_18]]),
    GOAL,
    MP,
  )!;
  assertEquals(out.summary.sessions, 2);
  // Only the 3×2mi clears 95%. Its 6.04 continuous miles is the longest
  // specific span — the number a 2:20 build wants climbing toward 10–15.
  assertEquals(out.summary.longest_specific_miles, 6.04);
  assertEquals(out.summary.specific_miles, 6.04);
});

Deno.test("sessions come back oldest first, whatever order they arrive in", () => {
  const out = buildGoalPace(
    [log("b", "2026-08-18", "intervals"), log("a", "2026-08-01", "long_wo")],
    new Map([["a", AUG_01], ["b", AUG_18]]),
    GOAL,
    MP,
  )!;
  assertEquals(out.sessions.map((s) => s.date), ["2026-08-01", "2026-08-18"]);
});

Deno.test("no goal, no block — the surface must not invent an anchor", () => {
  const none = buildGoalPace(
    [log("a", "2026-08-01", "long_wo")],
    new Map([["a", AUG_01]]),
    { ...GOAL, pace_sec_per_mile: 0 },
    MP,
  );
  assertEquals(none, null);
});

Deno.test("workouts without parsed structure are skipped, not zeroed", () => {
  const out = buildGoalPace(
    [log("a", "2026-08-01", "long_wo"), log("z", "2026-08-02", "easy")],
    new Map([["a", AUG_01]]), // "z" has no blocks
    GOAL,
    MP,
  )!;
  assertEquals(out.sessions.length, 1);
  assertEquals(out.sessions[0].workout_id, "a");
});

Deno.test("no pace profile still yields a chart, just no float split", () => {
  // Float classification needs the athlete's MP. Without it every leg keeps
  // its parser role, so the long run reports its work legs only.
  const out = buildGoalPace(
    [log("a", "2026-08-01", "long_wo")],
    new Map([["a", AUG_01]]),
    GOAL,
    null,
  )!;
  const s = out.sessions[0];
  assert(!s.is_float_session);
  assertEquals(s.continuous_miles, 12);
  assert(s.pct_of_goal > 85, "work legs alone read faster than the aggregate");
});

// ── Heat ────────────────────────────────────────────────────────

Deno.test("heat correction is carried alongside, never in place of, raw pace", () => {
  const wx = new Map([["a", { temp_f: 82, dew_point_f: 74 }]]);
  const hot = buildGoalPace(
    [log("a", "2026-08-01", "long_wo")],
    new Map([["a", AUG_01]]),
    GOAL, MP, wx,
  )!.sessions[0];
  const cool = buildGoalPace(
    [log("a", "2026-08-01", "long_wo")],
    new Map([["a", AUG_01]]),
    GOAL, MP,
  )!.sessions[0];

  assertEquals(hot.pace_sec, cool.pace_sec, "raw pace must be untouched by weather");
  assert(hot.pace_sec_heat_adj < hot.pace_sec, "a hot session should correct faster");
  assert(hot.heat_gain_sec > 0);
  assert(hot.pct_of_goal_heat_adj > hot.pct_of_goal, "corrected reads closer to goal");
});

Deno.test("no weather means no correction, and the field still reads", () => {
  const s = buildGoalPace(
    [log("a", "2026-08-01", "long_wo")],
    new Map([["a", AUG_01]]),
    GOAL, MP,
    new Map([["a", { temp_f: null, dew_point_f: null }]]),
  )!.sessions[0];
  // Equal, not null — a consumer can read the adjusted field without branching.
  assertEquals(s.pace_sec_heat_adj, s.pace_sec);
  assertEquals(s.heat_gain_sec, 0);
  assertEquals(s.pct_of_goal_heat_adj, s.pct_of_goal);
});

Deno.test("the GOAL is never heat-adjusted", () => {
  // Adjust both sides and the picture rescales together: the toggle appears to
  // do nothing. That is the self-normalising bug from the splits chart.
  const wx = new Map([["a", { temp_f: 88, dew_point_f: 76 }]]);
  const out = buildGoalPace(
    [log("a", "2026-08-01", "long_wo")],
    new Map([["a", AUG_01]]),
    GOAL, MP, wx,
  )!;
  assertEquals(out.goal.pace_sec_per_mile, GOAL.pace_sec_per_mile);
  assertEquals(out.bands.find((b) => b.pct === 100)!.pace_sec, 320);
});

Deno.test("a plain long run is volume, not a key session", () => {
  const none = buildGoalPace(
    [log("a", "2026-08-01", "long_run")],
    new Map([["a", AUG_01]]),
    GOAL, MP,
  );
  assertEquals(none, null, "long_run must not reach this surface");
});
