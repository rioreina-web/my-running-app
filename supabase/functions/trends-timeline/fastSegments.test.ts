/**
 * Tests for the fast-segments adapter's stream slicing (split grade input).
 * Run: deno test trends-timeline/fastSegments.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { sliceGradeSegments, smoothAltitudeWindow } from "./fastSegments.ts";
import { gradeAdjustRun } from "../_shared/pace-grade-adjustment.ts";

Deno.test("sliceGradeSegments: chunks a steady climb into ~50m segments at the right grade", () => {
  const time: number[] = [], distance: number[] = [], altitude: number[] = [];
  for (let i = 0; i <= 300; i += 10) {
    distance.push(i);
    time.push(i / 5);             // 5 m/s
    altitude.push(100 + i * 0.05); // steady 5% grade
  }
  const segs = sliceGradeSegments({ time, distance, altitude }, 0, time.length - 1, 50);
  assert(segs.length >= 5, `got ${segs.length} chunks`);
  for (const s of segs) assert(Math.abs(s.gradePct - 5) < 0.5, `grade ${s.gradePct}`);
  const totalT = segs.reduce((a, s) => a + s.seconds, 0);
  assert(Math.abs(totalT - 60) < 2, `total ${totalT}s`);
});

Deno.test("sliceGradeSegments: captures a downhill (negative grade)", () => {
  const time: number[] = [], distance: number[] = [], altitude: number[] = [];
  for (let i = 0; i <= 200; i += 10) {
    distance.push(i);
    time.push(i / 5);
    altitude.push(100 - i * 0.04); // -4% grade
  }
  const segs = sliceGradeSegments({ time, distance, altitude }, 0, time.length - 1, 50);
  assert(segs.length > 0);
  for (const s of segs) assert(s.gradePct < -3 && s.gradePct > -5, `grade ${s.gradePct}`);
});

Deno.test("smoothAltitudeWindow: a linear ramp survives smoothing unchanged", () => {
  const alt = Array.from({ length: 60 }, (_, i) => 100 + i * 0.5);
  const out = smoothAltitudeWindow(alt, 0, alt.length - 1);
  for (let i = 0; i < alt.length; i++) {
    assert(Math.abs(out[i] - alt[i]) < 1e-9, `i=${i}: ${out[i]} vs ${alt[i]}`);
  }
});

/**
 * The track regression (2026-08-06). A flat 400 m track with ±1.5 m of GPS /
 * barometric altitude noise used to report ~7 s/mi of "hill cost", because the
 * grade model damps downhill credit and so zero-mean noise accumulates one way.
 * Smoothing + 200 m chunks + the sub-1% deadband must bring that under 1 s/mi;
 * `HILL_RESOLUTION_SEC` in fast-segment-trends.ts then zeroes what's left.
 */
Deno.test("sliceGradeSegments: a flat track with GPS noise costs no meaningful time", () => {
  const time: number[] = [], distance: number[] = [], altitude: number[] = [];
  let seed = 12345;
  const rnd = () => (seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff;
  for (let i = 0; i <= 1600; i++) {          // 1600 m at 1 m spacing, dead flat
    distance.push(i);
    time.push(i / 5.3);                       // ~5:04/mi
    altitude.push(100 + (rnd() - 0.5) * 2 * 1.5); // ±1.5 m of pure noise
  }
  const segs = sliceGradeSegments({ time, distance, altitude }, 0, time.length - 1);
  assert(segs.length > 0, "expected chunks");
  const { rawSeconds, adjustedSeconds } = gradeAdjustRun(segs);
  const paceSec = 304;
  const phantomSecPerMile = (rawSeconds - adjustedSeconds) / rawSeconds * paceSec;
  assert(
    Math.abs(phantomSecPerMile) < 1,
    `flat track fabricated ${phantomSecPerMile.toFixed(2)} s/mi of hill cost`,
  );
});

Deno.test("sliceGradeSegments: empty on an invalid range", () => {
  assertEquals(sliceGradeSegments({ time: [0], distance: [0], altitude: [0] }, 0, 0), []);
  assertEquals(sliceGradeSegments({ time: [], distance: [], altitude: [] }, 0, 10), []);
});
