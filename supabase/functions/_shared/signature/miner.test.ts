/**
 * Unit tests for the signature miner — the behavior that matters:
 *   1. It reproduces a REAL pattern (the pilot's summer-evening easy-run cost).
 *   2. It REFUSES a plausible-looking non-pattern (no effect → nothing surfaces).
 *   3. It routes a niggle-outcome pattern into the niggle_assoc category (§7).
 *   4. It won't mine an athlete with too little history.
 *
 * This is the precision behavior the S1 "dark run" requires: find what's true,
 * refuse what isn't.
 *
 * Run: deno test --allow-none _shared/signature/miner.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { mineSignature } from "./miner.ts";
import { enumerateHypotheses, patternKey, shiftDate } from "./grammar.ts";
import type { AthleteDay } from "./types.ts";

// ── Fixtures ──────────────────────────────────────────────────────────────────

function day(date: string, p: Partial<AthleteDay> = {}): AthleteDay {
  return {
    date,
    logId: `log-${date}-${p.startPeriod ?? ""}`,
    ran: true,
    restDay: false,
    crossTrain: false,
    distanceMiles: 6,
    durationMinutes: 48,
    workoutType: "easy",
    isQuality: false,
    isLongRun: false,
    startPeriod: null,
    heatBand: null,
    intensityJumpWeek: false,
    downWeek: false,
    workSegmentPaceMps: null,
    workSegmentHr: null,
    easyEffortPerKm: null,
    longRunFadeSecPerMile: null,
    moodLabel: null,
    feelChip: null,
    niggleMentioned: false,
    niggleBodyArea: null,
    compliance: null,
    ...p,
  };
}

/** Deterministic tiny wiggle so within-arm SD is non-zero (no RNG in tests). */
function wiggle(i: number): number {
  return ((i % 3) - 1) * 0.03;
}

const START = "2025-07-07";

/**
 * Real pattern: 40 weeks, one AM easy run and one PM easy run per week, same
 * pace band, but PM costs materially more effort/km (pilot finding #1/#4).
 */
function summerPmAthlete(): AthleteDay[] {
  const days: AthleteDay[] = [];
  for (let w = 0; w < 40; w++) {
    const am = shiftDate(START, w * 7 + 0);
    const pm = shiftDate(START, w * 7 + 3);
    days.push(day(am, { startPeriod: "am", easyEffortPerKm: 4.56 + wiggle(w) }));
    days.push(day(pm, { startPeriod: "pm", easyEffortPerKm: 5.83 + wiggle(w) }));
  }
  return days;
}

/** No pattern: AM and PM easy runs cost the SAME (identical deterministic values). */
function nullAthlete(): AthleteDay[] {
  const days: AthleteDay[] = [];
  for (let w = 0; w < 40; w++) {
    const am = shiftDate(START, w * 7 + 0);
    const pm = shiftDate(START, w * 7 + 3);
    const e = 5.0 + wiggle(w);
    days.push(day(am, { startPeriod: "am", easyEffortPerKm: e }));
    days.push(day(pm, { startPeriod: "pm", easyEffortPerKm: e }));
  }
  return days;
}

/**
 * Niggle association: 24 weeks, alternating "intensity-jump" and normal weeks,
 * 3 run days each. Jump weeks carry niggle mentions; normal weeks don't.
 */
function niggleAthlete(): AthleteDay[] {
  const days: AthleteDay[] = [];
  for (let w = 0; w < 24; w++) {
    const jump = w % 2 === 0;
    for (const dow of [0, 2, 4]) {
      const date = shiftDate(START, w * 7 + dow);
      days.push(
        day(date, {
          // Flag the whole week; same_week lag pairs the week's run days to it.
          intensityJumpWeek: jump,
          niggleMentioned: jump,
          niggleBodyArea: jump ? "calf" : null,
        }),
      );
    }
  }
  return days;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

Deno.test("grammar enumerates the v1 space and forms canonical keys", () => {
  const hs = enumerateHypotheses();
  // 6 event antecedents × 7 lags × 6 outcomes + 2 contrasts × 1 lag × 6 = 264.
  assertEquals(hs.length, 6 * 7 * 6 + 2 * 1 * 6);
  const sample = hs.find(
    (h) => h.antecedent.key === "rest_day" && h.outcome.key === "work_pace" && h.lag.key === "+2d",
  )!;
  assertEquals(patternKey(sample), "rest_day->work_pace@+2d");
});

Deno.test("miner reproduces the summer-evening easy-run cost pattern", () => {
  const res = mineSignature(summerPmAthlete());
  assert(res.meta.mined, "athlete has > 12 weeks of history");

  const pm = res.observations.find((o) => o.patternKey === "start_pm->easy_effort@same_day");
  assert(pm, "the PM-easy-cost pattern should surface");
  assertEquals(pm!.category, "environment");
  // PM costs MORE than AM → conditional (exposed) rate above baseline.
  assert(pm!.evidence.effect > 0, "effect points the right way (PM > AM)");
  assert(pm!.evidence.conditional_rate > pm!.evidence.base_rate);
  assert(pm!.evidence.n >= 6 && pm!.evidence.baseline_n >= 6, "support floor met");
  assertEquals(pm!.confidence, "high"); // large, stable, well-supported
  assert(pm!.evidence.example_log_ids.length > 0, "carries example workout ids");
});

Deno.test("miner refuses a non-pattern (no effect → nothing surfaces)", () => {
  const res = mineSignature(nullAthlete());
  const pm = res.observations.find((o) => o.patternKey === "start_pm->easy_effort@same_day");
  assertEquals(pm, undefined, "an AM/PM tie must not surface as a pattern");
  // With no real signal anywhere, the whole set should be empty.
  assertEquals(res.observations.length, 0);
});

Deno.test("niggle-outcome patterns are categorized niggle_assoc (the §7 gate hook)", () => {
  const res = mineSignature(niggleAthlete());
  const niggle = res.observations.find((o) => o.evidence.outcome === "niggle");
  assert(niggle, "the intensity-jump → niggle association should surface");
  assertEquals(niggle!.category, "niggle_assoc");
  assertEquals(niggle!.evidence.antecedent, "intensity_jump");
  assertEquals(niggle!.evidence.effect_unit, "rate_diff");
  assert(niggle!.evidence.effect > 0);
});

Deno.test("miner won't touch an athlete with < 12 weeks of history", () => {
  const short = [day("2026-06-01", { startPeriod: "am", easyEffortPerKm: 4.5 })];
  const res = mineSignature(short);
  assertEquals(res.meta.mined, false);
  assertEquals(res.observations.length, 0);
  assert(res.meta.reason?.includes("minimum"));
});
