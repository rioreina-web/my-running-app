/**
 * Tests for the recency-weighted evidence blend.
 *
 * The defining case is the one Rio described: a 16:00 5K in January, eight
 * weeks of training at a 15:35 level, a 15:35 5K in March. The model must
 * read 15:35 BEFORE that March race is run.
 *
 * Run: deno test _shared/evidenceBlend.test.ts
 */
import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  blendEvidence,
  DEFAULT_HALF_LIFE_DAYS,
  RACE_WEIGHT,
  SESSION_WEIGHT,
  type Evidence,
} from "./evidenceBlend.ts";

const NOW = new Date("2026-03-15T00:00:00Z");
const MI = 6.21371;
const day = (agoDays: number) =>
  new Date(NOW.getTime() - agoDays * 86_400_000).toISOString().slice(0, 10);

/** A 5K time → the 10K pace it implies (ratio table: 5K = 0.48125 of 10K). */
const paceFrom5K = (seconds: number) => (seconds / 0.48125) / MI;
const to5K = (tenKPace: number) => tenKPace * MI * 0.48125;
const fmt = (s: number) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;

Deno.test("the January-to-March case: training carries the improvement", () => {
  const ev: Evidence[] = [
    { tenKPace: paceFrom5K(960), date: day(56), kind: "race" }, // 16:00, 8 weeks ago
  ];
  // Two sessions a week for eight weeks, all at the 15:35 level.
  for (let w = 0; w < 8; w++) {
    ev.push({ tenKPace: paceFrom5K(935), date: day(w * 7 + 2), kind: "session" });
    ev.push({ tenKPace: paceFrom5K(935), date: day(w * 7 + 5), kind: "session" });
  }
  const r = blendEvidence(ev, NOW);
  assert(r.tenKPace !== null);
  const fiveK = to5K(r.tenKPace);
  assert(
    fiveK < 940,
    `should read close to 15:35 before the race; got ${fmt(fiveK)} (old rule gave 15:55)`,
  );
});

Deno.test("a race run yesterday dominates the sessions around it", () => {
  const ev: Evidence[] = [
    { tenKPace: paceFrom5K(935), date: day(1), kind: "race" },
    { tenKPace: paceFrom5K(990), date: day(3), kind: "session" },
    { tenKPace: paceFrom5K(990), date: day(6), kind: "session" },
  ];
  const r = blendEvidence(ev, NOW)!;
  assert(r.raceShare > 0.55, `a fresh race should hold most of the weight; got ${r.raceShare}`);
  assert(to5K(r.tenKPace!) < 960, "and pull the estimate toward itself");
});

Deno.test("an old race fades rather than anchoring forever", () => {
  const mk = (raceAgoDays: number) =>
    blendEvidence([
      { tenKPace: paceFrom5K(960), date: day(raceAgoDays), kind: "race" },
      { tenKPace: paceFrom5K(935), date: day(3), kind: "session" },
      { tenKPace: paceFrom5K(935), date: day(10), kind: "session" },
    ], NOW).raceShare;
  assert(mk(3) > mk(60), "a 3-day-old race must outweigh a 60-day-old one");
  assert(mk(180) < 0.05, `a 6-month-old race should be nearly spent; got ${mk(180)}`);
});

Deno.test("training alone works — an athlete who has never raced still has a fitness", () => {
  const r = blendEvidence([
    { tenKPace: 309, date: day(4), kind: "session" },
    { tenKPace: 312, date: day(11), kind: "session" },
  ], NOW);
  assert(r.tenKPace !== null);
  assertEquals(r.raceShare, 0);
  assertEquals(r.raceCount, 0);
  assert(r.tenKPace > 308 && r.tenKPace < 313);
});

Deno.test("a race alone works — no training on file is not a failure", () => {
  const r = blendEvidence([{ tenKPace: 309, date: day(5), kind: "race" }], NOW);
  assertAlmostEquals(r.tenKPace!, 309, 1e-9);
  assertEquals(r.raceShare, 1);
});

Deno.test("no evidence yields null rather than a fabricated number", () => {
  const r = blendEvidence([], NOW);
  assertEquals(r.tenKPace, null);
  assert(r.why.includes("no evidence"));
});

Deno.test("there is no ceiling — sustained training can move any distance", () => {
  // An athlete 12% faster than their year-old race, training consistently.
  const ev: Evidence[] = [{ tenKPace: 360, date: day(365), kind: "race" }];
  for (let w = 0; w < 12; w++) ev.push({ tenKPace: 317, date: day(w * 7 + 2), kind: "session" });
  const r = blendEvidence(ev, NOW)!;
  assert(
    r.tenKPace! < 318,
    `training should reach its own level with no cap; got ${r.tenKPace!.toFixed(1)}`,
  );
});

Deno.test("the estimate follows form DOWN as readily as up", () => {
  const ev: Evidence[] = [{ tenKPace: 300, date: day(70), kind: "race" }];
  for (let w = 0; w < 8; w++) ev.push({ tenKPace: 330, date: day(w * 7 + 2), kind: "session" });
  const r = blendEvidence(ev, NOW)!;
  assert(r.tenKPace! > 325, `a block of slower work must be believed too; got ${r.tenKPace}`);
});

Deno.test("recency ordering holds within a kind", () => {
  const recentFast = blendEvidence([
    { tenKPace: 300, date: day(2), kind: "session" },
    { tenKPace: 320, date: day(60), kind: "session" },
  ], NOW).tenKPace!;
  const recentSlow = blendEvidence([
    { tenKPace: 320, date: day(2), kind: "session" },
    { tenKPace: 300, date: day(60), kind: "session" },
  ], NOW).tenKPace!;
  assert(recentFast < recentSlow, "whichever is newer should pull harder");
});

Deno.test("quality scales an item down without special-casing it", () => {
  const full = blendEvidence([
    { tenKPace: 300, date: day(2), kind: "session" },
    { tenKPace: 330, date: day(2), kind: "session" },
  ], NOW).tenKPace!;
  const halved = blendEvidence([
    { tenKPace: 300, date: day(2), kind: "session", quality: 0.1 },
    { tenKPace: 330, date: day(2), kind: "session" },
  ], NOW).tenKPace!;
  assert(halved > full, "down-weighting the fast one should slow the blend");
});

Deno.test("malformed rows are skipped, not fatal", () => {
  const r = blendEvidence([
    { tenKPace: 309, date: day(3), kind: "session" },
    { tenKPace: 0, date: day(3), kind: "session" },
    { tenKPace: 309, date: "garbage", kind: "race" },
  ], NOW);
  assertEquals(r.sessionCount, 1);
  assertEquals(r.raceCount, 0);
});

Deno.test("the two knobs are the whole model", () => {
  assertEquals(RACE_WEIGHT / SESSION_WEIGHT, 3);
  assertEquals(DEFAULT_HALF_LIFE_DAYS, 21);
});
