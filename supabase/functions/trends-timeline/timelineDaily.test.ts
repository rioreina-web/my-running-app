/**
 * Tests for buildDailyTimeline — the Trends-v2 daily calendar substrate.
 * Run: deno test supabase/functions/trends-timeline/timelineDaily.test.ts
 *
 * No LLM in this path, so no eval cassette is required. These guard the
 * pure math: dense day coverage, per-day miles + dedup, the key/long/easy/
 * rest channel precedence, mood attaching to any logged feeling, verbatim
 * niggles, and — the load-bearing one — daily miles summing to the weekly
 * rollup so the two views can never disagree.
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildDailyTimeline,
  buildTrendsTimeline,
  type TimelineInput,
} from "./timeline.ts";

// Reference = Mon 2026-06-15 (a Monday) so the window is clean.
const REF = new Date("2026-06-15T12:00:00Z");

Deno.test("daily timeline is dense: one entry per day from oldest Monday through today", () => {
  const input: TimelineInput = { logs: [], features: [], mentions: [] };
  const days = buildDailyTimeline(input, 2, REF);
  // 2 weeks: windows [6/8..6/15) and [6/15..6/22). Oldest Monday 6/8 → today 6/15
  // inclusive = 8 days. Daily stops at today, not the end of the partial week.
  assertEquals(days.length, 8);
  assertEquals(days[0].date, "2026-06-08");
  assertEquals(days[days.length - 1].date, "2026-06-15");
  // A window of pure rest days is still emitted, honestly.
  assert(days.every((d) => d.type === "rest" && d.miles === 0 && d.mood === null));
});

Deno.test("per-day miles, channel precedence, and cross-training exclusion", () => {
  const input: TimelineInput = {
    logs: [
      // Mon (today): easy run
      { id: "a", workout_date: "2026-06-15", workout_distance_miles: 8, workout_duration_minutes: 60, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "positive" },
      // Wed prior: tempo → key channel
      { id: "b", workout_date: "2026-06-10", workout_distance_miles: 6, workout_duration_minutes: 41, workout_type: "tempo", workout_pace_per_mile: "6:50", mood: "tired" },
      // Thu prior: cross-training → NOT miles, day stays rest
      { id: "c", workout_date: "2026-06-11", workout_distance_miles: 12, workout_duration_minutes: 45, workout_type: "cross_training", workout_pace_per_mile: null, mood: "neutral" },
      // Sun prior: long run WITH an embedded quality block → long precedence over key
      { id: "d", workout_date: "2026-06-14", workout_distance_miles: 16, workout_duration_minutes: 130, workout_type: "long", workout_pace_per_mile: "8:05", mood: "energized" },
    ],
    features: [
      // Give the long run a high intensity so isQuality would be true — long must still win.
      { training_log_id: "d", intensity_score: 2.1, total_duration_seconds: 7800 },
    ],
    mentions: [],
  };
  const days = buildDailyTimeline(input, 2, REF);
  const byDate = new Map(days.map((d) => [d.date, d]));

  assertEquals(byDate.get("2026-06-15")!.type, "easy");
  assertEquals(byDate.get("2026-06-15")!.miles, 8);
  assertEquals(byDate.get("2026-06-10")!.type, "key");
  assertEquals(byDate.get("2026-06-11")!.type, "rest"); // cross-training only
  assertEquals(byDate.get("2026-06-11")!.miles, 0);
  assertEquals(byDate.get("2026-06-14")!.type, "long"); // long > key
});

Deno.test("mood attaches to any logged feeling, including a zero-distance check-in", () => {
  const input: TimelineInput = {
    logs: [
      // Mood-only check-in: no distance, dropped by the running filter, still colors its day.
      { id: "m", workout_date: "2026-06-09", workout_distance_miles: 0, workout_duration_minutes: 0, workout_type: "rest", workout_pace_per_mile: null, mood: "struggling" },
    ],
    features: [],
    mentions: [],
  };
  const days = buildDailyTimeline(input, 2, REF);
  const d = days.find((x) => x.date === "2026-06-09")!;
  assertEquals(d.mood, "struggling");
  assertEquals(d.miles, 0);
  assertEquals(d.type, "rest");
});

Deno.test("niggles surface verbatim with raw severity, on the right day", () => {
  const input: TimelineInput = {
    logs: [],
    features: [],
    mentions: [
      { body_area: "achilles", side: "right", verbatim_quote: "tight right achilles on the last two miles", severity_hint: "tight", mentioned_at: "2026-06-12" },
    ],
  };
  const days = buildDailyTimeline(input, 2, REF);
  const d = days.find((x) => x.date === "2026-06-12")!;
  assertEquals(d.niggles.length, 1);
  assertEquals(d.niggles[0], {
    area: "achilles",
    side: "right",
    severity: "tight",
    quote: "tight right achilles on the last two miles",
  });
});

Deno.test("ANTI-DRIFT: daily miles sum to the weekly rollup for every week", () => {
  const input: TimelineInput = {
    logs: [
      { id: "a", workout_date: "2026-06-15", workout_distance_miles: 8, workout_duration_minutes: 60, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "positive" },
      { id: "b", workout_date: "2026-06-10", workout_distance_miles: 6, workout_duration_minutes: 41, workout_type: "tempo", workout_pace_per_mile: "6:50", mood: "tired" },
      { id: "d", workout_date: "2026-06-09", workout_distance_miles: 10, workout_duration_minutes: 75, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "energized" },
      { id: "e", workout_date: "2026-06-14", workout_distance_miles: 16, workout_duration_minutes: 130, workout_type: "long", workout_pace_per_mile: "8:05", mood: "positive" },
      // A double on one day — both must sum into that day and that week.
      { id: "f", workout_date: "2026-06-11", workout_distance_miles: 4, workout_duration_minutes: 30, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "neutral" },
    ],
    features: [],
    mentions: [],
  };
  const weeks = buildTrendsTimeline(input, 2, REF);
  const days = buildDailyTimeline(input, 2, REF);

  for (const wk of weeks) {
    const start = new Date(wk.week_start + "T00:00:00Z").getTime();
    const end = start + 7 * 24 * 3600 * 1000;
    const dailySum = days
      .filter((d) => {
        const t = new Date(d.date + "T00:00:00Z").getTime();
        return t >= start && t < end;
      })
      .reduce((s, d) => s + d.miles, 0);
    assertEquals(
      Math.round(dailySum * 10) / 10,
      wk.miles,
      `week ${wk.week_start}: daily sum ${dailySum} != weekly ${wk.miles}`,
    );
  }
});
