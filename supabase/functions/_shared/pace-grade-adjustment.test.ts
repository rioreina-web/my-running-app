/**
 * Tests for pace-grade-adjustment.ts.
 *
 * Run: deno test _shared/pace-grade-adjustment.test.ts
 *
 * Covers:
 *  - gradeFactor: flat = 1, uphill > 1, downhill < 1 but DAMPED vs raw Minetti
 *  - gradient clamp
 *  - adjustPaceForGrade direction
 *  - combineConditions (grade + heat)
 *  - Cap 10K CALIBRATION (integration): the real race must read as a net hill
 *    COST of ~45–90 s, never neutral / terrain-helped. This is the guard that
 *    keeps us from regressing to raw symmetric Minetti.
 *    See outputs/grade-adjusted-pace-plan-2026-06-21.md §10.1.
 */

import { assert, assertAlmostEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  DOWNHILL_CREDIT,
  adjustPaceForGrade,
  combineConditions,
  gradeAdjustRun,
  gradeFactor,
  minettiCost,
  type RunSegment,
} from "./pace-grade-adjustment.ts";

const MINETTI_FLAT = 3.6;

Deno.test("gradeFactor: flat is 1.0", () => {
  assertAlmostEquals(gradeFactor(0), 1.0, 1e-9);
});

Deno.test("gradeFactor: uphill > 1 (costs effort)", () => {
  assert(gradeFactor(5) > 1, "5% uphill should be > 1");
  assert(gradeFactor(10) > gradeFactor(5), "steeper uphill costs more");
});

Deno.test("gradeFactor: downhill < 1 but damped vs raw Minetti", () => {
  const g = -8;
  const rawMinetti = minettiCost(g / 100) / MINETTI_FLAT; // < 1
  const damped = gradeFactor(g);
  assert(damped < 1, "downhill factor should be < 1");
  // Damped credit means the factor is CLOSER to 1 than raw Minetti would be.
  assert(damped > rawMinetti, "downhill should be damped (less credit than raw Minetti)");
  // And it should sit exactly DOWNHILL_CREDIT of the way from 1 toward raw.
  assertAlmostEquals(damped, 1 + DOWNHILL_CREDIT * (rawMinetti - 1), 1e-9);
});

Deno.test("gradeFactor: gradient is clamped at ±30%", () => {
  assertAlmostEquals(gradeFactor(50), gradeFactor(30), 1e-9);
  assertAlmostEquals(gradeFactor(-50), gradeFactor(-30), 1e-9);
});

Deno.test("adjustPaceForGrade: uphill yields a faster equivalent pace", () => {
  const a = adjustPaceForGrade(360, 6); // 6:00/mi up a 6% grade
  assert(a.adjustedPaceSeconds < 360, "uphill effort is worth a faster flat pace");
  assert(a.adjustmentSecondsPerMile < 0);
});

Deno.test("combineConditions: grade + heat both reduce toward neutral/cool", () => {
  // 5:17/mi (317s) on flat (grade 0) with 2.36% heat → only heat removed.
  const c = combineConditions(317, 0, 0.0236);
  assertAlmostEquals(c.conditionsAdjustedPaceSeconds, 317 / 1.0236, 1e-6);
});

// ── Cap 10K calibration fixture ─────────────────────────────────
// Real race, Austin 2026-04-12 (Strava activity 18081526879), downsampled
// ~10s grade + cumulative-time streams. Rolling loop, ~100 m climb, net ≈ 0.
const CAP10K_GRADE = [0,1.8,1.8,0,0.9,0.9,1.9,0.9,1.9,1.8,3.1,0,2.9,1,1.9,0,1.9,2.1,-1,0,1,2,2.1,2,0,4.1,4.3,5,5.3,-1.1,4,-4.9,-5.6,-4.6,2.8,0,-10,-8.5,-4.5,-2.6,0,4.3,6.5,7.5,6.3,2,4.4,5.6,4.1,1,-2.9,-3.8,-1.8,0,-2,-2.8,-2.7,0,-1.8,2.1,3.5,2.2,8,2.9,-4.9,-12,-12,-5.5,-0.9,0,1,1,2,4.5,9.4,4.5,4.8,4.7,3.6,3.7,2,0,2.1,1,-3.8,-0.9,0.9,0,0.9,-2.7,-1.8,2.9,2,-1.9,-2.9,-3.8,-0.9,-4.7,-7.5,-1.9,4.3,0,-3.8,0,1.9,-1,0,2,2.2,0,4.3,3.1,-3.7,-6.6,-5.4,-2.7,-6.3,-5.5,0,2,1,1,0,2.1,0,0,-0.9,-9.6,-7.2,-1,-1,-2,-3.8,-2.8,-3.9,1.9,-1,0,-0.9,-2.8,-1,0,1,1,0,-1,1,2,1,-3,1,-1,0,-1,-2,-0.9,0,0,-1,1,0,1,0,0.9,-2,-1,0.9,-1.8,-2.9,3.1,1.9,0,1,5.2,2.2,1,-2,-1,2,1,1,1.1,3,0,1.9,1,0,1,0,1,1,0,-3.6,-2.5,1,0.9,1.9,0,-1.8,0];
const CAP10K_TIME = [0,9,18,27,37,46,56,65,74,84,94,104,114,124,134,144,153,164,173,183,193,203,213,223,233,243,253,264,274,285,296,306,316,325,335,345,354,363,372,381,391,402,412,423,434,444,455,466,477,487,497,507,516,525,535,545,554,564,573,583,593,604,616,627,637,647,656,665,674,684,693,703,713,724,736,747,759,771,782,794,806,816,827,838,848,857,867,877,887,896,905,915,926,936,945,955,965,975,984,994,1003,1013,1023,1032,1043,1052,1063,1073,1084,1094,1105,1116,1126,1135,1144,1154,1163,1172,1181,1191,1201,1211,1221,1231,1242,1252,1262,1271,1280,1289,1299,1309,1319,1328,1337,1347,1357,1367,1376,1386,1396,1405,1415,1425,1435,1445,1456,1466,1476,1486,1496,1506,1516,1526,1536,1545,1555,1565,1575,1585,1595,1605,1615,1625,1635,1644,1654,1663,1673,1683,1693,1703,1713,1723,1734,1745,1755,1765,1775,1785,1796,1806,1817,1828,1838,1848,1858,1868,1878,1887,1897,1906,1916,1925,1934,1944,1953,1963,1972,1982];

function cap10kSegments(): RunSegment[] {
  const segs: RunSegment[] = [];
  for (let k = 1; k < CAP10K_TIME.length; k++) {
    segs.push({ seconds: CAP10K_TIME[k] - CAP10K_TIME[k - 1], gradePct: CAP10K_GRADE[k] });
  }
  return segs;
}

Deno.test("Cap 10K calibration: net hill cost is 45–90 s (not neutral)", () => {
  const r = gradeAdjustRun(cap10kSegments());
  // Sanity: total time matches the race (1982 s).
  assertAlmostEquals(r.rawSeconds, 1982, 1);
  // The headline guard: damped downhills make the rolling loop a net COST,
  // landing in the acceptance band. Raw symmetric Minetti would FAIL this
  // (it reports ~ −14 s, i.e. terrain "helped").
  assert(
    r.hillCostSeconds >= 45 && r.hillCostSeconds <= 90,
    `expected net hill cost 45–90 s, got ${r.hillCostSeconds.toFixed(0)} s`,
  );
});
