/**
 * Tests for PaceEngine — the central pace calculator.
 *
 * Run: deno test --allow-env _shared/pace-engine.test.ts
 *
 * Calibration: "% of MP" framework. X% of MP = MP × (2 - X/100).
 * Reference example: MP 3:00/km × 1.10 = 3:18/km at 90% MP.
 *
 * For a 2:20 marathoner (MP = 5:20/mi = 320 sec/mi) the bands are:
 *   Easy:     70-80% MP  → 6:24 – 6:56 /mi  (mp × 1.20 – 1.30)
 *   Moderate: 80-90% MP  → 5:52 – 6:24 /mi  (mp × 1.10 – 1.20)
 *   Steady:   90-100% MP → 5:20 – 5:52 /mi  (mp × 1.00 – 1.10)
 *   MP:       5:20
 *   HMP:      5:06
 *
 * Every test below pins one of these values; if the engine drifts, the
 * test fails. iOS PaceCalculator and PaceModels MP ratios mirror the engine.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  computePaceZones,
  formatPace,
  formatRange,
  type PaceEngineInput,
  type TrainingLogRow,
  TRAINING_PACE_MULTIPLIERS,
} from "./pace-engine.ts";

const USER = "11111111-1111-1111-1111-111111111111";
const NOW = new Date("2026-05-06T12:00:00Z");

function emptyInput(): PaceEngineInput {
  return {
    athleteUserId: USER,
    profile: null,
    snapshot: null,
    plan: null,
    recentLogs: [],
    now: NOW,
  };
}

// ── Cold start ───────────────────────────────────────────

Deno.test("cold start: no data → all zones null", () => {
  const z = computePaceZones(emptyInput());
  assertEquals(z.primarySource, "none");
  assertEquals(z.marathon, null);
  assertEquals(z.easy, null);
  assertEquals(z.moderate, null);
  assertEquals(z.steady, null);
});

// ── Chart parity (the headline tests) ───────────────────

Deno.test("BAND 2:20 marathoner: Easy 6:24 – 6:56 /mi (70-80% MP)", () => {
  const z = computePaceZones({
    ...emptyInput(),
    plan: { target_race_distance: "marathon", target_time_seconds: 2 * 3600 + 20 * 60 },
  });
  assert(z.easy);
  // 320 × 1.25   = 400 = 6:40/mi (80% MP speed, fastest)
  // 320 × 1.4286 = 457 = 7:37/mi (70% MP speed, slowest)
  assertEquals(z.easy.paceFast, 400);
  assertEquals(z.easy.paceSlow, 457);
  assertEquals(formatPace(z.easy.paceFast), "6:40");
  assertEquals(formatPace(z.easy.paceSlow), "7:37");
  assertEquals(z.easy.openEndedSlow, false);
  assertEquals(z.easy.effortPercent, "70-80% MP");
});

Deno.test("BAND 2:20 marathoner: Moderate 5:56 – 6:40 /mi (80-90% MP)", () => {
  const z = computePaceZones({
    ...emptyInput(),
    plan: { target_race_distance: "marathon", target_time_seconds: 2 * 3600 + 20 * 60 },
  });
  assert(z.moderate);
  // 320 × 1.1111 = 356 = 5:56/mi (90% MP speed, fastest)
  // 320 × 1.25   = 400 = 6:40/mi (80% MP speed, slowest)
  assertEquals(z.moderate.paceFast, 356);
  assertEquals(z.moderate.paceSlow, 400);
  assertEquals(z.moderate.effortPercent, "80-90% MP");
});

Deno.test("BAND 2:20 marathoner: Steady 5:20 – 5:56 /mi (90-100% MP)", () => {
  const z = computePaceZones({
    ...emptyInput(),
    plan: { target_race_distance: "marathon", target_time_seconds: 2 * 3600 + 20 * 60 },
  });
  assert(z.steady);
  // 320 × 1.0    = 320 = 5:20/mi (100% MP speed = MP itself, fastest steady)
  // 320 × 1.1111 = 356 = 5:56/mi (90% MP speed, slowest)
  assertEquals(z.steady.paceFast, 320);
  assertEquals(z.steady.paceSlow, 356);
  assertEquals(z.steady.effortPercent, "90-100% MP");
});

Deno.test("BAND 2:20 marathoner: Recovery 7:37 – 8:53 /mi (60-70% MP, open-ended slow)", () => {
  const z = computePaceZones({
    ...emptyInput(),
    plan: { target_race_distance: "marathon", target_time_seconds: 2 * 3600 + 20 * 60 },
  });
  assert(z.recovery);
  // 320 × 1.4286 = 457 = 7:37/mi (70% MP speed = easy.slow boundary)
  // 320 × 1.6667 = 533 = 8:53/mi (60% MP speed, practical floor)
  assertEquals(z.recovery.paceFast, 457);
  assertEquals(z.recovery.paceSlow, 533);
  assertEquals(z.recovery.openEndedSlow, true);
  assertEquals(z.recovery.effortPercent, "<70% MP");
});

Deno.test("BAND CONTIGUITY: easy/moderate/steady touch with no gaps", () => {
  const z = computePaceZones({
    ...emptyInput(),
    plan: { target_race_distance: "marathon", target_time_seconds: 2 * 3600 + 20 * 60 },
  });
  assert(z.recovery && z.easy && z.moderate && z.steady);
  // Recovery slow (60% MP, practical floor)
  // Recovery fast = Easy slow (70% MP) → bands meet
  // Easy fast = Moderate slow (80% MP) → bands meet
  // Moderate fast = Steady slow (90% MP) → bands meet
  // Steady fast (100% MP) = MP itself
  assertEquals(z.recovery.paceFast, z.easy.paceSlow, "recovery fast should equal easy slow (70% MP)");
  assertEquals(z.easy.paceFast, z.moderate.paceSlow, "easy fast should equal moderate slow (80% MP)");
  assertEquals(z.moderate.paceFast, z.steady.paceSlow, "moderate fast should equal steady slow (90% MP)");
});

Deno.test("REFERENCE EXAMPLE: 90% MP boundary on the 2:20 marathoner", () => {
  // The 90% MP speed boundary appears as moderate.paceFast and steady.paceSlow.
  // For MP 5:20/mi (320 sec): 320 × 1.1111 = 356 sec = 5:56/mi.
  const z = computePaceZones({
    ...emptyInput(),
    plan: { target_race_distance: "marathon", target_time_seconds: 2 * 3600 + 20 * 60 },
  });
  assert(z.moderate && z.steady);
  const ninetyPercent = z.moderate.paceFast; // sec/mi
  assertEquals(ninetyPercent, 356);
  assertEquals(ninetyPercent, z.steady.paceSlow, "90% boundary must match across bands");
});

Deno.test("CHART PARITY 2:20 marathoner: MP 5:20, HMP 5:06", () => {
  const z = computePaceZones({
    ...emptyInput(),
    snapshot: {
      predicted_marathon_seconds: 2 * 3600 + 20 * 60,
      predicted_half_seconds: 66 * 60 + 51, // chart shows 1:06:51
      predicted_10k_seconds: null,
      predicted_5k_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
  });
  assert(z.marathon);
  assertEquals(formatPace(z.marathon.pace), "5:20");
  assert(z.halfMarathon);
  // 4011 / 13.1094 = 305.96 → 306 = 5:06/mi (chart shows 5:06)
  assertEquals(formatPace(z.halfMarathon.pace), "5:06");
});

// ── Source priority ─────────────────────────────────────

Deno.test("source priority: profile beats snapshot for race anchors", () => {
  const z = computePaceZones({
    ...emptyInput(),
    profile: {
      easy_pace_seconds: null,
      marathon_pace_seconds: 320,
      half_pace_seconds: 305,
      ten_k_pace_seconds: 290,
      five_k_pace_seconds: 280,
      mile_pace_seconds: 258,
      updated_at: NOW.toISOString(),
    },
    snapshot: {
      predicted_marathon_seconds: 9000, // very different — should be ignored
      predicted_half_seconds: 4500,
      predicted_10k_seconds: null,
      predicted_5k_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
  });
  assert(z.marathon);
  assertEquals(z.marathon.source, "profile");
  assertEquals(z.marathon.pace, 320);
});

Deno.test("source priority: profile partial → fall through to snapshot for missing anchors", () => {
  const z = computePaceZones({
    ...emptyInput(),
    profile: {
      easy_pace_seconds: null,
      marathon_pace_seconds: 320,
      half_pace_seconds: null,
      ten_k_pace_seconds: null,
      five_k_pace_seconds: null,
      mile_pace_seconds: null,
      updated_at: NOW.toISOString(),
    },
    snapshot: {
      predicted_5k_seconds: 14 * 60 + 30,
      predicted_10k_seconds: 30 * 60,
      predicted_half_seconds: null,
      predicted_marathon_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
  });
  assert(z.marathon);
  assertEquals(z.marathon.source, "profile");
  assert(z.fiveK);
  assertEquals(z.fiveK.source, "race_derived");
  assertEquals(z.halfMarathon, null); // not in either
});

// ── Observed-data overrides ─────────────────────────────

function makeEasyLog(date: string, paceSec: number, miles = 6): TrainingLogRow {
  return {
    workout_date: date,
    workout_distance_miles: miles,
    workout_duration_minutes: (paceSec * miles) / 60,
    workout_pace_per_mile: formatPace(paceSec),
    workout_type: "easy",
    parsed_structure: null,
    source: "strava",
  };
}

Deno.test("doctrine: 8+ easy runs do NOT redefine Easy — band stays MP × 1.20–1.30", () => {
  // Athlete is running easy too fast (7:00–7:35 with MP 5:20 = 1.31×–1.42× MP,
  // actually that's IN-BAND. Use a more aggressive set: 6:30–7:00 (390–420),
  // which is 1.22×–1.31× MP — partly OUT of easy on the fast end). Doctrine
  // band must NOT shrink to fit observed.
  const paces = [390, 395, 398, 402, 405, 408, 410, 415, 418, 420];
  const logs = paces.map((p, i) => makeEasyLog(`2026-04-${10 + i}T07:00:00Z`, p));
  const z = computePaceZones({
    ...emptyInput(),
    snapshot: {
      predicted_marathon_seconds: 2 * 3600 + 20 * 60,
      predicted_half_seconds: null,
      predicted_10k_seconds: null,
      predicted_5k_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
    recentLogs: logs,
  });
  // Easy is doctrine, regardless of observed run data.
  assert(z.easy);
  assertEquals(z.easy.paceFast, 400, "easy.paceFast must stay at MP × 1.25 even with observed data");
  assertEquals(z.easy.paceSlow, 457, "easy.paceSlow must stay at MP × 1.4286 even with observed data");
  assertEquals(z.easy.source, "race_derived"); // MP came from snapshot
  // primarySource never reports "observed" — observed is a diagnostic, not a source.
  assertEquals(z.primarySource, "race_derived");
});

Deno.test("observedEasy diagnostic: surfaces p25/p75 + sessionCount when ≥8 easy runs", () => {
  const paces = [420, 425, 428, 430, 435, 440, 445, 450, 452, 455];
  const logs = paces.map((p, i) => makeEasyLog(`2026-04-${10 + i}T07:00:00Z`, p));
  const z = computePaceZones({
    ...emptyInput(),
    snapshot: {
      predicted_marathon_seconds: 2 * 3600 + 20 * 60,
      predicted_half_seconds: null,
      predicted_10k_seconds: null,
      predicted_5k_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
    recentLogs: logs,
  });
  assert(z.observedEasy);
  // p25 = 428 + 0.25*(430-428) = 428.5 → 429; p75 = 445 + 0.75*(450-445) = 448.75 → 449
  assertEquals(z.observedEasy.paceFast, 429);
  assertEquals(z.observedEasy.paceSlow, 449);
  assertEquals(z.observedEasy.sessionCount, 10);
  assertEquals(z.observedEasy.lookbackDays, 90);
});

Deno.test("observedEasy: <8 easy runs → null (no diagnostic), Easy zone still doctrine", () => {
  const logs = [420, 430, 440, 445, 450].map((p, i) => makeEasyLog(`2026-04-${10 + i}T07:00:00Z`, p));
  const z = computePaceZones({
    ...emptyInput(),
    snapshot: {
      predicted_marathon_seconds: 2 * 3600 + 20 * 60,
      predicted_half_seconds: null,
      predicted_10k_seconds: null,
      predicted_5k_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
    recentLogs: logs,
  });
  assertEquals(z.observedEasy, null);
  assert(z.easy);
  assertEquals(z.easy.source, "race_derived");
  assertEquals(z.easy.paceFast, 400); // 320 × 1.25 (80% MP speed)
  assertEquals(z.easy.paceSlow, 457); // 320 × 1.4286 (70% MP speed)
});

Deno.test("observedEasy: mislabeled tempos excluded via parsed_structure.type", () => {
  const easyPaces = [430, 435, 440, 445, 450, 440, 435, 445];
  const logs: TrainingLogRow[] = easyPaces.map((p, i) =>
    makeEasyLog(`2026-04-${10 + i}T07:00:00Z`, p)
  );
  logs.push({
    workout_date: "2026-04-20T07:00:00Z",
    workout_distance_miles: 8,
    workout_duration_minutes: 40,
    workout_pace_per_mile: "5:00",
    workout_type: "easy", // mislabeled
    parsed_structure: { type: "tempo" }, // observer caught it
    source: "strava",
  });
  const z = computePaceZones({
    ...emptyInput(),
    snapshot: {
      predicted_marathon_seconds: 2 * 3600 + 20 * 60,
      predicted_half_seconds: null,
      predicted_10k_seconds: null,
      predicted_5k_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
    recentLogs: logs,
  });
  assert(z.observedEasy);
  // p25 of 8 easy paces = ~432; tempo at 300 must NOT pull diagnostic faster
  assert(z.observedEasy.paceFast > 420, `observed paceFast ${z.observedEasy.paceFast} polluted by mislabeled tempo`);
});

Deno.test("BAND INVARIANT: easy.paceFast never crosses into Moderate, even with hot observed runs", () => {
  // The bug we're guarding against: athlete runs easy at moderate effort
  // (~360–410 sec/mi for a 2:20 marathoner, MP=320 → that's 1.13×–1.28× MP,
  // well into Moderate territory), and the engine reshapes Easy to fit,
  // collapsing the gap between Easy and Steady.
  // With doctrine-only Easy, the band stays put. observed p25 of these
  // is well below doctrine easy.paceFast = 400 (MP × 1.25 = 80% MP speed).
  const tooHotPaces = [355, 360, 365, 370, 375, 380, 390, 395, 405, 410];
  const logs = tooHotPaces.map((p, i) => makeEasyLog(`2026-04-${10 + i}T07:00:00Z`, p));
  const z = computePaceZones({
    ...emptyInput(),
    snapshot: {
      predicted_marathon_seconds: 2 * 3600 + 20 * 60,
      predicted_half_seconds: null,
      predicted_10k_seconds: null,
      predicted_5k_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
    recentLogs: logs,
  });
  assert(z.easy && z.moderate && z.observedEasy);
  // Easy fast bound stays at MP × 1.25 = 400, NOT pulled toward observed p25.
  assertEquals(z.easy.paceFast, 400);
  // Bands remain contiguous — easy.fast == moderate.slow (80% MP speed boundary).
  assertEquals(z.easy.paceFast, z.moderate.paceSlow);
  // The diagnostic correctly reports observed running too hot.
  assert(
    z.observedEasy.paceFast < z.easy.paceFast,
    `observed paceFast ${z.observedEasy.paceFast} should be faster than doctrine easy.paceFast ${z.easy.paceFast} (athlete running easy too hot — that's the signal)`,
  );
});

// ── Race anchor cascades ─────────────────────────────────

Deno.test("10 Mile derives from 10K when only that's present", () => {
  const z = computePaceZones({
    ...emptyInput(),
    snapshot: {
      predicted_10k_seconds: 30 * 60,
      predicted_5k_seconds: null,
      predicted_half_seconds: null,
      predicted_marathon_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
  });
  assert(z.tenMile);
  // 10K pace 290s × 1.025 = 297.25 → 297
  assertEquals(z.tenMile.pace, 297);
  // Confidence steps down from medium → low
  assertEquals(z.tenMile.confidence, "low");
});

Deno.test("3K and 1500m derive when 5K + mile are present", () => {
  const z = computePaceZones({
    ...emptyInput(),
    snapshot: {
      predicted_5k_seconds: 14 * 60 + 30,
      predicted_mile_seconds: 4 * 60 + 18,
      predicted_10k_seconds: null,
      predicted_half_seconds: null,
      predicted_marathon_seconds: null,
      created_at: NOW.toISOString(),
    },
  });
  assert(z.threeK);
  assert(z.fifteenHundred);
});

// ── Bug-fix regression ───────────────────────────────────

Deno.test("REGRESSION: engine never produces 6:16 (the iOS PaceModels bug we replaced)", () => {
  const z = computePaceZones({
    ...emptyInput(),
    snapshot: {
      predicted_marathon_seconds: 2 * 3600 + 20 * 60,
      predicted_half_seconds: null,
      predicted_10k_seconds: null,
      predicted_5k_seconds: null,
      predicted_mile_seconds: null,
      created_at: NOW.toISOString(),
    },
  });
  assert(z.easy);
  // Buggy historical values to never produce: 376/378/384 (the old
  // approximation multipliers). Canonical engine produces 400 (mp × 1.25 =
  // 80% MP speed exactly).
  assert(z.easy.paceFast !== 376, "easy regressed to legacy mp × 1.175 = 6:16");
  assert(z.easy.paceFast !== 378, "easy regressed to intermediate mp × 1.18 = 6:18");
  assert(z.easy.paceFast !== 384, "easy regressed to old approximation mp × 1.20");
  assertEquals(z.easy.paceFast, 400);
});

// ── Ordering invariants ─────────────────────────────────

Deno.test("zone ordering: steady fastest, moderate middle, easy slowest", () => {
  const z = computePaceZones({
    ...emptyInput(),
    plan: { target_race_distance: "marathon", target_time_seconds: 2 * 3600 + 20 * 60 },
  });
  assert(z.easy && z.moderate && z.steady && z.marathon);
  // paceFast = smaller seconds = faster. Steady fast = 100% MP = MP itself.
  assertEquals(z.steady.paceFast, z.marathon.pace, "steady fast bound (100% MP) equals MP");
  // Moderate sits between MP and Easy.
  assert(z.moderate.paceFast > z.marathon.pace, "moderate fast bound should be slower than MP");
  assert(z.moderate.paceFast < z.easy.paceFast, "moderate fast bound should be faster than easy fast bound");
  // Steady spans 90-100% MP; easy spans 70-80% MP. Easy slow > steady slow > steady fast.
  assert(z.easy.paceSlow > z.moderate.paceSlow, "easy slow should be slower than moderate slow");
});

Deno.test("TRAINING_PACE_MULTIPLIERS pinned to canonical % of MP speed calibration", () => {
  // Canonical 10-zone spectrum, MP-anchored. Bands are exact reciprocals
  // of the speed fraction (1/0.7, 1/0.8, 1/0.9, 1/1.0) — not approximations.
  // Bands are contiguous: recovery.fast == easy.slow, easy.fast == moderate.slow, etc.
  assertEquals(TRAINING_PACE_MULTIPLIERS.recovery.fast, 1.4286); // 70% MP speed
  assertEquals(TRAINING_PACE_MULTIPLIERS.recovery.slow, 1.6667); // 60% MP speed (floor)
  assertEquals(TRAINING_PACE_MULTIPLIERS.easy.fast,     1.25);   // 80% MP speed
  assertEquals(TRAINING_PACE_MULTIPLIERS.easy.slow,     1.4286); // 70% MP speed (= recovery.fast)
  assertEquals(TRAINING_PACE_MULTIPLIERS.moderate.fast, 1.1111); // 90% MP speed
  assertEquals(TRAINING_PACE_MULTIPLIERS.moderate.slow, 1.25);   // 80% MP speed (= easy.fast)
  assertEquals(TRAINING_PACE_MULTIPLIERS.steady.fast,   1.0);    // 100% MP speed (= MP)
  assertEquals(TRAINING_PACE_MULTIPLIERS.steady.slow,   1.1111); // 90% MP speed (= moderate.fast)
});

Deno.test("TRAINING_PACE_MULTIPLIERS bands are contiguous (no gaps, no overlaps)", () => {
  assertEquals(
    TRAINING_PACE_MULTIPLIERS.recovery.fast,
    TRAINING_PACE_MULTIPLIERS.easy.slow,
    "recovery.fast must equal easy.slow",
  );
  assertEquals(
    TRAINING_PACE_MULTIPLIERS.easy.fast,
    TRAINING_PACE_MULTIPLIERS.moderate.slow,
    "easy.fast must equal moderate.slow",
  );
  assertEquals(
    TRAINING_PACE_MULTIPLIERS.moderate.fast,
    TRAINING_PACE_MULTIPLIERS.steady.slow,
    "moderate.fast must equal steady.slow",
  );
  assertEquals(
    TRAINING_PACE_MULTIPLIERS.steady.fast,
    1.0,
    "steady.fast must equal 1.0 (MP itself)",
  );
});

// ── Formatters ───────────────────────────────────────────

Deno.test("formatPace: M:SS with zero-padded seconds", () => {
  assertEquals(formatPace(425), "7:05");
  assertEquals(formatPace(320), "5:20");
  assertEquals(formatPace(60), "1:00");
});

Deno.test("formatRange: closed Easy renders as '6:40 – 7:37 /mi'", () => {
  const range = {
    paceFast: 400,
    paceSlow: 457,
    label: "Easy",
    effortPercent: "70-80% MP",
    openEndedSlow: false,
    source: "race_derived" as const,
    confidence: "medium" as const,
  };
  assertEquals(formatRange(range), "6:40 – 7:37 /mi");
});

Deno.test("formatRange: closed Moderate renders as '5:56 – 6:40 /mi'", () => {
  const range = {
    paceFast: 356,
    paceSlow: 400,
    label: "Moderate",
    effortPercent: "80-90% MP",
    openEndedSlow: false,
    source: "race_derived" as const,
    confidence: "medium" as const,
  };
  assertEquals(formatRange(range), "5:56 – 6:40 /mi");
});

// ── Step 6: legacy projection ────────────────────────────

Deno.test("Step 6: projectToLegacyZones for 2:20 marathoner — band midpoints from canonical multipliers", async () => {
  const { legacyZonesFromSnapshot } = await import("./pace-engine.ts");
  const legacy = legacyZonesFromSnapshot({
    predicted_marathon_seconds: 2 * 3600 + 20 * 60,
    predicted_half_seconds: 66 * 60 + 51,
    predicted_10k_seconds: 30 * 60,
    predicted_5k_seconds: 14 * 60 + 30,
    predicted_mile_seconds: 4 * 60 + 18,
  });
  assert(legacy);
  // Canonical band midpoints for MP=320 (midpoint of the UNROUNDED bounds,
  // then rounded — matches iOS easyMPRatio 1.3393: 320 × 1.3393 = 428.6 → 429):
  //   Recovery: (457.1 + 533.3) / 2 = 495 (8:15) — midpoint of 60-70% MP speed
  //   Easy:     (400 + 457.1) / 2 = 429 (7:09) — midpoint of 70-80% MP speed
  //   Moderate: (355.6 + 400) / 2 = 378 (6:18) — midpoint of 80-90% MP speed
  //   Steady:   (320 + 355.6) / 2 = 338 (5:38) — midpoint of 90-100% MP speed
  assertEquals(legacy.recovery, 495);
  assertEquals(legacy.easy, 429);
  assertEquals(legacy.moderate, 378);
  assertEquals(legacy.steady, 338);
  // Race anchors flow through verbatim
  assertEquals(legacy.marathon, 320);
  assertEquals(legacy.halfMarathon, 306);
  assertEquals(legacy.tenK, 290);
  assertEquals(legacy.fiveK, 280);
  assertEquals(legacy.mile, 258);
});

Deno.test("Step 6: projectToLegacyZones returns null with no source data", async () => {
  const { legacyZonesFromSnapshot } = await import("./pace-engine.ts");
  const legacy = legacyZonesFromSnapshot({});
  assertEquals(legacy, null);
});

Deno.test("formatRange: open-ended fallback still renders with '+'", () => {
  const range = {
    paceFast: 400,
    paceSlow: 600,
    label: "Easy",
    effortPercent: "70-80% MP",
    openEndedSlow: true,
    source: "race_derived" as const,
    confidence: "medium" as const,
  };
  assertEquals(formatRange(range), "6:40+ /mi");
});
