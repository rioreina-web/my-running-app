import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildLoadMetrics, type WorkoutRow } from "./buildLoadMetrics.ts";
import type { WorkoutFeaturesRow } from "../weeklyAnalytics.ts";

const NOW = new Date("2026-06-18T12:00:00Z");
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 86400000).toISOString();
const WINDOWS = {
  sevenDaysAgo: daysAgo(7),
  fourteenDaysAgo: daysAgo(14),
  twentyEightDaysAgo: daysAgo(28),
};
const emptyFeatures = new Map<string, WorkoutFeaturesRow>();

function run(logs: WorkoutRow[], snapshot?: Record<string, unknown>) {
  return buildLoadMetrics({ logs, featuresByLogId: emptyFeatures, snapshot, ...WINDOWS });
}

Deno.test("empty input → zeros and null acwr", () => {
  const m = run([]);
  assertEquals(m.rolling7dMiles, 0);
  assertEquals(m.rolling28dMiles, 0);
  assertEquals(m.acwr, null);
  assertEquals(m.runsLast7d, 0);
  assertEquals(m.longestRun14d, 0);
});

Deno.test("rolling miles + 28d weekly avg over the right windows", () => {
  const logs: WorkoutRow[] = [
    { id: "a", workout_date: daysAgo(1), workout_distance_miles: 6, workout_duration_minutes: 48, workout_type: "easy", source: "strava" },
    { id: "b", workout_date: daysAgo(3), workout_distance_miles: 4, workout_duration_minutes: 32, workout_type: "easy", source: "strava" },
    { id: "c", workout_date: daysAgo(20), workout_distance_miles: 10, workout_duration_minutes: 80, workout_type: "easy", source: "strava" },
    { id: "d", workout_date: daysAgo(40), workout_distance_miles: 99, workout_duration_minutes: 800, workout_type: "easy", source: "strava" }, // outside 28d
  ];
  const m = run(logs);
  assertEquals(m.rolling7dMiles, 10);          // a + b
  assertEquals(m.rolling28dMiles, 20);         // a + b + c (d excluded)
  assertEquals(m.weeklyAvg28d, 5);             // 20 / 4
});

Deno.test("cross-source dedup collapses duplicate uploads", () => {
  const logs: WorkoutRow[] = [
    { id: "v", workout_date: daysAgo(2) + "", workout_distance_miles: 6.0, workout_duration_minutes: 48, workout_type: "easy", source: "voice_log" },
    { id: "s", workout_date: daysAgo(2) + "", workout_distance_miles: 6.1, workout_duration_minutes: 49, workout_type: "easy", source: "strava" },
  ];
  const m = run(logs);
  assertEquals(m.workoutsWithMiles.length, 1, "duplicate uploads collapse to one");
});

Deno.test("hard-session classification: always-hard types, parsed type, long_run rules", () => {
  const logs: WorkoutRow[] = [
    { id: "1", workout_date: daysAgo(1), workout_distance_miles: 6, workout_duration_minutes: 36, workout_type: "tempo", source: "strava" },          // always hard
    { id: "2", workout_date: daysAgo(2), workout_distance_miles: 5, workout_duration_minutes: 30, workout_type: "easy", source: "strava", parsed_structure: { type: "interval" } }, // parsed hard
    { id: "3", workout_date: daysAgo(3), workout_distance_miles: 20, workout_duration_minutes: 170, workout_type: "long_run", source: "strava" },     // long ≥18 → hard
    { id: "4", workout_date: daysAgo(4), workout_distance_miles: 8, workout_duration_minutes: 64, workout_type: "easy", source: "strava" },           // easy
    { id: "5", workout_date: daysAgo(5), workout_distance_miles: 6, workout_duration_minutes: 48, workout_type: "recovery", source: "strava" },       // easy
  ];
  const m = run(logs);
  assertEquals(m.hardSessions7d, 3);
  // easySessions counts by RAW workout_type only (independent of hard
  // classification): id2 is workout_type "easy" so it counts here too, even
  // though it's parsed as an interval and counted as hard above. Preserved
  // quirk from the original inline logic.
  assertEquals(m.easySessions7d, 3); // id2 (easy) + id4 (easy) + id5 (recovery)
});

Deno.test("long_run counts as hard when run faster than 80% MP effort (pace ≤ MP×1.25)", () => {
  // MP from snapshot: 3:30 marathon → 12600s / 26.2188 ≈ 480.6 s/mi. MP×1.25 ≈ 600.8.
  // A 14mi long run at 9:00/mi (540s) is faster than that → hard.
  const snapshot = { predicted_marathon_seconds: 3 * 3600 + 30 * 60 };
  const fast = run([
    { id: "lr", workout_date: daysAgo(2), workout_distance_miles: 14, workout_duration_minutes: 14 * 9, workout_type: "long_run", source: "strava" },
  ], snapshot);
  assertEquals(fast.hardSessions7d, 1, "fast long run is hard");
  // Same run at 11:00/mi (660s > 600.8) and <18mi → not hard.
  const slow = run([
    { id: "lr", workout_date: daysAgo(2), workout_distance_miles: 14, workout_duration_minutes: 14 * 11, workout_type: "long_run", source: "strava" },
  ], snapshot);
  assertEquals(slow.hardSessions7d, 0, "easy-paced sub-18 long run is not hard");
});

Deno.test("longest run uses the 14-day window", () => {
  const logs: WorkoutRow[] = [
    { id: "a", workout_date: daysAgo(2), workout_distance_miles: 8, workout_duration_minutes: 64, workout_type: "easy", source: "strava" },
    { id: "b", workout_date: daysAgo(10), workout_distance_miles: 16, workout_duration_minutes: 140, workout_type: "long_run", source: "strava" },
    { id: "c", workout_date: daysAgo(20), workout_distance_miles: 22, workout_duration_minutes: 200, workout_type: "long_run", source: "strava" }, // outside 14d
  ];
  assertEquals(run(logs).longestRun14d, 16);
});

Deno.test("runsLast7d uses session grouping (same-day close uploads = one session)", () => {
  const logs: WorkoutRow[] = [
    { id: "wu", workout_date: "2026-06-17T08:00:00Z", workout_distance_miles: 2, workout_duration_minutes: 16, workout_type: "easy", source: "strava" },
    { id: "main", workout_date: "2026-06-17T08:30:00Z", workout_distance_miles: 6, workout_duration_minutes: 42, workout_type: "easy", source: "strava" },
    { id: "other", workout_date: "2026-06-16T08:00:00Z", workout_distance_miles: 5, workout_duration_minutes: 40, workout_type: "easy", source: "strava" },
  ];
  // Two uploads 30min apart on 06-17 collapse into one session; 06-16 is another.
  assertEquals(run(logs).runsLast7d, 2);
});

Deno.test("acwr is non-null when there is load", () => {
  const logs: WorkoutRow[] = [
    { id: "a", workout_date: daysAgo(1), workout_distance_miles: 6, workout_duration_minutes: 48, workout_type: "easy", source: "strava" },
    { id: "c", workout_date: daysAgo(20), workout_distance_miles: 10, workout_duration_minutes: 80, workout_type: "easy", source: "strava" },
  ];
  assert(run(logs).acwr !== null);
});
