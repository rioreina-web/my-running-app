/**
 * Tests for the REP-LEVEL workout progression path in coach-context.ts,
 * added 2026-09-16.
 *
 * Regression anchor — the bug this path exists to kill. Rio asked
 * session-ask "How does this compare to the last one like it?" about her
 * 2026-09-15 12×800m. The answer opened with 7:06/mi against 6:00/mi for the
 * 2026-08-11 10×1K and read the session as a collapse.
 *
 * Both of those numbers are total distance over total elapsed time. On a rep
 * session that measures how long the athlete stood between reps, not how fast
 * she ran. Her reps were 5:14/mi and 5:18/mi: four seconds per mile FASTER,
 * over a tighter spread, with no second-half fade. The shipped answer had the
 * sign backwards.
 *
 * Every lap in the fixtures below is real, copied from `running_workout_laps`
 * for those three sessions. Do not "tidy" them — the awkward parts (a 131 s
 * recovery, a 15 m trailing fragment, the 2×200m strides tacked onto the end
 * of the 12×800, the 874 m opener in the 08-25 ladder) are precisely the
 * shapes that broke earlier versions of this code.
 *
 * Run: deno test _shared/coach-context-progression.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  describeRepDistance,
  findSimilarPriorWorkout,
  formatProgressionBlock,
  repProfileFromLaps,
  type LapLite,
} from "./coach-context.ts";

// ── Fixtures: real laps ──────────────────────────────────────────────────

const LAPS_2026_09_15: LapLite[] = [
  { lap_index: 0, distance_meters: 805.02, moving_time_seconds: 158, avg_pace_sec_per_mile: 315.86, avg_heart_rate: 161, is_rest: false },
  { lap_index: 1, distance_meters: 51.43, moving_time_seconds: 62, avg_pace_sec_per_mile: 1940.1, avg_heart_rate: 160, is_rest: true },
  { lap_index: 2, distance_meters: 802.51, moving_time_seconds: 157, avg_pace_sec_per_mile: 314.85, avg_heart_rate: 161, is_rest: false },
  { lap_index: 3, distance_meters: 50.9, moving_time_seconds: 79, avg_pace_sec_per_mile: 2497.8, avg_heart_rate: 158, is_rest: true },
  { lap_index: 4, distance_meters: 807.06, moving_time_seconds: 158, avg_pace_sec_per_mile: 315.06, avg_heart_rate: 168, is_rest: false },
  { lap_index: 5, distance_meters: 56.2, moving_time_seconds: 69, avg_pace_sec_per_mile: 1975.88, avg_heart_rate: 152, is_rest: true },
  { lap_index: 6, distance_meters: 812.21, moving_time_seconds: 157, avg_pace_sec_per_mile: 311.09, avg_heart_rate: 166, is_rest: false },
  { lap_index: 7, distance_meters: 35.31, moving_time_seconds: 70, avg_pace_sec_per_mile: 3190.43, avg_heart_rate: 165, is_rest: true },
  { lap_index: 8, distance_meters: 807.03, moving_time_seconds: 157, avg_pace_sec_per_mile: 313.08, avg_heart_rate: 164, is_rest: false },
  { lap_index: 9, distance_meters: 48.31, moving_time_seconds: 75, avg_pace_sec_per_mile: 2498.46, avg_heart_rate: 160, is_rest: true },
  { lap_index: 10, distance_meters: 796.93, moving_time_seconds: 156, avg_pace_sec_per_mile: 315.03, avg_heart_rate: 169, is_rest: false },
  { lap_index: 11, distance_meters: 61.96, moving_time_seconds: 77, avg_pace_sec_per_mile: 1999.99, avg_heart_rate: 165, is_rest: true },
  { lap_index: 12, distance_meters: 801.71, moving_time_seconds: 156, avg_pace_sec_per_mile: 313.15, avg_heart_rate: 167, is_rest: false },
  { lap_index: 13, distance_meters: 60.33, moving_time_seconds: 66, avg_pace_sec_per_mile: 1760.6, avg_heart_rate: 161, is_rest: true },
  { lap_index: 14, distance_meters: 810.0, moving_time_seconds: 157, avg_pace_sec_per_mile: 311.93, avg_heart_rate: 172, is_rest: false },
  { lap_index: 15, distance_meters: 49.29, moving_time_seconds: 65, avg_pace_sec_per_mile: 2122.28, avg_heart_rate: 166, is_rest: true },
  { lap_index: 16, distance_meters: 802.32, moving_time_seconds: 158, avg_pace_sec_per_mile: 316.93, avg_heart_rate: 173, is_rest: false },
  { lap_index: 17, distance_meters: 31.31, moving_time_seconds: 64, avg_pace_sec_per_mile: 3289.62, avg_heart_rate: 168, is_rest: true },
  { lap_index: 18, distance_meters: 808.46, moving_time_seconds: 159, avg_pace_sec_per_mile: 316.51, avg_heart_rate: 173, is_rest: false },
  { lap_index: 19, distance_meters: 60.09, moving_time_seconds: 67, avg_pace_sec_per_mile: 1794.41, avg_heart_rate: 165, is_rest: true },
  { lap_index: 20, distance_meters: 801.68, moving_time_seconds: 158, avg_pace_sec_per_mile: 317.18, avg_heart_rate: 172, is_rest: false },
  { lap_index: 21, distance_meters: 57.44, moving_time_seconds: 62, avg_pace_sec_per_mile: 1737.11, avg_heart_rate: 166, is_rest: true },
  { lap_index: 22, distance_meters: 802.9, moving_time_seconds: 155, avg_pace_sec_per_mile: 310.68, avg_heart_rate: 174, is_rest: false },
  { lap_index: 23, distance_meters: 64.57, moving_time_seconds: 59, avg_pace_sec_per_mile: 1470.52, avg_heart_rate: 132, is_rest: true },
  { lap_index: 24, distance_meters: 203.53, moving_time_seconds: 33, avg_pace_sec_per_mile: 260.94, avg_heart_rate: 146, is_rest: false },
  { lap_index: 25, distance_meters: 98.75, moving_time_seconds: 89, avg_pace_sec_per_mile: 1450.45, avg_heart_rate: 152, is_rest: true },
  { lap_index: 26, distance_meters: 200.26, moving_time_seconds: 31, avg_pace_sec_per_mile: 249.12, avg_heart_rate: 141, is_rest: false },
  { lap_index: 27, distance_meters: 29.4, moving_time_seconds: 7, avg_pace_sec_per_mile: 383.18, avg_heart_rate: 157, is_rest: true },
];

const LAPS_2026_08_11: LapLite[] = [
  { lap_index: 1, distance_meters: 994.45, moving_time_seconds: 197, avg_pace_sec_per_mile: 318.81, avg_heart_rate: 157, is_rest: false },
  { lap_index: 2, distance_meters: 78.38, moving_time_seconds: 67, avg_pace_sec_per_mile: 1375.68, avg_heart_rate: 149, is_rest: true },
  { lap_index: 3, distance_meters: 1006.73, moving_time_seconds: 194, avg_pace_sec_per_mile: 310.13, avg_heart_rate: 165, is_rest: false },
  { lap_index: 4, distance_meters: 73.39, moving_time_seconds: 66, avg_pace_sec_per_mile: 1447.29, avg_heart_rate: 152, is_rest: true },
  { lap_index: 5, distance_meters: 1005.97, moving_time_seconds: 197, avg_pace_sec_per_mile: 315.16, avg_heart_rate: 161, is_rest: false },
  { lap_index: 6, distance_meters: 99.98, moving_time_seconds: 66, avg_pace_sec_per_mile: 1062.38, avg_heart_rate: 147, is_rest: true },
  { lap_index: 7, distance_meters: 1000.49, moving_time_seconds: 197, avg_pace_sec_per_mile: 316.89, avg_heart_rate: 163, is_rest: false },
  { lap_index: 8, distance_meters: 45.08, moving_time_seconds: 67, avg_pace_sec_per_mile: 2391.88, avg_heart_rate: 161, is_rest: true },
  { lap_index: 9, distance_meters: 993.4, moving_time_seconds: 198, avg_pace_sec_per_mile: 320.77, avg_heart_rate: 165, is_rest: false },
  { lap_index: 10, distance_meters: 86.55, moving_time_seconds: 64, avg_pace_sec_per_mile: 1190.04, avg_heart_rate: 151, is_rest: true },
  { lap_index: 11, distance_meters: 1008.85, moving_time_seconds: 199, avg_pace_sec_per_mile: 317.45, avg_heart_rate: 166, is_rest: false },
  { lap_index: 12, distance_meters: 46.57, moving_time_seconds: 131, avg_pace_sec_per_mile: 4527.04, avg_heart_rate: 160, is_rest: true },
  { lap_index: 13, distance_meters: 998.35, moving_time_seconds: 199, avg_pace_sec_per_mile: 320.79, avg_heart_rate: 165, is_rest: false },
  { lap_index: 14, distance_meters: 89.78, moving_time_seconds: 66, avg_pace_sec_per_mile: 1183.08, avg_heart_rate: 151, is_rest: true },
  { lap_index: 15, distance_meters: 1003.68, moving_time_seconds: 199, avg_pace_sec_per_mile: 319.09, avg_heart_rate: 165, is_rest: false },
  { lap_index: 16, distance_meters: 56.99, moving_time_seconds: 73, avg_pace_sec_per_mile: 2061.45, avg_heart_rate: 154, is_rest: true },
  { lap_index: 17, distance_meters: 990.79, moving_time_seconds: 203, avg_pace_sec_per_mile: 329.73, avg_heart_rate: 166, is_rest: false },
  { lap_index: 18, distance_meters: 92.93, moving_time_seconds: 55, avg_pace_sec_per_mile: 952.48, avg_heart_rate: 158, is_rest: true },
  { lap_index: 19, distance_meters: 992.24, moving_time_seconds: 194, avg_pace_sec_per_mile: 314.65, avg_heart_rate: 170, is_rest: false },
  { lap_index: 20, distance_meters: 15.42, moving_time_seconds: 2, avg_pace_sec_per_mile: 208.73, avg_heart_rate: 175, is_rest: true },
];

const LAPS_2026_08_25: LapLite[] = [
  { lap_index: 1, distance_meters: 873.8, moving_time_seconds: 177, avg_pace_sec_per_mile: 325.98, avg_heart_rate: 146, is_rest: false },
  { lap_index: 2, distance_meters: 65.2, moving_time_seconds: 52, avg_pace_sec_per_mile: 1284.12, avg_heart_rate: 146, is_rest: true },
  { lap_index: 3, distance_meters: 600.7, moving_time_seconds: 114, avg_pace_sec_per_mile: 305.44, avg_heart_rate: 162, is_rest: false },
  { lap_index: 4, distance_meters: 61.6, moving_time_seconds: 63, avg_pace_sec_per_mile: 1645.12, avg_heart_rate: 151, is_rest: true },
  { lap_index: 5, distance_meters: 1009.9, moving_time_seconds: 192, avg_pace_sec_per_mile: 305.97, avg_heart_rate: 169, is_rest: false },
  { lap_index: 6, distance_meters: 95.5, moving_time_seconds: 64, avg_pace_sec_per_mile: 1078.4, avg_heart_rate: 153, is_rest: true },
  { lap_index: 7, distance_meters: 603.5, moving_time_seconds: 113, avg_pace_sec_per_mile: 301.34, avg_heart_rate: 161, is_rest: false },
  { lap_index: 8, distance_meters: 38.8, moving_time_seconds: 61, avg_pace_sec_per_mile: 2530.15, avg_heart_rate: 163, is_rest: true },
  { lap_index: 9, distance_meters: 1003.7, moving_time_seconds: 192, avg_pace_sec_per_mile: 307.84, avg_heart_rate: 168, is_rest: false },
  { lap_index: 10, distance_meters: 84.8, moving_time_seconds: 61, avg_pace_sec_per_mile: 1157.8, avg_heart_rate: 155, is_rest: true },
  { lap_index: 11, distance_meters: 601.1, moving_time_seconds: 113, avg_pace_sec_per_mile: 302.53, avg_heart_rate: 160, is_rest: false },
  { lap_index: 12, distance_meters: 46.5, moving_time_seconds: 63, avg_pace_sec_per_mile: 2180.87, avg_heart_rate: 160, is_rest: true },
  { lap_index: 13, distance_meters: 1004.9, moving_time_seconds: 190, avg_pace_sec_per_mile: 304.28, avg_heart_rate: 169, is_rest: false },
  { lap_index: 14, distance_meters: 76.5, moving_time_seconds: 60, avg_pace_sec_per_mile: 1262.07, avg_heart_rate: 157, is_rest: true },
  { lap_index: 15, distance_meters: 601.0, moving_time_seconds: 114, avg_pace_sec_per_mile: 305.26, avg_heart_rate: 165, is_rest: false },
  { lap_index: 16, distance_meters: 56.6, moving_time_seconds: 61, avg_pace_sec_per_mile: 1733.23, avg_heart_rate: 163, is_rest: true },
  { lap_index: 17, distance_meters: 998.9, moving_time_seconds: 192, avg_pace_sec_per_mile: 309.35, avg_heart_rate: 169, is_rest: false },
  { lap_index: 18, distance_meters: 86.3, moving_time_seconds: 57, avg_pace_sec_per_mile: 1063.57, avg_heart_rate: 160, is_rest: true },
  { lap_index: 19, distance_meters: 609.6, moving_time_seconds: 115, avg_pace_sec_per_mile: 303.62, avg_heart_rate: 167, is_rest: false },
  { lap_index: 20, distance_meters: 59.3, moving_time_seconds: 66, avg_pace_sec_per_mile: 1789.97, avg_heart_rate: 161, is_rest: true },
  { lap_index: 21, distance_meters: 1004.6, moving_time_seconds: 191, avg_pace_sec_per_mile: 305.97, avg_heart_rate: 172, is_rest: false },
  { lap_index: 22, distance_meters: 71.5, moving_time_seconds: 52, avg_pace_sec_per_mile: 1170.92, avg_heart_rate: 164, is_rest: true },
  { lap_index: 23, distance_meters: 605.3, moving_time_seconds: 108, avg_pace_sec_per_mile: 287.14, avg_heart_rate: 172, is_rest: false },
  { lap_index: 24, distance_meters: 14.5, moving_time_seconds: 2, avg_pace_sec_per_mile: 222.44, avg_heart_rate: 179, is_rest: true },
];

const WX_09_15 = { temp_f: 79.9, dew_point_f: 75.7, heat_category: "very_hot", surfacing: "apply" };
const WX_08_11 = { temp_f: 78.4, dew_point_f: 75.3, heat_category: "very_hot", surfacing: "apply" };

/** `formatPace` rounds, so compare on the string a reader would actually see. */
function paceStr(sec: number): string {
  const t = Math.round(sec);
  return `${Math.floor(t / 60)}:${(t % 60).toString().padStart(2, "0")}`;
}

// ── repProfileFromLaps ───────────────────────────────────────────────────

Deno.test("12×800m + 2×200m: the primary set is the twelve 800s", () => {
  const p = repProfileFromLaps(LAPS_2026_09_15)!;
  assert(p, "profile must be built from 28 laps of real rep data");
  assertEquals(p.repCount, 12);
  assertEquals(p.repLabel, "800m");
  // The strides are a different question. Averaging them into the rep pace
  // drags it from 5:14 to 5:06 — a number she never ran.
  assertEquals(p.extraSets, [{ count: 2, label: "200m" }]);
  assertEquals(paceStr(p.avgPaceSec), "5:14");
  assertEquals(p.restSec, 67);
  assertEquals(p.avgHr, 168);
  assertEquals(p.lastRepHr, 174);
  assertEquals(p.totalWorkMi.toFixed(2), "6.00");
});

Deno.test("10×1K: one clean set, no extras", () => {
  const p = repProfileFromLaps(LAPS_2026_08_11)!;
  assertEquals(p.repCount, 10);
  assertEquals(p.repLabel, "1K");
  assertEquals(p.extraSets, []);
  assertEquals(paceStr(p.avgPaceSec), "5:18");
  assertEquals(p.avgHr, 164);
  // The 131 s stop mid-session must not drag the recovery figure; median, not mean.
  assertEquals(p.restSec, 66);
});

Deno.test("alternating 1K/600m ladder clusters by distance, not lap order", () => {
  // 2026-08-25 runs 1K and 600m reps alternately and opens with a short 874 m.
  // Greedy in-lap-order clustering anchors on the 874 and then absorbs the
  // 1004s one at a time, inventing a set. Sorted clustering must not.
  const p = repProfileFromLaps(LAPS_2026_08_25)!;
  assertEquals(p.repLabel, "1K");
  assertEquals(p.repCount, 6);
  assertEquals(p.extraSets, [{ count: 6, label: "600m" }]);
});

Deno.test("fewer than three work reps is not a rep session", () => {
  assertEquals(repProfileFromLaps(LAPS_2026_09_15.slice(0, 4)), null);
  assertEquals(repProfileFromLaps([]), null);
  assertEquals(repProfileFromLaps(null), null);
});

Deno.test("rep distances are named the way a runner names them", () => {
  assertEquals(describeRepDistance(802), "800m");      // GPS scatter on an 800
  assertEquals(describeRepDistance(1004), "1K");
  assertEquals(describeRepDistance(400), "400m");
  assertEquals(describeRepDistance(1609.34), "1mi");
  assertEquals(describeRepDistance(1450), "0.90 mi");  // nothing standard — stay honest
});

// ── formatProgressionBlock: the rep-level path ───────────────────────────

Deno.test("THE BUG: 12×800 vs 10×1K leads with rep pace, never session pace", () => {
  const cur = repProfileFromLaps(LAPS_2026_09_15)!;
  const pri = repProfileFromLaps(LAPS_2026_08_11)!;

  const out = formatProgressionBlock(
    // 6.72 mi @ 7:06/mi and 6.64 mi @ 6:00/mi are the real session averages.
    // They are passed in exactly as the caller has them, and must not appear.
    { workoutType: "intervals", distanceMiles: 6.72, paceSecPerMile: 426, repProfile: cur, weather: WX_09_15 },
    {
      date: "2026-08-11 11:29:53+00", daysAgo: 35, workoutType: "intervals",
      distanceMiles: 6.64, paceSecPerMile: 360, repProfile: pri,
      matchedOn: "shape", weather: WX_08_11,
    },
  )!;
  assert(out, "a quality-vs-quality comparison always produces a block");
  const b = out.block;

  // The numbers that must be there.
  assert(b.includes("5:14"), "today's rep average must be present");
  assert(b.includes("5:18"), "the prior's rep average must be present");
  assert(b.includes("rep pace 4 sec/mi faster"), `delta line wrong:\n${b}`);
  assert(b.includes("12×800m"), "structure of today's session");
  assert(b.includes("10×1K"), "structure of the prior session");

  // The numbers that must NOT be there. This is the whole point.
  assert(!b.includes("7:06"), `session average pace leaked:\n${b}`);
  assert(!b.includes("6:00"), `prior session average pace leaked:\n${b}`);
  assert(!b.includes("6.72"), `session total distance leaked:\n${b}`);
  assert(!b.includes("6.64"), `prior session total distance leaked:\n${b}`);

  // Read as progress, not collapse.
  assertEquals(out.hasImprovement, true);
  assertEquals(out.hasRegression, false);
});

Deno.test("rep-level block carries spread, fade, HR cost and conditions", () => {
  const cur = repProfileFromLaps(LAPS_2026_09_15)!;
  const pri = repProfileFromLaps(LAPS_2026_08_11)!;
  const b = formatProgressionBlock(
    { workoutType: "intervals", distanceMiles: 6.72, paceSecPerMile: 426, repProfile: cur, weather: WX_09_15 },
    {
      date: "2026-08-11", daysAgo: 35, workoutType: "intervals", distanceMiles: 6.64,
      paceSecPerMile: 360, repProfile: pri, matchedOn: "shape", weather: WX_08_11,
    },
  )!.block;

  assert(b.includes("(even)"), "today's halves were flat");
  assert(b.includes("faded 4 sec/mi"), "the prior faded in the second half");
  assert(b.includes("rep spread 6 vs 20 sec/mi"), `spread line wrong:\n${b}`);
  assert(b.includes("rep HR +4 bpm"));
  assert(b.includes("80°F"), "today's conditions");
  assert(b.includes("78°F"), "the prior's conditions");
  // 6.00 vs 6.21 mi of work is inside the noise floor; do not call it a change.
  assert(b.includes("work distance the same (within noise)"), `noise floor not applied:\n${b}`);
  // Same pace over a shorter rep is a smaller ask — say so.
  assert(b.includes("different length (800m vs 1K)"), `rep-length caveat missing:\n${b}`);
});

Deno.test("spread arithmetic matches the fastest/slowest actually printed", () => {
  const cur = repProfileFromLaps(LAPS_2026_09_15)!;
  const b = formatProgressionBlock(
    { workoutType: "intervals", distanceMiles: 6.72, paceSecPerMile: 426, repProfile: cur },
    {
      date: "2026-08-11", daysAgo: 35, workoutType: "intervals", distanceMiles: 6.64,
      paceSecPerMile: 360, repProfile: repProfileFromLaps(LAPS_2026_08_11)!, matchedOn: "shape",
    },
  )!.block;
  // 5:11 → 5:17 is six seconds. Rounding the raw 6.5 s difference instead
  // prints "(7 sec/mi spread)" next to those two numbers, which is visibly
  // wrong to anyone who checks.
  assert(
    b.includes("fastest 5:11, slowest 5:17 (6 sec/mi spread)"),
    `spread must agree with the printed bounds:\n${b}`,
  );
});

Deno.test("a family fallback is labelled as a different shape", () => {
  const cur = repProfileFromLaps(LAPS_2026_09_15)!;
  const b = formatProgressionBlock(
    { workoutType: "intervals", distanceMiles: 6.72, paceSecPerMile: 426, repProfile: cur },
    {
      date: "2026-07-24", daysAgo: 53, workoutType: "intervals",
      distanceMiles: 5.75, paceSecPerMile: 719, repProfile: null, matchedOn: "family",
    },
  )!.block;
  assert(b.includes("closest, different shape"), `unlabelled shape mismatch:\n${b}`);
  assert(
    b.includes("do not read the pace delta as a change in fitness"),
    "a session-average comparison between rep sessions needs the caveat",
  );
});

// ── Non-quality runs must be untouched ───────────────────────────────────

Deno.test("easy runs keep the session-average block and the noise filter", () => {
  const easy = { workoutType: "easy", distanceMiles: 5.0, paceSecPerMile: 510 };
  const prior = {
    date: "2026-08-20", daysAgo: 26, workoutType: "easy",
    distanceMiles: 5.0, paceSecPerMile: 512,
  };
  // 2 sec/mi over the same distance is noise — the block must not fire at all.
  assertEquals(formatProgressionBlock(easy, prior), null);

  const longer = formatProgressionBlock({ ...easy, distanceMiles: 7.0 }, prior);
  assert(longer, "a 40% distance jump is a real change");
  assert(longer!.block.includes("## Workout progression"));
  assert(longer!.block.includes("7.0 mi easy"), "session averages belong on an easy run");
});

// ── findSimilarPriorWorkout: the shape pass ──────────────────────────────

type LogRow = {
  id: string;
  workout_date: string;
  workout_type: string;
  workout_distance_miles: number;
  workout_pace_per_mile: string | null;
  workout_duration_minutes: number | null;
  weather_actual: Record<string, unknown> | null;
};

/**
 * The narrowest fake that satisfies the two PostgREST chains the matcher
 * builds. It deliberately does NOT emulate filtering: every test here asserts
 * on which candidate the SCORING picks, and a fake that silently dropped rows
 * could make a broken matcher look right.
 */
function fakeClient(logs: LogRow[], lapsByWorkout: Record<string, LapLite[]>) {
  const builder = (rows: unknown[]) => {
    const b: Record<string, unknown> = {};
    for (const m of ["select", "eq", "in", "gte", "lte", "lt", "order", "limit"]) {
      b[m] = () => b;
    }
    // Awaiting the builder resolves it, exactly as supabase-js does.
    (b as { then: unknown }).then = (
      res: (v: { data: unknown[]; error: null }) => unknown,
    ) => res({ data: rows, error: null });
    return b;
  };
  const lapRows = Object.entries(lapsByWorkout).flatMap(([workout_id, ls]) =>
    ls.map((l) => ({ ...l, workout_id }))
  );
  return {
    from: (table: string) =>
      builder(table === "running_workout_laps" ? lapRows : logs),
  } as unknown as Parameters<typeof findSimilarPriorWorkout>[0];
}

Deno.test("shape pass prefers the 10×1K over a mixed 1K/600m ladder", async () => {
  // Both candidates are inside ±25% rep distance of an 800 m rep, so this is
  // decided by the secondary terms: ten reps is much closer to twelve than six
  // is, and the 08-25 ladder only has six same-length reps in its primary set.
  const logs: LogRow[] = [
    {
      id: "aug25", workout_date: "2026-08-25T11:00:00Z", workout_type: "intervals",
      workout_distance_miles: 6.38, workout_pace_per_mile: "6:01",
      workout_duration_minutes: 38.43, weather_actual: null,
    },
    {
      id: "aug11", workout_date: "2026-08-11T11:29:53Z", workout_type: "intervals",
      workout_distance_miles: 6.64, workout_pace_per_mile: "6:00",
      workout_duration_minutes: 39.85, weather_actual: WX_08_11,
    },
  ];
  const client = fakeClient(logs, {
    aug25: LAPS_2026_08_25,
    aug11: LAPS_2026_08_11,
  });

  const prior = await findSimilarPriorWorkout(
    client,
    "user-1",
    {
      workoutType: "intervals", distanceMiles: 6.72, paceSecPerMile: 426,
      repProfile: repProfileFromLaps(LAPS_2026_09_15),
    },
    new Date("2026-09-15T11:33:43Z"),
  );

  assert(prior, "a shape match must be found");
  assertEquals(prior!.date.slice(0, 10), "2026-08-11");
  assertEquals(prior!.matchedOn, "shape");
  assertEquals(prior!.repProfile?.repCount, 10);
  // The weather rides along so the block can compare conditions.
  assertEquals(prior!.weather, WX_08_11);
});

Deno.test("shape pass reaches inside 14 days; the old floor would have hidden this", async () => {
  const logs: LogRow[] = [{
    id: "sep08", workout_date: "2026-09-08T11:00:00Z", workout_type: "threshold",
    workout_distance_miles: 5.57, workout_pace_per_mile: null,
    workout_duration_minutes: 33.02, weather_actual: null,
  }];
  const prior = await findSimilarPriorWorkout(
    fakeClient(logs, { sep08: LAPS_2026_08_11 }),
    "user-1",
    {
      workoutType: "intervals", distanceMiles: 6.72, paceSecPerMile: 426,
      repProfile: repProfileFromLaps(LAPS_2026_09_15),
    },
    new Date("2026-09-15T11:33:43Z"),
  );
  assert(prior, "a session seven days ago is the most useful comparison there is");
  assertEquals(prior!.daysAgo, 7);
  // Logged `threshold`, not `intervals`: the shape pass searches across the
  // quality types because the athlete's label for a rep session isn't stable.
  assertEquals(prior!.workoutType, "threshold");
});

Deno.test("no rep profile means the original family+distance behaviour", async () => {
  // generate-workout-insight and process-training-memo call without a profile.
  // They must not get a quality session with the distance gate removed.
  const logs: LogRow[] = [{
    id: "aug11", workout_date: "2026-08-11T11:29:53Z", workout_type: "intervals",
    workout_distance_miles: 6.64, workout_pace_per_mile: "6:00",
    workout_duration_minutes: 39.85, weather_actual: null,
  }];
  const prior = await findSimilarPriorWorkout(
    fakeClient(logs, { aug11: LAPS_2026_08_11 }),
    "user-1",
    { workoutType: "intervals", distanceMiles: 6.72, paceSecPerMile: 426 },
    new Date("2026-09-15T11:33:43Z"),
  );
  assert(prior);
  assertEquals(prior!.matchedOn, "family");
  assertEquals(prior!.repProfile, null);
});
