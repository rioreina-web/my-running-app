/**
 * Unit tests for build_vs_last_cycle (Phase 2 sub-task F).
 *
 * Maya's scenario: Houston Marathon 3:28:00 on 2026-01-18, BQ goal race
 * 2026-10-11 (active marathon plan), current build averaging ~42 mpw vs.
 * a ~38 mpw Houston-build baseline.
 *
 * Run: deno test --allow-all _shared/rules/buildVsLastCycle.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildVsLastCycle } from "./buildVsLastCycle.ts";
import type {
  ConfirmedRaceSummary,
  GoalRaceInfo,
  RuleContext,
  WeatherAwareTrainingLogRow,
} from "./types.ts";

const NOW = new Date("2026-06-09T12:00:00Z");

const HOUSTON: ConfirmedRaceSummary = {
  date: "2026-01-18",
  distance: "marathon",
  finish_time_seconds: 12480, // 3:28:00
  official: true,
  event_name: "Houston Marathon",
};

const GOAL: GoalRaceInfo = { date: "2026-10-11", distance: "marathon" };

/** Build n logs of `miles` each, evenly spaced inside the window. */
function logs(
  n: number,
  miles: number,
  startIso: string,
  opts: { type?: string; pace?: string } = {},
): WeatherAwareTrainingLogRow[] {
  const start = new Date(startIso).getTime();
  return Array.from({ length: n }, (_, i) => ({
    id: `log-${startIso}-${i}`,
    workout_date: new Date(start + i * 2 * 86400000).toISOString(),
    workout_distance_miles: miles,
    workout_duration_minutes: null,
    workout_type: opts.type ?? "easy",
    workout_pace_per_mile: opts.pace ?? null,
    pace_segments: null,
    mood: null,
    notes: null,
    cleaned_notes: null,
    coach_insight: null,
  }));
}

function ctx(overrides: Partial<RuleContext>): RuleContext {
  return {
    athleteUserId: "maya",
    coachId: "coach-1",
    now: NOW,
    // Current 28d: 12 runs × 14 mi = 168 mi → 42 mpw
    logs: logs(12, 14, "2026-05-14"),
    scheduledThisWeek: [],
    confirmedRaces: [HOUSTON],
    goalRace: GOAL,
    // Prior build (−63d…−21d before Houston): 16 runs × 14.4 mi ≈ 230 mi → ~38.3 mpw
    priorCycleLogs: logs(16, 14.4, "2025-11-20"),
    ...overrides,
  };
}

Deno.test("fires for Maya: above-baseline build with goal race + prior marathon", () => {
  const m = buildVsLastCycle(ctx({}));
  assert(m, "rule should fire");
  assertEquals(m.rule_id, "build_vs_last_cycle");
  assertEquals(m.action_type, "journey_comparison");
  assertEquals(m.severity, "low");
  assert(m.summary.includes("3:28:00 marathon"), `summary should cite the race: ${m.summary}`);
  assert(m.summary.includes("Houston Marathon"), "summary should name the event");
  assert(m.summary.includes("42 mpw"), `summary should cite current volume: ${m.summary}`);
  assert(/~\d+% above/.test(m.summary), "summary should cite the % above baseline");
  assert(m.source_log_ids.length > 0 && m.source_log_ids.length <= 10);
});

Deno.test("includes easy-pace shift when both windows have parseable easy paces", () => {
  const m = buildVsLastCycle(ctx({
    logs: logs(12, 14, "2026-05-14", { type: "easy", pace: "9:40" }),
    priorCycleLogs: logs(16, 14.4, "2025-11-20", { type: "easy", pace: "9:55" }),
  }));
  assert(m);
  assert(m.summary.includes("15 sec/mi quicker"), `expected pace sentence: ${m.summary}`);
});

Deno.test("no fire: no goal race", () => {
  assertEquals(buildVsLastCycle(ctx({ goalRace: null })), null);
});

Deno.test("no fire: goal race more than ~6 months out", () => {
  assertEquals(
    buildVsLastCycle(ctx({ goalRace: { date: "2027-06-01", distance: "marathon" } })),
    null,
  );
});

Deno.test("no fire: goal distance differs from anchor race distance", () => {
  assertEquals(
    buildVsLastCycle(ctx({ goalRace: { date: "2026-08-15", distance: "5k" } })),
    null,
  );
});

Deno.test("fires when goal distance is unknown (user_goals has no distance)", () => {
  const m = buildVsLastCycle(ctx({ goalRace: { date: "2026-10-11", distance: null } }));
  assert(m, "distance-unknown goal should not block the comparison");
});

Deno.test("no fire: no confirmed races", () => {
  assertEquals(buildVsLastCycle(ctx({ confirmedRaces: null })), null);
  assertEquals(buildVsLastCycle(ctx({ confirmedRaces: [] })), null);
});

Deno.test("no fire: current volume at or below the prior-cycle baseline", () => {
  // 12 runs × 12.5 mi = 150 mi → 37.5 mpw, below 38.3 baseline
  assertEquals(
    buildVsLastCycle(ctx({ logs: logs(12, 12.5, "2026-05-14") })),
    null,
  );
});

Deno.test("no fire: too little data in either window", () => {
  assertEquals(buildVsLastCycle(ctx({ logs: logs(5, 20, "2026-05-14") })), null);
  assertEquals(buildVsLastCycle(ctx({ priorCycleLogs: logs(3, 30, "2025-11-20") })), null);
  assertEquals(buildVsLastCycle(ctx({ priorCycleLogs: null })), null);
});
