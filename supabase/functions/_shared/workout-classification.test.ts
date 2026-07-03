/**
 * Tests for workout-classification.ts (WS1).
 * Run: deno test supabase/functions/_shared/workout-classification.test.ts
 *
 * Golden case = test athlete 03857bf3, May 20 2026: a real 9×1K @ ~5:07
 * session that the legacy label-based scorer filed as "easy / 0 quality".
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { classifyWorkout, classifyPace, type PaceZones, type ClassifierLap } from "./workout-classification.ts";

// Test athlete's real pace zones (sec/mi) from athlete_state.
const ZONES: PaceZones = {
  mile: 272, fiveK: 302, threeK: 287, tenK: 314, threshold: 328,
  mp: 343, steady: 362, moderate: 405, easy: 429,
};

function lap(m: number, sec: number, pace: number, hr: number, rest = false): ClassifierLap {
  return { distance_meters: m, moving_time_seconds: sec, avg_pace_sec_per_mile: pace, avg_heart_rate: hr, is_rest: rest };
}

Deno.test("classifyPace maps real paces to athlete zones", () => {
  assertEquals(classifyPace(307, ZONES), "fiveK");   // 5:07 → 5K band
  assertEquals(classifyPace(332, ZONES), "threshold"); // 5:32 → threshold
  assertEquals(classifyPace(317, ZONES), "tenK");    // 5:17 → 10K
  assertEquals(classifyPace(430, ZONES), "easy");    // 7:10 → easy
  assertEquals(classifyPace(540, ZONES), "recovery"); // 9:00 → recovery
});

Deno.test("May 20 9×1K classifies as quality intervals (the golden bug)", () => {
  // Real laps (warmup, 9 reps @ ~5:07 with ~60s rests, cooldown).
  const laps: ClassifierLap[] = [
    lap(1000, 309, 497, 138),       // warmup (8:17-ish, slow)
    lap(1609, 480, 480, 132),       // warmup
    lap(1000, 191, 307, 162),       // rep 1
    lap(64, 63, 1579, 167, true),   // rest
    lap(1000, 192, 309, 168),       // rep 2
    lap(55, 67, 2012, 156, true),   // rest
    lap(1000, 190, 306, 166),       // rep 3
    lap(53, 63, 1979, 172, true),   // rest
    lap(1000, 191, 307, 168),       // rep 4
    lap(53, 63, 1959, 163, true),   // rest
    lap(1000, 192, 309, 169),       // rep 5
    lap(66, 66, 1664, 157, true),   // rest
    lap(1000, 191, 307, 170),       // rep 6
    lap(65, 63, 1567, 161, true),   // rest
    lap(1000, 192, 309, 169),       // rep 7
    lap(64, 69, 1798, 162, true),   // rest
    lap(1000, 191, 307, 169),       // rep 8
    lap(61, 63, 1723, 163, true),   // rest
    lap(1000, 190, 306, 166),       // rep 9
    lap(1200, 540, 432, 140),       // cooldown
  ];
  const r = classifyWorkout(laps, ZONES, 9.5);

  assertEquals(r.type, "intervals");
  assert(r.isQuality, "should be a quality session");
  assertEquals(r.repCount, 9, "should detect 9 work reps");
  assert(r.hardSeconds > 1500, `hardSeconds should reflect ~28min of work, got ${r.hardSeconds}`);
  assert(r.intensityScore > 1.8, `intensity should be well above easy(1.0), got ${r.intensityScore}`);
  assert(r.structure!.startsWith("9×1K"), `structure was "${r.structure}"`);
});

Deno.test("an all-easy run is not quality", () => {
  const laps: ClassifierLap[] = [
    lap(1609, 440, 440, 140), lap(1609, 435, 435, 142), lap(1609, 438, 438, 141),
    lap(1609, 432, 432, 143), lap(1609, 430, 430, 144),
  ];
  const r = classifyWorkout(laps, ZONES, 5.0);
  assertEquals(r.type, "easy");
  assertEquals(r.isQuality, false);
  assertEquals(r.repCount, 0);
});

Deno.test("a long easy run classifies as long_run", () => {
  const laps: ClassifierLap[] = Array.from({ length: 13 }, () => lap(1609, 445, 445, 140));
  const r = classifyWorkout(laps, ZONES, 13.0);
  assertEquals(r.type, "long_run");
  assertEquals(r.isQuality, false);
});

Deno.test("6×1mi @ 5:22 classifies as threshold cruise", () => {
  const laps: ClassifierLap[] = [
    lap(1609, 480, 480, 140), // warmup
    lap(1609, 322, 322, 165), lap(1609, 320, 320, 167), lap(1609, 324, 324, 168),
    lap(1609, 322, 322, 169), lap(1609, 323, 323, 170), lap(1609, 321, 321, 170),
    lap(1609, 500, 500, 150), // cooldown
  ];
  const r = classifyWorkout(laps, ZONES, 12.7);
  assertEquals(r.type, "threshold");
  assert(r.isQuality);
});
