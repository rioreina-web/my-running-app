/**
 * Regression tests from the first real-data run (athlete 03857bf3, 75 days).
 *
 * Both cases below produced findings that were true about the data and false
 * about the athlete. They are the reason MIN_EASY_DISTANCE_MI and
 * MISLABEL_MARGIN_SEC exist.
 *
 * Run: deno test --allow-all _shared/watch/easyDayDiscipline.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { easyDayDiscipline } from "./easyDayDiscipline.ts";
import type { WatchContext } from "./types.ts";

const NOW = new Date("2026-08-27T12:00:00Z");
const ago = (n: number) => new Date(NOW.getTime() - n * 86_400_000).toISOString().slice(0, 10);
const BAND = { paceFast: 423, paceSlow: 483 }; // 7:03–8:03, this athlete's real band

const MODERATE = { paceFast: 376, paceSlow: 423 }; // this athlete's real moderate band

function ctx(easyRuns: WatchContext["easyRuns"]): WatchContext {
  return { athleteUserId: "a-1", now: NOW, moodHistory: [], easyBand: BAND, moderateBand: MODERATE, easyRuns };
}

Deno.test("warmup and cooldown fragments are not easy days", () => {
  // Real shape: 1–2.5mi rows logged around interval sessions. Includes a
  // 19:24/mi walking recovery and a 1mi rep at 5:19 — neither is an easy day.
  const r = easyDayDiscipline.evaluate(ctx([
    { date: ago(1), paceSecPerMile: 319, workoutType: "easy", distanceMiles: 1.0 },
    { date: ago(1), paceSecPerMile: 1164, workoutType: "recovery", distanceMiles: 2.24 },
    { date: ago(3), paceSecPerMile: 471, workoutType: "easy", distanceMiles: 2.01 },
    { date: ago(5), paceSecPerMile: 455, workoutType: "easy", distanceMiles: 7.47 },
    { date: ago(7), paceSecPerMile: 460, workoutType: "easy", distanceMiles: 10.01 },
    { date: ago(9), paceSecPerMile: 452, workoutType: "easy", distanceMiles: 8.01 },
  ]));
  // The three real runs all sit inside the band; the fragments must not drag
  // the finding out of "clear".
  assertEquals(r.kind, "clear");
});

Deno.test("a full run far too fast to be easy is reported as mislabelled, not as drift", () => {
  // Real row: 7 miles typed `easy` at 5:42/mi against a 7:03 band. Folding it
  // into the average produced "103s/mi too quick", which describes a mislabel,
  // not easy-day discipline.
  const r = easyDayDiscipline.evaluate(ctx([
    { date: ago(1), paceSecPerMile: 342, workoutType: "easy", distanceMiles: 7.0 },
    { date: ago(3), paceSecPerMile: 455, workoutType: "easy", distanceMiles: 7.0 },
    { date: ago(5), paceSecPerMile: 460, workoutType: "easy", distanceMiles: 6.0 },
    { date: ago(7), paceSecPerMile: 450, workoutType: "easy", distanceMiles: 8.0 },
  ]));
  assertEquals(r.kind, "finding", "a mislabel must not be silently swallowed");
  if (r.kind !== "finding") return;

  // Reported as a labelling problem, not as easy-day drift.
  assertEquals(r.finding.severity, "info");
  assert(r.finding.headline.toLowerCase().includes("filed as easy"));

  // And never averaged into a drift number — that was the original bug.
  assert(!r.finding.detail.includes("103s/mi"));
  assert(!r.finding.detail.includes("drifting"));
});

Deno.test("genuine drift still fires once the noise is filtered", () => {
  const r = easyDayDiscipline.evaluate(ctx([
    { date: ago(1), paceSecPerMile: 395, workoutType: "easy", distanceMiles: 6.0 },
    { date: ago(3), paceSecPerMile: 400, workoutType: "easy", distanceMiles: 7.0 },
    { date: ago(5), paceSecPerMile: 405, workoutType: "easy", distanceMiles: 5.0 },
    { date: ago(7), paceSecPerMile: 460, workoutType: "easy", distanceMiles: 8.0 },
  ]));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  assert(r.finding.detail.includes("3 of the last 4"));
});

Deno.test("a run with no distance recorded is kept, not silently dropped", () => {
  const r = easyDayDiscipline.evaluate(ctx([
    { date: ago(1), paceSecPerMile: 395, workoutType: "easy", distanceMiles: null },
    { date: ago(3), paceSecPerMile: 400, workoutType: "easy", distanceMiles: null },
    { date: ago(5), paceSecPerMile: 405, workoutType: "easy", distanceMiles: null },
  ]));
  assertEquals(r.kind, "finding");
});
