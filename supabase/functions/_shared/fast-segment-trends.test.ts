/**
 * Tests for fast-segment trend analytics (per-system, mixed-session aware).
 * Run: deno test _shared/fast-segment-trends.test.ts
 */
import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  analyzeFastSegmentTrends,
  analyzeKeySession,
  dewPointF,
  systemForPace,
  SYSTEM_WORK_VOLUME_MILES,
  type KeySessionInput,
  type WorkoutLap,
} from "./fast-segment-trends.ts";
import type { ZoneTable } from "./quality-volume.ts";

const M = 1609.344;

// A competitive runner's zones (sec/mi), round numbers for legible assertions.
const ZONES: ZoneTable = {
  easy: 450, moderate: 420, steady: 390,
  mp: 360, hm: 340, lt: 330, tenK: 320, fiveK: 300, threeK: 290, mile: 280,
};

// helper: a lap at a target sec/mi over a distance in meters
function lap(
  distM: number,
  paceSecPerMile: number,
  hr?: number,
  opts?: { gradePct?: number; elevGain?: number; segments?: Array<{ seconds: number; gradePct: number }> },
): WorkoutLap {
  const miles = distM / M;
  return {
    distance_meters: distM,
    moving_time_seconds: Math.round(paceSecPerMile * miles),
    avg_pace_sec_per_mile: paceSecPerMile,
    avg_heart_rate: hr ?? null,
    max_heart_rate: hr != null ? hr + 6 : null,
    total_elevation_gain: opts?.elevGain ?? 0,
    avg_grade_pct: opts?.gradePct ?? null,
    grade_segments: opts?.segments ?? null,
  };
}
const REC = (distM: number, secs: number): WorkoutLap => ({
  distance_meters: distM, moving_time_seconds: secs,
  avg_pace_sec_per_mile: (secs / (distM / M)),
  avg_heart_rate: null, max_heart_rate: null, total_elevation_gain: 0,
});

Deno.test("systemForPace: nearest race anchor at MP+, null when aerobic", () => {
  assertEquals(systemForPace(300, ZONES), "5K");   // exactly 5K
  assertEquals(systemForPace(281, ZONES), "Mile"); // nearest mile
  assertEquals(systemForPace(319, ZONES), "10K");
  assertEquals(systemForPace(358, ZONES), "MP");   // just faster than MP
  assertEquals(systemForPace(400, ZONES), null);   // slower than MP → aerobic
  assertEquals(systemForPace(300, {}), null);      // no MP anchor → null
});

Deno.test("10×1K @ 5K pace: reps counted, recoveries excluded, 5K system", () => {
  const laps: WorkoutLap[] = [];
  for (let i = 0; i < 10; i++) {
    laps.push(lap(1000, 300, 168));       // ~5:00/mi 1K rep
    if (i < 9) laps.push(REC(180, 80));   // jog recovery between
  }
  const m = analyzeKeySession({ id: "a", date: "2026-05-20", laps }, ZONES)!;
  assertEquals(m.repCount, 10);
  assertEquals(m.primarySystem, "5K");
  assertEquals(m.bySystem.length, 1);
  assertEquals(m.bySystem[0].system, "5K");
  // 10 × 1000m ≈ 6.21 mi of work
  assertAlmostEquals(m.fastMiles, 6.21, 0.05);
  // 10 reps → 9 recoveries of 80s
  assertEquals(m.restTimeSeconds, 9 * 80);
  assert(m.workRestRatio! > 1, "work should exceed rest here");
  assert(m.avgHeartRate! > 160 && m.avgHeartRate! < 175);
});

Deno.test("consecutive fast laps with no recovery merge into ONE rep", () => {
  // two 1K fast laps back-to-back, then a recovery, then one more — 2 reps not 3
  const laps = [lap(1000, 300), lap(1000, 300), REC(180, 80), lap(1000, 300)];
  const m = analyzeKeySession({ id: "b", date: "2026-05-21", laps }, ZONES)!;
  assertEquals(m.repCount, 2);
  assertEquals(m.reps[0].distanceMeters, 2000); // first two merged
  assertEquals(m.reps[1].distanceMeters, 1000);
});

Deno.test("warmup & cooldown are excluded, not counted as rest", () => {
  const laps = [
    lap(3000, 470),            // warmup (slower than MP) — before first fast
    lap(1000, 300), REC(180, 80), lap(1000, 300),
    lap(3000, 470),            // cooldown — after last fast
  ];
  const m = analyzeKeySession({ id: "c", date: "2026-05-22", laps }, ZONES)!;
  assertEquals(m.repCount, 2);
  assertEquals(m.restTimeSeconds, 80); // only the one real recovery, no WU/CD
});

Deno.test("mixed-system session breaks down per system", () => {
  // ladder: 1600 @10K, 800 @5K, 400 @mile — three systems in one session
  const laps = [
    lap(1600, 320, 165), REC(200, 90),
    lap(800, 300, 172), REC(200, 90),
    lap(400, 281, 178),
  ];
  const m = analyzeKeySession({ id: "d", date: "2026-06-01", laps }, ZONES)!;
  assertEquals(m.repCount, 3);
  const systems = m.bySystem.map((s) => s.system).sort();
  assertEquals(systems, ["10K", "5K", "Mile"].sort());
  // primary system = most work volume → the 1600 @ 10K
  assertEquals(m.primarySystem, "10K");
});

Deno.test("volume status reads per-system against expected ranges", () => {
  // a 5K session with exactly 3.5 mi of work → in range [3,4]
  const laps5k: WorkoutLap[] = [];
  for (let i = 0; i < 5; i++) { laps5k.push(lap(1127, 300)); if (i < 4) laps5k.push(REC(180, 80)); } // 5×0.7mi≈3.5mi
  const m = analyzeKeySession({ id: "e", date: "2026-06-02", laps: laps5k }, ZONES)!;
  assertEquals(m.bySystem[0].volumeStatus, "in_range");

  // a mile session with only 1 mi of work when 1–2 expected → in range; 0.5mi → below
  const oneMile = analyzeKeySession(
    { id: "f", date: "2026-06-03", laps: [lap(400, 281), REC(200, 90), lap(400, 281), REC(200, 90), lap(400, 281), REC(200, 90), lap(400, 281)] },
    ZONES,
  )!;
  assert(oneMile.bySystem[0].workMiles < 1.1);
  assertEquals(SYSTEM_WORK_VOLUME_MILES["Mile"][0], 1);
});

Deno.test("heat: neutral-equivalent pace is FASTER than raw when hot", () => {
  const laps = [lap(1609, 300, 170), REC(200, 90), lap(1609, 300, 172)];
  const hot = analyzeKeySession(
    { id: "g", date: "2026-07-14", laps, weather: { tempF: 85, dewPointF: 74 } },
    ZONES,
  )!;
  assert(hot.neutralPaceSecPerMile! < hot.avgPaceSecPerMile, "cool-equivalent should be faster");
  assert(hot.heat!.adjustmentSecPerMile > 0);
  // no weather → no neutral pace
  const cool = analyzeKeySession({ id: "g2", date: "2026-07-14", laps }, ZONES)!;
  assertEquals(cool.neutralPaceSecPerMile, null);
});

Deno.test("metersPerBeat present with HR, null without", () => {
  const withHR = analyzeKeySession(
    { id: "h", date: "2026-07-01", laps: [lap(1000, 300, 168), REC(180, 80), lap(1000, 300, 170)] },
    ZONES,
  )!;
  assert(withHR.metersPerBeat! > 0);
  const noHR = analyzeKeySession(
    { id: "h2", date: "2026-07-01", laps: [lap(1000, 300), REC(180, 80), lap(1000, 300)] },
    ZONES,
  )!;
  assertEquals(noHR.metersPerBeat, null);
});

Deno.test("trend groups by system; a mixed session lands in several systems", () => {
  const s1: KeySessionInput = { // pure 5K session
    id: "s1", date: "2026-05-20",
    laps: [lap(1000, 302), REC(180, 80), lap(1000, 300), REC(180, 80), lap(1000, 298)],
  };
  const s2: KeySessionInput = { // mixed: 10K + 5K + mile, each a real chunk
    id: "s2", date: "2026-06-01",
    laps: [
      lap(1600, 320), REC(200, 90), lap(1600, 320), REC(200, 90), lap(1600, 320), REC(200, 90), // ~3 mi @10K
      lap(1000, 300), REC(200, 90), lap(1000, 300), REC(200, 90), lap(1000, 300), REC(200, 90), // ~1.9 mi @5K
      lap(800, 281), REC(200, 90), lap(800, 281),                                                // ~1 mi @mile
    ],
  };
  const t = analyzeFastSegmentTrends([s2, s1], ZONES); // pass out of order
  // sessions sorted chronologically
  assertEquals(t.sessions.map((s) => s.id), ["s1", "s2"]);
  // 5K trend should include BOTH sessions (s1 pure 5K, s2's 800 @5K)
  const fiveK = t.systems.find((x) => x.system === "5K")!;
  assertEquals(fiveK.points.map((p) => p.sessionId), ["s1", "s2"]);
  // 10K and Mile trends include only the mixed session
  assertEquals(t.systems.find((x) => x.system === "10K")!.points.map((p) => p.sessionId), ["s2"]);
  assertEquals(t.systems.find((x) => x.system === "Mile")!.points.map((p) => p.sessionId), ["s2"]);
});

Deno.test("grade: uphill reps → conditions pace (cool+flat) faster than heat-only", () => {
  // 1-mile reps up a 3% grade, in the heat.
  const laps = [
    lap(1609, 300, 170, { gradePct: 3 }), REC(200, 90),
    lap(1609, 300, 172, { gradePct: 3 }),
  ];
  const m = analyzeKeySession(
    { id: "up", date: "2026-07-14", laps, weather: { tempF: 85, dewPointF: 74 } },
    ZONES,
  )!;
  // raw > heat-only neutral > conditions (heat AND grade removed)
  assert(m.neutralPaceSecPerMile! < m.avgPaceSecPerMile);
  assert(m.conditionsPaceSecPerMile! < m.neutralPaceSecPerMile!);
  assertEquals(m.grade!.avgGradePct, 3);
  assert(m.grade!.adjustmentSecPerMile > 0); // hills cost time
});

Deno.test("grade: net-grade fallback from elevation gain when avg_grade_pct absent", () => {
  // ~48m of climb over 1609m ≈ 3% net grade, no explicit grade field.
  const laps = [
    lap(1609, 300, undefined, { elevGain: 48 }), REC(200, 90),
    lap(1609, 300, undefined, { elevGain: 48 }),
  ];
  const m = analyzeKeySession({ id: "net", date: "2026-06-10", laps }, ZONES)!;
  assert(m.grade != null);
  assert(m.grade!.avgGradePct > 2.5 && m.grade!.avgGradePct < 3.5, `grade ${m.grade!.avgGradePct}`);
  // no weather but real grade → conditions pace still computed (flat-equivalent)
  assert(m.conditionsPaceSecPerMile != null);
  assert(m.conditionsPaceSecPerMile! < m.avgPaceSecPerMile); // uphill → faster flat-equiv
});

Deno.test("grade: flat + no weather → no conditions pace, no grade block", () => {
  const laps = [lap(1000, 300), REC(180, 80), lap(1000, 300)];
  const m = analyzeKeySession({ id: "flat", date: "2026-06-11", laps }, ZONES)!;
  assertEquals(m.conditionsPaceSecPerMile, null);
  assertEquals(m.grade, null);
});

Deno.test("grade: downhill reps read SLOWER on a flat-equivalent (damped credit)", () => {
  const laps = [lap(1000, 300, undefined, { gradePct: -4 }), REC(180, 80), lap(1000, 300, undefined, { gradePct: -4 })];
  const m = analyzeKeySession({ id: "down", date: "2026-06-12", laps }, ZONES)!;
  // downhill help is damped, so the flat-equivalent is slower than the raw pace
  assert(m.conditionsPaceSecPerMile! > m.avgPaceSecPerMile, `cond ${m.conditionsPaceSecPerMile} raw ${m.avgPaceSecPerMile}`);
});

Deno.test("split grade: uphill segments → faster flat-equivalent pace", () => {
  const segs = [{ seconds: 200, gradePct: 5 }];
  const laps = [lap(1000, 300, undefined, { segments: segs }), REC(180, 80), lap(1000, 300, undefined, { segments: segs })];
  const m = analyzeKeySession({ id: "up2", date: "2026-06-21", laps }, ZONES)!;
  assert(m.conditionsPaceSecPerMile! < m.avgPaceSecPerMile, "uphill flat-equiv should be faster");
  assert(m.grade!.avgGradePct > 4);
});

Deno.test("split grade: downhill segments → slower flat-equivalent (damped credit)", () => {
  const segs = [{ seconds: 200, gradePct: -5 }];
  const laps = [lap(1000, 300, undefined, { segments: segs }), REC(180, 80), lap(1000, 300, undefined, { segments: segs })];
  const m = analyzeKeySession({ id: "dn2", date: "2026-06-22", laps }, ZONES)!;
  assert(m.conditionsPaceSecPerMile! > m.avgPaceSecPerMile, "downhill flat-equiv should be slower");
});

Deno.test("split grade: rolling net-flat rep still credits time (net grade misses it)", () => {
  // up then down, net ~0% — net-grade would see ~no adjustment; split does.
  const segs = [{ seconds: 150, gradePct: 8 }, { seconds: 150, gradePct: -8 }];
  const laps = [lap(1200, 300, undefined, { segments: segs }), REC(180, 80), lap(1200, 300, undefined, { segments: segs })];
  const m = analyzeKeySession({ id: "roll2", date: "2026-06-23", laps }, ZONES)!;
  assert(m.conditionsPaceSecPerMile! <= m.avgPaceSecPerMile, "rolling terrain costs time → some credit");
  if (m.grade) assert(Math.abs(m.grade.avgGradePct) < 1, `net grade ~0, got ${m.grade.avgGradePct}`);
});

Deno.test("split grade takes precedence over the net-grade fallback", () => {
  // Same rep, once with a flat split profile, once with only elevation gain.
  const flatSeg = analyzeKeySession(
    { id: "a", date: "2026-06-24", laps: [lap(1000, 300, undefined, { segments: [{ seconds: 200, gradePct: 0 }], elevGain: 40 }), REC(180, 80), lap(1000, 300, undefined, { segments: [{ seconds: 200, gradePct: 0 }], elevGain: 40 })] },
    ZONES,
  )!;
  // The flat split profile wins over the 40 m of "gain" → ~no grade effect.
  assert(Math.abs(flatSeg.grade == null ? 0 : flatSeg.grade.avgGradePct) < 1);
});

Deno.test("totalMiles: whole-run distance carried through (input, else lap sum)", () => {
  const laps = [lap(1000, 300), REC(180, 80), lap(1000, 300)];
  // explicit total
  const a = analyzeKeySession({ id: "t", date: "2026-07-01", laps, totalMiles: 8.2 }, ZONES)!;
  assertEquals(a.totalMiles, 8.2);
  // fallback = sum of laps
  const b = analyzeKeySession({ id: "t2", date: "2026-07-01", laps }, ZONES)!;
  assert(b.totalMiles! > 1.3 && b.totalMiles! < 1.5, `lap-sum ${b.totalMiles}`);
});

Deno.test("noise filter: a small HMP bite inside a 5K run stays out of the HMP trend", () => {
  const s: KeySessionInput = {
    id: "mix", date: "2026-07-08", totalMiles: 8.0,
    laps: [
      lap(1000, 300), REC(180, 80), lap(1000, 300), REC(180, 80), lap(1000, 300), REC(180, 80), // ~1.9 mi @5K
      lap(800, 340), // ~0.5 mi @HMP — incidental (recovery before it keeps it its own rep)
    ],
  };
  const t = analyzeFastSegmentTrends([s], ZONES);
  // 5K is a real chunk → present; HMP is only 0.5 mi → filtered out of trends
  assert(t.systems.find((x) => x.system === "5K") != null);
  assertEquals(t.systems.find((x) => x.system === "HMP"), undefined);
  // but the session's own breakdown still records the HMP bite honestly
  const sess = t.sessions[0];
  assert(sess.bySystem.some((v) => v.system === "HMP"));
  assertEquals(sess.totalMiles, 8.0);
});

Deno.test("dewPointF: Magnus conversion is sane for Austin summer", () => {
  // 85°F @ 65% RH ≈ mid-70s dew point
  const dp = dewPointF(85, 65);
  assert(dp > 71 && dp < 76, `got ${dp}`);
  // drier air → lower dew point
  assert(dewPointF(85, 30) < dewPointF(85, 70));
});
