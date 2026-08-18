/**
 * Tests for the expected-heart-rate model.
 *
 * The case that matters: on the calibration athlete, raw efficiency fell 3%
 * from April to August while dew point rose seven degrees. Uncontrolled, heart
 * rate says "getting worse." Controlled, it says "holding." A model that
 * cannot tell those apart is worse than no model.
 *
 * Run: deno test _shared/expectedHr.test.ts
 */
import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  efficiencyTrend,
  expectedHr,
  fitExpectedHr,
  hrResidual,
  MIN_SAMPLES,
  type HrSample,
} from "./expectedHr.ts";

const NOW = new Date("2026-08-17T00:00:00Z");
const MPM = 1609.344 * 60;
const day = (ago: number) => new Date(NOW.getTime() - ago * 86_400_000).toISOString().slice(0, 10);

/** Build a rep whose HR obeys a known law, so the fit can be checked. */
function synth(
  ago: number,
  paceSec: number,
  dew: number,
  durationSeconds: number,
  fitnessBpm = 0,
): HrSample {
  const speed = MPM / paceSec;
  const hr = 60 + 0.30 * speed + 0.25 * dew + 2.0 * Math.log(durationSeconds) + fitnessBpm;
  return { date: day(ago), paceSecPerMile: paceSec, hr, durationSeconds, dewPointF: dew };
}

/** A spread of reps across pace, heat and rep length. */
function corpus(fitnessAt: (ago: number) => number = () => 0): HrSample[] {
  const out: HrSample[] = [];
  let i = 0;
  for (const ago of [4, 10, 16, 22, 30, 38, 46, 54, 62, 70, 78, 86]) {
    for (const [pace, dew, dur] of [
      [300, 60, 200], [315, 70, 240], [330, 75, 300], [430, 65, 1800], [460, 72, 2400],
    ] as const) {
      out.push(synth(ago, pace + (i % 3), dew + (i % 4), dur, fitnessAt(ago)));
      i++;
    }
  }
  return out;
}

Deno.test("recovers the coefficients it was generated from", () => {
  const m = fitExpectedHr(corpus());
  assert(m !== null);
  assertAlmostEquals(m.coefficients[1], 0.30, 0.02, "bpm per m/min");
  assertAlmostEquals(m.coefficients[2], 0.25, 0.05, "bpm per °F dew");
  assertAlmostEquals(m.coefficients[3], 2.0, 0.3, "bpm per ln(second)");
  assert(m.residualSd < 1.0, `should fit tightly on clean data; got ±${m.residualSd}`);
});

Deno.test("heat is separated from fitness — the April-to-August trap", () => {
  // Fitness genuinely UNCHANGED. Only the weather moves: dew 66 in the
  // baseline window, 75 in the recent one. Raw HR rises; the model must not
  // call that a decline.
  const s: HrSample[] = [];
  for (const ago of [70, 76, 82, 88, 94, 100]) {
    for (const p of [305, 315, 325]) s.push(synth(ago, p, 66, 240));
  }
  for (const ago of [3, 8, 13, 18, 23]) {
    for (const p of [305, 315, 325]) s.push(synth(ago, p, 75, 240));
  }
  const m = fitExpectedHr(s)!;
  const t = efficiencyTrend(s, m, NOW)!;
  assert(
    Math.abs(t.deltaBpm) < 1.0,
    `flat fitness in rising heat must read flat; got ${t.deltaBpm.toFixed(2)} bpm`,
  );
});

Deno.test("a genuine improvement is detected through rising heat", () => {
  // Dew VARIES within both windows, as it does in reality — the calibration
  // athlete's May was cooler than April even as the summer trend rose. That
  // overlap is what makes heat and fitness separable at all.
  const s: HrSample[] = [];
  const baselineDews = [62, 70, 66, 75, 68, 72];
  const recentDews = [64, 74, 68, 76, 70];
  baselineDews.forEach((dew, i) => {
    for (const p of [305, 315, 325]) s.push(synth(70 + i * 6, p, dew, 240, 0));
  });
  recentDews.forEach((dew, i) => {
    for (const p of [305, 315, 325]) s.push(synth(3 + i * 5, p, dew, 240, -4));
  });
  const m = fitExpectedHr(s)!;
  const t = efficiencyTrend(s, m, NOW)!;
  assert(t.deltaBpm < -2, `expected a clear improvement; got ${t.deltaBpm.toFixed(2)}`);
  assert(t.deltaPaceSecPerMile < 0, "cheaper beats should convert to faster pace");
  assert(t.why.includes("cheaper"));
});

Deno.test("perfectly confounded heat and time report nothing, not something", () => {
  // Every baseline rep at one dew, every recent rep at another: heat and
  // fitness move together and are mathematically inseparable. The model must
  // absorb it and report no change rather than attribute it to either. This
  // is the safe failure, and it is why an athlete who only ever trains into a
  // worsening season gets no efficiency signal at all.
  const s: HrSample[] = [];
  for (const ago of [70, 76, 82, 88, 94, 100]) {
    for (const p of [305, 315, 325]) s.push(synth(ago, p, 66, 240, 0));
  }
  for (const ago of [3, 8, 13, 18, 23]) {
    for (const p of [305, 315, 325]) s.push(synth(ago, p, 75, 240, -4));
  }
  const m = fitExpectedHr(s)!;
  const t = efficiencyTrend(s, m, NOW)!;
  assert(
    Math.abs(t.deltaBpm) < 0.5,
    `unidentifiable data must yield no claim; got ${t.deltaBpm.toFixed(2)} bpm`,
  );
});

Deno.test("decline is detected too — it is not a one-way signal", () => {
  const s: HrSample[] = [];
  for (const ago of [70, 76, 82, 88, 94, 100]) {
    for (const p of [305, 315, 325]) s.push(synth(ago, p, 70, 240, 0));
  }
  for (const ago of [3, 8, 13, 18, 23]) {
    for (const p of [305, 315, 325]) s.push(synth(ago, p, 70, 240, +5));
  }
  const m = fitExpectedHr(s)!;
  const t = efficiencyTrend(s, m, NOW)!;
  assert(t.deltaBpm > 2, `expected a decline; got ${t.deltaBpm.toFixed(2)}`);
  assert(t.deltaPaceSecPerMile > 0);
  assert(t.why.includes("dearer"));
});

Deno.test("rep length is controlled — a long rep is not read as a bad one", () => {
  const m = fitExpectedHr(corpus())!;
  const short = { ...synth(5, 315, 70, 200), hr: expectedHr(synth(5, 315, 70, 200), m) };
  const long = { ...synth(5, 315, 70, 1200), hr: expectedHr(synth(5, 315, 70, 1200), m) };
  assertAlmostEquals(hrResidual(short, m), 0, 1e-6);
  assertAlmostEquals(hrResidual(long, m), 0, 1e-6);
  assert(
    expectedHr(long, m) > expectedHr(short, m),
    "the model should expect MORE beats deeper into a rep",
  );
});

Deno.test("no max HR, no race HR, no percentage-of-max anywhere", async () => {
  const src = await Deno.readTextFile(new URL("./expectedHr.ts", import.meta.url));
  const body = src.split("// ====")[2] ?? src; // skip the header commentary
  for (const banned of ["maxHr", "maxHR", "hrReserve", "percentOfMax"]) {
    assert(!body.includes(banned), `${banned} must not appear — it is unknowable here`);
  }
});

// ── refusals ───────────────────────────────────────────────────────────────

Deno.test("too little history yields no model rather than a shaky one", () => {
  const few = corpus().slice(0, MIN_SAMPLES - 1);
  assertEquals(fitExpectedHr(few), null);
});

Deno.test("junk rows are excluded from the fit", () => {
  const s = [...corpus(),
    { date: "2026-08-01", paceSecPerMile: 315, hr: 40, durationSeconds: 240, dewPointF: 70 },
    { date: "bad-date", paceSecPerMile: 315, hr: 165, durationSeconds: 240, dewPointF: 70 },
    { date: "2026-08-01", paceSecPerMile: 9999, hr: 165, durationSeconds: 240, dewPointF: 70 },
  ];
  const m = fitExpectedHr(s)!;
  assertEquals(m.samples, corpus().length);
});

Deno.test("a thin window yields no trend rather than a noisy one", () => {
  const m = fitExpectedHr(corpus())!;
  const onlyRecent = corpus().filter((s) => s.date >= day(20));
  assertEquals(efficiencyTrend(onlyRecent, m, NOW), null);
});

Deno.test("all one temperature still fits — dew just carries no information", () => {
  const flat = corpus().map((s) => ({ ...s, dewPointF: 70 }));
  const m = fitExpectedHr(flat);
  assert(m !== null, "a constant predictor must not break the solve");
});

// ── generality: this must not be shaped around one runner ──────────────────

Deno.test("works for a slow runner as readily as a fast one", () => {
  // Same law, paces a 10-minute-miler would actually run. An earlier draft
  // bounded pace at 240-700 s/mi and would have discarded all of this.
  const s: HrSample[] = [];
  let i = 0;
  for (const ago of [4, 12, 20, 30, 40, 50, 60, 70, 80, 90]) {
    for (const [pace, dew, dur] of [
      [540, 62, 300], [600, 70, 600], [660, 74, 900], [720, 66, 2400], [780, 58, 3000],
    ] as const) {
      s.push(synth(ago, pace + (i % 5), dew + (i % 3), dur, 0));
      i++;
    }
  }
  const m = fitExpectedHr(s);
  assert(m !== null, "a slower runner's reps must not be filtered out");
  assertEquals(m.samples, s.length);
});

Deno.test("the pace conversion scales to the athlete, not to a fixed reference", () => {
  // The same bpm improvement is worth more seconds per mile to a slower
  // runner, because seconds per mile are bigger there. A hardcoded reference
  // pace would give both the same answer.
  const build = (base: number) => {
    const s: HrSample[] = [];
    const baseDews = [62, 70, 66, 75, 68, 72];
    const recentDews = [64, 74, 68, 76, 70];
    baseDews.forEach((dew, i) => {
      for (const d of [0, 10, 20]) s.push(synth(70 + i * 6, base + d, dew, 240, 0));
    });
    recentDews.forEach((dew, i) => {
      for (const d of [0, 10, 20]) s.push(synth(3 + i * 5, base + d, dew, 240, -4));
    });
    return s;
  };
  const fast = build(300);
  const slow = build(600);
  const tf = efficiencyTrend(fast, fitExpectedHr(fast)!, NOW)!;
  const ts = efficiencyTrend(slow, fitExpectedHr(slow)!, NOW)!;
  assert(tf.deltaPaceSecPerMile < 0 && ts.deltaPaceSecPerMile < 0, "both improved");
  assert(
    Math.abs(ts.deltaPaceSecPerMile) > Math.abs(tf.deltaPaceSecPerMile),
    `the same beats should buy the slower runner more seconds: ` +
      `fast ${tf.deltaPaceSecPerMile.toFixed(1)} vs slow ${ts.deltaPaceSecPerMile.toFixed(1)}`,
  );
});

Deno.test("no constant in this file was read off one athlete's data", async () => {
  const src = await Deno.readTextFile(new URL("./expectedHr.ts", import.meta.url));
  // The calibration athlete's signature paces. None may appear as a literal.
  for (const n of ["310", "309", "5:09", "31:20", "1920"]) {
    const asLiteral = new RegExp(`=\\s*${n}\\b`);
    assert(!asLiteral.test(src), `${n} looks like a value copied from one runner`);
  }
});
