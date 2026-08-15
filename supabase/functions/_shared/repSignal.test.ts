import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  classifyHrSource,
  repSeriesFromStream,
  repWindowsFromLaps,
  scoreRepSession,
  type HrStream,
  type RepLapRow,
} from "./repSignal.ts";
import { FIVEX4MIN, TENX1KM, TWOHUNDREDS } from "./repSignal.fixtures.ts";

// ============================================================================
// The three calibration sessions ARE the contract (2026-08-14 analysis).
// If any of these verdicts move, the model changed — that must be a decision,
// not a drift. See REP-RECOVERY-SCORE-APPLY.md / CURRENT-FITNESS-APPLY.md §6.
// ============================================================================

Deno.test("10×1km (the reference session): over the edge, HIGH confidence", () => {
  const s = scoreRepSession(TENX1KM);
  assertEquals(s.scored, true);
  assertEquals(s.confidence, "high");
  assertEquals(s.flags, []);
  assertEquals(s.verdict?.key, "over_the_edge");
  // Level = rep 1's hrr60, the freshest reading.
  assertEquals(s.level, 45.4);
  // Recovery closing (hrr60 falling across the set)…
  assertEquals(s.recovery?.direction, "down");
  assert(s.recovery!.total <= -REC_MIN_OBSERVED, `recovery total ${s.recovery!.total}`);
  // …while carryover accumulates (starting each rep higher)…
  assertEquals(s.carryover?.direction, "up");
  assert(s.carryover!.total >= 10, `carryover total ${s.carryover!.total}`);
  // …at held-to-fading pace with rising cost.
  assertEquals(s.hrCost?.direction, "up");
});
const REC_MIN_OBSERVED = 8;

Deno.test("10×1km: the final-rep kick is reported, never trended", () => {
  const s = scoreRepSession(TENX1KM);
  // She closed with a 5:17 after drifting to 5:34 — the close is its own fact.
  assertEquals(s.finalRep?.close, "fast");
  assert(s.finalRep!.deltaVsMedianSec <= -2, `close delta ${s.finalRep!.deltaVsMedianSec}`);
  // And because rep 10 is excluded from the trend, the pace slope still reads
  // the drift honestly instead of being bent flat by the kick.
  assertEquals(s.pace?.direction, "up");
});

Deno.test("5×4min (sensor-compromised): flags fire, verdict withheld, facts kept", () => {
  const s = scoreRepSession(FIVEX4MIN);
  assertEquals(s.scored, true); // facts render —
  assertEquals(s.verdict, null); // — the verdict does not.
  assertEquals(s.confidence, "low");
  // Carryover ran BACKWARDS on this session (117→91): the signature flag.
  assert(s.flags.includes("carryover_backwards"), `flags: ${s.flags}`);
});

Deno.test("200s: not scoreable at all — the duration gate is absolute", () => {
  const s = scoreRepSession(TWOHUNDREDS);
  assertEquals(s.scored, false);
  assert(/under 90s/.test(s.reason ?? ""), s.reason ?? "");
  // Not a low-confidence score. NO score. A different measurement wearing the
  // same name is worse than no measurement.
  assertEquals(s.verdict, null);
  assertEquals(s.level, null);
});

Deno.test("empty and tiny inputs fail closed", () => {
  assertEquals(scoreRepSession([]).scored, false);
  assertEquals(scoreRepSession(TENX1KM.slice(0, 3)).scored, false);
});

// ── Layer 1 · windows from laps ──────────────────────────────────────────

/** A lap-button interval session: WU · 4×(work 1km + jog 200m) · CD. */
function lapSession(): RepLapRow[] {
  const laps: RepLapRow[] = [];
  let i = 0;
  const push = (sec: number, meters: number, rest: boolean) =>
    laps.push({
      lap_index: i++,
      is_rest: rest,
      distance_meters: meters,
      moving_time_seconds: sec,
      elapsed_time_seconds: sec,
      avg_pace_sec_per_mile: (sec / meters) * 1609.344,
    });
  push(900, 3000, false); // warmup — slow, excluded by the pace ceiling
  for (let r = 0; r < 4; r++) {
    push(200, 1000, false); // work: ~5:22/mi
    push(120, 200, true); // jog
  }
  push(600, 2000, false); // cooldown — slow
  return laps;
}

Deno.test("windows: work laps in, warmup/cooldown/jogs out, offsets cumulative", () => {
  const w = repWindowsFromLaps(lapSession(), 362 /* steady, sec/mi */);
  assertEquals(w.length, 4);
  assertEquals(w[0].startS, 900); // after the warmup
  assertEquals(w[0].endS, 1100);
  assertEquals(w[1].startS, 1220); // 900+200+120
  assert(Math.abs(w[0].paceSecPerMile - 321.9) < 1);
});

Deno.test("windows: consecutive work laps merge (auto-lap fragmentation)", () => {
  const laps = lapSession();
  // Split rep 1's 1km work lap into two 500m auto-laps.
  laps.splice(1, 1,
    { lap_index: 1, is_rest: false, distance_meters: 500, moving_time_seconds: 100, elapsed_time_seconds: 100, avg_pace_sec_per_mile: (100 / 500) * 1609.344 },
    { lap_index: 1.5, is_rest: false, distance_meters: 500, moving_time_seconds: 100, elapsed_time_seconds: 100, avg_pace_sec_per_mile: (100 / 500) * 1609.344 },
  );
  const w = repWindowsFromLaps(laps, 362);
  assertEquals(w.length, 4); // still four reps, not five
  assertEquals(w[0].durationS, 200);
});

Deno.test("windows: no laps / no ceiling → empty, never a guess", () => {
  assertEquals(repWindowsFromLaps([], 362), []);
  assertEquals(repWindowsFromLaps(lapSession(), 0), []);
});

// ── Layer 2 · series from a synthetic stream ─────────────────────────────

/** Square-ish HR: climbs into each rep, plateaus, decays through recovery. */
function syntheticStream(totalS: number): HrStream {
  const time: number[] = [], hr: number[] = [];
  const reps = [[900, 1100], [1220, 1420], [1540, 1740], [1860, 2060]];
  let level = 110;
  for (let t = 0; t < totalS; t++) {
    const inRep = reps.some(([a, b]) => t >= a && t < b);
    const target = inRep ? 170 : 115;
    level += Math.max(-1.0, Math.min(1.5, (target - level) * 0.03));
    time.push(t);
    hr.push(Math.round(level));
  }
  return { time, hr };
}

Deno.test("series: peak at rep end, positive hrr, settled plateaus, carryover on all but last", () => {
  const w = repWindowsFromLaps(lapSession(), 362);
  const reps = repSeriesFromStream(w, syntheticStream(2800));
  assertEquals(reps.length, 4);
  for (const r of reps) {
    assert(r.hrPeak! > 150, `peak ${r.hrPeak}`);
    assert(r.hrSettled, `rep ${r.index} should settle on a 200s plateau`);
  }
  // 120s recoveries → hrr30 and hrr60 both computable on reps 1–3.
  for (const r of reps.slice(0, 3)) {
    assert(r.hrr60! > r.hrr30!, `hrr60 ${r.hrr60} > hrr30 ${r.hrr30}`);
    assert(r.hrr60! > 10, `real drop, got ${r.hrr60}`);
    assert(r.hrAtNextRepStart != null);
  }
  assertEquals(reps[3].hrAtNextRepStart, null); // no next rep
});

Deno.test("series: a 30s rep is tooShort and never settled", () => {
  const w = [{ index: 1, startS: 900, endS: 930, durationS: 30, distanceMeters: 200, paceSecPerMile: 260 }];
  const [r] = repSeriesFromStream(w, syntheticStream(1200));
  assertEquals(r.tooShort, true);
  assertEquals(r.hrSettled, false);
});

Deno.test("series: missing HR yields nulls, not zeros", () => {
  const w = repWindowsFromLaps(lapSession(), 362);
  const dead: HrStream = { time: [0, 1, 2], hr: [null, null, null] };
  const [r] = repSeriesFromStream(w, dead);
  assertEquals(r.hrPeak, null);
  assertEquals(r.hrr60, null);
  assertEquals(r.hrSettled, false);
});

// ── Device-aware confidence (2026-08-15) ─────────────────────────────────

Deno.test("hrSource: optical caps HIGH at MEDIUM; strap and unknown untouched", () => {
  const strap = scoreRepSession(TENX1KM, { hrSource: "strap" });
  const optical = scoreRepSession(TENX1KM, { hrSource: "optical" });
  const unknown = scoreRepSession(TENX1KM);
  assertEquals(strap.confidence, "high");
  assertEquals(unknown.confidence, "high");
  assertEquals(optical.confidence, "medium");
  // The verdict still renders on optical — capped, not withheld.
  assertEquals(optical.verdict?.key, "over_the_edge");
  assertEquals(optical.hrSource, "optical");
});

Deno.test("hrSource: flags still force LOW regardless of a strap", () => {
  const s = scoreRepSession(FIVEX4MIN, { hrSource: "strap" });
  assertEquals(s.confidence, "low");
  assertEquals(s.verdict, null);
});

Deno.test("classifyHrSource errs toward unknown", () => {
  assertEquals(classifyHrSource("Garmin HRM-Pro Plus"), "strap");
  assertEquals(classifyHrSource("Garmin Forerunner 965"), "optical");
  assertEquals(classifyHrSource("Apple Watch Ultra 2"), "optical");
  assertEquals(classifyHrSource("Garmin"), "unknown"); // names the account, not the sensor
  assertEquals(classifyHrSource(null), "unknown");
  assertEquals(classifyHrSource(""), "unknown");
});
