/**
 * Tests for the per-athlete distance curve.
 *
 * The calibration case is real: five races across four distances and twenty
 * months, whose half and marathon independently imply b = 1.051 and 1.053
 * against a generic 1.06. The model was substituting the generic one.
 *
 * Run: deno test _shared/raceCurve.test.ts
 */
import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  convertAlongCurve,
  EXPONENT_PRIOR_SD,
  fitRaceCurve,
  GENERIC_EXPONENT,
  MAX_EXPONENT,
  MIN_EXPONENT,
  RACE_KM,
  type RacePoint,
} from "./raceCurve.ts";

const NOW = new Date("2026-08-17T00:00:00Z");

/** The calibration athlete's real race history. */
const REAL: RacePoint[] = [
  { date: "2024-08-08", distanceKm: RACE_KM.fiveK, seconds: 905 },      // 15:05
  { date: "2024-12-08", distanceKm: RACE_KM.half, seconds: 4119 },      // 1:08:39
  { date: "2025-01-19", distanceKm: RACE_KM.marathon, seconds: 8563 },  // 2:22:43
  { date: "2026-02-07", distanceKm: RACE_KM.tenK, seconds: 1880 },      // 31:20
  { date: "2026-04-12", distanceKm: RACE_KM.tenK, seconds: 1913 },      // 31:53 neutral
];

Deno.test("the real history fits the athlete's own exponent, not the generic one", () => {
  const c = fitRaceCurve(REAL, NOW);
  assert(c.fittedExponent !== null);
  assertAlmostEquals(c.fittedExponent, 1.052, 0.006);
  assert(
    c.exponent < GENERIC_EXPONENT,
    `this athlete holds pace better than generic; got ${c.exponent}`,
  );
  assertEquals(c.racesUsed, 5);
  assertEquals(c.distinctDistances, 4);
});

Deno.test("the drift term absorbs fitness change instead of bending the exponent", () => {
  const c = fitRaceCurve(REAL, NOW);
  assert(c.driftPctPerYear !== null, "5 races should afford a drift term");
  // Roughly flat over 20 months — the point is it is SMALL, not that it is zero.
  assert(
    Math.abs(c.driftPctPerYear) < 5,
    `drift ${c.driftPctPerYear?.toFixed(2)}%/yr is implausibly large for this history`,
  );
});

// ── the guarantee that no single race is load-bearing ──────────────────────

Deno.test("dropping any one race barely moves the exponent", () => {
  const full = fitRaceCurve(REAL, NOW).exponent;
  for (let i = 0; i < REAL.length; i++) {
    const without = fitRaceCurve(REAL.filter((_, j) => j !== i), NOW).exponent;
    assert(
      Math.abs(without - full) < 0.012,
      `removing race ${i} (${REAL[i].date}) moved b by ${(without - full).toFixed(4)}`,
    );
  }
});

Deno.test("it does not matter WHICH distance the athlete raced", () => {
  // Two athletes on the identical curve, one who raced 10K+marathon and one
  // who raced half+5K, must be given the same shape.
  const b = 1.045;
  const at = (km: number) => 1880 * Math.pow(km / 10, b);
  const pairA: RacePoint[] = [
    { date: "2026-02-07", distanceKm: RACE_KM.tenK, seconds: at(RACE_KM.tenK) },
    { date: "2026-04-12", distanceKm: RACE_KM.marathon, seconds: at(RACE_KM.marathon) },
  ];
  const pairB: RacePoint[] = [
    { date: "2026-02-07", distanceKm: RACE_KM.fiveK, seconds: at(RACE_KM.fiveK) },
    { date: "2026-04-12", distanceKm: RACE_KM.half, seconds: at(RACE_KM.half) },
  ];
  const a = fitRaceCurve(pairA, NOW);
  const bb = fitRaceCurve(pairB, NOW);
  assertAlmostEquals(a.fittedExponent!, b, 1e-6);
  assertAlmostEquals(bb.fittedExponent!, b, 1e-6);
});

// ── shrinkage ──────────────────────────────────────────────────────────────

Deno.test("thin evidence lands near generic without a threshold rule", () => {
  const two: RacePoint[] = [
    { date: "2026-02-07", distanceKm: RACE_KM.tenK, seconds: 1880 },
    { date: "2026-04-12", distanceKm: RACE_KM.half, seconds: 4119 },
  ];
  const c = fitRaceCurve(two, NOW);
  assert(c.fittedExponent !== null, "two distances are fittable");
  // Zero degrees of freedom → SE falls back to the prior → ~50% weight.
  assertAlmostEquals(c.evidenceWeight, 0.5, 0.01);
  assert(
    Math.abs(c.exponent - GENERIC_EXPONENT) < Math.abs(c.fittedExponent - GENERIC_EXPONENT),
    "a two-race fit must be pulled toward generic, not taken at face value",
  );
});

Deno.test("strong consistent evidence outweighs the prior", () => {
  const strong = fitRaceCurve(REAL, NOW);
  const thin = fitRaceCurve(REAL.slice(0, 2), NOW);
  assert(
    strong.evidenceWeight > thin.evidenceWeight,
    `five races should carry more weight than two: ${strong.evidenceWeight} vs ${thin.evidenceWeight}`,
  );
});

Deno.test("one race, or many at one distance, yields the generic exponent", () => {
  assertEquals(fitRaceCurve([REAL[3]], NOW).exponent, GENERIC_EXPONENT);
  const allTenK: RacePoint[] = [
    { date: "2026-02-07", distanceKm: 10, seconds: 1880 },
    { date: "2026-04-12", distanceKm: 10, seconds: 1913 },
    { date: "2025-11-01", distanceKm: 10, seconds: 1935 },
  ];
  const c = fitRaceCurve(allTenK, NOW);
  assertEquals(c.exponent, GENERIC_EXPONENT);
  assertEquals(c.distinctDistances, 1);
  assert(c.why.includes("two distances"));
});

Deno.test("distances too close together do not pretend to fit a slope", () => {
  const c = fitRaceCurve([
    { date: "2026-02-07", distanceKm: 10, seconds: 1880 },
    { date: "2026-04-12", distanceKm: 12, seconds: 2300 },
  ], NOW);
  assertEquals(c.exponent, GENERIC_EXPONENT);
  assert(c.why.includes("too narrow"));
});

Deno.test("an absurd fit is clamped to the range real runners occupy", () => {
  // A 5K raced badly and a marathon raced brilliantly would fit b far too low.
  const c = fitRaceCurve([
    { date: "2026-02-07", distanceKm: RACE_KM.fiveK, seconds: 1500 },
    { date: "2026-03-07", distanceKm: RACE_KM.marathon, seconds: 8000 },
  ], NOW);
  assert(c.exponent >= MIN_EXPONENT && c.exponent <= MAX_EXPONENT);
});

Deno.test("no races at all is generic, and says so", () => {
  const c = fitRaceCurve([], NOW);
  assertEquals(c.exponent, GENERIC_EXPONENT);
  assertEquals(c.racesUsed, 0);
  assertEquals(c.evidenceWeight, 0);
});

Deno.test("malformed rows are dropped rather than poisoning the fit", () => {
  const c = fitRaceCurve([
    ...REAL,
    { date: "not-a-date", distanceKm: 10, seconds: 1800 },
    { date: "2026-01-01", distanceKm: 0, seconds: 1800 },
    { date: "2026-01-01", distanceKm: 10, seconds: 0 },
  ], NOW);
  assertEquals(c.racesUsed, 5);
});

// ── conversion ─────────────────────────────────────────────────────────────

Deno.test("converting along the curve round-trips", () => {
  const c = { exponent: 1.052 };
  const half = convertAlongCurve(1920, RACE_KM.tenK, RACE_KM.half, c);
  assertAlmostEquals(convertAlongCurve(half, RACE_KM.half, RACE_KM.tenK, c), 1920, 1e-6);
});

Deno.test("a lower exponent means a better marathon off the same 10K", () => {
  const durable = convertAlongCurve(1920, RACE_KM.tenK, RACE_KM.marathon, { exponent: 1.052 });
  const fading = convertAlongCurve(1920, RACE_KM.tenK, RACE_KM.marathon, { exponent: 1.062 });
  assert(durable < fading);
  // The gap this athlete's own curve is worth: about two minutes.
  const gap = fading - durable;
  assert(gap > 90 && gap < 180, `expected ~2 min of marathon, got ${Math.round(gap)}s`);
});

Deno.test("the generic exponent reproduces the shipped ratio table", () => {
  // RACE_RATIOS_TO_10K puts marathon at 4.615625 of a 10K. Riegel at 1.06
  // over the same distance ratio should land within a few tenths of a percent
  // — they are two encodings of the same curve, and a big gap would mean the
  // table and this module disagree about what "generic" means.
  const viaCurve = convertAlongCurve(1920, RACE_KM.tenK, RACE_KM.marathon, {
    exponent: GENERIC_EXPONENT,
  });
  const viaTable = 1920 * 4.615625;
  assert(
    Math.abs(viaCurve - viaTable) / viaTable < 0.005,
    `curve ${Math.round(viaCurve)}s vs table ${Math.round(viaTable)}s — more than 0.5% apart`,
  );
});

Deno.test("the prior scale is the knob, and it is documented as such", () => {
  assert(EXPONENT_PRIOR_SD > 0 && EXPONENT_PRIOR_SD < 0.05);
});
