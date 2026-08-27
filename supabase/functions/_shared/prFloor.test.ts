import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyFloor,
  computePrFloors,
  FLOOR_BASE,
  FLOOR_MAX_DECLINE,
  maxDecline,
  type PrRecord,
} from "./prFloor.ts";

const NOW = new Date("2026-08-25T12:00:00Z");
const pr = (distanceKey: PrRecord["distanceKey"], date: string, seconds: number, conditionsKnown = true): PrRecord =>
  ({ distanceKey, date, seconds, conditionsKnown });

// ── the allowance ───────────────────────────────────────────────────────────

Deno.test("held volume + quality present → only the base allowance", () => {
  const d = maxDecline(1.0, 0.15, 0);
  assertEquals(d.volume, 0);
  assertEquals(d.quality, 0);
  assertEquals(d.age, 0);
  assertEquals(d.total, FLOOR_BASE);
});

Deno.test("volume collapse opens the allowance; quality drought adds less", () => {
  const collapsed = maxDecline(0.3, 0.15, 0).total;
  const droughted = maxDecline(1.0, 0.0, 0).total;
  assert(collapsed > droughted, `${collapsed} vs ${droughted}`);
  assert(collapsed > FLOOR_BASE);
  // Volume is the stronger evidence of decline, by design — it is measured
  // from distance, while density depends on labels that are often absent.
});

Deno.test("unknown quality density is neutral, not assumed-worst", () => {
  assertEquals(maxDecline(1.0, null, 0).quality, 0);
});

Deno.test("allowance never exceeds the cap however bad it gets", () => {
  assertEquals(maxDecline(0, 0, 40).total, FLOOR_MAX_DECLINE);
});

// ── rule 1: same-distance only ──────────────────────────────────────────────

Deno.test("a 5K PR creates no floor at any other distance", () => {
  const floors = computePrFloors([pr("fiveK", "2024-08-08", 864)], {
    now: NOW,
    weeklyMiles: 65,
    referenceWeeklyMiles: 60,
    qualityDensity: 0.15,
  });
  assertEquals([...floors.keys()], ["fiveK"]);
  assertEquals(floors.get("tenK"), undefined);
  assertEquals(floors.get("marathon"), undefined);
  // The ratchet this prevents: converting every PR to a 10K-equivalent and
  // taking the best gives the calibration athlete 29:55 — faster than she has
  // ever run a 10K, off a heat-credited 5K from a different era.
});

Deno.test("fastest record per distance wins", () => {
  const floors = computePrFloors(
    [pr("tenK", "2026-02-07", 1880), pr("tenK", "2026-04-12", 1943)],
    { now: NOW, weeklyMiles: 65, referenceWeeklyMiles: 60, qualityDensity: 0.15 },
  );
  assertEquals(floors.get("tenK")!.prSeconds, 1880);
});

// ── rule 3: missing conditions fail loose ───────────────────────────────────

Deno.test("a PR with no weather on file uses its raw time, which loosens the floor", () => {
  // Same race, once known-neutral at 864 and once unnormalized at its raw 905.
  const known = computePrFloors([pr("fiveK", "2024-08-08", 864, true)], {
    now: NOW, weeklyMiles: 65, referenceWeeklyMiles: 60, qualityDensity: 0.15,
  }).get("fiveK")!;
  const unknown = computePrFloors([pr("fiveK", "2024-08-08", 905, false)], {
    now: NOW, weeklyMiles: 65, referenceWeeklyMiles: 60, qualityDensity: 0.15,
  }).get("fiveK")!;
  assert(unknown.floorSeconds > known.floorSeconds);
  assertEquals(unknown.conditionsKnown, false);
});

// ── rule 4: volume is athlete-relative ──────────────────────────────────────

Deno.test("an 18 mpw athlete at their own normal is not detraining", () => {
  const small = computePrFloors([pr("tenK", "2026-02-07", 2700)], {
    now: NOW, weeklyMiles: 18, referenceWeeklyMiles: 18, qualityDensity: 0.12,
  }).get("tenK")!;
  const big = computePrFloors([pr("tenK", "2026-02-07", 1880)], {
    now: NOW, weeklyMiles: 66, referenceWeeklyMiles: 66, qualityDensity: 0.12,
  }).get("tenK")!;
  // Identical allowance: both are training exactly as much as they normally do.
  assertEquals(small.maxDeclinePct, big.maxDeclinePct);
});

// ── clamping ────────────────────────────────────────────────────────────────

Deno.test("an estimate inside the floor is returned untouched", () => {
  const floors = computePrFloors([pr("tenK", "2026-02-07", 1880)], {
    now: NOW, weeklyMiles: 66, referenceWeeklyMiles: 63, qualityDensity: 0.15,
  });
  // The live 2026-08-24 estimate: 32:00, +2.13% off the 31:20 PR.
  const r = applyFloor(1920, floors.get("tenK"));
  assertEquals(r.bound, false);
  assertEquals(r.seconds, 1920);
});

Deno.test("THE 2:37 REGRESSION — a 2:22:43 PR at held volume caps the claim", () => {
  // 2026-08-17: a 31:20 10K PB and 66 mpw held published a 2:36:55 marathon,
  // 9.9% off a 2:22:43 PR. Nothing in the model compared the two.
  const floors = computePrFloors([pr("marathon", "2025-01-19", 8563)], {
    now: new Date("2026-08-17T12:00:00Z"),
    weeklyMiles: 66,
    referenceWeeklyMiles: 63,
    qualityDensity: 0.15,
  });
  const floor = floors.get("marathon")!;
  const r = applyFloor(9415, floor); // 2:36:55
  assert(r.bound, "the floor must bind on the incident");
  assert(r.seconds < 9415);
  // Volume held and quality present, so the allowance is base + age only.
  assertEquals(floor.terms.volume, 0);
  assertEquals(floor.terms.quality, 0);
  assert(floor.terms.age > 0, "a 1.6-year-old PR carries an age term");
  // It does not make 2:37 correct — the honest answer was ~2:29. It makes it
  // not absurd, which is the whole job of a guard rail.
  assert(r.seconds > 8563, "never clamps to the PR itself");
});
