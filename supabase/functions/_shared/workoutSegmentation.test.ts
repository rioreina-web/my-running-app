/**
 * Tests for the WS1 segmentation/classifier. Pace zones are the test
 * athlete's (03857bf3…): mile 272, 5K 302, 10K 314, HMP 328, MP 343,
 * steady 362, moderate 405, easy 429 (sec/mile).
 *
 * Run: deno test _shared/workoutSegmentation.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildZoneAnchors,
  paceToZone,
  paceWeight,
  segmentFromLaps,
  segmentFromOverall,
  type LapInput,
  type PaceZones,
} from "./workoutSegmentation.ts";

const ZONES: PaceZones = {
  mile: 272, fiveK: 302, tenK: 314, hm: 328, mp: 343,
  steady: 362, moderate: 405, easy: 429,
};

Deno.test("paceWeight: exact anchor paces return their knot weight", () => {
  const a = buildZoneAnchors(ZONES);
  assertEquals(paceWeight(272, a), 8.0); // mile
  assertEquals(paceWeight(302, a), 5.5); // 5k
  assertEquals(paceWeight(343, a), 2.5); // mp
  assertEquals(paceWeight(362, a), 2.15); // steady — an explicit knot again
  assertEquals(paceWeight(405, a), 1.4); // moderate
  assertEquals(paceWeight(429, a), 1.0); // easy
});

Deno.test("paceWeight: no slope cliff at steady (2026-08-11 reweight)", () => {
  const a = buildZoneAnchors(ZONES);
  // Weight per sec/mi across each segment of the low end. Before the reweight
  // steady→mp was 0.0562 against 0.0060 for moderate→steady — a 9x jump that
  // made the score hypersensitive to small pace changes near MP. The curve must
  // now steepen MONOTONICALLY as pace gets faster, with no segment more than 2x
  // its slower neighbour.
  const slope = (slow: number, fast: number) =>
    (paceWeight(fast, a) - paceWeight(slow, a)) / (slow - fast);
  const easyMod = slope(429, 405);
  const modSteady = slope(405, 362);
  const steadyMp = slope(362, 343);
  assert(easyMod < modSteady, `easy→mod ${easyMod} should be < mod→steady ${modSteady}`);
  assert(modSteady < steadyMp, `mod→steady ${modSteady} should be < steady→mp ${steadyMp}`);
  assert(steadyMp / modSteady < 2, `steady→mp ${steadyMp} is a cliff vs ${modSteady}`);
});

Deno.test("paceWeight: interpolates continuously between zones", () => {
  const a = buildZoneAnchors(ZONES);
  const near = (x: number, want: number) => assert(Math.abs(x - want) < 0.02, `${x} vs ${want}`);
  // (2026-08-13) Values moved slightly when straight-line interpolation became a
  // monotone cubic. The knots are unchanged; only the path BETWEEN them curves,
  // so a midpoint no longer lands on the arithmetic mean of its two anchors.
  // 308 sits midway between 5k(302→5.5) and 10k(314→4.0). Linear said 4.75.
  near(paceWeight(308, a), 4.71);
  // 353 sits between mp(343→2.5) and steady(362→2.15). Linear said 2.32.
  near(paceWeight(353, a), 2.29);
});

Deno.test("paceWeight: the curve has no corners — slope is continuous at every knot", () => {
  const a = buildZoneAnchors(ZONES);
  // The reason for the monotone cubic. Linear interpolation is continuous in
  // VALUE but breaks in SLOPE at each anchor — worst at MP, where the rate of
  // change leapt 64%. Sample the derivative either side of every interior knot;
  // no knot may break it by more than 5%.
  // Sample the one-sided derivatives CLOSE to the knot — far enough out and the
  // curve's own (intended) curvature dominates and the measurement is
  // meaningless. 0.05 sec/mi either side isolates the break itself.
  const deriv = (p: number) => (paceWeight(p + 0.005, a) - paceWeight(p - 0.005, a)) / 0.01;
  for (const knot of [302, 314, 328, 343, 362, 405]) {
    const before = Math.abs(deriv(knot - 0.05));
    const after = Math.abs(deriv(knot + 0.05));
    const brk = Math.abs(before - after) / Math.max(before, after);
    assert(brk < 0.05, `slope breaks ${(brk * 100).toFixed(0)}% at knot ${knot}`);
  }
});

Deno.test("paceWeight: monotone — a slower pace never scores higher", () => {
  const a = buildZoneAnchors(ZONES);
  // Fritsch–Carlson guarantees no overshoot. A natural cubic spline would bulge
  // on the sharp 10K→5K transition and could invert the ordering here.
  let prev = Infinity;
  for (let p = 260; p <= 440; p += 0.25) {
    const w = paceWeight(p, a);
    assert(w <= prev + 1e-9, `weight rose at ${p} sec/mi (${w} > ${prev})`);
    prev = w;
  }
});

Deno.test("paceWeight: reps faster than mile extrapolate ABOVE the mile weight", () => {
  const a = buildZoneAnchors(ZONES);
  // 255 s/mi (~4:15) is faster than the 272 mile anchor → past 8.0.
  const w = paceWeight(255, a);
  assert(w > 8.0, `expected > 8.0, got ${w}`);
  assert(Math.abs(w - 9.42) < 0.02, `expected ~9.42, got ${w}`);
});

Deno.test("paceWeight: slower than easy floors at 1.0; no anchors → 1.0", () => {
  const a = buildZoneAnchors(ZONES);
  assertEquals(paceWeight(500, a), 1.0);
  assertEquals(paceWeight(343, []), 1.0);
});

Deno.test("paceToZone: midpoint cutoffs are athlete-relative", () => {
  const a = buildZoneAnchors(ZONES);
  assertEquals(paceToZone(280, a), "mile"); // <=287
  assertEquals(paceToZone(307, a), "5k"); // <=308 (the May-20 rep pace)
  assertEquals(paceToZone(317, a), "10k"); // 314<317<=321
  assertEquals(paceToZone(332, a), "hmp"); // ~threshold
  assertEquals(paceToZone(348, a), "mp");
  assertEquals(paceToZone(600, a), "recovery"); // way slower than easy
});

// The golden session: May 20, 2026 — 9×1K @ ~5:07 with jog recovery, plus a
// stray 447m float lap (is_rest=false but ~9:54/mi — NOT a rep).
const MAY20: LapInput[] = [
  { lap_index: 1, is_rest: false, distance_meters: 1000, avg_pace_sec_per_mile: 307, moving_time_seconds: 191, avg_heart_rate: 162 },
  { lap_index: 2, is_rest: true, distance_meters: 64, avg_pace_sec_per_mile: 1579, moving_time_seconds: 63, avg_heart_rate: 167 },
  { lap_index: 3, is_rest: false, distance_meters: 1000, avg_pace_sec_per_mile: 309, moving_time_seconds: 192, avg_heart_rate: 168 },
  { lap_index: 4, is_rest: true, distance_meters: 55, avg_pace_sec_per_mile: 1952, moving_time_seconds: 67, avg_heart_rate: 156 },
  { lap_index: 5, is_rest: false, distance_meters: 1000, avg_pace_sec_per_mile: 306, moving_time_seconds: 190, avg_heart_rate: 166 },
  { lap_index: 6, is_rest: true, distance_meters: 53, avg_pace_sec_per_mile: 1919, moving_time_seconds: 63, avg_heart_rate: 172 },
  { lap_index: 7, is_rest: false, distance_meters: 1000, avg_pace_sec_per_mile: 307, moving_time_seconds: 191, avg_heart_rate: 168 },
  { lap_index: 8, is_rest: false, distance_meters: 447, avg_pace_sec_per_mile: 594, moving_time_seconds: 165, avg_heart_rate: 170 },
  { lap_index: 9, is_rest: true, distance_meters: 53, avg_pace_sec_per_mile: 1899, moving_time_seconds: 63, avg_heart_rate: 163 },
  { lap_index: 10, is_rest: false, distance_meters: 1000, avg_pace_sec_per_mile: 309, moving_time_seconds: 192, avg_heart_rate: 169 },
  { lap_index: 11, is_rest: true, distance_meters: 66, avg_pace_sec_per_mile: 1604, moving_time_seconds: 66, avg_heart_rate: 157 },
  { lap_index: 12, is_rest: false, distance_meters: 1000, avg_pace_sec_per_mile: 307, moving_time_seconds: 191, avg_heart_rate: 170 },
  { lap_index: 13, is_rest: true, distance_meters: 65, avg_pace_sec_per_mile: 1567, moving_time_seconds: 63, avg_heart_rate: 161 },
  { lap_index: 14, is_rest: false, distance_meters: 1000, avg_pace_sec_per_mile: 309, moving_time_seconds: 192, avg_heart_rate: 169 },
  { lap_index: 15, is_rest: true, distance_meters: 64, avg_pace_sec_per_mile: 1738, moving_time_seconds: 69, avg_heart_rate: 162 },
  { lap_index: 16, is_rest: false, distance_meters: 1000, avg_pace_sec_per_mile: 307, moving_time_seconds: 191, avg_heart_rate: 169 },
  { lap_index: 17, is_rest: true, distance_meters: 61, avg_pace_sec_per_mile: 1663, moving_time_seconds: 63, avg_heart_rate: 163 },
  { lap_index: 18, is_rest: false, distance_meters: 1000, avg_pace_sec_per_mile: 306, moving_time_seconds: 190, avg_heart_rate: 169 },
  { lap_index: 19, is_rest: true, distance_meters: 53, avg_pace_sec_per_mile: 934, moving_time_seconds: 31, avg_heart_rate: 169 },
];

Deno.test("May 20 golden: Intervals 9×1K @ 5:07 (5K), float lap excluded", () => {
  const r = segmentFromLaps(MAY20, ZONES);
  assertEquals(r.workoutKind, "intervals");
  assertEquals(r.repCount, 9); // the 447m float lap is NOT a rep
  assert(r.structure!.includes("9×1K"), `structure was: ${r.structure}`);
  assert(r.structure!.includes("5K"), `structure was: ${r.structure}`);
  // The session must now register real quality time (was 0 under the old path).
  assert(r.hardSeconds + r.thresholdSeconds > 1500, `quality secs: ${r.hardSeconds + r.thresholdSeconds}`);
  // 5K reps weigh 4.0; with rest folded in, intensity should be clearly > easy.
  assert(r.intensityScore > 2.5, `IS: ${r.intensityScore}`);
});

Deno.test("is_rest=false float slower than easy is recovery, not a rep", () => {
  const r = segmentFromLaps(MAY20, ZONES);
  const float = r.bouts.find((b) => Math.round(b.distanceMeters) === 447)!;
  assertEquals(float.isRep, false);
  assertEquals(float.isWork, false);
});

Deno.test("no work bouts → long_run vs easy by distance", () => {
  const longRun = segmentFromOverall(95 * 60, 13); // 13 mi easy
  assertEquals(longRun.workoutKind, "long_run");
  const easy = segmentFromOverall(45 * 60, 6); // 6 mi easy
  assertEquals(easy.workoutKind, "easy");
});

Deno.test("threshold cruise: long mile reps at 10K pace, tight CV", () => {
  const laps: LapInput[] = [];
  for (let i = 0; i < 5; i++) {
    laps.push({ lap_index: i * 2, is_rest: false, distance_meters: 1609, avg_pace_sec_per_mile: 317, moving_time_seconds: 317 });
    laps.push({ lap_index: i * 2 + 1, is_rest: true, distance_meters: 200, avg_pace_sec_per_mile: 700, moving_time_seconds: 60 });
  }
  const r = segmentFromLaps(laps, ZONES);
  assertEquals(r.workoutKind, "threshold");
  assertEquals(r.repCount, 5);
});

// Auto-lap coalescing — April 4, 2026 threshold session. The watch auto-split
// two continuous 3-mile efforts into six 1-mile laps + two slow breaks. The
// parser must report 2×3mi, NOT 6×1mi.
const APR4: LapInput[] = [
  { lap_index: 1, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 326, avg_pace_sec_per_mile: 326, avg_heart_rate: 163 },
  { lap_index: 2, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 323, avg_pace_sec_per_mile: 323, avg_heart_rate: 169 },
  { lap_index: 3, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 324, avg_pace_sec_per_mile: 324, avg_heart_rate: 168 },
  { lap_index: 4, is_rest: false, distance_meters: 762.25, moving_time_seconds: 227, avg_pace_sec_per_mile: 479, avg_heart_rate: 147 },
  { lap_index: 5, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 320, avg_pace_sec_per_mile: 320, avg_heart_rate: 167 },
  { lap_index: 6, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 320, avg_pace_sec_per_mile: 320, avg_heart_rate: 171 },
  { lap_index: 7, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 316, avg_pace_sec_per_mile: 316, avg_heart_rate: 174 },
  { lap_index: 8, is_rest: false, distance_meters: 619.68, moving_time_seconds: 190, avg_pace_sec_per_mile: 493, avg_heart_rate: 150 },
];

Deno.test("auto-lap coalescing: 6×1mi cruise reads as 2×3mi, not 6×1mi", () => {
  const r = segmentFromLaps(APR4, ZONES);
  assertEquals(r.repCount, 2);
  assert(r.structure!.includes("2×3mi"), `structure was: ${r.structure}`);
  assertEquals(r.workoutKind, "threshold");
});

Deno.test("coalescing leaves a continuous progression alone (not merged)", () => {
  // 5 contiguous work miles, each clearly faster — no rest between. Must stay
  // 5 reps so progression detection still fires.
  const paces = [335, 326, 317, 308, 300];
  const laps: LapInput[] = paces.map((p, i) => ({
    lap_index: i, is_rest: false, distance_meters: 1609, avg_pace_sec_per_mile: p, moving_time_seconds: p,
  }));
  const r = segmentFromLaps(laps, ZONES);
  assertEquals(r.repCount, 5);
  assertEquals(r.workoutKind, "progression");
});

// ── Run-relative (contextual) structure ──
//
// Aug 29 2026 (log 16b36c27): 7 mi moderate + 4×3mi with ~half-mile floats
// inside a 21-mile long-run workout. Every rep mile is SLOWER than the
// absolute work gate (mp/steady midpoint), so the anchor-based pass saw only
// the last two miles and published "1×2mi @ 5:31 (threshold)". The contextual
// pass must read the run's own bimodal split instead. Real laps, real zones
// (the 2026-08-30 profile: mp 338, steady≈356, moderate≈398, easy 451).
const LIVE_ZONES: PaceZones = {
  mile: 268, fiveK: 297, tenK: 309, hm: 323, mp: 338,
  steady: 356, moderate: 398, easy: 451,
};

const AUG29: LapInput[] = [
  // 7 mi moderate warm-up block (last mile includes a stop — 10:22).
  ...[464, 433, 432, 435, 417, 411, 622].map((p, i) => (
    { lap_index: i + 1, is_rest: false, distance_meters: 1609.34, moving_time_seconds: p, avg_pace_sec_per_mile: p }
  )),
  // 4×3mi (auto-lapped by mile) with ~half-mile floats between.
  { lap_index: 8, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 370, avg_pace_sec_per_mile: 370 },
  { lap_index: 9, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 369, avg_pace_sec_per_mile: 369 },
  { lap_index: 10, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 368, avg_pace_sec_per_mile: 368 },
  { lap_index: 11, is_rest: false, distance_meters: 804.72, moving_time_seconds: 228, avg_pace_sec_per_mile: 456 },
  { lap_index: 12, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 368, avg_pace_sec_per_mile: 368 },
  { lap_index: 13, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 367, avg_pace_sec_per_mile: 367 },
  { lap_index: 14, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 364, avg_pace_sec_per_mile: 364 },
  { lap_index: 15, is_rest: false, distance_meters: 760.72, moving_time_seconds: 221, avg_pace_sec_per_mile: 468 },
  { lap_index: 16, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 362, avg_pace_sec_per_mile: 362 },
  { lap_index: 17, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 361, avg_pace_sec_per_mile: 361 },
  { lap_index: 18, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 358, avg_pace_sec_per_mile: 358 },
  { lap_index: 19, is_rest: false, distance_meters: 820, moving_time_seconds: 245, avg_pace_sec_per_mile: 481 },
  { lap_index: 20, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 349, avg_pace_sec_per_mile: 349 },
  { lap_index: 21, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 332, avg_pace_sec_per_mile: 332 },
  { lap_index: 22, is_rest: false, distance_meters: 1609.34, moving_time_seconds: 330, avg_pace_sec_per_mile: 330 },
  { lap_index: 23, is_rest: false, distance_meters: 845.7, moving_time_seconds: 257, avg_pace_sec_per_mile: 489 },
];

Deno.test("contextual: 4×3mi at steady inside a 21-miler reads as 4×3mi long_wo, not 1×2mi", () => {
  const r = segmentFromLaps(AUG29, LIVE_ZONES);
  assertEquals(r.repCount, 4);
  assert(r.structure!.includes("4×3mi"), `structure was: ${r.structure}`);
  assert(r.structure!.includes("steady"), `structure was: ${r.structure}`);
  assertEquals(r.workoutKind, "long_wo");
  // Load math must NOT move: bout flags still come from the absolute gate.
  assertEquals(r.bouts.filter((b) => b.isWork).length, 2);
});

Deno.test("contextual: mile reps with 400m floats in a 17-mi long run (Aug 1) grow structure", () => {
  // Real laps from log 537ca8af: 3 mi warm-up, then mile-ish efforts at
  // 5:56–6:24 alternating with ~400m floats at 6:57–8:35. No lap is anywhere
  // near the MP anchor.
  const paces: Array<[number, number, boolean]> = [
    [1609.34, 467, false], [1609.34, 446, false], [1609.34, 456, false],
    [99.61, 517, true],
    [1609.34, 360, false], [401.95, 436, false], [1609.34, 378, false],
    [1609.34, 383, false], [343.2, 450, false], [50.04, 450, true],
    [1609.34, 359, false], [408.56, 425, false], [1609.34, 379, false],
    [1609.34, 384, false], [401.4, 449, false], [1609.34, 362, false],
    [405.38, 417, false], [1609.34, 374, false], [1609.34, 377, false],
    [314.94, 465, false], [1609.34, 356, false], [399.35, 463, false],
    [1609.34, 381, false], [1609.34, 384, false], [406.17, 515, false],
  ];
  const laps: LapInput[] = paces.map(([d, p, rest], i) => ({
    lap_index: i + 1, is_rest: rest, distance_meters: d,
    moving_time_seconds: Math.round(p * (d / 1609.344)), avg_pace_sec_per_mile: p,
  }));
  const r = segmentFromLaps(laps, LIVE_ZONES);
  assertEquals(r.workoutKind, "long_wo");
  assert(r.repCount >= 2, `repCount: ${r.repCount}`);
  assert(r.structure != null && !r.structure.includes("mi long"), `structure was: ${r.structure}`);
});

Deno.test("contextual: an evenly-paced long run stays a plain long run", () => {
  const paces = [408, 402, 399, 404, 396, 401, 398, 405, 400, 397, 403, 399, 402, 398, 400, 396, 401];
  const laps: LapInput[] = paces.map((p, i) => ({
    lap_index: i + 1, is_rest: false, distance_meters: 1609.34,
    moving_time_seconds: p, avg_pace_sec_per_mile: p,
  }));
  const r = segmentFromLaps(laps, LIVE_ZONES);
  assertEquals(r.workoutKind, "long_run");
  assertEquals(r.repCount, 0);
  assert(r.structure!.includes("mi long"), `structure was: ${r.structure}`);
});

Deno.test("contextual: a negative-split long run is NOT a workout (one merged block fails the 2-rep floor)", () => {
  const paces = [432, 428, 431, 429, 430, 428, 431, 430, 386, 384, 387, 383, 385, 386, 384, 385];
  const laps: LapInput[] = paces.map((p, i) => ({
    lap_index: i + 1, is_rest: false, distance_meters: 1609.34,
    moving_time_seconds: p, avg_pace_sec_per_mile: p,
  }));
  const r = segmentFromLaps(laps, LIVE_ZONES);
  assertEquals(r.workoutKind, "long_run");
  assertEquals(r.repCount, 0);
});

Deno.test("contextual: a continuous cutdown long run does not grow rep structure (May 28 false positive)", () => {
  // Real laps (log 3baceacc): 2 km warm-up, then a continuous 17 km cutdown
  // 6:31→5:46 with no floats, 1 km cool-down. The backfill briefly published
  // "17×1K @ 6:17 (moderate)" — the fast side's spread (56 s/mi) dwarfed the
  // 26 s/mi boundary gap, so this is one drifting effort, not 17 reps.
  const paces = [451, 451, 391, 388, 396, 385, 401, 381, 385, 402, 380, 375, 375, 386, 356, 354, 346, 348, 357, 428];
  const laps: LapInput[] = paces.map((p, i) => ({
    lap_index: i + 1, is_rest: false, distance_meters: 1000,
    moving_time_seconds: Math.round(p * (1000 / 1609.344)), avg_pace_sec_per_mile: p,
  }));
  const r = segmentFromLaps(laps, LIVE_ZONES);
  // "1×1K @ 5:46" is the pre-existing absolute reading (one km clears the
  // work gate) and stays; the guard only has to stop the 17-rep explosion.
  assert(!(r.structure ?? "").includes("17×"), `structure was: ${r.structure}`);
  assert(r.repCount <= 1, `repCount: ${r.repCount}`);
});

Deno.test("contextual: a long run with mild pace variance stays a long run (Jun 20 false positive)", () => {
  // Real laps (log 0abe300d): 13 mi wandering 6:26–7:44 with one slower km in
  // the middle. Was briefly read as "7mi-1K-1K-…-1K @ 6:53 (easy)".
  const paces = [459, 420, 423, 417, 423, 410, 420, 402, 399, 414, 406, 406, 457, 420, 431, 418, 406, 406, 386, 404, 430];
  const laps: LapInput[] = paces.map((p, i) => ({
    lap_index: i + 1, is_rest: false, distance_meters: 1000,
    moving_time_seconds: Math.round(p * (1000 / 1609.344)), avg_pace_sec_per_mile: p,
  }));
  const r = segmentFromLaps(laps, LIVE_ZONES);
  assertEquals(r.workoutKind, "long_run");
  assertEquals(r.repCount, 0);
  assert(r.structure!.includes("mi long"), `structure was: ${r.structure}`);
});
