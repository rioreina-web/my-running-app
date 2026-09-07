/**
 * Tests for the laps→workout_notes fallback ("6×800m @ 2:35 w/ 90s rec").
 * This is what lets the app know WHAT a workout was when the athlete didn't
 * describe it in a voice memo. Laps stay the source of truth.
 *
 * Run: deno test _shared/workout-notes.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { deriveWorkoutNotes, snapRepDistance, fmtClock } from "./workout-notes.ts";
import type { LapInput } from "./workoutSegmentation.ts";

// 800m run in `t` seconds → sec/mile.
const pace800 = (t: number) => t / (800 / 1609.344);

Deno.test("fmtClock: seconds under a minute, mm:ss at/above", () => {
  assertEquals(fmtClock(45), "45s");
  assertEquals(fmtClock(90), "1:30"); // ≥60s renders mm:ss; recovery uses its own <120s "90s" form
  assertEquals(fmtClock(155), "2:35");
  assertEquals(fmtClock(337), "5:37");
});

Deno.test("snapRepDistance: common distances snap, GPS slop tolerated", () => {
  assertEquals(snapRepDistance(805).label, "800m"); // 0.50mi
  assertEquals(snapRepDistance(800).sub, true);
  assertEquals(snapRepDistance(1609).label, "1600m"); // snaps to the 1600m common before the mile branch
  assertEquals(snapRepDistance(1609).sub, true); // 1600m reads as a track-style rep time, not pace/mile
  assertEquals(snapRepDistance(1700).label, "1mi"); // no common nearby → mile label
  assertEquals(snapRepDistance(1700).sub, false); // a true mile reads as pace/mile
});

Deno.test("deriveWorkoutNotes: clean 6×800 @ 2:35 w/ 90s rec", () => {
  const laps: LapInput[] = [];
  for (let i = 0; i < 6; i++) {
    laps.push({ distance_meters: 805, moving_time_seconds: 155, avg_pace_sec_per_mile: pace800(155), is_rest: false });
    if (i < 5) laps.push({ distance_meters: 200, moving_time_seconds: 90, avg_pace_sec_per_mile: 900, is_rest: true });
  }
  assertEquals(
    deriveWorkoutNotes({ workoutKind: "intervals", repCount: 6 }, laps),
    "6×800m @ 2:35 w/ 90s rec",
  );
});

Deno.test("deriveWorkoutNotes: recovery-bounded reps stay separate; unflagged jog dropped", () => {
  // 4×1mi tempo, each separated by a flagged recovery, then an UNFLAGGED slow
  // jog that must NOT count as a rep (it's >1.5× the fastest rep pace). Because
  // every mile is bounded by a real recovery, they read as 4 reps — not one
  // continuous 4-mile bout.
  const rest = { distance_meters: 110, moving_time_seconds: 70, avg_pace_sec_per_mile: 1000, is_rest: true };
  const laps: LapInput[] = [
    { distance_meters: 1609, moving_time_seconds: 326, avg_pace_sec_per_mile: 326, is_rest: false },
    rest,
    { distance_meters: 1609, moving_time_seconds: 327, avg_pace_sec_per_mile: 327, is_rest: false },
    rest,
    { distance_meters: 1609, moving_time_seconds: 337, avg_pace_sec_per_mile: 337, is_rest: false },
    rest,
    { distance_meters: 1609, moving_time_seconds: 358, avg_pace_sec_per_mile: 358, is_rest: false },
    // unflagged 9:48/mi float — a boundary, not a rep
    { distance_meters: 853, moving_time_seconds: 313, avg_pace_sec_per_mile: 588, is_rest: false },
  ];
  const out = deriveWorkoutNotes({ workoutKind: "intervals", repCount: 4 }, laps);
  assert(out !== null);
  assert(out!.includes("4×1600m"), `expected 4×1600m block in: ${out}`);
  // the slow float must not appear as its own rep block
  assert(!out!.includes("+"), `unflagged float should not add a block: ${out}`);
});

Deno.test("deriveWorkoutNotes: continuous 2k auto-lapped as 2×1k stays one 2k rep", () => {
  // The real Jun-17 session: 2 × (2k + 2×1k). The 2k reps are run continuously
  // but the watch auto-laps every km, so they arrive as two back-to-back 1000m
  // splits with NO recovery between them. They must merge into a single 2000m
  // rep — the bug was them re-splitting into a false "8×1000m".
  const work = (t: number) => ({ distance_meters: 1000, moving_time_seconds: t, avg_pace_sec_per_mile: t / (1000 / 1609.344), is_rest: false });
  const rest = (d: number, t: number) => ({ distance_meters: d, moving_time_seconds: t, avg_pace_sec_per_mile: 1500, is_rest: true });
  const laps: LapInput[] = [
    work(199), work(195),        // continuous 2k
    rest(128, 125),
    work(192),                   // 1k
    rest(73, 72),
    work(192),                   // 1k
    rest(69, 69),
    work(197), work(200),        // continuous 2k
    rest(148, 140),
    work(192),                   // 1k
    rest(77, 67),
    work(194),                   // 1k
  ];
  const out = deriveWorkoutNotes({ workoutKind: "threshold", repCount: 6 }, laps);
  assert(out !== null);
  assert(!out!.includes("8×1000m"), `must not re-split the continuous 2k: ${out}`);
  assert(out!.includes("2000m"), `expected merged 2k blocks: ${out}`);
  assert(out!.includes("2×1000m"), `expected the paired 1k blocks: ${out}`);
});

Deno.test("deriveWorkoutNotes: trims warmup/cooldown reps outside the work-pace band", () => {
  // A ~7:30 warmup mile and a ~7:11 cooldown mile bracket three 1k reps. Both
  // bracketing miles are slower than the reps but still under 1.5× the fastest
  // rep, so the recovery-jog filter alone wouldn't drop them — the end-trim
  // must, leaving just the three real reps.
  const rest = { distance_meters: 100, moving_time_seconds: 60, avg_pace_sec_per_mile: 900, is_rest: true };
  const laps: LapInput[] = [
    { distance_meters: 1609, moving_time_seconds: 450, avg_pace_sec_per_mile: 450, is_rest: false }, // warmup
    rest,
    { distance_meters: 1000, moving_time_seconds: 192, avg_pace_sec_per_mile: 309, is_rest: false },
    rest,
    { distance_meters: 1000, moving_time_seconds: 192, avg_pace_sec_per_mile: 309, is_rest: false },
    rest,
    { distance_meters: 1000, moving_time_seconds: 194, avg_pace_sec_per_mile: 312, is_rest: false },
    rest,
    { distance_meters: 1609, moving_time_seconds: 430, avg_pace_sec_per_mile: 430, is_rest: false }, // cooldown
  ];
  assertEquals(
    deriveWorkoutNotes({ workoutKind: "intervals", repCount: 5 }, laps),
    "3×1000m @ 3:13 w/ 60s rec",
  );
});

Deno.test("deriveWorkoutNotes: easy/continuous runs get no fabricated structure", () => {
  const laps: LapInput[] = [
    { distance_meters: 1609, moving_time_seconds: 450, avg_pace_sec_per_mile: 450, is_rest: false },
    { distance_meters: 1609, moving_time_seconds: 448, avg_pace_sec_per_mile: 448, is_rest: false },
  ];
  assertEquals(deriveWorkoutNotes({ workoutKind: "easy", repCount: 0 }, laps), null);
});

Deno.test("deriveWorkoutNotes: no laps → null", () => {
  assertEquals(deriveWorkoutNotes({ workoutKind: "intervals", repCount: 6 }, undefined), null);
  assertEquals(deriveWorkoutNotes({ workoutKind: "intervals", repCount: 6 }, []), null);
});
