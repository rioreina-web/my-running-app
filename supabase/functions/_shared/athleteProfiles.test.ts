/**
 * Synthetic athlete profiles — does the model work for anyone but Rio?
 *
 * There is exactly one real athlete in this database. Every calibration
 * decision, every threshold, every sanity check made during development was
 * made against his data: a 31:20 10K runner training 66 miles a week in Texas
 * humidity. That is a narrow slice of the people this will serve, and a model
 * tuned to it will fail quietly for everyone else — a beginner's tempo run
 * discarded as "not quality", a masters runner's heat credit computed off a
 * band fitted to a sub-5:00 miler.
 *
 * These profiles are not validation. Synthetic data cannot tell you whether a
 * prediction is right; only a race can, and that requires athletes. What they
 * CAN do is fail when a constant is secretly shaped like one person — the
 * class of bug caught twice by hand during development (a pace filter at
 * 240-700 s/mi that would have thrown out most runners' quality work, and a
 * bpm-to-pace conversion hardcoded at the calibration athlete's own 10K pace).
 *
 * Run: deno test _shared/athleteProfiles.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { blendEvidence, type Evidence } from "./evidenceBlend.ts";
import { convertAlongCurve, fitRaceCurve, RACE_KM, type RacePoint } from "./raceCurve.ts";
import { efficiencyTrend, fitExpectedHr, type HrSample } from "./expectedHr.ts";
import {
  combineZoneEstimates,
  estimateFromSession,
  type ParsedBlock,
  type ParsedSession,
} from "./trainingZoneSignal.ts";

const NOW = new Date("2026-08-17T00:00:00Z");
const MI = 6.21371;
const day = (ago: number) => new Date(NOW.getTime() - ago * 86_400_000).toISOString().slice(0, 10);
const mmss = (s: number) => `${Math.floor(s / 60)}:${String(Math.round(s % 60)).padStart(2, "0")}`;

interface Profile {
  name: string;
  /** 10K time in seconds — the level. */
  tenKSeconds: number;
  /** Fatigue exponent — the shape. Real runners span roughly 1.02–1.10. */
  exponent: number;
  /** Typical dew point they train in, °F. */
  dew: number;
  /** Rep distance they favour, miles. */
  repMiles: number;
}

/**
 * Deliberately spans the population, not the developer. The elite and the
 * beginner are four-and-a-half minutes per mile apart at 10K pace; the cold
 * and humid profiles are thirty degrees of dew apart.
 */
const PROFILES: Profile[] = [
  { name: "elite (28:00 10K)", tenKSeconds: 1680, exponent: 1.045, dew: 50, repMiles: 1.0 },
  { name: "calibration athlete", tenKSeconds: 1920, exponent: 1.052, dew: 74, repMiles: 0.62 },
  { name: "strong club (36:00)", tenKSeconds: 2160, exponent: 1.06, dew: 60, repMiles: 0.5 },
  { name: "mid-pack (45:00)", tenKSeconds: 2700, exponent: 1.07, dew: 66, repMiles: 0.5 },
  { name: "beginner (58:00)", tenKSeconds: 3480, exponent: 1.085, dew: 55, repMiles: 0.25 },
  { name: "masters, humid (52:00)", tenKSeconds: 3120, exponent: 1.075, dew: 76, repMiles: 0.5 },
];

const tenKPaceOf = (p: Profile) => p.tenKSeconds / MI;

/** A rep session at this profile's own 10K pace — their equivalent of 10×1K. */
function repSession(p: Profile, ago: number, paceSecPerMile: number): ParsedSession {
  const reps = Math.max(4, Math.round(6.2 / p.repMiles / 2));
  const blocks: ParsedBlock[] = [];
  for (let i = 0; i < reps; i++) {
    blocks.push({
      role: "work_rep",
      durationS: Math.round(paceSecPerMile * p.repMiles),
      distanceMiles: p.repMiles,
      avgPacePerMile: mmss(paceSecPerMile),
      avgHr: 165,
    });
    if (i < reps - 1) {
      blocks.push({ role: "recovery", durationS: 60, distanceMiles: 0.05, avgPacePerMile: "—", avgHr: 145 });
    }
  }
  return {
    date: day(ago),
    type: "interval",
    confidence: 1,
    blocks,
    tempF: p.dew + 4,
    dewPointF: p.dew,
  };
}

// ── the training signal ────────────────────────────────────────────────────

Deno.test("every profile's own 10K-pace session reads back as their 10K", () => {
  for (const p of PROFILES) {
    const anchor = tenKPaceOf(p);
    const { estimate, reason } = estimateFromSession(repSession(p, 5, anchor), anchor);
    assert(estimate, `${p.name}: session dropped — ${reason}`);
    const impliedTenK = estimate.equivalentPace * MI;
    const errPct = Math.abs(impliedTenK - p.tenKSeconds) / p.tenKSeconds;
    assert(
      errPct < 0.06,
      `${p.name}: own-pace session read as ${mmss(impliedTenK)} against a ${mmss(p.tenKSeconds)} 10K ` +
        `(${(errPct * 100).toFixed(1)}% off)`,
    );
  }
});

Deno.test("a faster session reads faster for every profile, not just quick ones", () => {
  for (const p of PROFILES) {
    const anchor = tenKPaceOf(p);
    const onPace = estimateFromSession(repSession(p, 5, anchor), anchor).estimate;
    const faster = estimateFromSession(repSession(p, 5, anchor * 0.97), anchor).estimate;
    assert(onPace && faster, `${p.name}: a 3%-faster session should still be readable`);
    assert(
      faster.equivalentPace < onPace.equivalentPace,
      `${p.name}: running faster did not read as fitter`,
    );
  }
});

Deno.test("the plausibility gate is not calibrated to one runner's histogram", () => {
  // Aerobic work well below quality must be dropped for EVERY profile, and
  // quality work must be kept for every profile. A cutoff shaped like one
  // athlete's session distribution would pass here and fail there.
  for (const p of PROFILES) {
    const anchor = tenKPaceOf(p);
    const quality = estimateFromSession(repSession(p, 5, anchor * 1.01), anchor).estimate;
    assert(quality, `${p.name}: near-10K-pace work must count as quality`);
    const aerobic = estimateFromSession(repSession(p, 5, anchor * 1.35), anchor);
    assertEquals(aerobic.estimate, null, `${p.name}: 35%-slower work must not count as a fitness statement`);
  }
});

// ── the distance curve ─────────────────────────────────────────────────────

Deno.test("each profile's own exponent is recovered, across the whole range", () => {
  for (const p of PROFILES) {
    const at = (km: number) => p.tenKSeconds * Math.pow(km / 10, p.exponent);
    const races: RacePoint[] = [
      { date: day(300), distanceKm: RACE_KM.fiveK, seconds: at(RACE_KM.fiveK) },
      { date: day(200), distanceKm: RACE_KM.tenK, seconds: at(RACE_KM.tenK) },
      { date: day(100), distanceKm: RACE_KM.half, seconds: at(RACE_KM.half) },
      { date: day(30), distanceKm: RACE_KM.marathon, seconds: at(RACE_KM.marathon) },
    ];
    const c = fitRaceCurve(races, NOW);
    assert(c.fittedExponent !== null, `${p.name}: four races across four distances must fit`);
    assert(
      Math.abs(c.fittedExponent - p.exponent) < 0.01,
      `${p.name}: fitted ${c.fittedExponent.toFixed(4)} against a true ${p.exponent}`,
    );
  }
});

Deno.test("marathon prediction tracks the exponent, not the pivot distance", () => {
  const durable = { exponent: 1.04 };
  const fading = { exponent: 1.09 };
  for (const p of PROFILES) {
    const d = convertAlongCurve(p.tenKSeconds, RACE_KM.tenK, RACE_KM.marathon, durable);
    const f = convertAlongCurve(p.tenKSeconds, RACE_KM.tenK, RACE_KM.marathon, fading);
    assert(f > d, `${p.name}: a higher exponent must give a slower marathon`);
    // And the gap must be material at every level, not just fast ones.
    assert((f - d) / d > 0.05, `${p.name}: exponent barely mattered (${((f - d) / d * 100).toFixed(1)}%)`);
  }
});

// ── the evidence blend ─────────────────────────────────────────────────────

Deno.test("blend behaves identically in shape for every profile", () => {
  for (const p of PROFILES) {
    const raced = tenKPaceOf(p);
    const training = raced * 0.97; // 3% fitter than the race
    const ev: Evidence[] = [{ tenKPace: raced, date: day(56), kind: "race" }];
    for (let w = 0; w < 8; w++) {
      ev.push({ tenKPace: training, date: day(w * 7 + 2), kind: "session" });
      ev.push({ tenKPace: training, date: day(w * 7 + 5), kind: "session" });
    }
    const r = blendEvidence(ev, NOW);
    assert(r.tenKPace !== null);
    // Eight weeks of consistent evidence should get most of the way there.
    const closed = (raced - r.tenKPace) / (raced - training);
    assert(
      closed > 0.8,
      `${p.name}: only closed ${(closed * 100).toFixed(0)}% of the gap in 8 weeks`,
    );
  }
});

// ── expected heart rate ────────────────────────────────────────────────────

Deno.test("expected-HR fits at every speed and climate, and scales its output", () => {
  const gains: Array<{ name: string; paceGain: number }> = [];
  for (const p of PROFILES) {
    const anchor = tenKPaceOf(p);
    const s: HrSample[] = [];
    const dews = [p.dew - 8, p.dew, p.dew + 6, p.dew - 3, p.dew + 3, p.dew - 6];
    dews.forEach((dew, i) => {
      for (const mult of [1.0, 1.08, 1.35]) {
        s.push({
          date: day(70 + i * 6),
          paceSecPerMile: anchor * mult,
          durationSeconds: Math.round(anchor * mult * p.repMiles),
          dewPointF: dew,
          hr: 60 + 0.3 * (1609.344 * 60 / (anchor * mult)) + 0.25 * dew + 2 * Math.log(200),
        });
      }
    });
    dews.slice(0, 5).forEach((dew, i) => {
      for (const mult of [1.0, 1.08, 1.35]) {
        s.push({
          date: day(3 + i * 5),
          paceSecPerMile: anchor * mult,
          durationSeconds: Math.round(anchor * mult * p.repMiles),
          dewPointF: dew,
          hr: 60 + 0.3 * (1609.344 * 60 / (anchor * mult)) + 0.25 * dew + 2 * Math.log(200) - 4,
        });
      }
    });
    const m = fitExpectedHr(s);
    assert(m !== null, `${p.name}: expected-HR must fit — a pace filter shaped like one runner drops these`);
    const t = efficiencyTrend(s, m, NOW);
    assert(t !== null, `${p.name}: trend must be computable`);
    assert(t.deltaBpm < -2, `${p.name}: a 4 bpm improvement must show up; got ${t.deltaBpm.toFixed(1)}`);
    gains.push({ name: p.name, paceGain: Math.abs(t.deltaPaceSecPerMile) });
  }
  // The same beats must buy a slower runner MORE seconds per mile. A fixed
  // reference pace would flatten this — that exact bug shipped and was caught.
  const elite = gains[0].paceGain;
  const beginner = gains[4].paceGain;
  assert(
    beginner > elite,
    `a 4 bpm gain gave the beginner ${beginner.toFixed(1)} s/mi and the elite ${elite.toFixed(1)} — ` +
      `the conversion is not scaling to the athlete`,
  );
});

// ── the guard against the bug class itself ─────────────────────────────────

Deno.test("no shared module hardcodes the calibration athlete's paces", async () => {
  const files = [
    "trainingZoneSignal.ts", "raceCurve.ts", "evidenceBlend.ts", "expectedHr.ts",
  ];
  // His 10K pace, 10K time, and the pace band his quality work sits in.
  const fingerprints = [/=\s*309\b/, /=\s*310\b/, /=\s*1920\b/, /=\s*31[0-9]\.\d/];
  for (const f of files) {
    const src = await Deno.readTextFile(new URL(`./${f}`, import.meta.url));
    const code = src.split("\n").filter((l) => !l.trim().startsWith("//") && !l.trim().startsWith("*")).join("\n");
    for (const fp of fingerprints) {
      assert(!fp.test(code), `${f} contains ${fp} — looks like a value read off one athlete`);
    }
  }
});
