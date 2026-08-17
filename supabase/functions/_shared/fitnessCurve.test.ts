/**
 * Tests for the fitness curve damper.
 *
 * The calibration case is the real one: on 2026-08-15 the raw model produced
 * 32:00 at 03:30 and 33:44 at 15:03 — 104 seconds apart, same athlete, same
 * day. The curve must make that impossible without also making a genuine
 * training block invisible.
 *
 * Run: deno test _shared/fitnessCurve.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  DEFAULT_TAU_DAYS,
  isOwnSnapshot,
  MAX_DAILY_MOVE_PCT,
  mostRecentPrior,
  smoothFitnessPace,
  STALE_PRIOR_DAYS,
} from "./fitnessCurve.ts";

const OWN = "race (10K) + pace segments · v2";
const DEVICE = "race (10K)"; // iOS on-device predictor — no "· v2"

const MI = 6.21371;
const paceOf = (raceSeconds: number) => raceSeconds / MI;
const raceOf = (pace: number) => pace * MI;
const fmt = (s: number) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;

Deno.test("first sample takes the raw value — nothing to damp against", () => {
  const r = smoothFitnessPace({ rawPace: 309, priorPace: null, deltaDays: 0 });
  assertEquals(r.pace, 309);
  assertEquals(r.reason, "first-sample");
});

Deno.test("the real 2026-08-15 jump: 32:00 → 33:44 same day barely moves", () => {
  // Both runs on one day. Δt is hours, so the curve must essentially hold.
  const prior = paceOf(1920); // 32:00
  const raw = paceOf(2024); // 33:44
  const r = smoothFitnessPace({ rawPace: raw, priorPace: prior, deltaDays: 0.48 });
  const moved = raceOf(r.pace) - 1920;
  assert(moved < 3, `same-day rederivation moved ${moved.toFixed(1)}s; want < 3s`);
  assertEquals(r.reason, "damped");
});

Deno.test("two samples in one day do not each take a full day's step", () => {
  const prior = paceOf(1920);
  const raw = paceOf(2024);
  const once = smoothFitnessPace({ rawPace: raw, priorPace: prior, deltaDays: 1 });
  const twiceA = smoothFitnessPace({ rawPace: raw, priorPace: prior, deltaDays: 0.5 });
  const twiceB = smoothFitnessPace({ rawPace: raw, priorPace: twiceA.pace, deltaDays: 0.5 });
  // Recomputing more often must not advance the curve faster.
  assert(
    Math.abs(twiceB.pace - once.pace) < 0.05,
    `cadence changed the curve: once=${once.pace.toFixed(3)} twice=${twiceB.pace.toFixed(3)}`,
  );
});

Deno.test("a sustained block still moves the curve over weeks", () => {
  // Raw says 31:00 every day. The curve should close most of the gap in ~6
  // weeks — slow enough to describe a block, not so slow it never arrives.
  let pace = paceOf(1920); // 32:00
  const raw = paceOf(1860); // 31:00
  for (let d = 0; d < 42; d++) {
    pace = smoothFitnessPace({ rawPace: raw, priorPace: pace, deltaDays: 1 }).pace;
  }
  const arrived = raceOf(pace);
  assert(
    arrived < 1890 && arrived > 1860,
    `after 6 weeks of 31:00 evidence the curve reads ${fmt(arrived)}; want inside 31:00–31:30`,
  );
});

Deno.test("one outlier session cannot jolt the curve", () => {
  // A single absurd reading (mis-parsed rep set) lands between honest days.
  let pace = paceOf(1920);
  for (const raw of [1920, 1925, 1500 /* absurd */, 1918, 1922]) {
    pace = smoothFitnessPace({ rawPace: paceOf(raw), priorPace: pace, deltaDays: 1 }).pace;
  }
  const after = raceOf(pace);
  assert(
    Math.abs(after - 1920) < 12,
    `an outlier moved the curve to ${fmt(after)}; want within 12s of 32:00`,
  );
});

Deno.test("the daily cap binds before alpha on a violent raw swing", () => {
  const prior = paceOf(1920);
  const r = smoothFitnessPace({ rawPace: paceOf(1500), priorPace: prior, deltaDays: 1 });
  assert(r.capped, "expected the daily cap to bind");
  const movePct = Math.abs(r.pace - prior) / prior;
  assert(
    movePct <= MAX_DAILY_MOVE_PCT + 1e-9,
    `moved ${(movePct * 100).toFixed(3)}%; cap is ${(MAX_DAILY_MOVE_PCT * 100).toFixed(1)}%`,
  );
});

Deno.test("a declared race resets outright — a measurement, not evidence", () => {
  const r = smoothFitnessPace({
    rawPace: paceOf(1860), priorPace: paceOf(1920), deltaDays: 1, hardReset: true,
  });
  // Tolerance, not equality: paceOf/raceOf round-trips through a division.
  assert(Math.abs(raceOf(r.pace) - 1860) < 1e-6);
  assertEquals(r.reason, "hard-reset");
});

Deno.test("a stale prior is abandoned rather than crawled back from", () => {
  const r = smoothFitnessPace({
    rawPace: paceOf(2100), priorPace: paceOf(1860), deltaDays: STALE_PRIOR_DAYS + 1,
  });
  assert(Math.abs(raceOf(r.pace) - 2100) < 1e-6);
  assertEquals(r.reason, "stale-prior");
});

Deno.test("a real gap travels further than a single day", () => {
  const prior = paceOf(1920);
  const raw = paceOf(1860);
  const oneDay = smoothFitnessPace({ rawPace: raw, priorPace: prior, deltaDays: 1 });
  const tenDays = smoothFitnessPace({ rawPace: raw, priorPace: prior, deltaDays: 10 });
  assert(
    Math.abs(tenDays.pace - prior) > Math.abs(oneDay.pace - prior),
    "a 10-day gap should move further than a 1-day step",
  );
  assert(tenDays.alpha > oneDay.alpha);
});

Deno.test("alpha matches the stated time constant", () => {
  const r = smoothFitnessPace({
    rawPace: 300, priorPace: 310, deltaDays: DEFAULT_TAU_DAYS,
  });
  // One time constant closes ~63.2% of the gap.
  assert(
    Math.abs(r.alpha - (1 - Math.exp(-1))) < 1e-9,
    `alpha at τ should be 1−1/e, got ${r.alpha}`,
  );
});

Deno.test("mostRecentPrior takes the newest, never the fastest", () => {
  const snaps = [
    { createdAt: "2026-08-10T03:30:00Z", estimated10kPaceSeconds: 290, dataSource: OWN }, // fastest
    { createdAt: "2026-08-15T03:30:00Z", estimated10kPaceSeconds: 309, dataSource: OWN }, // newest
    { createdAt: "2026-08-01T03:30:00Z", estimated10kPaceSeconds: 320, dataSource: OWN },
  ];
  const p = mostRecentPrior(snaps, new Date("2026-08-16T03:30:00Z"));
  assert(p);
  assertEquals(p.pace, 309, "picked the fastest instead of the most recent — that is the ratchet");
  assertEquals(Math.round(p.deltaDays), 1);
});

Deno.test("mostRecentPrior ignores snapshots from the future and junk rows", () => {
  const snaps = [
    { createdAt: "2026-09-01T03:30:00Z", estimated10kPaceSeconds: 250, dataSource: OWN }, // future
    { createdAt: "not-a-date", estimated10kPaceSeconds: 300, dataSource: OWN },
    { createdAt: "2026-08-14T03:30:00Z", estimated10kPaceSeconds: 0, dataSource: OWN }, // no value
    { createdAt: "2026-08-13T03:30:00Z", estimated10kPaceSeconds: 311, dataSource: OWN },
  ];
  const p = mostRecentPrior(snaps, new Date("2026-08-16T03:30:00Z"));
  assert(p);
  assertEquals(p.pace, 311);
});

Deno.test("empty history yields no prior", () => {
  assertEquals(mostRecentPrior([], new Date("2026-08-16T00:00:00Z")), null);
});

// ── Foreign-writer guard (2026-08-17) ────────────────────────────────────
//
// `fitness_snapshots` had two writers. The iOS on-device predictor sees no
// laps, no weather and no curve; it wrote 33:44 against this model's 32:00 on
// 2026-08-15 and 2026-08-16, and the curve then damped away FROM those rows —
// ~100 s off, six weeks to unwind at tau=21d.

Deno.test("isOwnSnapshot: only rows this model marked", () => {
  assert(isOwnSnapshot("race (10K) + pace segments · v2"));
  assert(isOwnSnapshot("training (intervalSession) + race (10K) · v2"));
  assert(!isOwnSnapshot("race (10K)"), "the device's exact string must not pass");
  assert(!isOwnSnapshot(null), "unknown provenance is not own provenance");
  assert(!isOwnSnapshot(undefined));
  assert(!isOwnSnapshot(""));
});

Deno.test("the real poisoning: a device row is not used as the prior", () => {
  // Exactly what prod held at the 2026-08-16 20:46 device write.
  const snaps = [
    { createdAt: "2026-08-16T20:46:00Z", estimated10kPaceSeconds: 325.7, dataSource: DEVICE },
    { createdAt: "2026-08-16T03:30:05Z", estimated10kPaceSeconds: 309.1, dataSource: OWN },
    { createdAt: "2026-08-15T15:03:00Z", estimated10kPaceSeconds: 325.7, dataSource: DEVICE },
    { createdAt: "2026-08-15T03:30:00Z", estimated10kPaceSeconds: 309.1, dataSource: OWN },
  ];
  const p = mostRecentPrior(snaps, new Date("2026-08-17T03:30:00Z"));
  assert(p);
  assertEquals(p.pace, 309.1, "damped against the device row instead of our own");
  // …and the resulting estimate stays near 32:00 rather than crawling from 33:44.
  const r = smoothFitnessPace({ rawPace: 309.5, priorPace: p.pace, deltaDays: p.deltaDays });
  const race = Math.round(r.pace * 6.21371);
  assert(race > 1915 && race < 1935, `expected ~32:00, got ${race}s`);
});

Deno.test("all-foreign history yields no prior — seed fresh, don't inherit", () => {
  const snaps = [
    { createdAt: "2026-08-16T20:46:00Z", estimated10kPaceSeconds: 325.7, dataSource: DEVICE },
    { createdAt: "2026-08-15T15:03:00Z", estimated10kPaceSeconds: 325.7, dataSource: null },
  ];
  assertEquals(mostRecentPrior(snaps, new Date("2026-08-17T03:30:00Z")), null);
});
