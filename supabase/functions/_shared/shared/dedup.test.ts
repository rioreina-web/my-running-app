import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { dedupBySourcePriority, sourcePriority } from "./dedup.ts";

Deno.test("sourcePriority ranks strava > auto_sync > voice_log > check_in > unknown", () => {
  assert(sourcePriority("strava") > sourcePriority("auto_sync"));
  assert(sourcePriority("auto_sync") > sourcePriority("voice_log"));
  assert(sourcePriority("voice_log") > sourcePriority("check_in"));
  assert(sourcePriority("check_in") > sourcePriority("manual"));
  assertEquals(sourcePriority(undefined), 0);
});

Deno.test("dedup: same day + close distance/duration collapses, keeping richer source", () => {
  const rows = [
    { workout_date: "2026-06-10T08:00:00Z", workout_distance_miles: 6.0, workout_duration_minutes: 48, source: "voice_log" },
    { workout_date: "2026-06-10T09:30:00Z", workout_distance_miles: 6.1, workout_duration_minutes: 49, source: "strava" },
  ];
  const out = dedupBySourcePriority(rows);
  assertEquals(out.length, 1, "the two near-identical entries should collapse");
  assertEquals(out[0].source, "strava", "richer source (strava) should win");
});

Deno.test("dedup: lower-priority duplicate does NOT replace the kept richer row", () => {
  const rows = [
    { workout_date: "2026-06-10T08:00:00Z", workout_distance_miles: 6.0, workout_duration_minutes: 48, source: "strava" },
    { workout_date: "2026-06-10T09:30:00Z", workout_distance_miles: 6.0, workout_duration_minutes: 48, source: "voice_log" },
  ];
  const out = dedupBySourcePriority(rows);
  assertEquals(out.length, 1);
  assertEquals(out[0].source, "strava");
});

Deno.test("dedup: distance beyond 0.2mi tolerance is kept as a distinct workout", () => {
  const rows = [
    { workout_date: "2026-06-10T08:00:00Z", workout_distance_miles: 6.0, workout_duration_minutes: 48, source: "strava" },
    { workout_date: "2026-06-10T17:00:00Z", workout_distance_miles: 6.5, workout_duration_minutes: 52, source: "strava" },
  ];
  assertEquals(dedupBySourcePriority(rows).length, 2);
});

Deno.test("dedup: different calendar days never collapse", () => {
  const rows = [
    { workout_date: "2026-06-10T08:00:00Z", workout_distance_miles: 6.0, workout_duration_minutes: 48, source: "strava" },
    { workout_date: "2026-06-11T08:00:00Z", workout_distance_miles: 6.0, workout_duration_minutes: 48, source: "strava" },
  ];
  assertEquals(dedupBySourcePriority(rows).length, 2);
});

Deno.test("dedup: empty input returns empty array, original array not mutated", () => {
  assertEquals(dedupBySourcePriority([]), []);
  const rows = [{ workout_date: "2026-06-10", workout_distance_miles: 5, workout_duration_minutes: 40, source: "strava" }];
  const out = dedupBySourcePriority(rows);
  assert(out !== rows, "returns a new array");
  assertEquals(rows.length, 1);
});
