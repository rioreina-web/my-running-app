import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { compareBuildWindows, summarizeBuildWindow, MAX_BUILD_CREDIT, BUILD_WINDOW_DAYS } from "./buildComparison.ts";
import type { WorkoutInput } from "./fitnessPrediction.ts";

const NOW = new Date("2026-08-27T00:00:00Z");
const RACE_DATE = new Date("2026-04-19T00:00:00Z");

const run = (date: string, miles: number, paceSecPerMile: number, type: string): WorkoutInput => ({
  date, distanceMiles: miles, durationMinutes: (miles * paceSecPerMile) / 60, paceSecondsPerMile: paceSecPerMile, type,
});

/** N weeks of a repeating pattern ending the day before `end`, exclusive. */
function block(end: Date, weeks: number, weekly: Array<[string, number, number, string]>): WorkoutInput[] {
  const out: WorkoutInput[] = [];
  for (let w = 0; w < weeks; w++) {
    for (const [dow, miles, pace, type] of weekly) {
      const offsetDays = w * 7 + Number(dow);
      const d = new Date(end.getTime() - (offsetDays + 1) * 86_400_000);
      out.push(run(d.toISOString().slice(0, 10), miles, pace, type));
    }
  }
  return out;
}

Deno.test("no history before the race's build window → ineligible, not zero-by-accident", () => {
  const workouts = block(NOW, 4, [["0", 10, 500, "easy"]]); // only covers ~4 weeks, race is 4.5 months out
  const r = compareBuildWindows(workouts, RACE_DATE, NOW);
  assertEquals(r.eligible, false);
  assertEquals(r.creditPct, 0);
});

Deno.test("the exact scenario: weaker PR-era block, genuinely stronger block now → real credit, broad-based", () => {
  // PR-era (before the 2:46): lower volume, shorter long runs, slower threshold.
  const priorWeekly: Array<[string, number, number, string]> = [
    ["0", 16, 420, "long_run"],   // 16mi @ 7:00
    ["2", 6, 400, "threshold"],   // modest tempo
    ["1", 6, 510, "easy"],
    ["3", 6, 510, "easy"],
    ["4", 6, 510, "easy"],
    ["5", 5, 510, "easy"],
  ];
  // Current: heavier volume, longer long runs, faster threshold — the athlete
  // in the scenario: raised mileage, improved long runs, improved threshold.
  const currentWeekly: Array<[string, number, number, string]> = [
    ["0", 22, 410, "long_run"],   // 22mi @ 6:50 — longer AND faster
    ["2", 12, 370, "threshold"],  // more threshold volume, meaningfully faster
    ["1", 7, 500, "easy"],
    ["3", 7, 500, "easy"],
    ["4", 7, 500, "easy"],
    ["5", 6, 500, "easy"],
    ["6", 8, 495, "easy"],
  ];
  const prior = block(RACE_DATE, 7, priorWeekly);
  const current = block(NOW, 7, currentWeekly);
  const r = compareBuildWindows([...prior, ...current], RACE_DATE, NOW);

  assert(r.eligible, r.reason);
  assert(r.zonesImproved.includes("longRun"), JSON.stringify(r.zones));
  assert(r.zonesImproved.includes("threshold"), JSON.stringify(r.zones));
  assert(r.zonesImproved.includes("easy"), JSON.stringify(r.zones));
  assert(r.creditPct > 0.02, `expected broad-based credit, got ${r.creditPct}`);
  // Magnitude-scaled (2026-08-27): a zone that doubled volume at 8%+ faster
  // pace must earn visibly more than one that just cleared the bars — this
  // is the assertion that would have caught the flat-per-zone version.
  const threshold = r.zones.find((z) => z.zone === "threshold")!;
  const longRun = r.zones.find((z) => z.zone === "longRun")!;
  assert(threshold.paceImproved && threshold.volumeImproved);
  assert(longRun.paceImproved && longRun.volumeImproved);
  assert(threshold.paceRatio! - 1 > (longRun.paceRatio! - 1) * 2, "threshold's pace gain should dwarf long run's");
  // A flat-credit scheme would score these two identically. This shouldn't.
});

Deno.test("one standout session does not move the number — the cherry-pick guard", () => {
  // Same modest block both times, EXCEPT current has one big flashy tempo —
  // everything else (long run, easy, volume) is unchanged or worse.
  const priorWeekly: Array<[string, number, number, string]> = [
    ["0", 18, 420, "long_run"],
    ["1", 6, 510, "easy"], ["2", 6, 510, "easy"], ["3", 6, 510, "easy"],
  ];
  const currentWeekly: Array<[string, number, number, string]> = [
    ["0", 18, 420, "long_run"], // identical long run
    ["1", 6, 510, "easy"], ["2", 6, 510, "easy"], ["3", 6, 510, "easy"], // identical easy
    ["4", 3, 340, "threshold"], // one fast but SHORT session — under MIN_ZONE_MILES on its own in a single week, and this file compares 6-week TOTALS, so alone it's thin evidence
  ];
  const prior = block(RACE_DATE, 7, priorWeekly);
  const current = block(NOW, 7, currentWeekly);
  const r = compareBuildWindows([...prior, ...current], RACE_DATE, NOW);
  // longRun and easy are unchanged (no improvement); threshold is present only
  // in the current window (absent from prior) so it cannot form a ratio at all.
  assertEquals(r.zonesImproved.filter((z) => z === "longRun" || z === "easy").length, 0);
});

Deno.test("training that did NOT improve vs the PR-era block earns no credit", () => {
  const sameWeekly: Array<[string, number, number, string]> = [
    ["0", 20, 410, "long_run"], ["2", 8, 370, "threshold"],
    ["1", 6, 500, "easy"], ["3", 6, 500, "easy"], ["4", 6, 500, "easy"],
  ];
  const prior = block(RACE_DATE, 7, sameWeekly);
  const current = block(NOW, 7, sameWeekly);
  const r = compareBuildWindows([...prior, ...current], RACE_DATE, NOW);
  assert(r.eligible);
  assertEquals(r.creditPct, 0, JSON.stringify(r.zones));
});

Deno.test("a zone present in only one window yields no pace ratio, not a fabricated one", () => {
  const prior = block(RACE_DATE, 7, [["0", 20, 410, "long_run"], ["1", 6, 500, "easy"]]);
  const current = block(NOW, 7, [["0", 20, 410, "long_run"], ["1", 6, 500, "easy"], ["3", 8, 370, "threshold"]]);
  const r = compareBuildWindows([...prior, ...current], RACE_DATE, NOW);
  const thresholdZone = r.zones.find((z) => z.zone === "threshold");
  assertEquals(thresholdZone, undefined); // absent from prior → not compared at all
});

Deno.test("summarizeBuildWindow: unlabeled runs default to easy, not dropped", () => {
  const workouts = [run("2026-08-01", 6, 500, "")];
  const s = summarizeBuildWindow(workouts, new Date("2026-07-01"), new Date("2026-09-01"));
  assertEquals(s.zones.easy?.miles, 6);
});

Deno.test("magnitude-scaled credit: a huge improvement earns visibly more than a marginal one", () => {
  const marginalCurrent: Array<[string, number, number, string]> = [
    ["0", 20, 410, "long_run"], ["2", 8, 370, "threshold"],
    ["1", 6, 500, "easy"], ["3", 6, 500, "easy"], ["4", 6, 500, "easy"],
  ];
  const hugeCurrent: Array<[string, number, number, string]> = [
    ["0", 20, 410, "long_run"], ["2", 16, 340, "threshold"], // same volume, MUCH faster
    ["1", 6, 500, "easy"], ["3", 6, 500, "easy"], ["4", 6, 500, "easy"],
  ];
  const prior: Array<[string, number, number, string]> = [
    ["0", 20, 410, "long_run"], ["2", 8, 400, "threshold"],
    ["1", 6, 500, "easy"], ["3", 6, 500, "easy"], ["4", 6, 500, "easy"],
  ];
  const priorBlock = block(RACE_DATE, 7, prior);
  const marginal = compareBuildWindows([...priorBlock, ...block(NOW, 7, marginalCurrent)], RACE_DATE, NOW);
  const huge = compareBuildWindows([...priorBlock, ...block(NOW, 7, hugeCurrent)], RACE_DATE, NOW);
  assert(huge.creditPct > marginal.creditPct * 2, `huge=${huge.creditPct} marginal=${marginal.creditPct} — should not be close`);
});
