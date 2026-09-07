/**
 * Tests for the watch-splits helpers in coach-context.ts — specifically the
 * MILE-SPLIT GUARD added 2026-08-06.
 *
 * Regression anchor: a 5×4:00 threshold session (reps at 5:18–5:23/mi with
 * short recoveries) synced from Strava as per-mile `pace_segments` tagged
 * "fast"/"steady". classifyEffortKind treats those as "work", and the old
 * labeling presented them to the LLM as "Rep 1..4" at 6:25–7:25/mi — the
 * model then narrated "actual 4×1 mile reps", contradicting the athlete.
 *
 * Run: deno test _shared/coach-context-splits.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  splitsFromLaps,
  splitsFromPaceSegments,
  splitsFromParsedBlocks,
} from "./coach-context.ts";

// ── splitsFromPaceSegments: the mile-split guard ─────────────────────────

Deno.test("mile splits from Strava sync are labeled Mile N, never Rep N", () => {
  // Shape strava-sync's splitsToPaceSegments emits for the Aug 6 session:
  // whole-mile averages of work + recovery, trailing partial mile.
  const segments = [
    { effort: "fast", distance_miles: 1.0, pace_per_mile: "6:25", avg_heart_rate: 152 },
    { effort: "steady", distance_miles: 1.0, pace_per_mile: "6:52", avg_heart_rate: 158 },
    { effort: "fast", distance_miles: 1.0, pace_per_mile: "6:34", avg_heart_rate: 148 },
    { effort: "steady", distance_miles: 1.0, pace_per_mile: "7:25", avg_heart_rate: 150 },
    { effort: "easy", distance_miles: 0.16, pace_per_mile: "8:10", avg_heart_rate: 135 },
  ];
  const out = splitsFromPaceSegments(segments);
  assertEquals(out.map((s) => s.label), ["Mile 1", "Mile 2", "Mile 3", "Mile 4", "Mile 5"]);
  assert(out.every((s) => !s.label.startsWith("Rep")), "no mile split may be labeled a rep");
});

Deno.test("guard tolerates GPS jitter around 1.00 mi", () => {
  const segments = [
    { effort: "steady", distance_miles: 0.99, pace_per_mile: "7:00" },
    { effort: "steady", distance_miles: 1.01, pace_per_mile: "7:05" },
    { effort: "steady", distance_miles: 1.04, pace_per_mile: "7:10" },
  ];
  const out = splitsFromPaceSegments(segments);
  assertEquals(out.map((s) => s.label), ["Mile 1", "Mile 2", "Mile 3"]);
});

Deno.test("genuine sub-mile rep segments keep Rep labels", () => {
  // A 6×800m session stored as pace_segments (e.g. voice-derived): distances
  // are nowhere near 1.00 mi, so the guard must not fire.
  const segments = Array.from({ length: 6 }, () => ({
    effort: "interval",
    distance_miles: 0.5,
    pace_per_mile: "5:40",
  }));
  const out = splitsFromPaceSegments(segments);
  assertEquals(out[0].label, "Rep 1");
  assertEquals(out[5].label, "Rep 6");
});

Deno.test("mixed-distance rep segments keep Rep labels", () => {
  // 2mi + 1mi + 2mi alternation — not uniform miles, so still reps.
  const segments = [
    { effort: "tempo", distance_miles: 2.0, pace_per_mile: "6:10" },
    { effort: "tempo", distance_miles: 1.0, pace_per_mile: "5:55" },
    { effort: "tempo", distance_miles: 2.0, pace_per_mile: "6:12" },
  ];
  const out = splitsFromPaceSegments(segments);
  assertEquals(out.map((s) => s.label), ["Rep 1", "Rep 2", "Rep 3"]);
});

Deno.test("warmup/cooldown labels survive the guard", () => {
  const segments = [
    { effort: "warmup", distance_miles: 1.0, pace_per_mile: "8:30" },
    { effort: "fast", distance_miles: 1.0, pace_per_mile: "6:20" },
    { effort: "fast", distance_miles: 1.0, pace_per_mile: "6:25" },
    { effort: "cooldown", distance_miles: 1.0, pace_per_mile: "8:45" },
  ];
  const out = splitsFromPaceSegments(segments);
  assertEquals(out.map((s) => s.label), ["Warmup", "Mile 1", "Mile 2", "Cooldown"]);
});

Deno.test("guard is pace-independent — a 12:00/mi runner's mile splits still read Mile N", () => {
  // Same guard, four-times-slower athlete. The guard keys on DISTANCE only;
  // no pace value can change the outcome.
  const segments = [
    { effort: "steady", distance_miles: 1.0, pace_per_mile: "11:45" },
    { effort: "fast", distance_miles: 1.0, pace_per_mile: "10:58" },
    { effort: "steady", distance_miles: 1.0, pace_per_mile: "12:20" },
    { effort: "easy", distance_miles: 0.4, pace_per_mile: "13:05" },
  ];
  const out = splitsFromPaceSegments(segments);
  assertEquals(out.map((s) => s.label), ["Mile 1", "Mile 2", "Mile 3", "Mile 4"]);
});

Deno.test("kilometer splits are recognized and labeled Km N", () => {
  // A km-based source: uniform ~0.62 mi segments must not be called reps.
  const segments = [
    { effort: "fast", distance_miles: 0.62, pace_per_mile: "9:10" },
    { effort: "steady", distance_miles: 0.62, pace_per_mile: "9:40" },
    { effort: "fast", distance_miles: 0.62, pace_per_mile: "9:05" },
    { effort: "steady", distance_miles: 0.63, pace_per_mile: "9:52" },
  ];
  const out = splitsFromPaceSegments(segments);
  assertEquals(out.map((s) => s.label), ["Km 1", "Km 2", "Km 3", "Km 4"]);
});

// ── splitsFromLaps: the source the memo prompt should now prefer ─────────

Deno.test("laps yield true rep structure with recoveries dropped", () => {
  // The Aug 6 session as the watch recorded it: 5 work laps ~0.75 mi @ 4:00
  // with flagged recovery laps between.
  const mi = 1609.34;
  const laps = [
    { lap_index: 1, distance_meters: 0.76 * mi, moving_time_seconds: 240, avg_pace_sec_per_mile: 318, is_rest: false },
    { lap_index: 2, distance_meters: 0.09 * mi, moving_time_seconds: 97, avg_pace_sec_per_mile: 1058, is_rest: true },
    { lap_index: 3, distance_meters: 0.75 * mi, moving_time_seconds: 241, avg_pace_sec_per_mile: 322, is_rest: false },
    { lap_index: 4, distance_meters: 0.06 * mi, moving_time_seconds: 112, avg_pace_sec_per_mile: 1844, is_rest: true },
    { lap_index: 5, distance_meters: 0.76 * mi, moving_time_seconds: 241, avg_pace_sec_per_mile: 318, is_rest: false },
    { lap_index: 6, distance_meters: 0.08 * mi, moving_time_seconds: 95, avg_pace_sec_per_mile: 1261, is_rest: true },
    { lap_index: 7, distance_meters: 0.74 * mi, moving_time_seconds: 239, avg_pace_sec_per_mile: 321, is_rest: false },
    { lap_index: 8, distance_meters: 0.04 * mi, moving_time_seconds: 133, avg_pace_sec_per_mile: 3518, is_rest: true },
    { lap_index: 9, distance_meters: 0.74 * mi, moving_time_seconds: 240, avg_pace_sec_per_mile: 323, is_rest: false },
  ];
  const out = splitsFromLaps(laps);
  assertEquals(out.length, 5, "five work reps, recoveries dropped");
  assertEquals(out.map((s) => s.label), ["Rep 1", "Rep 2", "Rep 3", "Rep 4", "Rep 5"]);
  // Every rep pace must read as the athlete ran it (5:18–5:23), not mile-blur.
  for (const s of out) {
    assert(s.paceSecPerMile >= 315 && s.paceSecPerMile <= 325, `rep pace ${s.paceSecPerMile} out of band`);
  }
});

Deno.test("jogged recoveries the absolute is_rest heuristic misses are still filtered", () => {
  // A mid-pack runner: 1k reps at 7:00/mi with 400m jog recoveries at
  // 12:00/mi. The recoveries are ≥200m AND faster than 2.0 m/s, so the
  // generated is_rest column does NOT flag them. The relative filter
  // (>1.5× the fastest lap) must drop them anyway — a ratio, not an
  // absolute pace, so it works at any athlete speed.
  const laps = [
    { lap_index: 1, distance_meters: 1000, moving_time_seconds: 261, avg_pace_sec_per_mile: 420, is_rest: false },
    { lap_index: 2, distance_meters: 400, moving_time_seconds: 179, avg_pace_sec_per_mile: 720, is_rest: false },
    { lap_index: 3, distance_meters: 1000, moving_time_seconds: 263, avg_pace_sec_per_mile: 424, is_rest: false },
    { lap_index: 4, distance_meters: 400, moving_time_seconds: 181, avg_pace_sec_per_mile: 728, is_rest: false },
    { lap_index: 5, distance_meters: 1000, moving_time_seconds: 262, avg_pace_sec_per_mile: 422, is_rest: false },
  ];
  const out = splitsFromLaps(laps);
  assertEquals(out.length, 3, "three work reps; unflagged jog recoveries dropped");
  for (const s of out) assert(s.paceSecPerMile < 500, "no recovery pace may survive as a rep");
});

Deno.test("an even easy run is untouched by the relative filter", () => {
  // No recovery structure: paces within a normal easy-run spread. The filter
  // must not eat anything (all laps well under 1.5× the fastest).
  const laps = Array.from({ length: 6 }, (_, i) => ({
    lap_index: i + 1,
    distance_meters: 1609,
    moving_time_seconds: 570 + i * 12,
    avg_pace_sec_per_mile: 570 + i * 12, // 9:30 → 10:30
    is_rest: false,
  }));
  const out = splitsFromLaps(laps);
  assertEquals(out.length, 6);
});

// ── splitsFromParsedBlocks: highest-fidelity source, now shared ──────────

Deno.test("parsed blocks map roles to warmup/work/cooldown with Rep labels", () => {
  const blocks = [
    { role: "warmup", distance_miles: 1.0, avg_pace_per_mile: "10:45" },
    { role: "work_rep", rep_num: 1, distance_miles: 0.62, avg_pace_per_mile: "8:05", avg_hr: 165 },
    { role: "recovery", distance_miles: 0.25, avg_pace_per_mile: "12:30" },
    { role: "work_rep", rep_num: 2, distance_miles: 0.62, avg_pace_per_mile: "8:10", avg_hr: 168 },
    { role: "cooldown", distance_miles: 0.8, avg_pace_per_mile: "11:00" },
  ];
  const out = splitsFromParsedBlocks(blocks);
  assertEquals(out.map((s) => s.label), ["warmup", "Rep 1", "recovery", "Rep 2", "cooldown"]);
  assertEquals(out.map((s) => s.effortKind), ["warmup", "work", "unknown", "work", "cooldown"]);
});

// ── laps-based pace_segments (2026-08-20) ────────────────────────────────
// Once `pace_segments` is built from the watch's laps rather than per-mile
// splits, recoveries arrive as their own rows. Two things must hold: they are
// never counted as reps, and their presence proves the work bouts really are
// reps, so the mile guard must stand down.

Deno.test("recovery segments are labeled Recovery, never Rep N", () => {
  const segments = [
    { effort: "fast", distance_miles: 1.01, pace_per_mile: "5:23", avg_heart_rate: 164 },
    { effort: "recovery", distance_miles: 0.1, pace_per_mile: "23:31", avg_heart_rate: 158 },
    { effort: "steady", distance_miles: 1.01, pace_per_mile: "5:31", avg_heart_rate: 171 },
  ];
  const out = splitsFromPaceSegments(segments);
  assertEquals(out.map((s) => s.label), ["Rep 1", "Recovery", "Rep 2"]);
  assertEquals(out.filter((s) => s.effortKind === "work").length, 2);
});

Deno.test("explicit recoveries stand the mile guard down for real mile reps", () => {
  // 2026-08-18: 6×1mi off the laps. Uniform ~1 mi, but with rests between —
  // which the mile guard must read as rep structure, not as mile splits.
  const segments = [
    { effort: "fast", distance_miles: 1.01, pace_per_mile: "5:23" },
    { effort: "steady", distance_miles: 1.02, pace_per_mile: "5:31" },
    { effort: "recovery", distance_miles: 0.1, pace_per_mile: "23:31" },
    { effort: "fast", distance_miles: 1.01, pace_per_mile: "5:18" },
    { effort: "steady", distance_miles: 1.01, pace_per_mile: "5:35" },
    { effort: "recovery", distance_miles: 0.08, pace_per_mile: "31:55" },
    { effort: "steady", distance_miles: 1.01, pace_per_mile: "5:27" },
    { effort: "steady", distance_miles: 1.01, pace_per_mile: "5:36" },
  ];
  const out = splitsFromPaceSegments(segments);
  const work = out.filter((s) => s.effortKind === "work");
  assertEquals(work.map((s) => s.label), ["Rep 1", "Rep 2", "Rep 3", "Rep 4", "Rep 5", "Rep 6"]);
  assert(!out.some((s) => s.label.startsWith("Mile")), "no mile relabel when rests are present");
});

Deno.test("the mile guard still fires on split-derived segments with no rests", () => {
  // Same session as it used to arrive: mile splits, no recovery rows. The
  // 2026-08-06 guard must keep working for anything still on that path.
  const segments = [
    { effort: "fast", distance_miles: 1.0, pace_per_mile: "5:24" },
    { effort: "steady", distance_miles: 1.0, pace_per_mile: "5:29" },
    { effort: "easy", distance_miles: 1.0, pace_per_mile: "6:54" },
    { effort: "steady", distance_miles: 1.0, pace_per_mile: "5:34" },
    { effort: "easy", distance_miles: 0.22, pace_per_mile: "5:51" },
  ];
  const out = splitsFromPaceSegments(segments);
  assert(out.every((s) => !s.label.startsWith("Rep")), "mile splits are never reps");
  assertEquals(out[0].label, "Mile 1");
});
