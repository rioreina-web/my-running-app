/**
 * Tests for the parser-driven training signal.
 *
 * The calibration case is the real one. On 2026-08-11 this athlete ran 10×1K
 * off 60s jog, averaging 5:18/mi in 78°F / 75°F dew. Riegel read that as a
 * 36:45 10K because it treats a 0.62-mile rep as a 0.62-mile time trial. The
 * athlete races ~31:50.
 *
 * Run: deno test _shared/trainingZoneSignal.test.ts
 */
import { assert, assertAlmostEquals, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  BEST_FRACTION,
  buildFitnessCurve,
  combineZoneEstimates,
  estimateFromSession,
  estimateFromSessions,
  formatMSS,
  MIN_WORK_SECONDS,
  parsePaceMSS,
  PLAUSIBLE_RATIO_MAX,
  predictedPaceForDuration,
  REST_DISCOUNT,
  type ParsedBlock,
  type ParsedSession,
  type ZoneEstimate,
} from "./trainingZoneSignal.ts";

const MI = 6.21371;
const paceOf = (raceSeconds: number) => raceSeconds / MI;
const raceOf = (pace: number) => Math.round(pace * MI);
const ANCHOR = paceOf(31 * 60 + 50); // the athlete's real 10K

const work = (durationS: number, distanceMiles: number, pace: string, hr?: number): ParsedBlock => ({
  role: "work_rep",
  durationS,
  distanceMiles,
  avgPacePerMile: pace,
  avgHr: hr ?? null,
});
const rest = (durationS: number): ParsedBlock => ({
  role: "recovery",
  durationS,
  distanceMiles: 0.05,
  avgPacePerMile: "—",
  avgHr: null,
});

/** 2026-08-11 exactly as `parsed_structure` stored it. */
function tenByOneK(): ParsedSession {
  const paces = ["5:19", "5:10", "5:15", "5:17", "5:21", "5:17", "5:21", "5:19", "5:30", "5:15"];
  const durs = [197, 194, 197, 197, 198, 199, 199, 199, 203, 194];
  const hrs = [157, 165, 161, 162, 165, 166, 165, 164, 166, 170];
  const rests = [67, 66, 66, 67, 64, 131, 66, 73, 55];
  const blocks: ParsedBlock[] = [];
  paces.forEach((p, i) => {
    blocks.push(work(durs[i], 0.62, p, hrs[i]));
    if (i < rests.length) blocks.push(rest(rests[i]));
  });
  return {
    date: "2026-08-11",
    type: "interval",
    confidence: 1,
    intentPattern: "10x1K @ 3:15-3:23 pace w/ 60s rest",
    tempF: 78.4,
    dewPointF: 75.3,
    blocks,
  };
}

// ── the bug this module exists to fix ──────────────────────────────────────

Deno.test("10×1K at 5:18 reads as a ~32:00 10K, not Riegel's 36:45", () => {
  const { estimate } = estimateFromSession(tenByOneK(), ANCHOR);
  assert(estimate, "the calibration session must produce an estimate");
  const race = raceOf(estimate.equivalentPace);
  assert(
    race > 1890 && race < 1980,
    `10×1K priced at ${formatMSS(race)}; want 31:30–33:00 (Riegel gave 36:45)`,
  );
});

Deno.test("rep DISTANCE does not change the answer — only work total and pace", () => {
  // Same 33 minutes of work at the same pace, cut as 1K reps vs mile reps.
  // Riegel's whole error was making these two disagree by 9%.
  const paceSec = 318; // 5:18/mi
  const mk = (repMiles: number, count: number): ParsedSession => {
    const dur = Math.round(paceSec * repMiles);
    const blocks: ParsedBlock[] = [];
    for (let i = 0; i < count; i++) {
      blocks.push(work(dur, repMiles, formatMSS(paceSec), 164));
      if (i < count - 1) blocks.push(rest(Math.round(dur * 0.33)));
    }
    return { date: "2026-08-11", type: "interval", confidence: 1, blocks, tempF: null, dewPointF: null };
  };
  const asKs = estimateFromSession(mk(0.62, 10), ANCHOR).estimate;
  const asMiles = estimateFromSession(mk(1.0, 6), ANCHOR).estimate;
  assert(asKs && asMiles);
  const gap = Math.abs(raceOf(asKs.equivalentPace) - raceOf(asMiles.equivalentPace));
  assert(gap < 25, `rep length moved the estimate by ${gap}s; the two sessions are the same work`);
});

// ── the model's core claims ────────────────────────────────────────────────

Deno.test("running exactly the predicted pace confirms the estimate, it does not move it", () => {
  // 6 × 1 mile at precisely what the curve says a 27-minute effective effort
  // is worth. Ratio should be ~1.0 and the 10K equivalent ~the anchor.
  const curve = buildFitnessCurve(ANCHOR);
  const restPerRep = 60;
  // Solve for the pace whose own work total prices at itself.
  let pace = ANCHOR;
  for (let i = 0; i < 30; i++) {
    const workSec = pace * 6;
    const effective = workSec / (1 + REST_DISCOUNT * ((restPerRep * 5) / workSec));
    pace = predictedPaceForDuration(curve, effective).pace;
  }
  const dur = Math.round(pace);
  const blocks: ParsedBlock[] = [];
  for (let i = 0; i < 6; i++) {
    blocks.push(work(dur, 1.0, formatMSS(pace), 165));
    if (i < 5) blocks.push(rest(restPerRep));
  }
  const { estimate } = estimateFromSession(
    { date: "2026-08-11", type: "interval", confidence: 1, blocks, tempF: null, dewPointF: null },
    ANCHOR,
  );
  assert(estimate);
  assertAlmostEquals(estimate.ratio, 1.0, 0.01);
  assertAlmostEquals(raceOf(estimate.equivalentPace), raceOf(ANCHOR), 20);
});

Deno.test("more rest at the same pace is worth less", () => {
  const mk = (restS: number): ParsedSession => {
    const blocks: ParsedBlock[] = [];
    for (let i = 0; i < 8; i++) {
      blocks.push(work(300, 1.0, "5:00", 165));
      if (i < 7) blocks.push(rest(restS));
    }
    return { date: "2026-08-11", type: "interval", confidence: 1, blocks, tempF: null, dewPointF: null };
  };
  const tight = estimateFromSession(mk(45), ANCHOR).estimate;
  const loose = estimateFromSession(mk(300), ANCHOR).estimate;
  assert(tight && loose);
  assert(
    tight.equivalentPace < loose.equivalentPace,
    "the same pace off long recovery must grade out slower than off short recovery",
  );
});

Deno.test("heat credits the effort — the same paces in hot air imply more fitness", () => {
  const hot = tenByOneK();
  const cool: ParsedSession = { ...hot, tempF: 52, dewPointF: 40 };
  const a = estimateFromSession(hot, ANCHOR).estimate;
  const b = estimateFromSession(cool, ANCHOR).estimate;
  assert(a && b);
  assert(a.equivalentPace < b.equivalentPace, "the hot session should imply the faster 10K");
  assert(a.heatNormalized);
  assert(!b.heatNormalized, "40°F dew is below the chart — nothing to credit");
  assert(b.caveats.some((c) => c.includes("not heat-normalized")));
});

Deno.test("a session with no weather says so rather than pretending neutral", () => {
  const s = { ...tenByOneK(), tempF: null, dewPointF: null };
  const { estimate } = estimateFromSession(s, ANCHOR);
  assert(estimate);
  assert(!estimate.heatNormalized);
  assert(estimate.caveats.some((c) => c.includes("no weather on this row")));
});

// ── what is deliberately excluded ──────────────────────────────────────────

Deno.test("a declared race is not training — it goes down the anchor path", () => {
  const { estimate, reason } = estimateFromSession({ ...tenByOneK(), declaredRace: true }, ANCHOR);
  assertEquals(estimate, null);
  assert(reason.includes("declared race"));
});

Deno.test("easy and long runs carry no fitness statement whatever their paces", () => {
  for (const type of ["easy", "recovery", "long_run"]) {
    const { estimate } = estimateFromSession({ ...tenByOneK(), type }, ANCHOR);
    assertEquals(estimate, null, `type "${type}" must not produce an estimate`);
  }
});

Deno.test("aerobic work typed as interval is dropped, and named honestly", () => {
  // The real 2026-08-07 row: 5 mi at 7:51 then 2 mi at 7:24, parsed "progression".
  const s: ParsedSession = {
    date: "2026-08-07",
    type: "progression",
    confidence: 0.7,
    tempF: 79.3,
    dewPointF: 75.7,
    blocks: [work(2356, 5.0, "7:51", 141), rest(33), work(880, 1.98, "7:24", 147)],
  };
  const { estimate, reason } = estimateFromSession(s, ANCHOR);
  assertEquals(estimate, null);
  assert(reason.includes("aerobic work"), `got: ${reason}`);
  assert(!reason.includes("mis-parsed"), "slow is not the same claim as implausible");
});

Deno.test("an impossibly fast parse is rejected as bad data, not banked as fitness", () => {
  const blocks: ParsedBlock[] = [];
  for (let i = 0; i < 8; i++) {
    // 4:00/mi for a mile-plus, eight times — inside the raw rep-pace bounds, so
    // this has to be caught by the curve rather than by the sanity filter.
    blocks.push(work(288, 1.2, "4:00", 150));
    if (i < 7) blocks.push(rest(60));
  }
  const { estimate, reason } = estimateFromSession(
    { date: "2026-08-11", type: "interval", confidence: 1, blocks, tempF: null, dewPointF: null },
    ANCHOR,
  );
  assertEquals(estimate, null);
  assert(reason.includes("mis-parsed") || reason.includes("bad GPS"), `got: ${reason}`);
});

Deno.test("too little work says nothing", () => {
  const s: ParsedSession = {
    date: "2026-08-11",
    type: "interval",
    confidence: 1,
    tempF: null,
    dewPointF: null,
    blocks: [work(150, 0.5, "5:00", 165), rest(60), work(150, 0.5, "5:00", 165)],
  };
  const { estimate, reason } = estimateFromSession(s, ANCHOR);
  assertEquals(estimate, null);
  assert(reason.includes(String(MIN_WORK_SECONDS / 60)));
});

Deno.test("strides are not reps — the real 2026-07-24 200s session is skipped", () => {
  const blocks: ParsedBlock[] = [];
  for (let i = 0; i < 8; i++) {
    blocks.push(work(32, 0.12, "4:18", 145));
    if (i < 7) blocks.push(rest(60));
  }
  const { estimate } = estimateFromSession(
    { date: "2026-07-24", type: "interval", confidence: 0.9, blocks, tempF: 77.1, dewPointF: 75 },
    ANCHOR,
  );
  assertEquals(estimate, null, "32-second reps cannot price a 10K");
});

// ── the curve ──────────────────────────────────────────────────────────────

Deno.test("the curve is monotonic — longer efforts are never faster", () => {
  const curve = buildFitnessCurve(ANCHOR);
  for (let i = 1; i < curve.length; i++) {
    assert(curve[i].seconds > curve[i - 1].seconds, `durations out of order at ${curve[i].label}`);
    assert(
      curve[i].paceSecPerMile >= curve[i - 1].paceSecPerMile,
      `${curve[i].label} is faster than ${curve[i - 1].label}`,
    );
  }
});

Deno.test("the curve holds its endpoints rather than extrapolating", () => {
  const curve = buildFitnessCurve(ANCHOR);
  const first = curve[0];
  const last = curve[curve.length - 1];
  assertEquals(predictedPaceForDuration(curve, 10).pace, first.paceSecPerMile);
  assertEquals(predictedPaceForDuration(curve, 86_400).pace, last.paceSecPerMile);
});

Deno.test("the curve passes through its own anchor at 10K duration", () => {
  const curve = buildFitnessCurve(ANCHOR);
  const tenKSeconds = ANCHOR * MI;
  assertAlmostEquals(predictedPaceForDuration(curve, tenKSeconds).pace, ANCHOR, 0.5);
});

Deno.test("the anchor cancels: the same session prices the same from any starting belief", () => {
  // The algebra in the module header says the anchor drops out of the value and
  // survives only in where the duration lands on the curve. Measured across the
  // whole span the plausibility gate admits, the verdict moves ~15s.
  const s = tenByOneK();
  const from30 = estimateFromSession(s, paceOf(30 * 60)).estimate;
  const from35 = estimateFromSession(s, paceOf(35 * 60)).estimate;
  assert(from30 && from35, "both beliefs should admit this session");
  const gap = Math.abs(raceOf(from30.equivalentPace) - raceOf(from35.equivalentPace));
  assert(gap < 30, `a 5-minute swing in the anchor moved the session's verdict by ${gap}s`);
});

Deno.test("a belief far enough off makes real work look implausible — either way", () => {
  // The VALUE is anchor-free; the COVERAGE gate is not, and that asymmetry is
  // deliberate. Believe this athlete is a 38:30 runner and a 10×1K at 5:09
  // neutral is not a credible workout; believe they are a 28:30 runner and the
  // same session looks like they jogged it. Both are refusals to read a session
  // through a belief that cannot support it.
  const tooSlow = estimateFromSession(tenByOneK(), paceOf(38 * 60 + 30));
  assertEquals(tooSlow.estimate, null);
  assert(tooSlow.reason.includes("faster than the curve allows"), `got: ${tooSlow.reason}`);

  const tooFast = estimateFromSession(tenByOneK(), paceOf(28 * 60 + 30));
  assertEquals(tooFast.estimate, null);
  assert(tooFast.reason.includes("aerobic work"), `got: ${tooFast.reason}`);
});

// ── combining ──────────────────────────────────────────────────────────────

const est = (date: string, tenK: number, effectiveSeconds = 1700): ZoneEstimate => ({
  date,
  neutralWorkPace: paceOf(tenK),
  predictedPaceForDuration: paceOf(tenK),
  ratio: 1,
  equivalentPace: paceOf(tenK),
  distanceKey: "tenK",
  zoneLabel: "10K",
  workSeconds: effectiveSeconds,
  workMiles: 6,
  restSeconds: 600,
  restRatio: 0.33,
  effectiveSeconds,
  repCount: 10,
  meanHr: 164,
  hrDrift: 4,
  heatNormalized: true,
  confidence: 1,
  reps: [{ paceSeconds: paceOf(tenK), distanceMiles: 6, seconds: effectiveSeconds, hr: 164 }],
  why: "",
  caveats: [],
});

Deno.test("a submaximal aerobic session cannot drag the estimate down", () => {
  const now = new Date("2026-08-17T00:00:00Z");
  const sharp = [est("2026-08-11", 1920), est("2026-08-08", 1925), est("2026-08-05", 1930)];
  const withDrag = [...sharp, est("2026-08-01", 2138, 4100)]; // the real 12-mile 35:38 read
  const a = combineZoneEstimates(sharp, now)!;
  const b = combineZoneEstimates(withDrag, now)!;
  assert(
    Math.abs(raceOf(a.equivalentPace) - raceOf(b.equivalentPace)) < 10,
    `one long submaximal session moved the estimate ${Math.abs(raceOf(a.equivalentPace) - raceOf(b.equivalentPace))}s`,
  );
  assertEquals(b.consideredCount, 4);
  assert(b.sessionCount < 4, "the drag session must not be selected");
});

Deno.test("the estimate follows form DOWN — best-of is not a ratchet", () => {
  const now = new Date("2026-08-17T00:00:00Z");
  const good = combineZoneEstimates(
    [est("2026-08-15", 1900), est("2026-08-12", 1910), est("2026-08-09", 1920)],
    now,
  )!;
  // Same window, later, every session genuinely slower.
  const faded = combineZoneEstimates(
    [est("2026-08-15", 2000), est("2026-08-12", 2010), est("2026-08-09", 2020)],
    now,
  )!;
  assert(
    raceOf(faded.equivalentPace) > raceOf(good.equivalentPace) + 60,
    "a window of slower sessions must produce a slower estimate",
  );
});

Deno.test("recency outweighs an equally-good older session", () => {
  const now = new Date("2026-08-17T00:00:00Z");
  const c = combineZoneEstimates([est("2026-08-16", 1900), est("2026-06-16", 1900)], now)!;
  assertAlmostEquals(raceOf(c.equivalentPace), 1900, 2);
  assertEquals(c.sessionCount, 2);
});

Deno.test("at least two sessions are kept even from a tiny pool", () => {
  const now = new Date("2026-08-17T00:00:00Z");
  const c = combineZoneEstimates([est("2026-08-16", 1900), est("2026-08-14", 2000)], now)!;
  assertEquals(c.sessionCount, 2);
  assert(BEST_FRACTION < 1);
});

Deno.test("no sessions yields no signal rather than a default", () => {
  assertEquals(combineZoneEstimates([], new Date("2026-08-17T00:00:00Z")), null);
});

Deno.test("estimateFromSessions keeps rejections for the coverage note", () => {
  const easy: ParsedSession = { ...tenByOneK(), date: "2026-08-10", type: "easy" };
  const { estimates, rejected } = estimateFromSessions([tenByOneK(), easy], ANCHOR);
  assertEquals(estimates.length, 1);
  assertEquals(rejected.length, 1);
  assertEquals(rejected[0].date, "2026-08-10");
});

// ── small helpers ──────────────────────────────────────────────────────────

Deno.test("parsePaceMSS handles the parser's real vocabulary", () => {
  assertEquals(parsePaceMSS("5:19"), 319);
  assertEquals(parsePaceMSS("05:43"), 343);
  assertEquals(parsePaceMSS("—"), null, "the parser writes an em-dash for a standing block");
  assertEquals(parsePaceMSS("0:00"), null);
  assertEquals(parsePaceMSS(null), null);
  assertEquals(parsePaceMSS("garbage"), null);
});

Deno.test("formatMSS rounds the total, never the remainder", () => {
  assertEquals(formatMSS(299.9), "5:00", "rounding the remainder alone yields the 4:60 bug");
  assertEquals(formatMSS(319), "5:19");
  assertEquals(formatMSS(60), "1:00");
});

Deno.test("PLAUSIBLE_RATIO_MAX leaves room for a hot, honest quality session", () => {
  // 2026-08-04 really did come in 7.6% slow in 76°F / 76°F dew and is real work.
  assert(PLAUSIBLE_RATIO_MAX > 1.08);
});

// ── distance-native seed (2026-08-27) ────────────────────────────────────────

Deno.test("a marathon-seeded curve is not a mile-seeded curve mislabeled", () => {
  // Same athlete, same underlying fitness — but buildFitnessCurve must build
  // a DIFFERENT shape depending on which distance actually anchors it, or the
  // seed parameter does nothing.
  const marathonPace = 550; // sec/mi, roughly a 4:00 marathon pace
  const fromMarathon = buildFitnessCurve(marathonPace, "marathon");
  const asIfTenK = buildFitnessCurve(marathonPace, "tenK");
  const mpFromMarathon = fromMarathon.find((p) => p.label === "MP")!.paceSecPerMile;
  const mpAsIfTenK = asIfTenK.find((p) => p.label === "MP")!.paceSecPerMile;
  // Seeded correctly at marathon, MP should equal the seed almost exactly.
  // Mislabeled as a 10K, the generic table stretches it out over marathon
  // distance from what it thinks is a 10K, landing far off the seed.
  assertAlmostEquals(mpFromMarathon, marathonPace, 2);
  assert(Math.abs(mpAsIfTenK - marathonPace) > 40, "mislabeling the seed must not be free");
});

Deno.test("curveTilt=0 is bit-identical to the untilted table, at any seed distance", () => {
  const a = buildFitnessCurve(600, "half", 0);
  const b = buildFitnessCurve(600, "half");
  assertEquals(a, b);
});

Deno.test("a nonzero tilt changes the shape without moving the seed's own point", () => {
  const flat = buildFitnessCurve(600, "half", -0.01); // more durable than generic
  const generic = buildFitnessCurve(600, "half", 0);
  const hmFlat = flat.find((p) => p.label === "HM")!.paceSecPerMile;
  const hmGeneric = generic.find((p) => p.label === "HM")!.paceSecPerMile;
  const mpFlat = flat.find((p) => p.label === "MP")!.paceSecPerMile;
  const mpGeneric = generic.find((p) => p.label === "MP")!.paceSecPerMile;
  assertAlmostEquals(hmFlat, hmGeneric, 1); // the seed's own distance is untouched
  assert(mpFlat < mpGeneric, "a flatter-than-generic athlete should get a faster marathon");
});

Deno.test("estimateFromSession prices a marathon-anchored session in marathon-native terms", () => {
  const marathonPace = 400; // roughly a 2:55 marathon
  // A 1-hour threshold effort at 6:30/mi — priced against a curve seeded at
  // marathonPace this lands inside the plausible window under EITHER
  // interpretation (a marathon-native curve at ~376 s/mi predicted for this
  // duration, a 10K-mislabeled curve at ~410), so the test isolates the
  // question this file exists to ask: does the seed's distance change the
  // answer, not whether the session clears the plausibility gate.
  const session: ParsedSession = {
    date: "2026-06-01",
    type: "steady",
    confidence: 0.9,
    intentPattern: null,
    tempF: null,
    dewPointF: null,
    declaredRace: false,
    blocks: [
      { role: "work_rep", durationS: 3600, distanceMiles: 9.23, avgPacePerMile: "6:30", avgHr: null, elevationGainM: null },
    ],
  };
  const seededRight = estimateFromSession(session, marathonPace, "marathon");
  const seededWrong = estimateFromSession(session, marathonPace, "tenK");
  assert(seededRight.estimate !== null, seededRight.reason);
  assert(seededWrong.estimate !== null, seededWrong.reason);
  assertEquals(seededRight.estimate!.distanceKey, "marathon");
  // Same rep, same current pace number — but mislabeling what distance that
  // number is AT changes what the curve thinks the rep was worth.
  assert(seededRight.estimate!.ratio !== seededWrong.estimate!.ratio);
});
