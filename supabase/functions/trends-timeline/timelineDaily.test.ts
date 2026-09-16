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

// ─── Day mood = the hardest session's mood ─────────────────────────────
//
// A day is not the average of how it felt. These guard `hardestSessionMood`
// against a regression back to a modal count, which returns the wrong answer
// for the commonest shape of a workout day.

Deno.test("day mood: a good warm-up and cool-down do NOT outvote a bad workout", () => {
  const input: TimelineInput = {
    logs: [
      { id: "wu", workout_date: "2026-06-15T06:00:00Z", workout_distance_miles: 2, workout_duration_minutes: 18, workout_type: "easy", workout_pace_per_mile: "9:00", mood: "positive" },
      { id: "wo", workout_date: "2026-06-15T06:30:00Z", workout_distance_miles: 6, workout_duration_minutes: 40, workout_type: "tempo", workout_pace_per_mile: "6:40", mood: "tired" },
      { id: "cd", workout_date: "2026-06-15T07:20:00Z", workout_distance_miles: 2, workout_duration_minutes: 18, workout_type: "easy", workout_pace_per_mile: "9:00", mood: "positive" },
    ],
    features: [
      { training_log_id: "wu", intensity_score: 0.4, total_duration_seconds: 1080 },
      { training_log_id: "wo", intensity_score: 2.6, total_duration_seconds: 2400 },
      { training_log_id: "cd", intensity_score: 0.4, total_duration_seconds: 1080 },
    ],
    mentions: [],
  };
  const day = buildDailyTimeline(input, 2, REF).find((d) => d.date === "2026-06-15")!;
  // Modal would say "positive", 2 votes to 1. The workout carries the day.
  assertEquals(day.mood, "tired");
});

Deno.test("day mood: falls back to distance when no intensity feature exists", () => {
  const input: TimelineInput = {
    logs: [
      { id: "shakeout", workout_date: "2026-06-15T06:00:00Z", workout_distance_miles: 3, workout_duration_minutes: 27, workout_type: "easy", workout_pace_per_mile: "9:00", mood: "positive" },
      { id: "long", workout_date: "2026-06-15T15:00:00Z", workout_distance_miles: 18, workout_duration_minutes: 145, workout_type: "long", workout_pace_per_mile: "8:03", mood: "struggling" },
    ],
    features: [],
    mentions: [],
  };
  const day = buildDailyTimeline(input, 2, REF).find((d) => d.date === "2026-06-15")!;
  assertEquals(day.mood, "struggling");
});

Deno.test("day mood: a rest-day check-in still colours its day", () => {
  const input: TimelineInput = {
    logs: [
      { id: "checkin", workout_date: "2026-06-12", workout_distance_miles: 0, workout_duration_minutes: 0, workout_type: "check_in", workout_pace_per_mile: null, mood: "energized", source: "check_in" },
    ],
    features: [],
    mentions: [],
  };
  const day = buildDailyTimeline(input, 2, REF).find((d) => d.date === "2026-06-12")!;
  assertEquals(day.type, "rest");
  assertEquals(day.mood, "energized");
});

Deno.test("day mood: a session outranks a mood-only check-in on the same day", () => {
  const input: TimelineInput = {
    logs: [
      { id: "wo", workout_date: "2026-06-15T06:30:00Z", workout_distance_miles: 8, workout_duration_minutes: 52, workout_type: "tempo", workout_pace_per_mile: "6:30", mood: "struggling" },
      { id: "ci", workout_date: "2026-06-15T21:00:00Z", workout_distance_miles: 0, workout_duration_minutes: 0, workout_type: "check_in", workout_pace_per_mile: null, mood: "positive", source: "check_in" },
    ],
    features: [{ training_log_id: "wo", intensity_score: 2.4, total_duration_seconds: 3120 }],
    mentions: [],
  };
  const day = buildDailyTimeline(input, 2, REF).find((d) => d.date === "2026-06-15")!;
  assertEquals(day.mood, "struggling");
});

Deno.test("day mood: never fabricated when a run carries no feeling", () => {
  const input: TimelineInput = {
    logs: [
      { id: "r", workout_date: "2026-06-15", workout_distance_miles: 7, workout_duration_minutes: 55, workout_type: "easy", workout_pace_per_mile: "7:51", mood: null },
    ],
    features: [],
    mentions: [],
  };
  const day = buildDailyTimeline(input, 2, REF).find((d) => d.date === "2026-06-15")!;
  assertEquals(day.miles, 7);
  assertEquals(day.mood, null);
});

Deno.test("week mood stays modal — the rank rule is a day-level rule", () => {
  // One hard "tired" session against four easy "positive" days. The DAY the
  // workout falls on reads tired; the WEEK still reads positive, because a
  // week is a distribution over separate days, not readings of one session.
  const input: TimelineInput = {
    logs: [
      { id: "a", workout_date: "2026-06-09", workout_distance_miles: 6, workout_duration_minutes: 48, workout_type: "easy", workout_pace_per_mile: "8:00", mood: "positive" },
      { id: "b", workout_date: "2026-06-10", workout_distance_miles: 6, workout_duration_minutes: 48, workout_type: "easy", workout_pace_per_mile: "8:00", mood: "positive" },
      { id: "c", workout_date: "2026-06-11", workout_distance_miles: 8, workout_duration_minutes: 52, workout_type: "tempo", workout_pace_per_mile: "6:30", mood: "tired" },
      { id: "d", workout_date: "2026-06-12", workout_distance_miles: 6, workout_duration_minutes: 48, workout_type: "easy", workout_pace_per_mile: "8:00", mood: "positive" },
      { id: "e", workout_date: "2026-06-13", workout_distance_miles: 6, workout_duration_minutes: 48, workout_type: "easy", workout_pace_per_mile: "8:00", mood: "positive" },
    ],
    features: [{ training_log_id: "c", intensity_score: 2.5, total_duration_seconds: 3120 }],
    mentions: [],
  };
  const days = buildDailyTimeline(input, 2, REF);
  assertEquals(days.find((d) => d.date === "2026-06-11")!.mood, "tired");

  const weeks = buildTrendsTimeline(input, 2, REF);
  const week = weeks.find((w) => w.week_start === "2026-06-08")!;
  assertEquals(week.mood, "positive");
});

// ─── Per-day zone breakdown (2026-08-10) ───────────────────────────────
// The week-load surface needs day x 10-zone minutes AND miles. These guard
// the two things that make it trustworthy: easy volume is INCLUDED (unlike
// quality_volume.zone_seconds, which filters to WORK_ZONES), and the split
// reconciles to the day's totals rather than drifting from them.

const ZONES = {
  easy: 480, moderate: 440, steady: 415, mp: 380, hm: 360,
  tenK: 335, fiveK: 320, threeK: 305, mile: 290,
};
const MILE_M = 1609.344;
/** n laps of one mile at `pace` sec/mi. */
const miles = (n: number, pace: number) =>
  Array.from({ length: n }, () => ({
    distance_meters: MILE_M,
    avg_pace_sec_per_mile: pace,
    moving_time_seconds: pace,
  }));

Deno.test("zone breakdown: a long run with an MP block splits, and easy is counted", () => {
  const input: TimelineInput = {
    logs: [{
      id: "L", workout_date: "2026-06-14", workout_distance_miles: 10,
      workout_duration_minutes: 73, workout_type: "long",
      workout_pace_per_mile: "7:20", mood: "tired",
    }],
    features: [],
    mentions: [],
    zones: ZONES,
    lapsByWorkout: new Map([["L", [...miles(6, 480), ...miles(4, 380)]]]),
  };
  const day = buildDailyTimeline(input, 2, REF).find((d) => d.date === "2026-06-14")!;

  // Easy is present. This is the whole point — the existing weekly
  // quality_volume surface would report NOTHING for the 6 easy miles.
  assert(day.zone_minutes !== undefined, "expected a breakdown");
  assertEquals(day.zone_miles!.easy, 6);
  assertEquals(day.zone_miles!.mp, 4);
  assertEquals(day.zone_minutes!.easy, 48);          // 6 x 480s
  assertEquals(day.zone_minutes!.mp, 25.33);         // 4 x 380s

  // Zones with no time are omitted, not zero-filled.
  assertEquals(Object.keys(day.zone_miles!).sort(), ["easy", "mp"]);

  // Reconciliation: the split must equal the day, or the surface is lying.
  const totMi = Object.values(day.zone_miles!).reduce((a, b) => a + b, 0);
  const totMin = Object.values(day.zone_minutes!).reduce((a, b) => a + b, 0);
  assert(Math.abs(totMi - day.miles) < 0.05, `miles drift: ${totMi} vs ${day.miles}`);
  assert(Math.abs(totMin - day.duration_min!) < 1, `minutes drift: ${totMin} vs ${day.duration_min}`);
});

Deno.test("zone breakdown is ABSENT, not empty, when a day's runs carry no laps", () => {
  const input: TimelineInput = {
    logs: [{
      id: "M", workout_date: "2026-06-14", workout_distance_miles: 5,
      workout_duration_minutes: 40, workout_type: "easy",
      workout_pace_per_mile: "8:00", mood: null,
    }],
    features: [],
    mentions: [],
    zones: ZONES,
    lapsByWorkout: new Map(),
  };
  const days = buildDailyTimeline(input, 2, REF);
  const ran = days.find((d) => d.date === "2026-06-14")!;
  const rest = days.find((d) => d.date === "2026-06-12")!;

  // Ran, but we cannot say how it was distributed.
  assertEquals(ran.miles, 5);
  assertEquals(ran.zone_minutes, undefined);
  // A genuine rest day is also absent — the client tells them apart by miles,
  // which is the honest discriminator.
  assertEquals(rest.miles, 0);
  assertEquals(rest.zone_minutes, undefined);
});

Deno.test("zone breakdown degrades to absent when no zone table exists", () => {
  const input: TimelineInput = {
    logs: [{
      id: "N", workout_date: "2026-06-14", workout_distance_miles: 10,
      workout_duration_minutes: 73, workout_type: "long",
      workout_pace_per_mile: "7:20", mood: null,
    }],
    features: [],
    mentions: [],
    lapsByWorkout: new Map([["N", miles(10, 440)]]),
    // zones deliberately omitted — a new athlete with no zone table
  };
  const day = buildDailyTimeline(input, 2, REF).find((d) => d.date === "2026-06-14")!;
  assertEquals(day.zone_minutes, undefined, "must not guess zones without a table");
});
