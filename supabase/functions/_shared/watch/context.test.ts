/**
 * Unit tests for the WatchContext assembler.
 *
 * Run: deno test --allow-all _shared/watch/context.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildWatchContext,
  nextQualityWithinDays,
  paceStringToSec,
  type WatchStateInput,
} from "./context.ts";
import { runWatches } from "./index.ts";

const NOW = new Date("2026-08-24T12:00:00Z");
const ago = (n: number) => new Date(NOW.getTime() - n * 86_400_000).toISOString().slice(0, 10);
const ahead = (n: number) => new Date(NOW.getTime() + n * 86_400_000).toISOString().slice(0, 10);

Deno.test("pace strings parse with or without the /mi suffix", () => {
  assertEquals(paceStringToSec("8:30"), 510);
  assertEquals(paceStringToSec("8:30/mi"), 510);
  assertEquals(paceStringToSec(" 8:30 / mile "), 510);
  assertEquals(paceStringToSec("garbage"), null);
  assertEquals(paceStringToSec(null), null);
});

Deno.test("long runs are not easy days", () => {
  // Folding long runs in would flag nearly every athlete, since a long run
  // sits above easy pace by design.
  const ctx = buildWatchContext({
    user_id: "a-1",
    recent_workouts: [
      { date: ago(1), type: "easy", pace: "9:10/mi" },
      { date: ago(2), type: "long_run", pace: "8:40/mi" },
      { date: ago(3), type: "recovery", pace: "9:40/mi" },
      { date: ago(4), type: "tempo", pace: "6:30/mi" },
    ],
  }, NOW);

  assertEquals(ctx.easyRuns?.length, 2);
  assert(!ctx.easyRuns?.some((r) => r.workoutType === "long_run"));
});

Deno.test("work_pace wins over blended average pace", () => {
  const ctx = buildWatchContext({
    user_id: "a-1",
    recent_workouts: [
      { date: ago(1), type: "easy", pace: "9:00/mi", work_pace: "8:20/mi" },
    ],
  }, NOW);
  assertEquals(ctx.easyRuns?.[0].paceSecPerMile, 500);
});

Deno.test("runs without a parseable pace are dropped, not zeroed", () => {
  const ctx = buildWatchContext({
    user_id: "a-1",
    recent_workouts: [
      { date: ago(1), type: "easy", pace: null },
      { date: ago(2), type: "easy", pace: "9:10/mi" },
    ],
  }, NOW);
  assertEquals(ctx.easyRuns?.length, 1);
});

Deno.test("a missing easy band stays null rather than defaulting", () => {
  // feedback_no_hardcoded_paces — the watch goes blind and says so.
  const ctx = buildWatchContext({ user_id: "a-1" }, NOW);
  assertEquals(ctx.easyBand, null);
  assertEquals(ctx.zonePct7d, null);
  assertEquals(ctx.niggles, null);
});

Deno.test("nearest upcoming quality session wins; past ones are ignored", () => {
  const upcoming = [
    { date: ahead(6), workout_type: "intervals" },
    { date: ahead(2), workout_type: "tempo" },
    { date: ahead(1), workout_type: "easy" },
    { date: ago(1), workout_type: "tempo" },
  ];
  assertEquals(nextQualityWithinDays(upcoming, NOW), 2);
});

Deno.test("no quality on the calendar reads as null, not zero", () => {
  assertEquals(nextQualityWithinDays([{ date: ahead(2), workout_type: "easy" }], NOW), null);
  assertEquals(nextQualityWithinDays([], NOW), null);
  assertEquals(nextQualityWithinDays(null, NOW), null);
});

Deno.test("loose scheduled rows don't crash the assembler", () => {
  const upcoming = [
    {},
    { date: 12345, workout_type: "tempo" },
    { workout_date: ahead(3), type: "intervals" },
  ] as Array<Record<string, unknown>>;
  assertEquals(nextQualityWithinDays(upcoming, NOW), 3);
});

// ─── End to end ──────────────────────────────────────────────────────────────

Deno.test("state in, findings out", () => {
  const state: WatchStateInput = {
    user_id: "a-1",
    recent_workouts: [
      { date: ago(1), type: "easy", mood: "tired", pace: "8:20/mi" },
      { date: ago(3), type: "easy", mood: "struggling", pace: "8:15/mi" },
      { date: ago(5), type: "easy", mood: "tired", pace: "8:10/mi" },
      { date: ago(9), type: "easy", mood: "tired", pace: "8:30/mi" },
      { date: ago(15), type: "easy", mood: "positive", pace: "9:20/mi" },
      { date: ago(20), type: "easy", mood: "energized", pace: "9:15/mi" },
      { date: ago(26), type: "easy", mood: "positive", pace: "9:10/mi" },
      { date: ago(31), type: "easy", mood: "energized", pace: "9:20/mi" },
    ],
    pace_zone_ranges: { easy: { paceFast: 540, paceSlow: 600 } },
    load_distribution: {
      zone_pct_7d: { easy: 52, moderate: 33, threshold: 10, hard: 5 },
    },
    niggle_recurrence: [{
      body_area: "calf",
      side: "left",
      occurrences: 3,
      first_seen: ago(30),
      last_seen: ago(2),
      worst_severity: "sore",
      status: "active",
      resolved_at: null,
    }],
    upcoming_workouts: [{ date: ahead(2), workout_type: "intervals" }],
  };

  const sweep = runWatches(buildWatchContext(state, NOW));

  // All three domains should have something to say about this athlete: mood
  // sliding, easy days quick, calf recurring with quality two days out.
  const domains = sweep.findings.map((f) => f.domain);
  assert(domains.includes("recovery"), "recovery watch should fire");
  assert(domains.includes("pace"), "pace watch should fire");
  assert(domains.includes("niggles"), "niggle watch should fire");

  // Loudest first, and the recurring calf with quality imminent is loudest.
  assertEquals(sweep.findings[0].domain, "niggles");
  assertEquals(sweep.findings[0].severity, "high");
  assertEquals(sweep.findings[0].suggested, "pause_quality");

  // Every finding cites real numbers.
  for (const f of sweep.findings) {
    assert(f.evidence.length > 0, `${f.watch_id} produced no evidence`);
  }
});

Deno.test("an empty athlete produces gaps, and no findings at all", () => {
  const sweep = runWatches(buildWatchContext({ user_id: "new-1" }, NOW));
  assertEquals(sweep.findings.length, 0);
  assert(sweep.gaps.length >= 2, "a new athlete is mostly blind spots");
  // Critically: not reported as all-clear.
  assert(!sweep.clear.includes("recovery_trend"));
});
