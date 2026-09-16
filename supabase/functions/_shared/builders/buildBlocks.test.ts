import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildBlocks, type BlockRow } from "./buildBlocks.ts";

const NOW = new Date("2026-06-18T12:00:00Z");
const daysAgo = (n: number) => new Date(NOW.getTime() - n * 86400000).toISOString();

function row(over: Partial<BlockRow> & { workout_date: string }): BlockRow {
  return { workout_distance_miles: 6, workout_duration_minutes: 48, source: "strava", ...over };
}

Deno.test("empty history → no blocks", () => {
  assertEquals(buildBlocks({ blockHistoryRows: [], niggleMentionDates: [], now: NOW }), []);
});

Deno.test("blocks with no rows in window are skipped (only populated blocks returned)", () => {
  // All runs in the current 28-day block; older blocks empty.
  const rows: BlockRow[] = [
    row({ workout_date: daysAgo(2), workout_distance_miles: 6 }),
    row({ workout_date: daysAgo(10), workout_distance_miles: 8 }),
  ];
  const blocks = buildBlocks({ blockHistoryRows: rows, niggleMentionDates: [], now: NOW });
  assertEquals(blocks.length, 1);
  assertEquals(blocks[0].total_miles, 14);
  assertEquals(blocks[0].weekly_avg_miles, 3.5); // 14 / 4
});

Deno.test("quality vs easy classification + races, by parsed type", () => {
  const rows: BlockRow[] = [
    row({ workout_date: daysAgo(1), parsed_structure: { type: "interval" } }),
    row({ workout_date: daysAgo(2), parsed_structure: { type: "tempo" } }),
    row({ workout_date: daysAgo(3), parsed_structure: { type: "race" } }),
    row({ workout_date: daysAgo(4), parsed_structure: { type: "easy" } }),
    row({ workout_date: daysAgo(5) }), // unlabeled → easy
  ];
  const b = buildBlocks({ blockHistoryRows: rows, niggleMentionDates: [], now: NOW })[0];
  assertEquals(b.quality_sessions, 3); // interval + tempo + race
  assertEquals(b.races_entered, 1);
  assertEquals(b.easy_sessions, 2);    // easy + unlabeled
});

Deno.test("avg easy pace from column, with derived fallback; out-of-range excluded", () => {
  const rows: BlockRow[] = [
    row({ workout_date: daysAgo(1), parsed_structure: { type: "easy" }, workout_pace_per_mile: "8:00" }),       // 480
    row({ workout_date: daysAgo(2), parsed_structure: { type: "recovery" }, workout_pace_per_mile: null, workout_distance_miles: 5, workout_duration_minutes: 50 }), // derived 600
  ];
  const b = buildBlocks({ blockHistoryRows: rows, niggleMentionDates: [], now: NOW })[0];
  assertEquals(b.avg_easy_pace_sec, 540); // (480 + 600) / 2
});

Deno.test("injury_mentions counts niggle dates falling inside the block window", () => {
  const rows: BlockRow[] = [row({ workout_date: daysAgo(3) })];
  const blocks = buildBlocks({
    blockHistoryRows: rows,
    niggleMentionDates: [daysAgo(5).slice(0, 10), daysAgo(40).slice(0, 10)], // one in-block, one older
    now: NOW,
  });
  assertEquals(blocks[0].injury_mentions, 1);
});

Deno.test("dominant mood summary", () => {
  const rows: BlockRow[] = [
    row({ workout_date: daysAgo(1), mood: "tired" }),
    row({ workout_date: daysAgo(2), mood: "tired" }),
    row({ workout_date: daysAgo(3), mood: "positive" }),
  ];
  assertEquals(buildBlocks({ blockHistoryRows: rows, niggleMentionDates: [], now: NOW })[0].mood_summary, "tired");
});

Deno.test("cross-source duplicates are collapsed before rollup", () => {
  const rows: BlockRow[] = [
    row({ workout_date: daysAgo(2), workout_distance_miles: 6.0, workout_duration_minutes: 48, source: "voice_log" }),
    row({ workout_date: daysAgo(2), workout_distance_miles: 6.1, workout_duration_minutes: 49, source: "strava" }),
  ];
  const b = buildBlocks({ blockHistoryRows: rows, niggleMentionDates: [], now: NOW })[0];
  assertEquals(b.total_miles, 6.1); // one workout kept (richer source), not summed to ~12
});
