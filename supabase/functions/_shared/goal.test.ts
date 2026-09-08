/**
 * Tests for the one true goal resolver.
 *
 * The load-bearing cases here are the ones that were LIVE BUGS on
 * 2026-09-08, before this module existed:
 *
 *   - `structured:` — `athlete-state.ts` selected only `goal_title` and
 *     re-derived the distance by regex, so "Run sub 2:20 at CIM" resolved via
 *     a hard-coded `\bcim\b` alias while `target_race_distance: "marathon"`
 *     sat unread in the same row.
 *   - `date:` — four of the five old resolvers never selected `target_date`
 *     at all, so every AI surface knew the goal time and not the goal date.
 *   - `orphan/stale:` — an active `user_goals` row with a NULL `user_id` and a
 *     five-month-past target date sat in production and was reachable by the
 *     resolvers that filtered on status alone.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  describeRunway,
  fmtPace,
  normalizeRaceKey,
  parseGoalTitle,
  resolveGoalFrom,
  type GoalInputs,
} from "./goal.ts";

const TODAY = "2026-09-08";

function inputs(over: Partial<GoalInputs> = {}): GoalInputs {
  return {
    userGoals: [],
    activeGoals: [],
    plan: null,
    stateGoalRace: null,
    stateGoalTimeSeconds: null,
    ...over,
  };
}

/** The real production row, as it stands after the 2026-09-08 cleanup. */
const CIM = {
  goal_title: "Run sub 2:20 at CIM",
  target_race_distance: "marathon",
  target_time_seconds: 8400,
  target_date: "2026-12-06T00:00:00+00:00",
  athlete_confirmed: false,
  created_at: "2026-06-20T23:01:40Z",
};

Deno.test("structured: reads the columns instead of regex-parsing the title", () => {
  const { goal } = resolveGoalFrom(inputs({ userGoals: [CIM] }), TODAY);
  assert(goal);
  assertEquals(goal.source, "structured");
  assertEquals(goal.raceKey, "marathon");
  assertEquals(goal.timeSeconds, 8400);
  // 8400 / 26.2188 = 320.4 s/mi
  assertEquals(fmtPace(goal.pacePerMileSeconds), "5:20");
});

Deno.test("date: the runway reaches the caller, which four old resolvers never did", () => {
  const { goal } = resolveGoalFrom(inputs({ userGoals: [CIM] }), TODAY);
  assert(goal);
  assertEquals(goal.targetDate, "2026-12-06");
  assertEquals(goal.daysToRace, 89);
  assertEquals(goal.weeksToRace, 13);
  assertEquals(describeRunway(goal), "13 weeks out");
});

Deno.test("stale: a past-due goal never outranks a live one", () => {
  const stale = {
    goal_title: "Get in shape for a sub 15 5k",
    target_race_distance: "5k",
    target_time_seconds: 900,
    target_date: "2026-04-03T22:29:00+00:00",
    created_at: "2026-02-16T22:29:46Z",
  };
  // Stale sorts first by target_date ascending, which is how the old
  // "soonest goal" ordering would have picked it.
  const { goal } = resolveGoalFrom(inputs({ userGoals: [stale, CIM] }), TODAY);
  assert(goal);
  assertEquals(goal.raceKey, "marathon");
  assertEquals(goal.title, "Run sub 2:20 at CIM");
});

Deno.test("stale: with only past goals, the most recent still resolves, dated in the past", () => {
  const past = { ...CIM, target_date: "2026-01-05T00:00:00Z" };
  const { goal } = resolveGoalFrom(inputs({ userGoals: [past] }), TODAY);
  assert(goal);
  assert(goal.daysToRace != null && goal.daysToRace < 0);
  assertEquals(describeRunway(goal), "past");
});

Deno.test("tiers: active_goals carries the goal when the structured columns are empty", () => {
  const bare = { goal_title: "Run sub 2:20 at CIM", target_date: CIM.target_date };
  const { goal } = resolveGoalFrom(
    inputs({
      userGoals: [bare],
      activeGoals: [{
        title: "Run sub 2:20 at CIM",
        target_distance_key: "marathon",
        target_time_seconds: 8400,
        target_date: CIM.target_date,
      }],
    }),
    TODAY,
  );
  assert(goal);
  assertEquals(goal.source, "active_goal");
  assertEquals(goal.weeksToRace, 13);
});

Deno.test("tiers: the plan supplies both the goal and the race date", () => {
  const { goal } = resolveGoalFrom(
    inputs({
      plan: {
        name: "CIM build",
        target_race_distance: "marathon",
        target_time_seconds: 8400,
        end_date: "2026-12-06",
      },
    }),
    TODAY,
  );
  assert(goal);
  assertEquals(goal.source, "plan");
  assertEquals(goal.targetDate, "2026-12-06");
});

Deno.test("tiers: flat athlete_state columns borrow a date from user_goals", () => {
  const { goal } = resolveGoalFrom(
    inputs({
      userGoals: [{ goal_title: "Run sub 2:20 at CIM", target_date: CIM.target_date }],
      stateGoalRace: "marathon",
      stateGoalTimeSeconds: 8400,
    }),
    TODAY,
  );
  assert(goal);
  assertEquals(goal.source, "athlete_state");
  // The tier itself has no date column; the resolution still has one.
  assertEquals(goal.targetDate, "2026-12-06");
});

Deno.test("title: parses a goal that names its distance", () => {
  const { goal } = resolveGoalFrom(
    inputs({ userGoals: [{ goal_title: "sub 1:10 at Austin Half Marathon", target_date: "2026-11-01" }] }),
    TODAY,
  );
  assert(goal);
  assertEquals(goal.source, "title");
  assertEquals(goal.raceKey, "half");
  assertEquals(goal.timeSeconds, 4200);
});

Deno.test("title: refuses to guess a distance from the magnitude of a time", () => {
  const { goal, unparsedTitle } = resolveGoalFrom(
    inputs({ userGoals: [{ goal_title: "Run sub 2:20 at CIM", target_date: CIM.target_date }] }),
    TODAY,
  );
  // "CIM" is world knowledge, not a distance word. Ask, never guess.
  assertEquals(goal, null);
  assertEquals(unparsedTitle, "Run sub 2:20 at CIM");
});

Deno.test("title: half is tested before marathon so 'half marathon' is not a marathon", () => {
  assertEquals(parseGoalTitle("sub 1:10 half marathon")?.raceKey, "half");
  assertEquals(parseGoalTitle("sub 2:20 marathon")?.raceKey, "marathon");
});

Deno.test("title: two-part times read by distance", () => {
  // 2:20 for a marathon is two hours twenty.
  assertEquals(parseGoalTitle("sub 2:20 marathon")?.seconds, 8400);
  // 4:20 for a mile is four minutes twenty.
  assertEquals(parseGoalTitle("sub 4:20 mile")?.seconds, 260);
});

Deno.test("keys: both casing systems in the codebase normalize to one", () => {
  assertEquals(normalizeRaceKey("fiveK"), "5k");
  assertEquals(normalizeRaceKey("5K"), "5k");
  assertEquals(normalizeRaceKey("tenK"), "10k");
  assertEquals(normalizeRaceKey("half_marathon"), "half");
  assertEquals(normalizeRaceKey("Marathon"), "marathon");
  assertEquals(normalizeRaceKey("triathlon"), null);
});

Deno.test("empty: no goal anywhere resolves to nothing, not a default", () => {
  const { goal, unparsedTitle } = resolveGoalFrom(inputs(), TODAY);
  assertEquals(goal, null);
  assertEquals(unparsedTitle, null);
});

Deno.test("runway: phrasing switches from days to weeks at two weeks", () => {
  const at = (d: string) => {
    const { goal } = resolveGoalFrom(inputs({ userGoals: [{ ...CIM, target_date: d }] }), TODAY);
    return goal ? describeRunway(goal) : null;
  };
  assertEquals(at("2026-09-08"), "today");
  assertEquals(at("2026-09-17"), "9 days out");
  assertEquals(at("2026-09-30"), "3 weeks out");
});

Deno.test("timezone: a date-only boundary does not shift the day count", () => {
  // Midnight-UTC arithmetic on both sides: the offset in the stored timestamp
  // must not move the answer. Same class of bug as Ask calling today "yesterday".
  const a = resolveGoalFrom(inputs({ userGoals: [{ ...CIM, target_date: "2026-12-06T00:00:00+00:00" }] }), TODAY);
  const b = resolveGoalFrom(inputs({ userGoals: [{ ...CIM, target_date: "2026-12-06T23:59:00-06:00" }] }), TODAY);
  assertEquals(a.goal?.daysToRace, b.goal?.daysToRace);
});
