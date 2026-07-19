/**
 * Tests for the fast-segments adapter's stream slicing (split grade input).
 * Run: deno test trends-timeline/fastSegments.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { sliceGradeSegments } from "./fastSegments.ts";

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

Deno.test("sliceGradeSegments: empty on an invalid range", () => {
  assertEquals(sliceGradeSegments({ time: [0], distance: [0], altitude: [0] }, 0, 0), []);
  assertEquals(sliceGradeSegments({ time: [], distance: [], altitude: [] }, 0, 10), []);
});
