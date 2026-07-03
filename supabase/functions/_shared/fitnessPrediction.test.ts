import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  generateFitnessPrediction,
  detectRaces,
  detectTrainingAnchors,
  detectDetraining,
  paceStringToSeconds,
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
  // Range is the high-tier fraction (1.5%) of the point.
  assertEquals(r!.range10kSeconds, Math.trunc(r!.predicted10kSeconds * 0.015));
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
  assertEquals(r!.confidence, "High");
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
  assertEquals(r!.dataSource, "fastest workout");
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
