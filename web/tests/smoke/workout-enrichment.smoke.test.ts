// Pure enrichment for the coach WorkoutDrawer (P1). Validates the reshaping of
// laps / weather / prescription rows into the drawer's WorkoutDetail blocks
// without any live DB — synthetic rows only.
//
// Run: cd web && npm run test:smoke

import { test } from "node:test";
import { strict as assert } from "node:assert";

import {
  buildPrescribed,
  buildConditions,
  buildChart,
  buildSplits,
  heatAdjHeadline,
  parseBand,
  verdictTitle,
  fmtClock,
  fmtPaceSec,
  type EnrichLap,
} from "@/lib/coach-dashboard/workout-enrichment";
import type { WorkoutStep } from "@/components/coach/workout-helpers";

// One synthetic lap. Defaults to a 1-mile lap at 9:30 pace with a heat-adj of
// 9:00, mild HR, 10m gain, in a hot dew point.
let lapIdx = 0;
function lap(p: Partial<EnrichLap> = {}): EnrichLap {
  return {
    lap_index: p.lap_index ?? lapIdx++,
    distance_meters: p.distance_meters ?? 1609.344,
    avg_pace_sec_per_mile: p.avg_pace_sec_per_mile ?? 570,
    heat_adjusted_pace_sec_per_mile:
      p.heat_adjusted_pace_sec_per_mile === undefined ? 540 : p.heat_adjusted_pace_sec_per_mile,
    avg_heart_rate: p.avg_heart_rate ?? 148,
    // honor an explicit null (a lap with no captured temp), unlike `?? 84`
    temp_f: p.temp_f === undefined ? 84 : p.temp_f,
    dew_point_f: p.dew_point_f === undefined ? 71 : p.dew_point_f,
    heat_category: p.heat_category ?? "hot",
    total_elevation_gain: p.total_elevation_gain ?? 25, // meters
    is_rest: p.is_rest ?? false,
  };
}

// ── formatters ───────────────────────────────────────────
test("fmtClock: sub-hour renders M:SS, over-hour H:MM:SS", () => {
  assert.equal(fmtClock(135), "2:15");
  assert.equal(fmtClock(8548), "2:22:28");
});

test("fmtPaceSec: rounds to the nearest second, pads", () => {
  assert.equal(fmtPaceSec(539.6), "9:00");
  assert.equal(fmtPaceSec(570), "9:30");
});

// ── parseBand ────────────────────────────────────────────
test("parseBand: reads a window into ordered second bounds", () => {
  assert.deepEqual(parseBand("8:55–9:25"), { low: 535, high: 565 });
  assert.deepEqual(parseBand("9:25-8:55"), { low: 535, high: 565 }); // hyphen + reversed
});

test("parseBand: a single target collapses low=high; junk → undefined", () => {
  assert.deepEqual(parseBand("7:30/mi"), { low: 450, high: 450 });
  assert.equal(parseBand(undefined), undefined);
});

// ── prescription ─────────────────────────────────────────
test("buildPrescribed: a 16 mi long run, run 15, flags a −1.0 cut", () => {
  const steps: WorkoutStep[] = [
    { id: "s1", stepType: "active", durationType: "distance_miles", durationValue: 16, paceZone: "longRun", notes: "" },
  ];
  const p = buildPrescribed({ steps }, 15);
  assert.ok(p);
  assert.equal(p!.label, "Long");
  assert.equal(p!.distance, 16);
  assert.equal(p!.cutAtMi, -1); // 15 − 16
});

test("buildPrescribed: sub-half-mile deltas don't render a cut chip", () => {
  const steps: WorkoutStep[] = [
    { id: "s1", stepType: "active", durationType: "distance_miles", durationValue: 8, paceZone: "mp", notes: "" },
  ];
  const p = buildPrescribed({ steps }, 8.2);
  assert.equal(p!.cutAtMi, undefined);
});

test("buildPrescribed: no steps → undefined (drawer omits the line)", () => {
  assert.equal(buildPrescribed(null, 10), undefined);
  assert.equal(buildPrescribed({ steps: [] }, 10), undefined);
});

// ── verdict title ────────────────────────────────────────
test("verdictTitle: a cut run leads with the verdict, sentence-cased", () => {
  assert.equal(verdictTitle("Long run", 15, 16), "Long run, cut at 15.");
  assert.equal(verdictTitle("Long run", 15.5, 18), "Long run, cut at 15.5.");
});

test("verdictTitle: on- or over-plan runs return undefined (fall back to label)", () => {
  assert.equal(verdictTitle("MP", 8, 8), undefined);
  assert.equal(verdictTitle("Long run", 16, 16), undefined);
  assert.equal(verdictTitle("Easy", 6), undefined); // no prescription
});

// ── conditions ───────────────────────────────────────────
test("buildConditions: dew point past 68° flags hot + a numbered caption", () => {
  const c = buildConditions([lap(), lap(), lap()], null, "9:41 AM");
  assert.ok(c);
  assert.equal(c!.dewPointF, 71);
  assert.equal(c!.dewHot, true);
  assert.equal(c!.hrAvg, 148);
  assert.equal(c!.startTime, "9:41 AM");
  assert.match(c!.caption ?? "", /68° hot threshold/);
});

test("buildConditions: cool dew point is not hot and has no caption", () => {
  const c = buildConditions([lap({ dew_point_f: 45 })], null);
  assert.equal(c!.dewHot, false);
  assert.equal(c!.caption, undefined);
});

test("buildConditions: falls back to weather_actual when laps lack temp", () => {
  const c = buildConditions(
    [lap({ temp_f: null, dew_point_f: null })],
    { temp_f: 60, dew_point_f: 50 },
  );
  assert.equal(c!.tempF, 60);
  assert.equal(c!.dewPointF, 50);
});

// ── chart ────────────────────────────────────────────────
test("buildChart: cumulative samples, ghost tail when planned > ran", () => {
  const laps = [lap(), lap(), lap(), lap(), lap()]; // 5 mi
  const chart = buildChart(laps, { bandLow: 535, bandHigh: 565, plannedMi: 6, cutAtMi: 5 });
  assert.ok(chart);
  // seed sample at 0 + one per lap
  assert.equal(chart!.laps.length, 6);
  assert.equal(chart!.laps[0].mi, 0);
  assert.equal(Math.round(chart!.laps[chart!.laps.length - 1].mi), 5);
  assert.equal(chart!.plannedMi, 6);
  assert.equal(chart!.cutAtMi, 5);
  assert.match(chart!.climbLabel ?? "", /ft/);
});

test("buildChart: fewer than 2 running laps → undefined", () => {
  assert.equal(buildChart([lap()], { bandLow: 500, bandHigh: 560, plannedMi: 5 }), undefined);
});

// ── splits ───────────────────────────────────────────────
test("buildSplits: a long run buckets into thirds with raw + heat-adj", () => {
  const laps = Array.from({ length: 15 }, (_, i) =>
    lap({ lap_index: i, avg_pace_sec_per_mile: 560 + i * 4, heat_adjusted_pace_sec_per_mile: 530 + i * 3 }),
  );
  const out = buildSplits(laps, { isLong: true, bandHigh: 565, plannedMi: 16, ranMi: 15 });
  assert.ok(out);
  // three thirds + one ghost row for the unrun 16th mile
  assert.equal(out!.splits.length, 4);
  assert.equal(out!.splits[0].name, "Miles 1–5");
  assert.ok(out!.splits[0].adj); // heat-adj present
  assert.equal(out!.splits[3].pace, null); // ghost
  assert.match(out!.splits[3].name, /Mile 16/);
  assert.match(out!.splitLabel, /heat-adj/);
});

test("buildSplits: the closing third over band reads off-target", () => {
  const laps = Array.from({ length: 15 }, (_, i) =>
    lap({ lap_index: i, avg_pace_sec_per_mile: i < 10 ? 555 : 604, heat_adjusted_pace_sec_per_mile: null }),
  );
  const out = buildSplits(laps, { isLong: true, bandHigh: 565, plannedMi: 15, ranMi: 15 });
  assert.equal(out!.splits[0].onTarget, true);
  assert.equal(out!.splits[2].onTarget, false); // last third over 9:25
  assert.equal(out!.splitLabel, "Splits"); // no heat-adj column
});

// ── splits: quality session rep grouping ─────────────────
test("buildSplits: a quality session groups into warm-up / reps / cool-down", () => {
  // 2mi warm-up (1 lap), 5×1mi reps at 5K pace with 0.25mi jog recoveries,
  // 1mi cool-down. Band high = 400s (6:40) — reps at 390, jogs + wu/cd slower.
  const laps: EnrichLap[] = [];
  let idx = 0;
  laps.push(lap({ lap_index: idx++, distance_meters: 3218, avg_pace_sec_per_mile: 540, heat_adjusted_pace_sec_per_mile: null })); // 2mi warmup
  for (let r = 0; r < 5; r++) {
    laps.push(lap({ lap_index: idx++, distance_meters: 1609, avg_pace_sec_per_mile: 388 + r * 3, heat_adjusted_pace_sec_per_mile: null })); // rep
    if (r < 4) laps.push(lap({ lap_index: idx++, distance_meters: 402, avg_pace_sec_per_mile: 560, heat_adjusted_pace_sec_per_mile: null })); // jog
  }
  laps.push(lap({ lap_index: idx++, distance_meters: 1609, avg_pace_sec_per_mile: 545, heat_adjusted_pace_sec_per_mile: null })); // cooldown

  const out = buildSplits(laps, { isLong: false, bandHigh: 400, plannedMi: 9, ranMi: 9 });
  assert.ok(out);
  const names = out!.splits.map((s) => s.name);
  assert.match(names[0], /^Warm-up/);
  assert.equal(names.filter((n) => n.startsWith("Rep ")).length, 5);
  assert.match(names[1], /^Rep 1 · 1\.0 mi/);
  assert.match(names[names.length - 1], /^Cool-down/);
  // recoveries are folded out — no jog rows
  assert.equal(names.some((n) => /0\.2 mi/.test(n)), false);
});

test("buildSplits: sub-mile reps render in metres", () => {
  const laps: EnrichLap[] = [
    lap({ lap_index: 0, distance_meters: 1609, avg_pace_sec_per_mile: 540, heat_adjusted_pace_sec_per_mile: null }), // wu
    lap({ lap_index: 1, distance_meters: 800, avg_pace_sec_per_mile: 360, heat_adjusted_pace_sec_per_mile: null }),
    lap({ lap_index: 2, distance_meters: 800, avg_pace_sec_per_mile: 362, heat_adjusted_pace_sec_per_mile: null }),
  ];
  const out = buildSplits(laps, { isLong: false, bandHigh: 380, plannedMi: 3, ranMi: 3 });
  const reps = out!.splits.filter((s) => s.name.startsWith("Rep "));
  assert.equal(reps.length, 2);
  assert.match(reps[0].name, /800m/);
});

test("buildSplits: no work laps falls back to a flat per-lap list", () => {
  const laps: EnrichLap[] = [
    lap({ lap_index: 0, distance_meters: 1609, avg_pace_sec_per_mile: 560, heat_adjusted_pace_sec_per_mile: null }),
    lap({ lap_index: 1, distance_meters: 1609, avg_pace_sec_per_mile: 555, heat_adjusted_pace_sec_per_mile: null }),
  ];
  // band far faster than anything run → nothing classifies as a rep
  const out = buildSplits(laps, { isLong: false, bandHigh: 300, plannedMi: 2, ranMi: 2 });
  assert.ok(out);
  assert.equal(out!.splits.every((s) => s.name.startsWith("Lap ")), true);
});

// ── heat-adjusted headline ───────────────────────────────
test("heatAdjHeadline: weighted adj pace, delta to raw, in-band verdict", () => {
  const laps = [
    lap({ avg_pace_sec_per_mile: 570, heat_adjusted_pace_sec_per_mile: 539 }),
    lap({ avg_pace_sec_per_mile: 570, heat_adjusted_pace_sec_per_mile: 539 }),
  ];
  const h = heatAdjHeadline(laps, { low: 535, high: 565 });
  assert.ok(h);
  assert.equal(h!.v, "8:59/mi");
  assert.match(h!.sub, /−31s/);
  assert.match(h!.sub, /in band/);
});

test("heatAdjHeadline: no heat-adjusted laps → undefined", () => {
  const laps = [lap({ heat_adjusted_pace_sec_per_mile: null })];
  assert.equal(heatAdjHeadline(laps, undefined), undefined);
});
