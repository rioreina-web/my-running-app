import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  generateFitnessPrediction,
  enduranceFactor,
  longRunReadiness,
  dedupeRaces,
  thresholdCapacity,
  THRESHOLD_TO_10K,
  MARA_READY_LONGRUN_MILES,
  MARA_READY_LONGRUN_COUNT,
  MARA_MAX_ENDURANCE_PENALTY,
  detectRaces,
  detectTrainingAnchors,
  detectDetraining,
  deriveLapEfforts,
  raceEffectivePace,
  paceStringToSeconds,
  type LapInput,
  type PredictionInput,
  type VoiceLogInput,
  type WorkoutInput,
} from "./fitnessPrediction.ts";

// Fixed "now" so date math is deterministic.
const NOW = new Date("2026-07-02T12:00:00Z");

function daysAgo(n: number): string {
  const d = new Date(NOW.getTime() - n * 86_400_000);
  return d.toISOString().slice(0, 10);
}

function log(date: string, notes: string, extra: Partial<VoiceLogInput> = {}): VoiceLogInput {
  return { date, notes, pacesMentioned: [], paceSegments: null, parsedStructure: null, ...extra };
}

function run(date: string, miles: number, paceSec: number, dur?: number): WorkoutInput {
  return {
    date,
    distanceMiles: miles,
    durationMinutes: dur ?? (miles * paceSec) / 60,
    paceSecondsPerMile: paceSec,
    type: "run",
  };
}

// ── helpers ──────────────────────────────────────────────────────────────

Deno.test("paceStringToSeconds parses and rejects", () => {
  assertEquals(paceStringToSeconds("7:30"), 450);
  assertEquals(paceStringToSeconds("garbage"), 0);
});

// ── no signal ──────────────────────────────────────────────────────────────

Deno.test("no data → null (never fabricates a snapshot)", () => {
  const input: PredictionInput = { workouts: [], voiceLogs: [], now: NOW };
  assertEquals(generateFitnessPrediction(input), null);
});

// ── race anchor (High) ──────────────────────────────────────────────────────

Deno.test("recent 10K race → High confidence, race-anchored", () => {
  const voiceLogs = [log(daysAgo(20), "Race today! Raced the 10k, finish time 40:00.")];
  const input: PredictionInput = {
    workouts: [],
    voiceLogs,
    extendedVoiceLogs: voiceLogs,
    now: NOW,
  };
  const r = generateFitnessPrediction(input);
  assert(r !== null, "expected a prediction");
  assertEquals(r!.confidence, "High");
  assertEquals(r!.confidenceTier, "high");
  // 40:00 10K = 2400s → predicted10k should be within a few seconds after
  // decay over ~3 weeks with no offsetting training.
  assert(r!.predicted10kSeconds >= 2400 && r!.predicted10kSeconds <= 2460, `got ${r!.predicted10kSeconds}`);
  // Range is now DISTANCE-AWARE (Part 1 fix #12) and ROUNDED (fix #10):
  // high tier base (1.0%) + |log2(dist/anchorDist)|·0.008 + age widening.
  // Anchor is a 10K (6.214 mi), item is 10K (6.2137119 mi), ~20.5 days old.
  const weeks = 20.5 / 7; // daysAgo(20) parses to UTC midnight; NOW is 12:00Z
  const frac = 0.010 + Math.abs(Math.log2(6.2137119 / 6.214)) * 0.008 + Math.min(weeks * 0.0004, 0.01);
  assertEquals(r!.range10kSeconds, Math.round(r!.predicted10kSeconds * frac));
  // Marathon > half > 10k > 5k > mile in seconds.
  assert(r!.predictedMarathonSeconds > r!.predictedHalfSeconds);
  assert(r!.predictedHalfSeconds > r!.predicted10kSeconds);
  assert(r!.predicted10kSeconds > r!.predicted5kSeconds);
  assert(r!.predicted5kSeconds > r!.predictedMileSeconds);
});

Deno.test("detectRaces parses explicit result from notes", () => {
  const races = detectRaces([], [log(daysAgo(10), "Raced the 5k today, finish time 20:00.")]);
  assertEquals(races.length, 1);
  assertEquals(races[0].raceType, "fiveK");
  assertEquals(races[0].totalTimeSeconds, 1200);
});

Deno.test("detectRaces ignores forward-looking race mentions", () => {
  const races = detectRaces([], [log(daysAgo(3), "Easy run leading up to the race next month, felt good.")]);
  assertEquals(races.length, 0);
});

Deno.test("detectRaces ignores workout-context 'race pace' logs", () => {
  const races = detectRaces([], [log(daysAgo(3), "Workout today: 6 x 800 at race pace, finish time felt hard.")]);
  assertEquals(races.length, 0);
});

Deno.test("seededRaces (confirmed_races) anchors when there are no notes", () => {
  const r = generateFitnessPrediction({
    workouts: [],
    voiceLogs: [],
    seededRaces: [{ raceType: "tenK", paceSecondsPerMile: 2400 / 6.21371, date: daysAgo(18), totalTimeSeconds: 2400 }],
    now: NOW,
  });
  assert(r !== null);
  assertEquals(r!.confidence, "High");
  assert(r!.predicted10kSeconds >= 2400 && r!.predicted10kSeconds <= 2460, `got ${r!.predicted10kSeconds}`);
});

// ── training anchor (Medium) ────────────────────────────────────────────────

Deno.test("recent parsed interval session → training anchor, Medium", () => {
  const voiceLogs = [
    log(daysAgo(5), "Track: 8x800.", {
      parsedStructure: {
        confidence: 0.8,
        type: "interval",
        equivalentRacePace: { pacePerMile: "6:00", distanceKey: "5k" },
        workSummary: { totalDistanceMi: 4 },
      },
    }),
  ];
  const anchors = detectTrainingAnchors(voiceLogs);
  assertEquals(anchors.length, 1);
  assertEquals(anchors[0].kind, "intervalSession");

  const r = generateFitnessPrediction({ workouts: [], voiceLogs, extendedVoiceLogs: voiceLogs, now: NOW });
  assert(r !== null);
  assertEquals(r!.confidenceTier, "medium");
  assert(r!.dataSource.startsWith("training"), r!.dataSource);
});

Deno.test("low-confidence parse is not used as an anchor", () => {
  const voiceLogs = [
    log(daysAgo(5), "maybe intervals?", {
      parsedStructure: {
        confidence: 0.4, // below 0.6 threshold
        type: "interval",
        equivalentRacePace: { pacePerMile: "6:00", distanceKey: "5k" },
        workSummary: { totalDistanceMi: 4 },
      },
    }),
  ];
  assertEquals(detectTrainingAnchors(voiceLogs).length, 0);
});

Deno.test("rested interval reps grade slower than raw rep pace", () => {
  // 4 × 0.5mi reps at 4:50 with full standing recoveries between them.
  const segments = [
    { effort: "fast", pacePerMile: "4:50", distanceMiles: 0.5, durationSeconds: 145 },
    { effort: "easy", pacePerMile: "22:00", distanceMiles: 0.05, durationSeconds: 66 },
    { effort: "fast", pacePerMile: "4:50", distanceMiles: 0.5, durationSeconds: 145 },
    { effort: "easy", pacePerMile: "22:00", distanceMiles: 0.05, durationSeconds: 66 },
    { effort: "fast", pacePerMile: "4:50", distanceMiles: 0.5, durationSeconds: 145 },
    { effort: "easy", pacePerMile: "22:00", distanceMiles: 0.05, durationSeconds: 66 },
    { effort: "fast", pacePerMile: "4:50", distanceMiles: 0.5, durationSeconds: 145 },
  ];
  const parsed = {
    confidence: 0.8,
    type: "interval",
    equivalentRacePace: { pacePerMile: "4:50", distanceKey: "fiveK" },
    workSummary: { totalDistanceMi: 2 },
  };
  const withSeg = detectTrainingAnchors([log(daysAgo(5), "intervals", { parsedStructure: parsed, paceSegments: segments })]);
  const noSeg = detectTrainingAnchors([log(daysAgo(5), "intervals", { parsedStructure: parsed })]);
  assertEquals(withSeg.length, 1);
  assertEquals(noSeg.length, 1);
  // Recovery-rested reps must produce a SLOWER (larger) 10K-equivalent pace.
  assert(
    withSeg[0].equivalentTenKPace > noSeg[0].equivalentTenKPace + 5,
    `expected penalty to slow the anchor: ${withSeg[0].equivalentTenKPace} vs ${noSeg[0].equivalentTenKPace}`,
  );
});

// ── anchor-displacement rule ────────────────────────────────────────────────

Deno.test("stale race is NOT displaced by a slower recent training anchor", () => {
  // Strong 10K race 20 weeks ago (past the 16wk primary window) + a modest
  // recent tempo parsed as a slow 10K-equivalent. Race must remain the anchor.
  const voiceLogs = [
    log(daysAgo(140), "Raced the 10k, finish time 33:00."),
    log(daysAgo(5), "Evening tempo.", {
      parsedStructure: {
        confidence: 0.7,
        type: "interval",
        equivalentRacePace: { pacePerMile: "7:30", distanceKey: "tenK" }, // slower than race
        workSummary: { totalDistanceMi: 4 },
      },
    }),
  ];
  const r = generateFitnessPrediction({ workouts: [], voiceLogs, extendedVoiceLogs: voiceLogs, now: NOW });
  assert(r !== null);
  // AGE-AWARE TIER (Part 1 fix #11): the race stays the anchor, but at 20
  // weeks old it is past the 16-week primary window — Medium, wider ranges
  // (was High before the 2026-07-16 evidence-first pass).
  assertEquals(r!.confidence, "Medium");
  assertEquals(r!.confidenceTier, "medium");
  assert(r!.dataSource.startsWith("race"), r!.dataSource);
  assert(r!.predicted10kSeconds < 2200, `expected ~race pace, got ${r!.predicted10kSeconds}`);
});

Deno.test("stale race IS displaced by a genuinely faster recent training anchor", () => {
  const voiceLogs = [
    log(daysAgo(140), "Raced the 10k, finish time 33:00."),
    log(daysAgo(5), "Evening intervals.", {
      parsedStructure: {
        confidence: 0.8,
        type: "interval",
        equivalentRacePace: { pacePerMile: "4:55", distanceKey: "tenK" }, // faster than race
        workSummary: { totalDistanceMi: 5 },
      },
    }),
  ];
  const r = generateFitnessPrediction({ workouts: [], voiceLogs, extendedVoiceLogs: voiceLogs, now: NOW });
  assert(r !== null);
  assertEquals(r!.confidenceTier, "medium");
  assert(r!.dataSource.startsWith("training"), r!.dataSource);
});

// ── plan goal fallback (Medium) ─────────────────────────────────────────────

Deno.test("training-plan goal anchors when no race/training signal", () => {
  const r = generateFitnessPrediction({
    workouts: [],
    voiceLogs: [],
    plan: { status: "active", raceDistanceKey: "marathon", targetTimeSeconds: 3 * 3600 + 30 * 60, raceDistanceMiles: 26.219 },
    now: NOW,
  });
  assert(r !== null);
  assertEquals(r!.confidenceTier, "medium");
  assert(r!.dataSource.includes("training plan"), r!.dataSource);
});

// ── fastest-workout last resort (Low) ───────────────────────────────────────

Deno.test("only easy workouts, no anchor → Low, fastest-workout source", () => {
  const workouts = [run(daysAgo(2), 5, 540), run(daysAgo(4), 6, 560), run(daysAgo(6), 4, 520)];
  const r = generateFitnessPrediction({ workouts, voiceLogs: [], now: NOW });
  assert(r !== null);
  assertEquals(r!.confidenceTier, "low");
  // " · v2" marks the multi-signal server model (Part 2 data_source suffix).
  assertEquals(r!.dataSource, "fastest workout · v2");
  assertEquals(r!.workoutCount, 3);
});

// ── detraining decay ────────────────────────────────────────────────────────

Deno.test("detectDetraining fires on a layoff + low volume", () => {
  const workouts = [run(daysAgo(25), 3, 540)]; // single old short run in 4wk window
  const sig = detectDetraining(workouts, [], NOW);
  assert(sig !== null);
  assert(sig!.layoff);
  assert(sig!.severity >= 0.4);
});

Deno.test("detectDetraining returns null when training continues", () => {
  const workouts = [
    run(daysAgo(1), 8, 480),
    run(daysAgo(3), 10, 470),
    run(daysAgo(5), 6, 500),
    run(daysAgo(7), 12, 460),
    run(daysAgo(9), 8, 490),
    run(daysAgo(11), 10, 470),
  ];
  const voiceLogs = [
    log(daysAgo(4), "tempo", {
      parsedStructure: { confidence: 0.8, type: "tempo", equivalentRacePace: { pacePerMile: "6:00", distanceKey: "10k" }, workSummary: { totalDistanceMi: 4 } },
    }),
  ];
  assertEquals(detectDetraining(workouts, voiceLogs, NOW), null);
});

// ── range/tier monotonicity ─────────────────────────────────────────────────

Deno.test("range fraction grows as confidence drops", () => {
  // High (race)
  const high = generateFitnessPrediction({
    workouts: [],
    voiceLogs: [log(daysAgo(15), "Raced the 10k, finish time 40:00.")],
    now: NOW,
  })!;
  // Low (fastest workout)
  const low = generateFitnessPrediction({
    workouts: [run(daysAgo(2), 5, 540)],
    voiceLogs: [],
    now: NOW,
  })!;
  const highFrac = high.range10kSeconds / high.predicted10kSeconds;
  const lowFrac = low.range10kSeconds / low.predicted10kSeconds;
  assert(lowFrac > highFrac, `low ${lowFrac} should exceed high ${highFrac}`);
});

// ═══════════════════════════════════════════════════════════════════════════
// 2026-07-16 evidence-first + multi-signal (v2) tests
// ═══════════════════════════════════════════════════════════════════════════

// Race pace-equivalent 10K anchor for a 40:00 10K (RACE_TYPE_MILES.tenK).
const ANCHOR_40_TENK_PACE = 2400 / 6.214;

/** A log carrying only hard-STIMULUS segments (tiny distance so they can never
 *  enter the hard-effort pool or quality density; pace outside 210–540). */
function stimulusLog(date: string, durationSeconds: number): VoiceLogInput {
  return log(date, "hard session", {
    paceSegments: [{ effort: "interval", durationSeconds, distanceMiles: 0.05, pacePerMile: "9:30" }],
  });
}

// ── New test 1 (Part 1 fix #1): empty prior window → no build credit ────────

Deno.test("empty prior window grants no build credit (trend default 1.0, not 2.0)", () => {
  // 10-week-old race; ALL training data in the recent 2 weeks (prior window
  // empty). Old model defaulted volume/stimulus trends to 2.0, trivially
  // passing the build gate and granting improvement credit off missing data.
  const raceLog = log(daysAgo(70), "Raced the 10k, finish time 40:00.");
  const workouts = [1, 3, 5, 7, 9, 11].map((d) => run(daysAgo(d), 10, 500)); // 60 mi, all recent
  const voiceLogs = [raceLog, stimulusLog(daysAgo(2), 9500), stimulusLog(daysAgo(6), 9500)];
  const r = generateFitnessPrediction({ workouts, voiceLogs, extendedVoiceLogs: voiceLogs, now: NOW });
  assert(r !== null);
  assert(r!.dataSource.startsWith("race"), r!.dataSource);
  assert(!r!.dataSource.includes("(improving)"), `no improvement off missing data: ${r!.dataSource}`);
  // No build credit → the decayed estimate is never faster than the anchor.
  assert(
    r!.estimated10kPaceSeconds >= ANCHOR_40_TENK_PACE - 1e-9,
    `expected >= anchor ${ANCHOR_40_TENK_PACE}, got ${r!.estimated10kPaceSeconds}`,
  );
});

// ── New test 2 (Part 1 fix #3): unproven improvement capped at 0.5% ─────────

Deno.test("unproven improvement is capped at 0.5% total (13-week-old anchor)", () => {
  // 13-week-old race + genuinely building training (both windows populated,
  // trends up, 30+ min/wk stimulus) but NO measured hard paces. The old model
  // compounded −0.2%/wk since the anchor (−2.6% here); the cap allows 0.5%.
  const raceLog = log(daysAgo(91), "Raced the 10k, finish time 40:00.");
  const recent = [1, 2, 3, 4, 5, 6, 7, 9, 11, 13].map((d) => run(daysAgo(d), 10.7, 500)); // 107 mi
  const prior = [15, 17, 19, 21, 23, 25].map((d) => run(daysAgo(d), 8.9, 500)); // 53.4 mi
  const voiceLogs = [
    raceLog,
    stimulusLog(daysAgo(2), 6600),
    stimulusLog(daysAgo(6), 6600),
    stimulusLog(daysAgo(16), 5400),
    stimulusLog(daysAgo(20), 5400),
  ];
  const r = generateFitnessPrediction({
    workouts: [...recent, ...prior],
    voiceLogs,
    extendedVoiceLogs: voiceLogs,
    now: NOW,
  });
  assert(r !== null);
  assert(r!.dataSource.includes("(improving)"), r!.dataSource); // build credit IS granted...
  // ...but the total improvement from trends alone is capped at 0.5%.
  assert(
    Math.abs(r!.estimated10kPaceSeconds - ANCHOR_40_TENK_PACE * 0.995) < 0.01,
    `expected anchor×0.995 = ${ANCHOR_40_TENK_PACE * 0.995}, got ${r!.estimated10kPaceSeconds}`,
  );
});

// ── New test 3 (Part 1 fix #5): segment signal speed-up capped at 2% ────────

Deno.test("segment signal cannot speed the estimate up more than 2%", () => {
  const raceLog = log(daysAgo(21), "Raced the 10k, finish time 40:00.");
  const fastSegments = Array.from({ length: 6 }, () => ({
    effort: "interval",
    durationSeconds: 300,
    distanceMiles: 1.0,
    pacePerMile: "5:00",
  }));
  // Control: identical durations (same stimulus/decay) but distances too small
  // to enter the hard-effort pool → pure decayed anchor.
  const tinySegments = fastSegments.map((s) => ({ ...s, distanceMiles: 0.05 }));

  const withSignal = generateFitnessPrediction({
    workouts: [],
    voiceLogs: [raceLog, log(daysAgo(3), "track", { paceSegments: fastSegments })],
    now: NOW,
  })!;
  const noSignal = generateFitnessPrediction({
    workouts: [],
    voiceLogs: [raceLog, log(daysAgo(3), "track", { paceSegments: tinySegments })],
    now: NOW,
  })!;

  // The 5:00 reps convert (per-distance Riegel, fix #4) to a 10K-equivalent
  // FAR faster than the anchor; the uncapped blend would land well below the
  // 2% cap.
  const signal = 300 * Math.pow(6.21371 / 1.0, 0.06);
  const rawBlend = noSignal.estimated10kPaceSeconds * 0.6 + signal * 0.4;
  assert(withSignal.estimated10kPaceSeconds < noSignal.estimated10kPaceSeconds, "signal should speed the estimate");
  assert(
    withSignal.estimated10kPaceSeconds >= noSignal.estimated10kPaceSeconds * 0.98 - 1e-6,
    `capped at 2%: got ${withSignal.estimated10kPaceSeconds} vs floor ${noSignal.estimated10kPaceSeconds * 0.98}`,
  );
  assert(
    withSignal.estimated10kPaceSeconds > rawBlend + 1,
    `cap must actually bind (raw blend ${rawBlend})`,
  );
});

// ── New test 4 (Part 1 fix #7): training-anchor displacement cap ────────────

Deno.test("training anchor displaces a stale race only up to the 50/50 blend with 3% floor", () => {
  const raceTenKPace = 1980 / 6.214; // 33:00 10K
  const voiceLogs = [
    log(daysAgo(140), "Raced the 10k, finish time 33:00."), // 20 weeks — past primary window
    log(daysAgo(5), "Evening intervals.", {
      parsedStructure: {
        confidence: 0.8,
        type: "interval",
        equivalentRacePace: { pacePerMile: "4:30", distanceKey: "tenK" }, // much faster than race
        workSummary: { totalDistanceMi: 5 },
      },
    }),
  ];
  const r = generateFitnessPrediction({ workouts: [], voiceLogs, extendedVoiceLogs: voiceLogs, now: NOW });
  assert(r !== null);
  assertEquals(r!.confidenceTier, "medium");
  assert(r!.dataSource.startsWith("training"), r!.dataSource);
  assert(r!.dataSource.includes("+ race"), `blended source: ${r!.dataSource}`);
  // The blended anchor is floored at race×0.97; the estimate can additionally
  // improve at most 0.5% (fix #3). A wholesale swap to the 4:30 session
  // (270 s/mi) would land near 270 — the floor keeps it near the race.
  assert(
    r!.estimated10kPaceSeconds >= raceTenKPace * 0.97 * 0.995 - 1e-6,
    `expected >= ${raceTenKPace * 0.97 * 0.995}, got ${r!.estimated10kPaceSeconds}`,
  );
});

// ── New test 5 (Part 1 fix #12): distance-aware ranges ──────────────────────

Deno.test("mile range fraction exceeds half range fraction when anchored on a half", () => {
  // "half" (not "half marathon") — the shared detector checks the "marathon"
  // pattern first, so "half marathon" would match as a marathon (same
  // pattern-order as the Swift detector).
  const voiceLogs = [log(daysAgo(20), "Raced the half, finish time 1:30:00.")];
  const r = generateFitnessPrediction({ workouts: [], voiceLogs, extendedVoiceLogs: voiceLogs, now: NOW });
  assert(r !== null);
  assert(r!.dataSource.startsWith("race (Half Marathon)"), r!.dataSource);
  const mileFrac = r!.rangeMileSeconds / r!.predictedMileSeconds;
  const halfFrac = r!.rangeHalfSeconds / r!.predictedHalfSeconds;
  assert(
    mileFrac > halfFrac,
    `mile (4 doublings from anchor, no speed evidence) must be wider: mile ${mileFrac} vs half ${halfFrac}`,
  );
});

// ── New test 6 (Part 1 fix #13): mile shading without speed evidence ────────

Deno.test("mile without speed evidence sits between the VDOT ratio and Riegel values", () => {
  const voiceLogs = [log(daysAgo(20), "Raced the 10k, finish time 40:00.")];
  const r = generateFitnessPrediction({ workouts: [], voiceLogs, extendedVoiceLogs: voiceLogs, now: NOW });
  assert(r !== null);
  const mileVDOT = Math.round(r!.predicted10kSeconds * 0.139583); // ratio-table mile
  const mileRiegel = r!.predicted10kSeconds * 0.14434; // Riegel-1.06 mile
  assertEquals(r!.predictedMileSeconds, Math.round((mileVDOT + mileRiegel) / 2));
  assert(r!.predictedMileSeconds > mileVDOT, "shaded slower than pure VDOT");
  assert(r!.predictedMileSeconds < mileRiegel + 1, "but never slower than Riegel");
});

// ── New test 7 (Part 1 fix #14): marathon volume factor ─────────────────────

Deno.test("marathon endurance shading: thin long-run base shades within the literature 3–10% band", () => {
  // v2 (2026-07-24): the marathon multiplier now reflects long-run TRAINING,
  // not just weekly volume. A 10K-anchored athlete whose long runs top out at
  // 10mi should read markedly slower over 26.2 than one who repeats 20-milers.
  const raceLog = log(daysAgo(28), "Raced the 10k, finish time 40:00.");
  const dates = [2, 5, 8, 11, 16, 19, 22, 25];
  const mk = (miles: number) => dates.map((d) => run(daysAgo(d), miles, 540));
  // Thin base: 20 mi/wk, longest run only 10mi, zero runs ≥16.
  const thin = generateFitnessPrediction({ workouts: mk(10), voiceLogs: [raceLog], extendedVoiceLogs: [raceLog], now: NOW })!;
  // Marathon-ready base: 40 mi/wk built from repeated 20-milers.
  const ready = generateFitnessPrediction({ workouts: mk(20), voiceLogs: [raceLog], extendedVoiceLogs: [raceLog], now: NOW })!;
  // Compare marathon:10K ratios — the endurance factor is the only
  // marathon-specific multiplier, so this isolates it from decay.
  const ratio = (thin.predictedMarathonSeconds / thin.predicted10kSeconds) /
    (ready.predictedMarathonSeconds / ready.predicted10kSeconds);
  assert(ratio > 1.03 && ratio < 1.10, `thin base shaded ${((ratio - 1) * 100).toFixed(1)}% vs ready; expected 3–10%`);
});

// ── New tests 8+9 (Part 2 A/B): heat normalization + rest-aware laps ────────

function intervalLaps(opts: { tempF: number | null; dewPointF: number | null; restSecondsEach: number }): LapInput[] {
  // 7 × 0.62 mi @ 320 s/mi with rest laps between (work:rest set by caller).
  const laps: LapInput[] = [];
  for (let i = 0; i < 7; i++) {
    laps.push({
      workoutId: "w1",
      date: daysAgo(3),
      lapIndex: i * 2 + 1,
      distanceMeters: 0.62 * 1609.344,
      movingTimeSeconds: Math.round(0.62 * 320),
      avgPaceSecPerMile: 320,
      isRest: false,
      totalElevationGain: 0,
      tempF: opts.tempF,
      dewPointF: opts.dewPointF,
      heatAdjustedPaceSecPerMile: null,
    });
    if (i < 6) {
      laps.push({
        workoutId: "w1",
        date: daysAgo(3),
        lapIndex: i * 2 + 2,
        distanceMeters: 50,
        movingTimeSeconds: opts.restSecondsEach,
        avgPaceSecPerMile: null,
        isRest: true,
        totalElevationGain: 0,
        tempF: opts.tempF,
        dewPointF: opts.dewPointF,
        heatAdjustedPaceSecPerMile: null,
      });
    }
  }
  return laps;
}

Deno.test("heat: the same interval session in 95°F/70°F dew reads FITTER than in 55°F/45°F", () => {
  // DIRECTION: heat normalization converts the observed pace to its
  // neutral-day equivalent — observed / (1 + pct·repFactor) — which is FASTER
  // than observed (the heat made the effort cost more). So the hot session's
  // 10K-equivalent contribution is FASTER (smaller) than the identical cool
  // session's, and the resulting estimate is faster. At 55/45 the composite
  // score is 100 → zero adjustment (control).
  const hotEfforts = deriveLapEfforts(intervalLaps({ tempF: 95, dewPointF: 70, restSecondsEach: 30 }));
  const coolEfforts = deriveLapEfforts(intervalLaps({ tempF: 55, dewPointF: 45, restSecondsEach: 30 }));
  assertEquals(hotEfforts.length, 7);
  assertEquals(coolEfforts.length, 7);
  assert(
    hotEfforts[0].paceSeconds < coolEfforts[0].paceSeconds,
    `hot rep must normalize faster: ${hotEfforts[0].paceSeconds} vs ${coolEfforts[0].paceSeconds}`,
  );
  assertEquals(coolEfforts[0].paceSeconds, 320); // cool + short rest → untouched

  // End-to-end: anchored on a 36:30 10K (~352 s/mi) the rep signals land
  // NEAR the estimate — cool reps (10K-equiv ≈ 367) slow it a few seconds
  // inside the ±2% validation band, hot reps normalize to ≈ 356 (within the
  // 5 s/mi blend trigger → estimate untouched). The hot session therefore
  // reads strictly fitter. (With a much faster anchor both sides pin to the
  // +2% slow cap and read identical — the band working as intended.)
  const raceLog = log(daysAgo(14), "Raced the 10k, finish time 36:30.");
  const hot = generateFitnessPrediction({
    workouts: [],
    voiceLogs: [raceLog],
    laps: intervalLaps({ tempF: 95, dewPointF: 70, restSecondsEach: 30 }),
    now: NOW,
  })!;
  const cool = generateFitnessPrediction({
    workouts: [],
    voiceLogs: [raceLog],
    laps: intervalLaps({ tempF: 55, dewPointF: 45, restSecondsEach: 30 }),
    now: NOW,
  })!;
  assert(
    hot.estimated10kPaceSeconds < cool.estimated10kPaceSeconds,
    `heat-credited session should read fitter: hot ${hot.estimated10kPaceSeconds} vs cool ${cool.estimated10kPaceSeconds}`,
  );
});

Deno.test("rest-aware: reps with rest ratio 2.0 grade slower than with ratio 0.4", () => {
  // work = 7 × ~198 s = ~1389 s. rest laps sit between the reps.
  // ratio 2.0 → rest ≈ 2779 s (6 × 463); ratio ~0.4 → 6 × 93 s.
  const workSeconds = 7 * Math.round(0.62 * 320);
  const rested = deriveLapEfforts(
    intervalLaps({ tempF: null, dewPointF: null, restSecondsEach: Math.ceil((workSeconds * 2.0) / 6) }),
  );
  const shortRest = deriveLapEfforts(
    intervalLaps({ tempF: null, dewPointF: null, restSecondsEach: Math.floor((workSeconds * 0.4) / 6) }),
  );
  // Full-recovery reps overstate continuous race fitness → +2.5% penalty;
  // short-rest reps are honest → no penalty. Pace is monotone into the
  // per-distance Riegel 10K-equivalent, so the rested 10K-equivalent is slower.
  assertEquals(shortRest[0].paceSeconds, 320);
  assert(
    rested[0].paceSeconds > shortRest[0].paceSeconds,
    `rested ${rested[0].paceSeconds} should exceed short-rest ${shortRest[0].paceSeconds}`,
  );
  assert(Math.abs(rested[0].paceSeconds - 320 * 1.025) < 1e-6, `expected +2.5% cap, got ${rested[0].paceSeconds}`);
});

// ── Effort-aware equivalence + slow cap (2026-07-16 hotfix #2) ──────────────
// A controlled tempo is an LT effort, not an all-out race at the segment's
// length: Riegel-by-distance read a relaxed tempo as a maximal short race and
// dragged live run #2 ~5% slow. Sustained efforts convert LT→10K (×0.975) and
// the validation band caps any slow-down at 2%.

Deno.test("sustained tempo cannot drag a race-anchored estimate more than 2%", () => {
  // 4-week-old 33:00 10K race → anchor ≈ 318.6 s/mi (est ≈ 320 after decay).
  // Six 2 mi tempo segments @ 350 s/mi: Riegel-by-distance would call each a
  // maximal 2-mile race (10K-equiv ≈ 375, −17%); LT→10K gives 341.
  const raceLog = log(daysAgo(28), "Raced the 10k, finish time 33:00.");
  const tempoLogs = [3, 6, 10].map((d) =>
    log(daysAgo(d), "tempo work", {
      paceSegments: [
        { effort: "tempo", durationSeconds: 700, distanceMiles: 2.0, pacePerMile: "5:50" },
        { effort: "tempo", durationSeconds: 700, distanceMiles: 2.0, pacePerMile: "5:50" },
      ],
    })
  );
  const r = generateFitnessPrediction({
    workouts: [],
    voiceLogs: [raceLog, ...tempoLogs],
    extendedVoiceLogs: [raceLog, ...tempoLogs],
    now: NOW,
  })!;
  const anchorPace = 1980 / 6.214;
  // Whatever the blend does, the estimate may not sit more than 2% + decay
  // slower than the anchor-supported value.
  assert(
    r.estimated10kPaceSeconds <= anchorPace * 1.02 * 1.02,
    `estimate ${r.estimated10kPaceSeconds} dragged too far past anchor ${anchorPace}`,
  );
});

// ── Race gathering: lifetime PRs + race-history speed evidence (2026-07-17) ─

Deno.test("old 5K race gives mile speed evidence and lifetime PRs surface", () => {
  // Current anchor: recent 10K race. An 18-month-old 15:05 5K is far outside
  // the 36-week anchor window — it must NOT change the 10K estimate, but it
  // proves trained speed (mile uses the VDOT ratio, not the Riegel midpoint)
  // and appears in lifetimePRs.
  const recentRace = log(daysAgo(28), "Raced the 10k, finish time 33:00.");
  const old5K = {
    raceType: "fiveK" as const,
    paceSecondsPerMile: 905 / 3.107,
    date: daysAgo(540),
    totalTimeSeconds: 905,
    sourceWorkoutId: "old5k",
  };
  const base = generateFitnessPrediction({
    workouts: [], voiceLogs: [recentRace], extendedVoiceLogs: [recentRace], now: NOW,
  })!;
  const withHistory = generateFitnessPrediction({
    workouts: [], voiceLogs: [recentRace], extendedVoiceLogs: [recentRace],
    seededRaces: [old5K], now: NOW,
  })!;
  // Anchor unchanged (the old race is outside the trusted window).
  assertEquals(withHistory.predicted10kSeconds, base.predicted10kSeconds);
  // Speed evidence: mile firms to the VDOT ratio (faster than the shaded base).
  assert(
    withHistory.predictedMileSeconds < base.predictedMileSeconds,
    `mile ${withHistory.predictedMileSeconds} should be faster than shaded ${base.predictedMileSeconds}`,
  );
  // PR surfaces.
  assertEquals(withHistory.lifetimePRs.fiveK?.timeSeconds, 905);
});

// ── Race flat-cool equivalents (2026-07-17) ─────────────────────────────────
// A confirmed race with laps is read in context: per-lap heat + grade
// adjusted, clamped to ±5% of raw. Laps match by sourceWorkoutId, never by
// date (warmup/cooldown sync as separate workouts).

Deno.test("hilly humid race with laps anchors faster than its raw pace, clamped at 5%", () => {
  // 10K race: 6.2 hilly humid mile laps @ 319 s/mi, ~16m gain each (≈1% up),
  // 88°F/72°F dew. Both adjustments push the equivalent pace faster; the ±5%
  // clamp binds before they can overcredit (laps store gain only, no loss).
  const raceLaps: LapInput[] = Array.from({ length: 6 }, (_, i) => ({
    workoutId: "race1",
    date: daysAgo(30),
    lapIndex: i + 1,
    distanceMeters: 1670,
    movingTimeSeconds: Math.round(319 * (1670 / 1609.344)),
    avgPaceSecPerMile: 319,
    isRest: false,
    totalElevationGain: 16.6,
    tempF: 88,
    dewPointF: 72,
    heatAdjustedPaceSecPerMile: null,
  }));
  const race = {
    raceType: "tenK" as const,
    paceSecondsPerMile: 319,
    date: daysAgo(30),
    totalTimeSeconds: 1982,
    sourceWorkoutId: "race1",
  };
  const eff = raceEffectivePace(race, raceLaps);
  assert(eff.lapAdjusted, "laps should have been used");
  assert(eff.pace < 319, `equivalent must be faster than raw, got ${eff.pace}`);
  assert(Math.abs(eff.pace - 319 * 0.95) < 1e-9, `clamp at 5% expected, got ${eff.pace}`);

  // Warmup laps under a DIFFERENT workout id (same date) must not blend in,
  // and without its own laps the race falls back to raw pace.
  const warmupOnly = raceLaps.map((l) => ({ ...l, workoutId: "warmup1" }));
  const untouched = raceEffectivePace(race, warmupOnly);
  assert(!untouched.lapAdjusted && untouched.pace === 319, "must fall back to raw pace");

  // Coverage guard: laps summing to a fraction of the race distance → raw.
  const partial = raceEffectivePace(race, raceLaps.slice(0, 2));
  assert(!partial.lapAdjusted && partial.pace === 319, "partial laps must not adjust");
});

// ── Continuous-training decay cap (2026-07-16) ──────────────────────────────

Deno.test("a continuously-training athlete's race anchor decays at most 2% total", () => {
  // 22-week-old 31:20 10K; steady 45 mi/wk with no gaps and recent quality →
  // no detraining triggers. The old model applied ~0.2%/wk × 22wk ≈ +4.5%
  // because effort labels were too sparse to prove maintenance.
  const raceLog = log(daysAgo(154), "Raced the 10k, finish time 31:20.");
  const workouts: WorkoutInput[] = [];
  for (let d = 1; d <= 40; d += 2) workouts.push(run(daysAgo(d), 7, 470)); // every other day
  const quality = log(daysAgo(3), "workout", {
    parsedStructure: { type: "tempo", confidence: 0.9 },
    paceSegments: [{ effort: "tempo", durationSeconds: 1200, distanceMiles: 0.05, pacePerMile: "9:30" }],
  });
  const r = generateFitnessPrediction({
    workouts,
    voiceLogs: [raceLog, quality],
    extendedVoiceLogs: [raceLog, quality],
    now: NOW,
  })!;
  const anchorPace = 1880 / 6.214;
  // Anchor-decay contribution capped at ×1.02; the validation band may add at
  // most another ×1.02 on top.
  assert(
    r.estimated10kPaceSeconds <= anchorPace * 1.02 * 1.02 + 1e-9,
    `estimate ${r.estimated10kPaceSeconds} exceeds capped decay from ${anchorPace}`,
  );
});

// ── Regression (2026-07-16 hotfix): easy-run laps must not pollute the pool ─
// Laps carry no effort labels; the absolute 210–540 s/mi window admitted easy
// laps (first live run: estimate dragged 17% slow by ~7:20–7:50/mi easy laps).
// Gate: a lap qualifies only at ≤ anchor 10K pace × 1.12 (MP-or-faster for
// THIS athlete, mirroring quality-volume.ts).

Deno.test("easy-run laps (unlabeled) do not slow the estimate", () => {
  // 6-week-old 40:00 10K race → anchor pace ~386 s/mi; hardness cap ~432 s/mi.
  const raceLog = log(daysAgo(42), "Raced the 10k, finish time 40:00.");
  const workouts = [2, 5, 8, 11, 16, 20, 24].map((d) => run(daysAgo(d), 8, 470));
  // 12 easy laps @ 470 s/mi (inside the old absolute window, above the cap).
  const easyLaps: LapInput[] = Array.from({ length: 12 }, (_, i) => ({
    workoutId: "easy1",
    date: daysAgo(4),
    lapIndex: i + 1,
    distanceMeters: 1609.344,
    movingTimeSeconds: 470,
    avgPaceSecPerMile: 470,
    isRest: false,
    totalElevationGain: 0,
    tempF: null,
    dewPointF: null,
    heatAdjustedPaceSecPerMile: null,
  }));
  const base = generateFitnessPrediction({
    workouts, voiceLogs: [raceLog], extendedVoiceLogs: [raceLog], now: NOW,
  })!;
  const withEasyLaps = generateFitnessPrediction({
    workouts, voiceLogs: [raceLog], extendedVoiceLogs: [raceLog], laps: easyLaps, now: NOW,
  })!;
  assert(
    Math.abs(withEasyLaps.estimated10kPaceSeconds - base.estimated10kPaceSeconds) < 1e-9,
    `easy laps changed the estimate: ${base.estimated10kPaceSeconds} → ${withEasyLaps.estimated10kPaceSeconds}`,
  );
});

// ── v2 endurance-aware projection (2026-07-24) ──────────────────────────────
// The marathon/half is a race-equivalence conversion from 10K speed. Published
// guidance (Riegel ~80% accurate; "assumes appropriate training for the
// distance"; adjust 3–10% slower when endurance volume is inadequate) says the
// conversion over-predicts without long-run base. These tests hold the RACE
// constant and vary the TRAINING to prove the number reflects training.

// Shared 32:00 10K anchor + high weekly volume so the volume floor is inert
// (weeklyMiles ≥ 40 → volume factor 1.0) and the endurance factor is isolated.
type SeedRace = NonNullable<PredictionInput["seededRaces"]>[number];
const TENK_3200: SeedRace = { raceType: "tenK", paceSecondsPerMile: 1920 / 6.21371, date: daysAgo(30), totalTimeSeconds: 1920 };
const HIGH_VOL_BASE = Array.from({ length: 24 }, (_, i) => run(daysAgo(1 + i), 7, 430)); // ~42 mi/wk of easy running

function predictWithLongRuns(longs: WorkoutInput[], race: SeedRace = TENK_3200) {
  return generateFitnessPrediction({
    workouts: HIGH_VOL_BASE,
    extendedWorkouts: [...HIGH_VOL_BASE, ...longs],
    voiceLogs: [],
    seededRaces: [race],
    now: NOW,
  })!;
}

Deno.test("v2: marathon reflects long-run TRAINING, not just the race", () => {
  const rioLongs = [run(daysAgo(27), 17.8, 460), run(daysAgo(13), 15, 460), run(daysAgo(6), 14, 460), run(daysAgo(20), 13.5, 460), run(daysAgo(9), 13.1, 460)];
  const readyLongs = [run(daysAgo(27), 20, 460), run(daysAgo(13), 20, 460), run(daysAgo(6), 21, 460), run(daysAgo(20), 20, 460)];
  const rio = predictWithLongRuns(rioLongs);
  const ready = predictWithLongRuns(readyLongs);
  // Same race, same volume — only the long-run training differs.
  assert(rio.predictedMarathonSeconds > ready.predictedMarathonSeconds, "thin long-run base must read slower over 26.2");
  const ratio = (rio.predictedMarathonSeconds / rio.predicted10kSeconds) /
    (ready.predictedMarathonSeconds / ready.predicted10kSeconds);
  // A 17.8-mi ceiling (one run ≥16) lands ~2% slower than a 20-miler base.
  assert(ratio > 1.015 && ratio < 1.03, `expected ~2% endurance shade, got ${((ratio - 1) * 100).toFixed(2)}%`);
});

Deno.test("v2: endurance shade spans the population sensibly (ready→0, thin→≤12%)", () => {
  const at = (longest: number, count: number) => {
    const longs: WorkoutInput[] = [];
    for (let i = 0; i < Math.max(count, 1); i++) longs.push(run(daysAgo(6 + i * 5), i === 0 ? longest : Math.max(16, longest - 1), 460));
    if (count === 0) longs.length = 0, longs.push(run(daysAgo(6), longest, 460));
    return predictWithLongRuns(longs);
  };
  const ready = predictWithLongRuns([run(daysAgo(20), 21, 460), run(daysAgo(10), 20, 460), run(daysAgo(4), 20, 460)]);
  const none = predictWithLongRuns([run(daysAgo(6), 6, 430)]); // never runs long
  const readyFactor = ready.predictedMarathonSeconds / ready.predicted10kSeconds;
  const noneFactor = none.predictedMarathonSeconds / none.predicted10kSeconds;
  const shade = noneFactor / readyFactor;
  // Longest run here is the 7mi base (not literal zero), so it shades ~8% —
  // high, bounded well under the 12% ceiling, and inside the 3–10% band.
  assert(shade > 1.07 && shade < 1.10, `thin base should shade ~8%, got ${((shade - 1) * 100).toFixed(1)}%`);
});

Deno.test("v2 unit: enduranceFactor spans 0%→ceiling; longRunReadiness reads longest+count", () => {
  // Pure-function spread across the whole runner population.
  const ready = enduranceFactor(20, 3, MARA_READY_LONGRUN_MILES, MARA_READY_LONGRUN_COUNT, MARA_MAX_ENDURANCE_PENALTY);
  const zero = enduranceFactor(0, 0, MARA_READY_LONGRUN_MILES, MARA_READY_LONGRUN_COUNT, MARA_MAX_ENDURANCE_PENALTY);
  const rioLike = enduranceFactor(17.8, 1, MARA_READY_LONGRUN_MILES, MARA_READY_LONGRUN_COUNT, MARA_MAX_ENDURANCE_PENALTY);
  const short = enduranceFactor(13, 0, MARA_READY_LONGRUN_MILES, MARA_READY_LONGRUN_COUNT, MARA_MAX_ENDURANCE_PENALTY);
  assertEquals(Math.round(ready * 1000) / 1000, 1.0); // a true 20-miler base → no shade
  assertEquals(Math.round(zero * 1000) / 1000, 1.12); // literal zero base → full 12% ceiling
  assert(rioLike > 1.015 && rioLike < 1.025, `rio-like ~2%, got ${rioLike}`);
  assert(short > 1.03 && short < 1.06, `13mi-longest ~4-5%, got ${short}`); // monotonic between
  assert(zero > short && short > rioLike && rioLike > ready, "penalty decreases as base grows");

  const lr = longRunReadiness(
    [run(daysAgo(5), 18, 460), run(daysAgo(12), 16, 460), run(daysAgo(40), 12, 460), run(daysAgo(200), 22, 460)],
    NOW,
  );
  assertEquals(lr.longestMiles, 18); // the 22mi run is outside the 70-day window
  assertEquals(lr.count16, 2); // 18 and 16 within window; 12 doesn't count, 22 too old
});

Deno.test("v2: a demonstrated marathon race anchor is NOT endurance-shaded", () => {
  const maraRace: SeedRace = { raceType: "marathon", paceSecondsPerMile: 9000 / 26.21875, date: daysAgo(20), totalTimeSeconds: 9000 };
  // Even with zero long runs logged, a real marathon result proves the endurance.
  const r = predictWithLongRuns([run(daysAgo(6), 6, 430)], maraRace);
  // marathon prediction should track the raced time closely (within decay), not be shaded up.
  assert(Math.abs(r.predictedMarathonSeconds - 9000) < 9000 * 0.05, `marathon-anchored prediction drifted too far: ${r.predictedMarathonSeconds}`);
});

Deno.test("v2: half is shaded more gently than the marathon", () => {
  const thin = [run(daysAgo(6), 10, 460), run(daysAgo(16), 9, 460)]; // short long runs
  const r = predictWithLongRuns(thin);
  const ready = predictWithLongRuns([run(daysAgo(20), 20, 460), run(daysAgo(10), 20, 460), run(daysAgo(4), 20, 460)]);
  const halfShade = (r.predictedHalfSeconds / r.predicted10kSeconds) / (ready.predictedHalfSeconds / ready.predicted10kSeconds);
  const maraShade = (r.predictedMarathonSeconds / r.predicted10kSeconds) / (ready.predictedMarathonSeconds / ready.predicted10kSeconds);
  assert(halfShade >= 1.0 && halfShade < maraShade, `half (${halfShade.toFixed(3)}) should shade less than marathon (${maraShade.toFixed(3)})`);
});

Deno.test("v2 VALIDATION (not a fit target): Rio's real profile lands ~2:31", () => {
  // 32:00 10K, longest long run 17.8mi (once), 13–15mi otherwise, ~high volume.
  const rioLongs = [run(daysAgo(27), 17.8, 460), run(daysAgo(13), 15, 460), run(daysAgo(6), 14, 460), run(daysAgo(20), 13.5, 460), run(daysAgo(9), 13.1, 460), run(daysAgo(2), 13, 460)];
  const rio = predictWithLongRuns(rioLongs);
  const mm = Math.floor(rio.predictedMarathonSeconds / 60), ss = rio.predictedMarathonSeconds % 60;
  console.log(`   Rio marathon prediction: ${Math.floor(mm/60)}:${String(mm%60).padStart(2,"0")}:${String(ss).padStart(2,"0")} (${rio.predictedMarathonSeconds}s)`);
  // Independent check: falls in an honest 2:29:30–2:32:30 window around his 2:31.
  assert(rio.predictedMarathonSeconds > 8970 && rio.predictedMarathonSeconds < 9150, `expected ~2:31, got ${rio.predictedMarathonSeconds}s`);
});

// ── v2 user-overridable marks + duplicate collapsing (2026-07-24) ───────────
// One real race often lands in the log 2-3× (double-import, or a training run
// auto-tagged "race"). The athlete must be able to correct any mark, and one
// physical race must anchor once — not inflate confidence as "agreeing races".

Deno.test("dedupeRaces collapses one real race logged 3× (Apr 12/14/15 ~33:00)", () => {
  const races = [
    { raceType: "tenK" as const, paceSecondsPerMile: 1984 / 6.21371, date: daysAgo(103), totalTimeSeconds: 1984 }, // Apr 15
    { raceType: "tenK" as const, paceSecondsPerMile: 1984 / 6.21371, date: daysAgo(104), totalTimeSeconds: 1984 }, // Apr 14 (dup)
    { raceType: "tenK" as const, paceSecondsPerMile: 1982 / 6.21371, date: daysAgo(106), totalTimeSeconds: 1982, sourceWorkoutId: "confirmed-1" }, // Apr 12, confirmed
  ];
  const out = dedupeRaces(races);
  assertEquals(out.length, 1); // one physical event
  assertEquals(out[0].sourceWorkoutId, "confirmed-1"); // keeps the confirmed representative
  // A genuinely separate race (different time) is preserved.
  const withDistinct = dedupeRaces([...races, { raceType: "tenK" as const, paceSecondsPerMile: 2400 / 6.21371, date: daysAgo(40), totalTimeSeconds: 2400 }]);
  assertEquals(withDistinct.length, 2);
});

Deno.test("user can override a mark: excluding the wrong 'race' re-anchors the prediction", () => {
  const real: SeedRace = { raceType: "tenK", paceSecondsPerMile: 1980 / 6.21371, date: daysAgo(20), totalTimeSeconds: 1980 }; // 33:00
  const bogus = (excluded: boolean): SeedRace => ({ raceType: "tenK", paceSecondsPerMile: 1680 / 6.21371, date: daysAgo(15), totalTimeSeconds: 1680, userExcluded: excluded }); // a mislabeled 28:00 "race"
  const withBogus = generateFitnessPrediction({ workouts: [], voiceLogs: [], seededRaces: [real, bogus(false)], now: NOW })!;
  const corrected = generateFitnessPrediction({ workouts: [], voiceLogs: [], seededRaces: [real, bogus(true)], now: NOW })!;
  // Uncorrected, the faster bogus mark anchors (~28:00). Corrected, the real 33:00 does.
  assert(withBogus.predicted10kSeconds < 1750, `bogus mark should anchor fast, got ${withBogus.predicted10kSeconds}`);
  assert(corrected.predicted10kSeconds > 1950 && corrected.predicted10kSeconds < 2050, `override should re-anchor to the real race, got ${corrected.predicted10kSeconds}`);
});

Deno.test("userExcludedFromFitness drops a workout from all signals", () => {
  const race = log(daysAgo(20), "Raced the 10k, finish time 40:00.");
  const bogusFast = run(daysAgo(3), 5, 260, 22); // a garbage 4:20/mi import
  const withIt = generateFitnessPrediction({ workouts: [bogusFast], voiceLogs: [race], extendedVoiceLogs: [race], now: NOW })!;
  const without = generateFitnessPrediction({ workouts: [{ ...bogusFast, userExcludedFromFitness: true }], voiceLogs: [race], extendedVoiceLogs: [race], now: NOW })!;
  // The excluded workout must not drag the estimate (identical to it being absent).
  const clean = generateFitnessPrediction({ workouts: [], voiceLogs: [race], extendedVoiceLogs: [race], now: NOW })!;
  assertEquals(without.predicted10kSeconds, clean.predicted10kSeconds);
});

// ── v3 threshold pillar (2026-07-24) ────────────────────────────────────────
// Sustained tempo/threshold work → a threshold capacity, independent of races.
// Effort labels are coarse in production, so threshold is separated from VO2 by
// rep GEOMETRY (sustained ≥0.8mi rep = threshold; short rep = VO2).

function seg(effort: string, pace: string, mi: number) {
  return { effort, pacePerMile: pace, distanceMiles: mi, durationSeconds: Math.round(paceStringToSeconds(pace) * mi) };
}

Deno.test("v3 threshold: sustained tempo work yields a threshold + 10K-equivalent", () => {
  // Rio's real June 9 threshold session shape: 4×1mi 'fast' + steady + easy.
  const s = thresholdCapacity([
    log(daysAgo(5), "Threshold", { paceSegments: [
      seg("fast", "5:26", 1), seg("fast", "5:27", 1), seg("fast", "5:37", 1), seg("fast", "5:59", 1),
      seg("steady", "7:37", 1), seg("easy", "11:28", 1), seg("easy", "8:02", 1), seg("easy", "8:14", 0.39),
    ] }),
  ], NOW)!;
  assert(s !== null);
  // Distance-weighted over the four 1mi reps ≈ 5:37/mi; easy/steady excluded.
  assert(Math.abs(s.thresholdPaceSeconds - 337) <= 2, `threshold pace ${s.thresholdPaceSeconds}`);
  assertEquals(s.equivalentTenKPace, Math.round(s.thresholdPaceSeconds * THRESHOLD_TO_10K));
  assertEquals(s.evidenceMiles, 4);
});

Deno.test("v3 threshold: short VO2 reps do NOT count as threshold; thin work → null", () => {
  // 6×400m at 5K pace — all short reps, so no sustained threshold evidence.
  const vo2 = log(daysAgo(4), "Intervals", { paceSegments: Array.from({ length: 6 }, () => seg("fast", "4:50", 0.25)) });
  assertEquals(thresholdCapacity([vo2], NOW), null);
  // A single 1.5mi tempo rep is below the 2mi evidence floor → null.
  const thin = log(daysAgo(4), "Tempo", { paceSegments: [seg("tempo", "5:40", 1.5)] });
  assertEquals(thresholdCapacity([thin], NOW), null);
});

Deno.test("v3 threshold: work older than the 6-week window is ignored", () => {
  const old = log(daysAgo(60), "Threshold", { paceSegments: [seg("fast", "5:30", 2), seg("fast", "5:35", 2)] });
  assertEquals(thresholdCapacity([old], NOW), null);
  const fresh = log(daysAgo(10), "Threshold", { paceSegments: [seg("fast", "5:30", 2), seg("fast", "5:35", 2)] });
  assert(thresholdCapacity([fresh], NOW) !== null);
});
