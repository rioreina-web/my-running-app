/**
 * Tests for paceSegments.ts — the laps-over-mile-splits change (2026-08-20).
 *
 * Regression anchor: the Trends pace spectrum showed 1.6 mi total at
 * 5:12–5:22/mi across a 4-week window, while the single 2026-08-18 session
 * below actually held ~1.4 mi in that band. The mile splits reported that
 * session as 5:24 / 5:29 / 5:34 / 5:33; the laps report it as 5:23 / 5:31 /
 * 5:18 / 5:35 / 5:27 / 5:36 with the standing rests broken out.
 *
 * Fixtures are REAL Strava lap payloads for those two sessions, not invented
 * numbers — if the shape of what we store changes, these should fail.
 *
 * Run: deno test _shared/paceSegments.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildPaceSegments,
  isRestLap,
  lapsAreUsable,
  lapsToPaceSegments,
  METERS_PER_MILE,
  paceStringFromSec,
  splitsToPaceSegments,
  type StravaLapLike,
} from "./paceSegments.ts";

const mi = (m: number) => m * METERS_PER_MILE;

/**
 * 2026-08-18 — 6×1mi with short standing rests. Activity: 10018 m, 4.5516 m/s.
 * Distances are `moving_time × average_speed`, the way Strava reports them, so
 * the derived pace matches the watch to the second.
 */
const AUG18_LAPS: StravaLapLike[] = [
  { lap_index: 1, distance: 1624.3, moving_time: 326, average_speed: 4.9825, average_heartrate: 164 },
  { lap_index: 2, distance: 1633.7, moving_time: 336, average_speed: 4.8621, average_heartrate: 171 },
  { lap_index: 3, distance: 166.5, moving_time: 146, average_speed: 1.1405, average_heartrate: 158 },
  { lap_index: 4, distance: 1624.5, moving_time: 321, average_speed: 5.0608, average_heartrate: 171 },
  { lap_index: 5, distance: 1618.9, moving_time: 337, average_speed: 4.8040, average_heartrate: 163 },
  { lap_index: 6, distance: 126.1, moving_time: 150, average_speed: 0.8404, average_heartrate: 160 },
  { lap_index: 7, distance: 1619.2, moving_time: 329, average_speed: 4.9215, average_heartrate: 171 },
  { lap_index: 8, distance: 1618.9, moving_time: 338, average_speed: 4.7897, average_heartrate: 169 },
];
const AUG18_AVG_SPEED = 4.5516;
const AUG18_DISTANCE_M = 10018;

/** The per-mile splits the SAME session produced — what we used to store. */
const AUG18_MILE_SPLITS = [
  { distance: mi(1), moving_time: 324, average_speed: 4.967, average_heartrate: 164, split: 1 },
  { distance: mi(1), moving_time: 330, average_speed: 4.877, average_heartrate: 171, split: 2 },
  { distance: mi(1), moving_time: 413, average_speed: 3.897, average_heartrate: 158, split: 3 },
  { distance: mi(1), moving_time: 334, average_speed: 4.818, average_heartrate: 171, split: 4 },
  { distance: mi(1), moving_time: 388, average_speed: 4.148, average_heartrate: 163, split: 5 },
  { distance: mi(1), moving_time: 333, average_speed: 4.833, average_heartrate: 171, split: 6 },
  { distance: mi(0.22), moving_time: 79, average_speed: 4.583, average_heartrate: 169, split: 7 },
];

/** 2026-08-11 — 10×1000m, rests are tiny standing laps. */
const AUG11_LAPS: StravaLapLike[] = [
  { lap_index: 1, distance: mi(0.62), moving_time: 197, average_speed: 5.063 },
  { lap_index: 2, distance: mi(0.05), moving_time: 67, average_speed: 1.170 },
  { lap_index: 3, distance: mi(0.63), moving_time: 194, average_speed: 5.193 },
  { lap_index: 4, distance: mi(0.05), moving_time: 66, average_speed: 1.111 },
  { lap_index: 5, distance: mi(0.63), moving_time: 197, average_speed: 5.127 },
  { lap_index: 6, distance: mi(0.06), moving_time: 66, average_speed: 1.511 },
];

// ── the headline regression ──────────────────────────────────────────────

Deno.test("laps preserve rep pace that mile splits smear away", () => {
  const fromLaps = lapsToPaceSegments(AUG18_LAPS, AUG18_AVG_SPEED);
  const work = fromLaps.filter((s) => s.effort !== "recovery");
  assertEquals(work.length, 6, "six reps");
  assertEquals(
    work.map((s) => s.pace_per_mile),
    ["5:23", "5:31", "5:18", "5:35", "5:27", "5:36"],
  );

  // The old path, same session: every rep reads slower, and two miles land a
  // full minute off because they swallowed a rest.
  const fromSplits = splitsToPaceSegments(AUG18_MILE_SPLITS, AUG18_AVG_SPEED);
  assert(
    fromSplits.some((s) => s.pace_per_mile.startsWith("6:")),
    "mile splits contain a 6:xx mile that no rep was actually run at",
  );

  // What the spectrum counts: miles at 5:10–5:30 pace.
  const inBand = (segs: typeof fromLaps) =>
    segs.filter((s) => {
      const [m, sec] = s.pace_per_mile.split(":").map(Number);
      const p = m * 60 + sec;
      return p >= 310 && p <= 330;
    }).reduce((a, s) => a + s.distance_miles, 0);
  assert(
    inBand(fromLaps) > inBand(fromSplits),
    `laps must credit more fast volume than splits (${inBand(fromLaps)} vs ${inBand(fromSplits)})`,
  );
  assert(inBand(fromLaps) >= 2, "the 5:10–5:30 band holds real miles on this day");
});

// ── rest handling ────────────────────────────────────────────────────────

Deno.test("standing rests are tagged recovery, never dropped", () => {
  const segs = lapsToPaceSegments(AUG18_LAPS, AUG18_AVG_SPEED);
  assertEquals(segs.length, AUG18_LAPS.length, "every lap survives");
  assertEquals(segs.filter((s) => s.effort === "recovery").length, 2);

  // Distances still sum to the run — the spectrum sums these.
  const total = segs.reduce((a, s) => a + s.distance_miles, 0);
  const expected = AUG18_DISTANCE_M / METERS_PER_MILE;
  assert(Math.abs(total - expected) < 0.05, `segments sum to the run (${total} vs ${expected})`);
});

Deno.test("isRestLap mirrors the running_workout_laps generated column", () => {
  assert(isRestLap(150, 4.0), "under 200 m is a rest whatever the speed");
  assert(isRestLap(400, 1.5), "under 2.0 m/s is a rest whatever the distance");
  assert(!isRestLap(400, 4.0), "a real 400 m rep is not a rest");
  // Boundary: the column uses strict <, so exactly 200 m / 2.0 m/s is work.
  assert(!isRestLap(200, 2.0));
});

Deno.test("short recovery jogs on a 1000m session read as recovery", () => {
  const segs = lapsToPaceSegments(AUG11_LAPS, 4.02);
  assertEquals(segs.map((s) => s.effort === "recovery"), [
    false, true, false, true, false, true,
  ]);
});

// ── choosing between laps and splits ─────────────────────────────────────

Deno.test("buildPaceSegments prefers laps when they cover the run", () => {
  const segs = buildPaceSegments({
    laps: AUG18_LAPS,
    splits_standard: AUG18_MILE_SPLITS,
    average_speed: AUG18_AVG_SPEED,
    distance: AUG18_DISTANCE_M,
  });
  assert(segs);
  assertEquals(segs!.length, AUG18_LAPS.length);
  assert(segs!.some((s) => s.effort === "recovery"), "lap path was taken");
});

Deno.test("a single whole-run lap loses to mile splits", () => {
  assert(!lapsAreUsable([{ distance: AUG18_DISTANCE_M, moving_time: 2201 }], AUG18_DISTANCE_M));
  const segs = buildPaceSegments({
    laps: [{ distance: AUG18_DISTANCE_M, moving_time: 2201, average_speed: AUG18_AVG_SPEED }],
    splits_standard: AUG18_MILE_SPLITS,
    average_speed: AUG18_AVG_SPEED,
    distance: AUG18_DISTANCE_M,
  });
  assertEquals(segs!.length, AUG18_MILE_SPLITS.length, "fell back to splits");
});

Deno.test("laps that do not account for the run lose to mile splits", () => {
  const partial = AUG18_LAPS.slice(0, 2); // ~2 of 6.2 miles
  assert(!lapsAreUsable(partial, AUG18_DISTANCE_M));
  const segs = buildPaceSegments({
    laps: partial,
    splits_standard: AUG18_MILE_SPLITS,
    average_speed: AUG18_AVG_SPEED,
    distance: AUG18_DISTANCE_M,
  });
  assertEquals(segs!.length, AUG18_MILE_SPLITS.length);
});

Deno.test("no laps and no splits yields null, not an empty segment list", () => {
  assertEquals(buildPaceSegments({ average_speed: 4.5, distance: 10000 }), null);
});

Deno.test("unknown activity distance still allows the lap path", () => {
  assert(lapsAreUsable(AUG18_LAPS, 0), "missing distance must not force a fallback");
});

Deno.test("zero-distance and zero-time laps are skipped, not emitted as NaN", () => {
  const segs = lapsToPaceSegments(
    [
      { distance: 0, moving_time: 12, average_speed: 0 },
      { distance: mi(1), moving_time: 0, average_speed: 0 },
      { distance: mi(1), moving_time: 330, average_speed: 4.877 },
    ],
    4.5,
  );
  assertEquals(segs.length, 1);
  assertEquals(segs[0].pace_per_mile, "5:30");
});

// ── formatting ───────────────────────────────────────────────────────────

Deno.test("pace formatting never emits :60", () => {
  assertEquals(paceStringFromSec(359.7), "6:00");
  assertEquals(paceStringFromSec(323), "5:23");
  assertEquals(paceStringFromSec(0), "");
});
