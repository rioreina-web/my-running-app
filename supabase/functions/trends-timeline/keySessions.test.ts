/**
 * Tests for keySessions.ts — Section-A quality-session derivation.
 * Run: deno test supabase/functions/trends-timeline/keySessions.test.ts
 *
 * No LLM in this path, so no eval cassette is required (the eval gate fires
 * only on `_shared/prompts/` changes). These guard the pure math: work-bout
 * pace (rest excluded), zone selection, heat-adjusted pace, time-weighted
 * work HR, structure fallback, and honest degradation (no laps → no dot).
 */
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildKeySessions,
  buildQualityVolume,
  deriveKeySession,
  type KeySessionFeature,
  type KeySessionLap,
  type KeySessionLog,
} from "./keySessions.ts";
import type { PaceZones } from "../_shared/workoutSegmentation.ts";

// Maya-ish zone table (sec/mile). fiveK = 6:00, so ~6:00 reps classify 5k.
const ZONES: PaceZones = {
  mile: 330,
  threeK: 345,
  fiveK: 360,
  tenK: 380,
  hm: 410,
  mp: 440,
  steady: 480,
  moderate: 520,
  easy: 560,
};

const M_PER_MILE = 1609.344;
/** moving_time for `meters` at `paceSecPerMile`. */
const movSecs = (meters: number, pace: number) => Math.round((meters / M_PER_MILE) * pace);

/** A work rep: 1000 m at `pace`, optional HR + heat. */
function rep(
  lap_index: number,
  pace: number,
  opts: Partial<KeySessionLap> = {},
): KeySessionLap {
  return {
    lap_index,
    is_rest: false,
    distance_meters: 1000,
    avg_pace_sec_per_mile: pace,
    moving_time_seconds: movSecs(1000, pace),
    elapsed_time_seconds: movSecs(1000, pace),
    ...opts,
  };
}

/** A recovery jog: 400 m, flagged rest. */
function rest(lap_index: number, pace = 540): KeySessionLap {
  return {
    lap_index,
    is_rest: true,
    distance_meters: 400,
    avg_pace_sec_per_mile: pace,
    moving_time_seconds: movSecs(400, pace),
    elapsed_time_seconds: movSecs(400, pace),
  };
}

/** An easy warmup/cooldown mile. */
function easy(lap_index: number, pace = 540): KeySessionLap {
  return {
    lap_index,
    is_rest: false,
    distance_meters: 1609,
    avg_pace_sec_per_mile: pace,
    moving_time_seconds: movSecs(1609, pace),
    elapsed_time_seconds: movSecs(1609, pace),
  };
}

const LOG: KeySessionLog = {
  id: "log-1",
  workout_date: "2026-06-23T13:00:00Z",
  workout_distance_miles: 6.0,
};

Deno.test("5K rep session: rest excluded, zone = 5k, distance-weighted pace", () => {
  const laps: KeySessionLap[] = [
    easy(0),
    rep(1, 358),
    rest(2),
    rep(3, 360),
    rest(4),
    rep(5, 365),
    easy(6),
  ];
  const s = deriveKeySession(LOG, laps, undefined, ZONES);
  assert(s !== null, "expected a derived session");
  assertEquals(s!.zone, "5k");
  // Equal-distance reps → simple mean (358+360+365)/3 = 361.0 → 361.
  assertEquals(s!.work_pace_sec, 361);
  assertEquals(s!.date, "2026-06-23");
  // No heat data on these laps.
  assertEquals(s!.work_pace_adj_sec, null);
  assertEquals(s!.heat_category, null);
});

Deno.test("heat-adjusted pace uses the uniform session ratio", () => {
  // Every lap carries the workout weather snapshot: adj = raw * 0.95.
  const withHeat = (l: KeySessionLap): KeySessionLap => ({
    ...l,
    heat_adjusted_pace_sec_per_mile: Math.round((l.avg_pace_sec_per_mile ?? 0) * 0.95),
    heat_category: "hot",
  });
  const laps = [easy(0), rep(1, 360), rest(2), rep(3, 360)].map(withHeat);
  const s = deriveKeySession(LOG, laps, undefined, ZONES)!;
  assertEquals(s.work_pace_sec, 360);
  assertEquals(s.heat_category, "hot");
  // 360 * 0.95 = 342.
  assertEquals(s.work_pace_adj_sec, 342);
});

Deno.test("quality_load: weighted work-minutes, rest + easy excluded", () => {
  const laps: KeySessionLap[] = [
    easy(0),      // excluded from load
    rep(1, 358),
    rest(2),      // excluded from load
    rep(3, 360),
    rest(4),      // excluded from load
    rep(5, 365),
    easy(6),      // excluded from load
  ];
  const s = deriveKeySession(LOG, laps, undefined, ZONES)!;
  // Same three 5k work bouts the pace test asserts (zone = 5k → weight 4.0).
  // Load = Σ(bout sec × 4.0) / 60, over work bouts only.
  const workSec = movSecs(1000, 358) + movSecs(1000, 360) + movSecs(1000, 365);
  const expected = Math.round((workSec * 4.0 / 60) * 10) / 10;
  assertEquals(s.quality_load, expected);
  assert(s.quality_load > 0, "a real rep session carries load");
});

Deno.test("time-weighted work HR over work bouts only", () => {
  const laps: KeySessionLap[] = [
    easy(0, 540), // no HR
    rep(1, 360, { avg_heart_rate: 168 }),
    rest(2),
    rep(3, 360, { avg_heart_rate: 172 }),
  ];
  const s = deriveKeySession(LOG, laps, undefined, ZONES)!;
  // Equal-duration reps → mean(168,172) = 170.
  assertEquals(s.work_hr_avg, 170);
});

Deno.test("structure: feature string wins, else ZONE + distance fallback", () => {
  const laps = [rep(1, 360), rest(2), rep(3, 360)];
  const feat: KeySessionFeature = { training_log_id: "log-1", workout_structure: "5K 5×1km · 6.0 mi" };
  assertEquals(deriveKeySession(LOG, laps, feat, ZONES)!.structure, "5K 5×1km · 6.0 mi");
  assertEquals(deriveKeySession(LOG, laps, undefined, ZONES)!.structure, "5K 6 mi");
});

Deno.test("honest degradation: no laps and pure-easy runs produce no dot", () => {
  assertEquals(deriveKeySession(LOG, [], undefined, ZONES), null);
  const easyOnly = [easy(0), easy(1), easy(2)];
  assertEquals(deriveKeySession(LOG, easyOnly, undefined, ZONES), null);
});

Deno.test("buildKeySessions: one dot per qualifying workout, date-sorted", () => {
  const logs: KeySessionLog[] = [
    { id: "b", workout_date: "2026-06-19", workout_distance_miles: 2.6 },
    { id: "a", workout_date: "2026-06-09", workout_distance_miles: 7.4 },
    { id: "c", workout_date: "2026-06-17", workout_distance_miles: 5.3 }, // easy only
  ];
  const laps = new Map<string, KeySessionLap[]>([
    ["b", [rep(1, 348), rest(2), rep(3, 350)]], // ~3k/5k boundary
    ["a", [easy(0), rep(1, 408), rep(2, 412), easy(3)]], // hmp-ish continuous
    ["c", [easy(0), easy(1)]], // no work
  ]);
  const out = buildKeySessions(logs, laps, new Map(), ZONES);
  assertEquals(out.map((s) => s.log_id), ["a", "b"]); // c omitted, date-sorted
  assertEquals(out[0].date, "2026-06-09");
});

// Reference = Mon 2026-06-15 → weeks=4 windows start 05-25, 06-01, 06-08, 06-15.
const VOL_REF = new Date("2026-06-15T12:00:00Z");

Deno.test("buildQualityVolume buckets work seconds into the right week", () => {
  const logs: KeySessionLog[] = [
    { id: "w1", workout_date: "2026-06-02", workout_distance_miles: 4 }, // wk 06-01
    { id: "w2", workout_date: "2026-06-09", workout_distance_miles: 4 }, // wk 06-08
  ];
  const laps = new Map<string, KeySessionLap[]>([
    ["w1", [rep(1, 360), rest(2), rep(3, 360)]], // two 5k reps → 2×224s
    ["w2", [rep(1, 360), rest(2), rep(3, 360)]],
  ]);
  const vol = buildQualityVolume(logs, laps, ZONES, 4, VOL_REF);
  assertEquals(vol.length, 4);
  assertEquals(vol.map((w) => w.week_start), ["2026-05-25", "2026-06-01", "2026-06-08", "2026-06-15"]);
  // Each qualifying week holds 2 reps × mov(1000,360)=224s = 448s at 5k.
  assertEquals(vol[1].zone_seconds["5k"], 448);
  assertEquals(vol[2].zone_seconds["5k"], 448);
  // Down weeks are a real empty object, not a gap.
  assertEquals(vol[0].zone_seconds, {});
  assertEquals(vol[3].zone_seconds, {});
});

Deno.test("buildQualityVolume excludes rest + non-work, no laps → all empty", () => {
  const logs: KeySessionLog[] = [
    { id: "e", workout_date: "2026-06-09", workout_distance_miles: 6 },
  ];
  const laps = new Map<string, KeySessionLap[]>([["e", [easy(0), easy(1)]]]);
  const vol = buildQualityVolume(logs, laps, ZONES, 4, VOL_REF);
  for (const w of vol) assertEquals(w.zone_seconds, {});
});
