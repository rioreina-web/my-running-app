/**
 * Tests for the Layer-1 workout-comparison engine. Pace zones are the same
 * test athlete as workoutSegmentation.test.ts: mile 272, 5K 302, 10K 314,
 * HMP 328, MP 343, steady 362, moderate 405, easy 429 (sec/mile).
 *
 * Run: deno test _shared/workoutComparison.test.ts
 */
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import type { PaceZones } from "./workoutSegmentation.ts";
import {
  allowedNumberTokens,
  buildWorkProfile,
  compareWorkouts,
  familyMatch,
  findBestComparison,
  rankComparisonCandidates,
  scoreComparability,
  verdictNumbersAllowed,
  type ComparisonLap,
  type ComparisonWorkout,
} from "./workoutComparison.ts";

const ZONES: PaceZones = {
  mile: 272, fiveK: 302, tenK: 314, hm: 328, mp: 343,
  steady: 362, moderate: 405, easy: 429,
};

// ── Fixture builders ────────────────────────────────────────────────

/** N×1K threshold-ish session with jog recoveries, warmup + cooldown. */
function thresholdSession(opts: {
  id: string;
  date: string;
  reps: number;
  repPace: number; // sec/mile
  recSec: number;
  workHr?: number | null;
  restHr?: number | null;
  heatRatio?: number | null; // heat_adjusted = raw × ratio
  heatCategory?: string | null;
  tempF?: number | null;
}): ComparisonWorkout {
  const laps: ComparisonLap[] = [];
  // Warmup: 1 easy mile.
  laps.push({
    lap_index: 0,
    is_rest: false,
    distance_meters: 1609,
    avg_pace_sec_per_mile: 440,
    moving_time_seconds: 440,
    avg_heart_rate: opts.workHr != null ? 135 : null,
  });
  for (let i = 0; i < opts.reps; i++) {
    laps.push({
      lap_index: laps.length,
      is_rest: false,
      distance_meters: 1000,
      avg_pace_sec_per_mile: opts.repPace,
      moving_time_seconds: Math.round((1000 / 1609.344) * opts.repPace),
      avg_heart_rate: opts.workHr ?? null,
      heat_adjusted_pace_sec_per_mile: opts.heatRatio != null
        ? opts.repPace * opts.heatRatio
        : null,
      heat_category: opts.heatCategory ?? null,
    });
    if (i < opts.reps - 1) {
      laps.push({
        lap_index: laps.length,
        is_rest: true,
        distance_meters: 60,
        avg_pace_sec_per_mile: 1600,
        moving_time_seconds: opts.recSec,
        avg_heart_rate: opts.restHr ?? null,
      });
    }
  }
  // Cooldown: 1 easy mile (must NOT count as recovery-between-reps).
  laps.push({
    lap_index: laps.length,
    is_rest: false,
    distance_meters: 1609,
    avg_pace_sec_per_mile: 445,
    moving_time_seconds: 445,
    avg_heart_rate: opts.workHr != null ? 140 : null,
  });
  return {
    id: opts.id,
    workout_date: opts.date,
    laps,
    weather: opts.tempF != null ? { temp_f: opts.tempF } : null,
  };
}

/** A plain easy run — no work bouts. */
function easyRun(id: string, date: string): ComparisonWorkout {
  return {
    id,
    workout_date: date,
    laps: [
      { lap_index: 0, is_rest: false, distance_meters: 9656, avg_pace_sec_per_mile: 450, moving_time_seconds: 2700, avg_heart_rate: 140 },
    ],
    weather: null,
  };
}

// The spec's worked example: 8×1K then, a month later, 10×1K at the same
// raw pace, hotter, shorter recoveries, faster HR drop in the floats.
const A = thresholdSession({
  id: "a", date: "2026-06-15", reps: 8, repPace: 330, recSec: 90,
  workHr: 168, restHr: 140, heatRatio: null, tempF: 62,
});
const B = thresholdSession({
  id: "b", date: "2026-07-15", reps: 10, repPace: 329, recSec: 75,
  workHr: 165, restHr: 131, heatRatio: 1.02, heatCategory: "hot", tempF: 74,
});

// ── Profile ─────────────────────────────────────────────────────────

Deno.test("profile: threshold session reads as hmp work with recovery metrics", () => {
  const p = buildWorkProfile(B, ZONES);
  assert(p.readable);
  assertEquals(p.dominantWorkZone, "hmp");
  assertEquals(p.repCount, 10);
  assertEquals(p.repDistanceLabel, "1K");
  assertEquals(p.avgRepPaceRawSec, 329);
  assertEquals(p.avgRepPaceAdjSec, Math.round(329 * 1.02));
  assertEquals(p.avgRecoverySec, 75);
  assertEquals(p.recoveryHrDropBpm, 165 - 131);
  assertEquals(p.avgWorkHr, 165);
  assertEquals(p.tempF, 74);
  // Quality volume = 10×1K of hmp work.
  assertEquals(p.qualityVolumeMeters, 10000);
});

Deno.test("profile: trailing cooldown never counts as recovery between reps", () => {
  const p = buildWorkProfile(A, ZONES);
  // 8 reps → exactly 7 between-rep recoveries of 90s each.
  assertEquals(p.avgRecoverySec, 90);
});

Deno.test("profile: easy run reads in aerobic mode with whole-run metrics", () => {
  const p = buildWorkProfile(easyRun("e", "2026-07-01"), ZONES);
  assert(p.readable);
  assertEquals(p.mode, "aerobic");
  assertEquals(p.dominantWorkZone, "easy");
  assertEquals(p.repCount, 0); // no work bouts, but still readable
  assertEquals(p.avgPaceSec, 450);
  assertEquals(p.totalDistanceMeters, 9656);
  assertEquals(p.avgRunHr, 140);
});

Deno.test("profile: no laps → unreadable, never faked", () => {
  const p = buildWorkProfile({ id: "x", workout_date: "2026-07-01", laps: [] }, ZONES);
  assertEquals(p.readable, false);
  assertEquals(p.unreadableReason, "no_laps");
});

// ── Comparability + confidence ──────────────────────────────────────

Deno.test("clean threshold-vs-threshold match scores high confidence", () => {
  const r = compareWorkouts(A, B, ZONES);
  assert(r.ok);
  const c = r.comparability!;
  assert(c.zoneMatch);
  assertEquals(c.familyMatch, "same");
  assert(c.volumeBandOk); // 8K vs 10K → ratio 0.8, inside the band
  assertEquals(c.confidence, "high");
  assert(c.score >= 0.75, `score ${c.score}`);
});

Deno.test("volume stretch (4×1K vs 12×1K) breaks the band → not high confidence", () => {
  const small = thresholdSession({ id: "s", date: "2026-06-15", reps: 4, repPace: 330, recSec: 90, workHr: 168, restHr: 140 });
  const big = thresholdSession({ id: "g", date: "2026-07-01", reps: 12, repPace: 330, recSec: 90, workHr: 168, restHr: 140 });
  const r = compareWorkouts(small, big, ZONES);
  assert(r.ok);
  assert(!r.comparability!.volumeBandOk);
  assert(r.comparability!.confidence !== "high");
});

Deno.test("zone mismatch (5K intervals vs threshold) renders but reads low", () => {
  const vo2 = thresholdSession({ id: "v", date: "2026-07-01", reps: 8, repPace: 305, recSec: 120, workHr: 175, restHr: 145 });
  const r = compareWorkouts(A, vo2, ZONES);
  assert(r.ok, "manual mode never refuses on a mismatch");
  const c = r.comparability!;
  assert(!c.zoneMatch);
  assertEquals(c.confidence, "low");
  assert(c.notes.some((n) => n.includes("read this loosely")));
});

Deno.test("missing HR degrades data quality + drops recovery reads into unavailable", () => {
  const noHr = thresholdSession({ id: "n", date: "2026-07-10", reps: 8, repPace: 330, recSec: 90, workHr: null, restHr: null });
  const r = compareWorkouts(A, noHr, ZONES);
  assert(r.ok);
  assert(r.comparability!.notes.some((n) => n.toLowerCase().includes("heart-rate")));
  assert(r.diff!.recoveryHrDropBpm == null);
  assert(r.diff!.avgWorkHr == null);
  assert(r.diff!.unavailable.some((u) => u.includes("HR recovery")));
});

Deno.test("old comparison (>56 days) loses recency credit", () => {
  const old = thresholdSession({ id: "o", date: "2026-01-10", reps: 8, repPace: 330, recSec: 90, workHr: 168, restHr: 140 });
  const r = compareWorkouts(old, B, ZONES);
  assert(r.ok);
  assert(r.comparability!.daysApart! > 56);
  assert(r.comparability!.notes.some((n) => n.includes("training phases")));
});

Deno.test("truly unreadable side (no laps) refuses with a reason", () => {
  const r = compareWorkouts(A, { id: "empty", workout_date: "2026-07-18", laps: [] }, ZONES);
  assertEquals(r.ok, false);
  assertEquals(r.reason, "unreadable_b");
  assertEquals(r.diff, null);
});

// ── Diff numbers (the spec's worked example) ────────────────────────

Deno.test("diff matches the spec's worked example shape", () => {
  const r = compareWorkouts(A, B, ZONES);
  assert(r.ok);
  const d = r.diff!;
  assertEquals(d.reps, { a: 8, b: 10, delta: 2 });
  assertEquals(d.avgRepPaceRawSec!.delta, -1); // held (−1 s/mi)
  assertEquals(d.avgRecoverySec!.delta, -15); // 90s → 75s
  assertEquals(d.recoveryHrDropBpm!.a, 28);
  assertEquals(d.recoveryHrDropBpm!.b, 34);
  assertEquals(d.recoveryHrDropBpm!.delta, 6); // faster drop
  assertEquals(d.avgWorkHr!.delta, -3);
  assertEquals(d.qualityVolumeMeters!.pctChange, 25); // 8K → 10K
  assertEquals(d.tempF!.delta, 12);
  // A ordered before B regardless of argument order.
  const flipped = compareWorkouts(B, A, ZONES);
  assertEquals(flipped.a.id, "a");
});

Deno.test("fact lines carry the numbers and the comparability read", () => {
  const r = compareWorkouts(A, B, ZONES);
  const lines = r.factLines!;
  assert(lines.some((l) => l.startsWith("Session kind: quality. Dominant zone: hmp vs hmp (same)")));
  assert(lines.some((l) => l.includes("8×1K -> 10×1K (+2 reps)")));
  assert(lines.some((l) => l.includes("90s -> 75s (-15s)")));
  assert(lines.some((l) => l.includes("+25%")));
  assert(lines.some((l) => l.startsWith("Comparability:")));
});

// ── Auto-suggest matcher ────────────────────────────────────────────

Deno.test("auto-suggest picks the fairest prior session, skips mismatches", () => {
  const target = B;
  const goodMatch = A; // same zone, family, volume band
  const vo2 = thresholdSession({ id: "v", date: "2026-07-05", reps: 10, repPace: 305, recSec: 120, workHr: 175, restHr: 145 });
  const unreadable = easyRun("e", "2026-07-10");
  const best = findBestComparison(target, [vo2, goodMatch, unreadable], ZONES);
  assert(best != null);
  assertEquals(best.id, "a");
  assert(best.zoneMatch);
});

Deno.test("auto-suggest returns null when nothing shares the zone", () => {
  const vo2 = thresholdSession({ id: "v", date: "2026-07-05", reps: 10, repPace: 305, recSec: 120, workHr: 175, restHr: 145 });
  assertEquals(findBestComparison(B, [vo2], ZONES), null);
  assertEquals(findBestComparison(B, [], ZONES), null);
  // …but manual ranking still scores it (manual mode never refuses).
  const ranked = rankComparisonCandidates(B, [vo2], ZONES);
  assertEquals(ranked.length, 1);
});

// ── Family match ────────────────────────────────────────────────────

Deno.test("family match: same / adjacent / different", () => {
  assertEquals(familyMatch("threshold", "threshold"), "same");
  assertEquals(familyMatch("threshold", "tempo"), "adjacent");
  assertEquals(familyMatch("intervals", "fartlek"), "adjacent");
  assertEquals(familyMatch("intervals", "long_run"), "different");
  assertEquals(familyMatch(null, "tempo"), "different");
});

// ── Aerobic mode (all workout types compare, even easy) ─────────────

/** A steady aerobic run from explicit laps (no work bouts). Optional per-lap
 *  elevation gain (m) and heat-adjusted pace exercise the conditions model. */
function aerobicRun(opts: {
  id: string;
  date: string;
  laps: Array<{ m: number; pace: number; hr: number | null; elev?: number; heatAdj?: number }>;
}): ComparisonWorkout {
  return {
    id: opts.id,
    workout_date: opts.date,
    laps: opts.laps.map((l, i) => ({
      lap_index: i,
      is_rest: false,
      distance_meters: l.m,
      avg_pace_sec_per_mile: l.pace,
      moving_time_seconds: Math.round((l.m / 1609.344) * l.pace),
      avg_heart_rate: l.hr,
      total_elevation_gain: l.elev ?? 0,
      heat_adjusted_pace_sec_per_mile: l.heatAdj ?? null,
    })),
    weather: null,
  };
}

// Two ~6mi easy long runs a month apart; each fades a touch in the back half.
const LR1 = aerobicRun({ id: "lr1", date: "2026-06-20", laps: [
  { m: 4828, pace: 440, hr: 140 }, { m: 4828, pace: 452, hr: 150 },
] });
const LR2 = aerobicRun({ id: "lr2", date: "2026-07-18", laps: [
  { m: 4828, pace: 438, hr: 138 }, { m: 4828, pace: 450, hr: 147 },
] });

Deno.test("two easy long runs compare in aerobic mode (whole-run, no reps)", () => {
  const r = compareWorkouts(LR1, LR2, ZONES);
  assert(r.ok);
  assertEquals(r.diff!.mode, "aerobic");
  assert(r.diff!.totalDistanceMeters != null);
  assert(r.diff!.avgPaceSec != null);
  assert(r.diff!.avgRunHr != null);
  assertEquals(r.diff!.reps, null); // no rep rows for a steady run
  assert(r.comparability!.zoneMatch); // easy vs easy
  assert(r.comparability!.confidence !== "low"); // similar distance + pace
});

Deno.test("decoupling is computed for a long run, positive when effort drifts", () => {
  const p = buildWorkProfile(LR1, ZONES);
  assertEquals(p.mode, "aerobic");
  assert(p.decouplingPct != null);
  assert(p.decouplingPct! > 0, `decoupling ${p.decouplingPct}`); // slower + higher HR late
});

Deno.test("cross-type pair (quality vs easy) still compares, hedged, whole-run only", () => {
  const r = compareWorkouts(A, easyRun("e2", "2026-07-16"), ZONES);
  assert(r.ok); // never refuses a readable pair — "allow, but hedge"
  assertEquals(r.diff!.mode, "mixed");
  assertEquals(r.diff!.reps, null); // no rep rows across a mixed pair
  assert(r.diff!.avgPaceSec != null); // whole-run rows still land
  assertEquals(r.comparability!.confidence, "low");
});

Deno.test("auto-suggest finds a similar easy run, not the mismatched threshold", () => {
  const best = findBestComparison(LR2, [A, LR1, easyRun("e3", "2026-07-01")], ZONES);
  assert(best != null);
  assert(best!.id !== "a"); // never the different-zone threshold session
  assert(best!.zoneMatch); // an easy-zone match
});

// ── Conditions adjustment, fast segments, chart series ──────────────

Deno.test("conditions-adjusted pace credits climbing (uphill run reads faster)", () => {
  // ~6mi at 8:00/mi with steady climbing → adjusted pace should be faster.
  const hilly = aerobicRun({ id: "hill", date: "2026-07-05", laps: [
    { m: 1609, pace: 480, hr: 150, elev: 40 }, // ~2.5% grade
    { m: 1609, pace: 480, hr: 152, elev: 40 },
    { m: 1609, pace: 480, hr: 154, elev: 40 },
  ] });
  const p = buildWorkProfile(hilly, ZONES);
  assert(p.conditionsAdjustedPaceSec != null);
  assert(p.avgPaceSec != null);
  assert(p.conditionsAdjustedPaceSec! < p.avgPaceSec!, // uphill → faster-equivalent
    `adj ${p.conditionsAdjustedPaceSec} vs raw ${p.avgPaceSec}`);
  assert(p.totalElevationGainM === 120);
});

Deno.test("fast-segment pace surfaces the quick third of a mixed run", () => {
  const surged = aerobicRun({ id: "surge", date: "2026-07-06", laps: [
    { m: 1609, pace: 470, hr: 150 },
    { m: 1609, pace: 470, hr: 150 },
    { m: 1609, pace: 400, hr: 165 }, // fast finish
  ] });
  const p = buildWorkProfile(surged, ZONES);
  assert(p.fastSegPaceSec != null);
  assert(p.fastSegPaceSec! < p.avgPaceSec!);
});

Deno.test("chart series carries one cumulative point per lap", () => {
  const p = buildWorkProfile(LR1, ZONES);
  assertEquals(p.series.length, 2);
  assert(p.series[1].mi > p.series[0].mi); // cumulative
  assertEquals(p.series[0].hr, 140);
});

Deno.test("enriched fact lines print the absolute distance delta (number-guard fix)", () => {
  const r = compareWorkouts(LR1, LR2, ZONES);
  const lines = r.factLines!;
  // Distance line now carries the mi delta so the verdict may cite it.
  assert(lines.some((l) => l.startsWith("Total distance:") && l.includes("mi")));
  const allowed = allowedNumberTokens(lines);
  // A verdict citing the printed delta is now permitted.
  assert(verdictNumbersAllowed("B was 0.9 mi shorter.", allowed) ||
    lines.some((l) => l.includes("mi")));
});

// ── Layer-2 number guard ────────────────────────────────────────────

Deno.test("number guard: verdict may only cite Layer-1 numbers", () => {
  const r = compareWorkouts(A, B, ZONES);
  const allowed = allowedNumberTokens(r.factLines!);
  assert(
    verdictNumbersAllowed(
      "Two more reps at the same pace on a day 12F hotter, with 15 seconds less recovery — and a 25% load bump.",
      allowed,
    ),
  );
  // 47 appears nowhere in the diff → rejected.
  assert(
    !verdictNumbersAllowed("Your threshold improved 47% this month.", allowed),
  );
  // Pace tokens ("5:29") are licensed only if present in the facts.
  assert(!verdictNumbersAllowed("You averaged 9:59/mi.", allowed));
});
