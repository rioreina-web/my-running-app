import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  bandForIndex,
  computeWorkloadScore,
  DEFAULT_REFERENCE_LOAD,
  referenceLoadFromSessions,
  sessionLoadFromIntensity,
} from "./workloadScore.ts";

// ── Raw load ───────────────────────────────────────────────────────────────

Deno.test("sessionLoadFromIntensity = intensity × minutes", () => {
  // An easy hour: intensity ~1.0 × 60 min = 60 weighted-min.
  assertEquals(sessionLoadFromIntensity(1.0, 3600), 60);
});

Deno.test("sessionLoadFromIntensity guards zero / null inputs", () => {
  assertEquals(sessionLoadFromIntensity(null, 3600), 0);
  assertEquals(sessionLoadFromIntensity(2.5, 0), 0);
  assertEquals(sessionLoadFromIntensity(0, 3600), 0);
});

// ── The vision's headline example ───────────────────────────────────────────

Deno.test("2:30 marathoner: 14 mi @ 5:45 (MP) reads as a massive block, not an easy run", () => {
  // 14 mi × 5:45 (345 s/mi) = 4830 s ≈ 80.5 min, essentially all in the MP zone
  // (weight 2.5). Load ≈ 201 weighted-min.
  const mpLoad = sessionLoadFromIntensity(2.5, 14 * 345);
  const easyHour = sessionLoadFromIntensity(1.0, 3600);
  assert(mpLoad > 200 && mpLoad < 203, `expected ~201, got ${mpLoad}`);
  // The whole point: this MP session out-loads an easy hour by >3×, so the
  // score can't mistake a hard marathon-pace long run for a recovery jog.
  assert(mpLoad / easyHour > 3, `MP-14 should be >3× an easy hour, got ${mpLoad / easyHour}`);

  // Against a 2:30 marathoner's own big-session distribution (p90 ≈ 300 —
  // they train on 20-milers and long MP blocks), 14 @ MP is a "heavy" day:
  // real, demanding, but not their absolute peak. Exactly the read we want.
  const score = computeWorkloadScore(mpLoad, 300);
  assertEquals(score.band, "heavy");
  assert(score.index >= 6 && score.index < 8, `index ${score.index}`);
});

// ── Index scaling + bands ────────────────────────────────────────────────────

Deno.test("index is athlete-relative: same load, different fitness → different score", () => {
  const load = 120;
  // A low-volume athlete (small reference) feels this as near-peak…
  assert(computeWorkloadScore(load, 130).index >= 8);
  // …while a high-volume athlete (big reference) reads it as routine.
  assert(computeWorkloadScore(load, 300).index < 5);
});

Deno.test("index caps at 10 and floors at 0", () => {
  assertEquals(computeWorkloadScore(9999, 200).index, 10);
  assertEquals(computeWorkloadScore(0, 200).index, 0);
  assertEquals(computeWorkloadScore(-50, 200).index, 0);
});

Deno.test("bands partition the 0–10 index", () => {
  assertEquals(bandForIndex(0.5), "light");
  assertEquals(bandForIndex(3), "moderate");
  assertEquals(bandForIndex(5), "solid");
  assertEquals(bandForIndex(7), "heavy");
  assertEquals(bandForIndex(9), "peak");
  assertEquals(bandForIndex(10), "peak");
});

Deno.test("no reference → DEFAULT_REFERENCE_LOAD, not a divide-by-zero", () => {
  const s = computeWorkloadScore(90, null);
  assertEquals(s.index, Math.round((90 / DEFAULT_REFERENCE_LOAD) * 100) / 10);
  assertEquals(computeWorkloadScore(90, 0).index, s.index);
});

// ── Reference load ───────────────────────────────────────────────────────────

Deno.test("referenceLoadFromSessions takes the p90 of real sessions", () => {
  // 10 sessions 10..100; p90 rank = floor(0.9 × 9) = 8 → the 90-value.
  const loads = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
  assertEquals(referenceLoadFromSessions(loads), 90);
});

Deno.test("referenceLoadFromSessions ignores zeros and thin history", () => {
  assertEquals(referenceLoadFromSessions([0, 0, 120]), DEFAULT_REFERENCE_LOAD); // <3 real
  // Zeros (rest days) drop out; p90 of the 4 real loads [40,80,120,200] is the
  // rank-2 value (120), so a lone 200 outlier can't define the ceiling.
  assertEquals(referenceLoadFromSessions([0, 0, 40, 80, 120, 200]), 120);
});
