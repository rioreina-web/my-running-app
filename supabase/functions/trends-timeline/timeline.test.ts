/**
 * Tests for timeline.ts — the Trends weekly bucketing.
 * Run: deno test supabase/functions/trends-timeline/timeline.test.ts
 *
 * No LLM in this path, so no eval cassette is required (the eval gate
 * fires only on `_shared/prompts/` changes). These guard the pure math:
 * Mon–Sun bucketing, quality classification, modal mood, niggle
 * windowing, and cross-training exclusion.
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildTrendsTimeline,
  buildWeekWindows,
  flaggedRuns,
  trimmedRuns,
  parsePaceToSec,
  type TimelineInput,
} from "./timeline.ts";

// Reference = Mon 2026-06-15 (a Monday) so windows are clean.
const REF = new Date("2026-06-15T12:00:00Z");

Deno.test("parsePaceToSec parses M:SS and rejects junk", () => {
  assertEquals(parsePaceToSec("6:41"), 401);
  assertEquals(parsePaceToSec("10:00"), 600);
  assertEquals(parsePaceToSec(null), null);
  assertEquals(parsePaceToSec("abc"), null);
  assertEquals(parsePaceToSec("6:7"), null);
});

Deno.test("buildWeekWindows returns N consecutive Mon–Sun windows ending this week", () => {
  const w = buildWeekWindows(12, REF);
  assertEquals(w.length, 12);
  // Last window starts on the reference Monday.
  assertEquals(w[11].start.toISOString().split("T")[0], "2026-06-15");
  // Each window is exactly 7 days.
  for (const win of w) {
    const days = (win.end.getTime() - win.start.getTime()) / (24 * 3600 * 1000);
    assertEquals(days, 7);
  }
  // Consecutive.
  assertEquals(w[10].end.getTime(), w[11].start.getTime());
});

Deno.test("buckets miles into the correct week and excludes cross-training", () => {
  const input: TimelineInput = {
    logs: [
      // This week (Mon 6/15)
      { id: "a", workout_date: "2026-06-15", workout_distance_miles: 8, workout_duration_minutes: 60, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "positive" },
      { id: "b", workout_date: "2026-06-17", workout_distance_miles: 6, workout_duration_minutes: 41, workout_type: "tempo", workout_pace_per_mile: "6:50", mood: "tired" },
      // Cross-training should NOT count toward miles.
      { id: "c", workout_date: "2026-06-16", workout_distance_miles: 12, workout_duration_minutes: 45, workout_type: "cross_training", workout_pace_per_mile: null, mood: "neutral" },
      // Previous week
      { id: "d", workout_date: "2026-06-09", workout_distance_miles: 10, workout_duration_minutes: 75, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "energized" },
    ],
    features: [],
    mentions: [],
  };
  const out = buildTrendsTimeline(input, 2, REF);
  assertEquals(out.length, 2);

  const prev = out[0];
  const cur = out[1];
  assertEquals(cur.week_start, "2026-06-15");
  assertEquals(cur.miles, 14); // 8 + 6, NOT 12 cross-train
  assertEquals(prev.miles, 10);
});

Deno.test("quality volume: whole-run fallback counts MP-or-faster runs only", () => {
  // MP = 6:40. Quality is measured against the athlete's own MP anchor, NOT by
  // classifying the whole workout via intensity_score (which used to count a
  // rep session's recoveries and miss a long run's MP block entirely).
  const input: TimelineInput = {
    logs: [
      { id: "easy1", workout_date: "2026-06-15", workout_distance_miles: 8, workout_duration_minutes: 60, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "positive" },
      { id: "hard1", workout_date: "2026-06-17", workout_distance_miles: 6, workout_duration_minutes: 40, workout_type: "run", workout_pace_per_mile: "6:40", mood: "tired" },
    ],
    features: [
      { training_log_id: "hard1", intensity_score: 3.0, total_duration_seconds: 2400 },
      { training_log_id: "easy1", intensity_score: 1.0, total_duration_seconds: 3600 },
    ],
    mentions: [],
    mpSecPerMile: 400, // 6:40
  };
  const out = buildTrendsTimeline(input, 1, REF);
  assertEquals(out[0].quality_miles, 6); // hard1 at MP; easy1 at 7:30 is aerobic
  assertEquals(out[0].key_pace_sec, 400);
});

Deno.test("quality volume: no MP anchor → 0, never guessed from the athlete's average", () => {
  const input: TimelineInput = {
    logs: [
      { id: "hard1", workout_date: "2026-06-17", workout_distance_miles: 6, workout_duration_minutes: 40, workout_type: "run", workout_pace_per_mile: "6:40", mood: "tired" },
    ],
    features: [{ training_log_id: "hard1", intensity_score: 3.0, total_duration_seconds: 2400 }],
    mentions: [],
    // no mpSecPerMile
  };
  const out = buildTrendsTimeline(input, 1, REF);
  assertEquals(out[0].quality_miles, 0);
});

Deno.test("quality volume: reps count, recoveries do not", () => {
  // A 3-mile session: 2 × 1mi reps at 6:00, with 0.5mi jogs at 9:00 between.
  // The old rule counted all 3 miles (whole workout classified quality).
  const input: TimelineInput = {
    logs: [
      {
        id: "reps",
        workout_date: "2026-06-17",
        workout_distance_miles: 3,
        workout_duration_minutes: 21,
        workout_type: "intervals",
        workout_pace_per_mile: "7:00",
        mood: "positive",
        pace_segments: [
          { distance_miles: 1, pace_per_mile: "6:00", duration_seconds: 360 },
          { distance_miles: 0.5, pace_per_mile: "9:00", duration_seconds: 270 },
          { distance_miles: 1, pace_per_mile: "6:00", duration_seconds: 360 },
          { distance_miles: 0.5, pace_per_mile: "9:00", duration_seconds: 270 },
        ],
      },
    ],
    features: [],
    mentions: [],
    mpSecPerMile: 400, // 6:40
  };
  const out = buildTrendsTimeline(input, 1, REF);
  assertEquals(out[0].miles, 3);
  assertEquals(out[0].quality_miles, 2); // the two reps, not the jogs
});

Deno.test("quality volume: rep-level laps beat blurred mile splits", () => {
  // One mile split holding a 5:10 rep + a 9:00 float averages ~7:05 — slower
  // than MP, so mile splits score this session ZERO. The laps see the rep.
  const input: TimelineInput = {
    logs: [
      {
        id: "blurred",
        workout_date: "2026-06-17",
        workout_distance_miles: 2,
        workout_duration_minutes: 14,
        workout_type: "intervals",
        workout_pace_per_mile: "7:00",
        mood: "positive",
        pace_segments: [
          { distance_miles: 1, pace_per_mile: "7:05", duration_seconds: 425 },
          { distance_miles: 1, pace_per_mile: "7:05", duration_seconds: 425 },
        ],
      },
    ],
    features: [],
    mentions: [],
    mpSecPerMile: 400,
    lapsByWorkout: new Map([[
      "blurred",
      [
        { distance_meters: 804.672, avg_pace_sec_per_mile: 310, moving_time_seconds: 155 }, // 0.5mi rep @ 5:10
        { distance_meters: 804.672, avg_pace_sec_per_mile: 540, moving_time_seconds: 270 }, // 0.5mi float @ 9:00
        { distance_meters: 804.672, avg_pace_sec_per_mile: 310, moving_time_seconds: 155 },
        { distance_meters: 804.672, avg_pace_sec_per_mile: 540, moving_time_seconds: 270 },
      ],
    ]]),
  };
  const out = buildTrendsTimeline(input, 1, REF);
  // Laps win: the two 0.5mi reps = 1.0 quality mi. Mile splits would give 0.
  assertEquals(out[0].quality_miles, 1);
});

Deno.test("modal mood; no logs → null (never fabricated)", () => {
  const input: TimelineInput = {
    logs: [
      { id: "a", workout_date: "2026-06-15", workout_distance_miles: 6, workout_duration_minutes: 45, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "tired" },
      { id: "b", workout_date: "2026-06-16", workout_distance_miles: 6, workout_duration_minutes: 45, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "tired" },
      { id: "c", workout_date: "2026-06-17", workout_distance_miles: 6, workout_duration_minutes: 45, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "positive" },
    ],
    features: [],
    mentions: [],
  };
  const out = buildTrendsTimeline(input, 2, REF);
  assertEquals(out[1].mood, "tired"); // modal
  assertEquals(out[0].mood, null); // empty week, no fabrication
  assertEquals(out[0].key_pace_sec, null);
});

Deno.test("dedup: same run from multiple sources counts once (GPS wins)", () => {
  const input: TimelineInput = {
    logs: [
      // Tue: one physical interval session, logged by voice + strava
      { id: "v1", workout_date: "2026-06-09", workout_distance_miles: 11.4, workout_duration_minutes: 80, workout_type: "interval", workout_pace_per_mile: null, mood: "tired", source: "voice_log" },
      { id: "s1", workout_date: "2026-06-09", workout_distance_miles: 10.4, workout_duration_minutes: 72, workout_type: "intervals", workout_pace_per_mile: "6:55", mood: null, source: "strava" },
      // Wed: same easy run via strava + healthkit auto_sync (same distance)
      { id: "s2", workout_date: "2026-06-10", workout_distance_miles: 7.4, workout_duration_minutes: 55, workout_type: "easy", workout_pace_per_mile: "7:26", mood: "positive", source: "strava" },
      { id: "a2", workout_date: "2026-06-10", workout_distance_miles: 7.4, workout_duration_minutes: 55, workout_type: "easy", workout_pace_per_mile: null, mood: null, source: "auto_sync" },
    ],
    features: [],
    mentions: [],
  };
  const out = buildTrendsTimeline(input, 2, REF); // Jun 8 + Jun 15 weeks
  // Tue: voice_log dropped (GPS present) → 10.4; Wed: strava beats auto_sync → 7.4
  assertEquals(out[0].miles, 17.8); // 10.4 + 7.4, NOT 11.4+10.4+7.4+7.4 (37.6)
});

Deno.test("plausibility: watch-not-paused run is excluded from miles and flagged", () => {
  const input: TimelineInput = {
    logs: [
      { id: "ok", workout_date: "2026-06-09", workout_distance_miles: 8, workout_duration_minutes: 60, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "positive", source: "strava" },
      // 26 mi at 22:00/mi — watch left running
      { id: "bad", workout_date: "2026-06-10", workout_distance_miles: 26, workout_duration_minutes: 572, workout_type: "easy", workout_pace_per_mile: null, mood: null, source: "strava" },
    ],
    features: [],
    mentions: [],
  };
  const out = buildTrendsTimeline(input, 2, REF); // Jun 8 + Jun 15 weeks
  assertEquals(out[0].miles, 8); // garbage 26mi excluded
  const flags = flaggedRuns(input.logs);
  assertEquals(flags.length, 1);
  assertEquals(flags[0].training_log_id, "bad");
  assert(flags[0].reason.length > 0);
});

Deno.test("athlete decision overrides heuristic: keep counts, trim excludes", () => {
  const input: TimelineInput = {
    logs: [
      // implausible by heuristic, but athlete KEPT it (stats_excluded=false) → counts, not flagged
      { id: "kept", workout_date: "2026-06-09", workout_distance_miles: 26, workout_duration_minutes: 572, workout_type: "long_run", workout_pace_per_mile: null, mood: null, source: "strava", stats_excluded: false },
      // plausible, but athlete TRIMMED it (stats_excluded=true) → excluded + in trimmed
      { id: "trim", workout_date: "2026-06-10", workout_distance_miles: 8, workout_duration_minutes: 60, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "tired", source: "strava", stats_excluded: true },
    ],
    features: [],
    mentions: [],
  };
  const out = buildTrendsTimeline(input, 2, REF);
  assertEquals(out[0].miles, 26);          // kept run counts despite heuristic
  assertEquals(flaggedRuns(input.logs).length, 0); // decided → not flagged
  const trimmed = trimmedRuns(input.logs);
  assertEquals(trimmed.length, 1);
  assertEquals(trimmed[0].training_log_id, "trim");
});

Deno.test("niggles windowed, distinct, with representative quote by severity", () => {
  const input: TimelineInput = {
    logs: [
      { id: "a", workout_date: "2026-06-16", workout_distance_miles: 6, workout_duration_minutes: 45, workout_type: "easy", workout_pace_per_mile: "7:30", mood: "tired" },
    ],
    features: [],
    mentions: [
      { body_area: "achilles", side: "R", verbatim_quote: "tight on the warm-up", severity_hint: "tight", mentioned_at: "2026-06-16" },
      { body_area: "achilles", side: "R", verbatim_quote: "sharp twinge late", severity_hint: "sharp", mentioned_at: "2026-06-17" },
      { body_area: "hip", side: "L", verbatim_quote: "a little sore", severity_hint: "sore", mentioned_at: "2026-06-18" },
      // Out of window (previous week) — must not appear in current week.
      { body_area: "knee", side: "L", verbatim_quote: "old thing", severity_hint: "tight", mentioned_at: "2026-06-09" },
    ],
  };
  const out = buildTrendsTimeline(input, 2, REF);
  assertEquals(out[1].niggles, ["R achilles", "L hip"]); // distinct, dated order
  assertEquals(out[1].voice_quote, "sharp twinge late"); // highest severity
  assertEquals(out[0].niggles, ["L knee"]); // previous week
});
