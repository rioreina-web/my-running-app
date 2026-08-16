/**
 * Tests for the pace-at-HR fitness signal (WS-fitness). Pace zones are the test
 * athlete's (03857bf3…): mile 272, 5K 302, 10K 314, HMP 328, MP 343,
 * steady 362, moderate 405, easy 429 (sec/mile) — same fixture set the
 * segmentation tests use.
 *
 * Run: deno test _shared/fitnessSignal.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  computeFitnessSignal,
  sessionDecouplingPct,
  type SessionInput,
} from "./fitnessSignal.ts";
import { type LapInput, type PaceZones } from "./workoutSegmentation.ts";

const ZONES: PaceZones = {
  mile: 272, fiveK: 302, tenK: 314, hm: 328, mp: 343,
  steady: 362, moderate: 405, easy: 429,
};

// Fixed "now" so recent/baseline windows are deterministic.
const NOW = new Date("2026-06-15T12:00:00Z");
const dateDaysAgo = (n: number): string =>
  new Date(NOW.getTime() - n * 86400000).toISOString().slice(0, 10);

// ── Lap builders ──

/** One steady aerobic mile at `pace` sec/mi and `hr` bpm. */
const easyMile = (pace: number, hr: number, i: number): LapInput => ({
  lap_index: i, is_rest: false, distance_meters: 1609.344,
  avg_pace_sec_per_mile: pace, moving_time_seconds: pace, avg_heart_rate: hr,
});

/** A 1K work rep at `pace` sec/mi, `hr` bpm. */
const rep1k = (pace: number, hr: number, i: number): LapInput => ({
  lap_index: i, is_rest: false, distance_meters: 1000,
  avg_pace_sec_per_mile: pace, moving_time_seconds: Math.round((1000 / 1609.344) * pace),
  avg_heart_rate: hr,
});

/** A short jog-recovery lap. */
const jog = (i: number): LapInput => ({
  lap_index: i, is_rest: true, distance_meters: 60,
  avg_pace_sec_per_mile: 1600, moving_time_seconds: 63, avg_heart_rate: 150,
});

const easySession = (miles: number, pace: number, hr: number): LapInput[] =>
  Array.from({ length: miles }, (_, k) => easyMile(pace, hr, k + 1));

/** N×1K reps at `pace`/`hr` with jog recoveries between. */
const repSession = (n: number, pace: number, hr: number): LapInput[] => {
  const laps: LapInput[] = [];
  let idx = 1;
  for (let k = 0; k < n; k++) {
    laps.push(rep1k(pace, hr, idx++));
    if (k < n - 1) laps.push(jog(idx++));
  }
  return laps;
};

// ── 1. EF math + easy improving direction (same pace, lower HR = fitter) ──

Deno.test("easy efficiency: same pace at lower HR reads as improving", () => {
  // Baseline (weeks 5–12): 7:30/mi @ ~150 bpm. Recent (last 4wk): 7:30/mi @ ~143.
  const sessions: SessionInput[] = [
    { date: dateDaysAgo(70), laps: easySession(6, 450, 150) },
    { date: dateDaysAgo(56), laps: easySession(6, 450, 151) },
    { date: dateDaysAgo(42), laps: easySession(7, 450, 150) },
    { date: dateDaysAgo(14), laps: easySession(6, 450, 143) },
    { date: dateDaysAgo(7), laps: easySession(6, 450, 144) },
    { date: dateDaysAgo(2), laps: easySession(5, 450, 143) },
  ];
  const sig = computeFitnessSignal(sessions, ZONES, NOW);
  const easy = sig.efficiency.find((e) => e.bucket === "easy");
  assert(easy, "expected an easy efficiency bucket");
  assertEquals(easy!.pace_recent_sec, 450);
  assertEquals(easy!.pace_baseline_sec, 450);
  assert(easy!.hr_recent >= 143 && easy!.hr_recent <= 144, `hr_recent=${easy!.hr_recent}`);
  assert(easy!.hr_baseline >= 150 && easy!.hr_baseline <= 151, `hr_baseline=${easy!.hr_baseline}`);
  assertEquals(easy!.direction, "improving");
  assert(easy!.ef_delta_pct > 1.5, `ef_delta_pct=${easy!.ef_delta_pct}`);
  // recent 3, baseline 3 → medium (HIGH needs baseline ≥ 4).
  assertEquals(easy!.confidence, "medium");
});

Deno.test("easy efficiency confidence reaches HIGH with enough samples", () => {
  const sessions: SessionInput[] = [
    { date: dateDaysAgo(75), laps: easySession(6, 450, 150) },
    { date: dateDaysAgo(63), laps: easySession(6, 450, 150) },
    { date: dateDaysAgo(50), laps: easySession(6, 450, 150) },
    { date: dateDaysAgo(36), laps: easySession(6, 450, 150) }, // 4 baseline
    { date: dateDaysAgo(20), laps: easySession(6, 450, 144) },
    { date: dateDaysAgo(10), laps: easySession(6, 450, 144) },
    { date: dateDaysAgo(3), laps: easySession(6, 450, 144) }, // 3 recent
  ];
  const sig = computeFitnessSignal(sessions, ZONES, NOW);
  const easy = sig.efficiency.find((e) => e.bucket === "easy")!;
  assertEquals(easy.recent_samples, 3);
  assertEquals(easy.baseline_samples, 4);
  assertEquals(easy.confidence, "high");
  assert(sig.verdict && /lower cost/.test(sig.verdict), `verdict=${sig.verdict}`);
});

// ── 2. Bucketing: interval vs threshold vs long-run ──

Deno.test("threshold sessions bucket; interval sessions no longer feed EF (2026-08-15)", () => {
  const sessions: SessionInput[] = [
    // 5K-pace rep sessions — would have bucketed "interval" before the
    // amendment. HR lags effort on short/hard reps (measured: the 200s
    // calibration session never plateaued), so speed-per-beat here is
    // systematically flattering. These must now contribute NOTHING.
    { date: dateDaysAgo(60), laps: repSession(5, 305, 168) },
    { date: dateDaysAgo(46), laps: repSession(5, 305, 168) },
    { date: dateDaysAgo(12), laps: repSession(5, 305, 164) },
    { date: dateDaysAgo(5), laps: repSession(5, 305, 163) },
    // Threshold: reps at HMP (330) — recent + baseline, HR falling. 1K reps
    // run ~200s, comfortably over the 90s EF rep floor, so these still pool.
    { date: dateDaysAgo(58), laps: repSession(4, 330, 162) },
    { date: dateDaysAgo(44), laps: repSession(4, 330, 162) },
    { date: dateDaysAgo(15), laps: repSession(4, 330, 158) },
    { date: dateDaysAgo(6), laps: repSession(4, 330, 157) },
  ];
  const sig = computeFitnessSignal(sessions, ZONES, NOW);
  const buckets = sig.efficiency.map((e) => e.bucket).sort();
  assertEquals(buckets, ["threshold"]);
  const threshold = sig.efficiency.find((e) => e.bucket === "threshold")!;
  assertEquals(threshold.direction, "improving");
  assert(sig.verdict && /threshold/i.test(sig.verdict), `verdict=${sig.verdict}`);
});

// ── 3. Decoupling on a long run ──

Deno.test("sessionDecouplingPct: HR drift in the back half is positive decoupling", () => {
  // 12 mi long run at 7:30/mi; HR 150 first half, 158 second half.
  const laps: LapInput[] = [
    ...Array.from({ length: 6 }, (_, k) => easyMile(450, 150, k + 1)),
    ...Array.from({ length: 6 }, (_, k) => easyMile(450, 158, k + 7)),
  ];
  const dec = sessionDecouplingPct(laps, ZONES);
  assert(dec != null, "expected a decoupling value");
  // Same pace, higher HR late → efSecond < efFirst → positive %. ≈ (1-150/158)*100 ≈ 5.1%
  assert(dec! > 3 && dec! < 7, `decoupling=${dec}`);
});

Deno.test("decoupling trend improves when recent long runs hold HR better", () => {
  const baselineLong = [
    ...Array.from({ length: 6 }, (_, k) => easyMile(450, 150, k + 1)),
    ...Array.from({ length: 6 }, (_, k) => easyMile(450, 160, k + 7)), // big drift
  ];
  const recentLong = [
    ...Array.from({ length: 6 }, (_, k) => easyMile(450, 150, k + 1)),
    ...Array.from({ length: 6 }, (_, k) => easyMile(450, 152, k + 7)), // small drift
  ];
  const sessions: SessionInput[] = [
    { date: dateDaysAgo(70), laps: baselineLong },
    { date: dateDaysAgo(50), laps: baselineLong },
    { date: dateDaysAgo(14), laps: recentLong },
    { date: dateDaysAgo(4), laps: recentLong },
  ];
  const sig = computeFitnessSignal(sessions, ZONES, NOW);
  assert(sig.decoupling, "expected a decoupling trend");
  assert(sig.decoupling!.recent_pct! < sig.decoupling!.baseline_pct!, "recent should decouple less");
  assertEquals(sig.decoupling!.direction, "improving");
});

// ── 4. Gating: thin data yields no trend ──

Deno.test("a single session per window yields no efficiency trend", () => {
  const sessions: SessionInput[] = [
    { date: dateDaysAgo(60), laps: easySession(6, 450, 150) },
    { date: dateDaysAgo(5), laps: easySession(6, 450, 144) },
  ];
  const sig = computeFitnessSignal(sessions, ZONES, NOW);
  assertEquals(sig.efficiency.length, 0);
  assertEquals(sig.confidence, "low");
  assertEquals(sig.verdict, null);
});

Deno.test("sessions outside the 84-day scan window are ignored", () => {
  const sessions: SessionInput[] = [
    { date: dateDaysAgo(200), laps: easySession(6, 450, 150) },
    { date: dateDaysAgo(120), laps: easySession(6, 450, 150) },
    { date: dateDaysAgo(5), laps: easySession(6, 450, 144) },
    { date: dateDaysAgo(2), laps: easySession(6, 450, 144) },
  ];
  const sig = computeFitnessSignal(sessions, ZONES, NOW);
  const easy = sig.efficiency.find((e) => e.bucket === "easy");
  assertEquals(easy, undefined);
});

// ── Heat normalization (2026-08-15) ──────────────────────────────────────
//
// The bug these pin: EF divided by RAW pace, so a hot recent window read as
// lost fitness. On the calibration athlete the recent 28d averaged 13.0 s/mi
// of heat cost against the baseline's 11.6, and threshold landed at +1.40%
// against a 1.5% direction gate.

/** An easy mile that also carries a neutral-day equivalent pace. */
const easyMileHeat = (
  pace: number, neutral: number, hr: number, i: number,
): LapInput => ({
  lap_index: i, is_rest: false, distance_meters: 1609.344,
  avg_pace_sec_per_mile: pace, moving_time_seconds: pace, avg_heart_rate: hr,
  heat_adjusted_pace_sec_per_mile: neutral,
});

const easySessionHeat = (
  miles: number, pace: number, neutral: number, hr: number,
): LapInput[] =>
  Array.from({ length: miles }, (_, k) => easyMileHeat(pace, neutral, hr, k + 1));

Deno.test("heat: an equally-fit athlete running hotter no longer reads as declining", () => {
  // Same HR, same neutral-air capability (450 s/mi) in both windows. The only
  // difference is that recent runs cost 20 s/mi of heat and baseline cost 5.
  const sessions: SessionInput[] = [
    { date: dateDaysAgo(70), laps: easySessionHeat(6, 455, 450, 148) },
    { date: dateDaysAgo(60), laps: easySessionHeat(6, 455, 450, 148) },
    { date: dateDaysAgo(10), laps: easySessionHeat(6, 470, 450, 148) },
    { date: dateDaysAgo(4), laps: easySessionHeat(6, 470, 450, 148) },
  ];
  const easy = computeFitnessSignal(sessions, ZONES, NOW)
    .efficiency.find((e) => e.bucket === "easy");
  assert(easy, "expected an easy bucket");
  // Corrected, the two windows are identical → flat, ~0% delta.
  assertEquals(easy.direction, "flat");
  assert(
    Math.abs(easy.ef_delta_pct) < 0.5,
    `heat-corrected EF should be ~0%, got ${easy.ef_delta_pct}%`,
  );
  // The reported paces stay the ones actually run — never the neutral pair.
  assertEquals(easy.pace_recent_sec, 470);
  assertEquals(easy.pace_baseline_sec, 455);
  assertEquals(easy.pace_recent_neutral_sec, 450);
  assertEquals(easy.pace_baseline_neutral_sec, 450);
  assertEquals(easy.heat_coverage_recent_pct, 100);
});

Deno.test("heat: real improvement still reads as improving once corrected", () => {
  // Recent is hotter AND genuinely faster in neutral air (450 → 430) at the
  // same HR. Raw pace would show only 455 → 465 (slower); EF must see the gain.
  const sessions: SessionInput[] = [
    { date: dateDaysAgo(70), laps: easySessionHeat(6, 455, 450, 148) },
    { date: dateDaysAgo(60), laps: easySessionHeat(6, 455, 450, 148) },
    { date: dateDaysAgo(10), laps: easySessionHeat(6, 465, 430, 148) },
    { date: dateDaysAgo(4), laps: easySessionHeat(6, 465, 430, 148) },
  ];
  const easy = computeFitnessSignal(sessions, ZONES, NOW)
    .efficiency.find((e) => e.bucket === "easy");
  assert(easy, "expected an easy bucket");
  assertEquals(easy.direction, "improving");
  assert(easy.ef_delta_pct > 4, `expected a clear gain, got ${easy.ef_delta_pct}%`);
});

Deno.test("heat: undecorated laps are unchanged — the correction is a no-op, not a guess", () => {
  // No heat_adjusted_pace on any lap: EF must equal the raw-pace answer, and
  // coverage must report 0 so a surface can see the trend is un-corrected.
  const sessions: SessionInput[] = [
    { date: dateDaysAgo(70), laps: easySession(6, 450, 150) },
    { date: dateDaysAgo(60), laps: easySession(6, 450, 150) },
    { date: dateDaysAgo(10), laps: easySession(6, 450, 144) },
    { date: dateDaysAgo(4), laps: easySession(6, 450, 144) },
  ];
  const easy = computeFitnessSignal(sessions, ZONES, NOW)
    .efficiency.find((e) => e.bucket === "easy");
  assert(easy, "expected an easy bucket");
  // Same pace, lower HR → more efficient, exactly as before the change.
  assertEquals(easy.direction, "improving");
  assertEquals(easy.heat_coverage_recent_pct, 0);
  assertEquals(easy.heat_coverage_baseline_pct, 0);
  assertEquals(easy.pace_recent_neutral_sec, easy.pace_recent_sec);
});

Deno.test("heat: partial coverage degrades lap by lap and is reported", () => {
  // Half the recent miles carry a stamp, half don't. The undecorated half runs
  // at 460 — deliberately inside the easy zone (the recovery cutoff is 429 ×
  // 1.09 = 467.6), because an undecorated 470 would classify as recovery and
  // drop out of the pool entirely, which is correct behaviour but a different
  // test. Here we want both halves pooled so coverage is genuinely partial.
  const mixed = [
    ...easySessionHeat(3, 470, 450, 148),
    ...easySession(3, 460, 148).map((l, k) => ({ ...l, lap_index: k + 4 })),
  ];
  const sessions: SessionInput[] = [
    { date: dateDaysAgo(70), laps: easySessionHeat(6, 455, 450, 148) },
    { date: dateDaysAgo(60), laps: easySessionHeat(6, 455, 450, 148) },
    { date: dateDaysAgo(10), laps: mixed },
    { date: dateDaysAgo(4), laps: mixed },
  ];
  const easy = computeFitnessSignal(sessions, ZONES, NOW)
    .efficiency.find((e) => e.bucket === "easy");
  assert(easy, "expected an easy bucket");
  assertEquals(easy.heat_coverage_recent_pct, 50);
  assertEquals(easy.heat_coverage_baseline_pct, 100);
  // Neutral pace lands between the credited 450 and the uncredited 470.
  assert(
    easy.pace_recent_neutral_sec > 450 && easy.pace_recent_neutral_sec < 470,
    `expected a blended neutral pace, got ${easy.pace_recent_neutral_sec}`,
  );
});
