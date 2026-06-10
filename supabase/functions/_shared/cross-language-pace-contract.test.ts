/**
 * Cross-language pace contract test.
 *
 * Run: deno test --allow-read _shared/cross-language-pace-contract.test.ts
 *
 * Pins iOS Swift constants to backend TypeScript constants so the chart and
 * the engine never silently disagree. Reads the Swift source files as text
 * and parses out the literal multipliers, then asserts equality against
 * pace-engine.ts.
 *
 * What this protects:
 *   - Editing Swift PaceModels MP ratios without keeping them aligned to the
 *     engine's bands (recovery 1.35, easy/long 1.25, moderate 1.15, steady 1.05).
 *
 * Historical note: this file used to also pin Swift
 * PaceCalculator.calculateTrainingPaces multipliers, but that function was
 * deleted when PaceChartView migrated to consume PaceZonesService (the
 * engine) directly. Multipliers now live in exactly one place: pace-engine.ts.
 */

import { assert, assertEquals, assertAlmostEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { TRAINING_PACE_MULTIPLIERS } from "./pace-engine.ts";

// Swift constants are written as 4-decimal literals (e.g. 1.3393), so the
// comparison against the engine's exact band midpoints needs a one-unit-in-
// the-4th-decimal tolerance, not exact float equality. (Engine midpoints can
// land exactly on the rounding boundary — e.g. 1.18055 → Swift 1.1806.)
const SWIFT_LITERAL_TOLERANCE = 0.0001;

// Resolve repo root from this file's directory: _shared/.. → functions/.. → supabase/.. → repo root
import { dirname, fromFileUrl, join } from "https://deno.land/std@0.224.0/path/mod.ts";
const HERE = dirname(fromFileUrl(import.meta.url));
const REPO_ROOT = join(HERE, "..", "..", "..");

const PACE_MODELS_PATH = join(
  REPO_ROOT,
  "RunningLog/RunningLog/Models/PaceModels.swift",
);

// ── PaceModels.swift midpoint anchors ────────────────────

Deno.test("contract: iOS PaceModels easyMPRatio is the midpoint of engine easy band (75% MP = 1.25)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const swiftValue = parseSwiftConstant(swift, "easyMPRatio");
  const expectedMidpoint = (TRAINING_PACE_MULTIPLIERS.easy.fast + TRAINING_PACE_MULTIPLIERS.easy.slow) / 2;
  assertAlmostEquals(
    swiftValue,
    expectedMidpoint,
    SWIFT_LITERAL_TOLERANCE,
    `PaceModels easyMPRatio (${swiftValue}) must equal midpoint of engine easy band (${expectedMidpoint})`,
  );
});

Deno.test("contract: iOS PaceModels moderateMPRatio is the midpoint of engine moderate band (85% MP = 1.15)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const swiftValue = parseSwiftConstant(swift, "moderateMPRatio");
  const expectedMidpoint = (TRAINING_PACE_MULTIPLIERS.moderate.fast + TRAINING_PACE_MULTIPLIERS.moderate.slow) / 2;
  assertAlmostEquals(swiftValue, expectedMidpoint, SWIFT_LITERAL_TOLERANCE);
});

Deno.test("contract: iOS PaceModels steadyMPRatio is the midpoint of engine steady band (95% MP = 1.05)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const swiftValue = parseSwiftConstant(swift, "steadyMPRatio");
  const expectedMidpoint = (TRAINING_PACE_MULTIPLIERS.steady.fast + TRAINING_PACE_MULTIPLIERS.steady.slow) / 2;
  assertAlmostEquals(swiftValue, expectedMidpoint, SWIFT_LITERAL_TOLERANCE);
});

Deno.test("contract: iOS PaceModels longRunMPRatio equals easy midpoint (long convention)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const longValue = parseSwiftConstant(swift, "longRunMPRatio");
  const easyValue = parseSwiftConstant(swift, "easyMPRatio");
  assertEquals(
    longValue,
    easyValue,
    "longRunMPRatio should equal easyMPRatio (long run = easy effort by convention)",
  );
});

Deno.test("contract: iOS PaceModels recoveryMPRatio is slower than easy slow bound", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const recoveryValue = parseSwiftConstant(swift, "recoveryMPRatio");
  assert(
    recoveryValue >= TRAINING_PACE_MULTIPLIERS.easy.slow,
    `recoveryMPRatio (${recoveryValue}) should be ≥ easy.slow (${TRAINING_PACE_MULTIPLIERS.easy.slow}) — recovery is slower than easy floor`,
  );
});

// ── Web workout-helpers.ts ↔ server paces.ts ratio parity ───────────
//
// THE Maya bug from outputs/phase-2-race-anchoring-plan-2026-06-04.md
// sub-task B: web and server carried different TRAINING_MP_SPEED_RATIO
// band conventions, so the same MP produced different easy paces on the
// coach portal vs. the edge functions. Canonical values per
// outputs/pace-chart-unified-spec-2026-06-04.md — these tests parse the
// web source as text (like the Swift tests) and pin both sides together.

const WORKOUT_HELPERS_PATH = join(
  REPO_ROOT,
  "web/src/components/coach/workout-helpers.ts",
);

function parseWebRatio(src: string, key: string): number {
  const block = src.match(/TRAINING_MP_SPEED_RATIO = \{([\s\S]*?)\} as const/);
  assert(block, "web workout-helpers.ts must declare TRAINING_MP_SPEED_RATIO");
  const m = block[1].match(new RegExp(`${key}:\\s*([0-9.]+)`));
  assert(m, `web TRAINING_MP_SPEED_RATIO must contain '${key}'`);
  return parseFloat(m[1]);
}

Deno.test("contract: web and server TRAINING_MP_SPEED_RATIO are identical (steady/moderate/easy/longRun/recovery)", async () => {
  const { TRAINING_MP_SPEED_RATIO: server } = await import("./paces.ts");
  const webSrc = await Deno.readTextFile(WORKOUT_HELPERS_PATH);
  for (const key of ["steady", "moderate", "longRun", "easy", "recovery"] as const) {
    assertEquals(
      parseWebRatio(webSrc, key),
      server[key],
      `TRAINING_MP_SPEED_RATIO.${key} differs between web and server — same MP would render different ${key} paces`,
    );
  }
});

Deno.test("contract: server ratio midpoints match the engine's band midpoints (steady/moderate/easy)", async () => {
  const { TRAINING_MP_SPEED_RATIO: server } = await import("./paces.ts");
  for (const key of ["steady", "moderate", "easy"] as const) {
    // Engine multipliers are pace ratios (1/speed); the speed-ratio midpoint
    // of the band [fast, slow] is (1/fast + 1/slow) / 2 in speed terms.
    const band = TRAINING_PACE_MULTIPLIERS[key];
    const speedMidpoint = (1 / band.fast + 1 / band.slow) / 2;
    assertAlmostEquals(
      server[key],
      speedMidpoint,
      0.005,
      `paces.ts ${key} (${server[key]}) should sit at the engine band's speed midpoint (${speedMidpoint.toFixed(4)})`,
    );
  }
});

// ── PaceModels.NamedPace.mpPaceMultipliers (engine-aligned bands) ────
//
// Pins the slow-zone bands consumed by `displayPaceRange` in workout-step UI
// to the engine's TRAINING_PACE_MULTIPLIERS. Every range the user sees in a
// workout step must come from the same numbers as the chart.

Deno.test("contract: iOS NamedPace.easy.fast multiplier == engine easy.fast", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const m = parseMpPaceMultiplier(swift, "easy");
  assertEquals(
    m.fast,
    TRAINING_PACE_MULTIPLIERS.easy.fast,
    `NamedPace.easy.fast (${m.fast}) must equal engine easy.fast (${TRAINING_PACE_MULTIPLIERS.easy.fast})`,
  );
});

Deno.test("contract: iOS NamedPace.easy.slow multiplier == engine easy.slow", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const m = parseMpPaceMultiplier(swift, "easy");
  assertEquals(m.slow, TRAINING_PACE_MULTIPLIERS.easy.slow);
});

Deno.test("contract: iOS NamedPace.moderate.fast multiplier == engine moderate.fast", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const m = parseMpPaceMultiplier(swift, "moderate");
  assertEquals(m.fast, TRAINING_PACE_MULTIPLIERS.moderate.fast);
});

Deno.test("contract: iOS NamedPace.moderate.slow multiplier == engine moderate.slow", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const m = parseMpPaceMultiplier(swift, "moderate");
  assertEquals(m.slow, TRAINING_PACE_MULTIPLIERS.moderate.slow);
});

Deno.test("contract: iOS NamedPace.steady.fast multiplier == engine steady.fast", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const m = parseMpPaceMultiplier(swift, "steady");
  assertEquals(m.fast, TRAINING_PACE_MULTIPLIERS.steady.fast);
});

Deno.test("contract: iOS NamedPace.steady.slow multiplier == engine steady.slow", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const m = parseMpPaceMultiplier(swift, "steady");
  assertEquals(m.slow, TRAINING_PACE_MULTIPLIERS.steady.slow);
});

Deno.test("contract: iOS NamedPace.longRun mirrors easy band (long-run convention)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const easy = parseMpPaceMultiplier(swift, "easy");
  const longRun = parseMpPaceMultiplier(swift, "longRun");
  assertEquals(longRun.fast, easy.fast, "longRun.fast must equal easy.fast");
  assertEquals(longRun.slow, easy.slow, "longRun.slow must equal easy.slow");
});

Deno.test("contract: iOS NamedPace.recovery starts no faster than the easy floor", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const recovery = parseMpPaceMultiplier(swift, "recovery");
  assert(
    recovery.fast >= TRAINING_PACE_MULTIPLIERS.easy.slow,
    `recovery.fast (${recovery.fast}) should be ≥ easy.slow (${TRAINING_PACE_MULTIPLIERS.easy.slow}) — recovery is slower than easy floor`,
  );
});

Deno.test("contract: iOS NamedPace bands are contiguous (steady.slow == moderate.fast)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const steady = parseMpPaceMultiplier(swift, "steady");
  const moderate = parseMpPaceMultiplier(swift, "moderate");
  assertEquals(
    steady.slow,
    moderate.fast,
    "steady's slow bound must equal moderate's fast bound — bands are contiguous",
  );
});

Deno.test("contract: iOS NamedPace bands are contiguous (moderate.slow == easy.fast)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const moderate = parseMpPaceMultiplier(swift, "moderate");
  const easy = parseMpPaceMultiplier(swift, "easy");
  assertEquals(
    moderate.slow,
    easy.fast,
    "moderate's slow bound must equal easy's fast bound — bands are contiguous",
  );
});

// ── Helpers ──────────────────────────────────────────────

/**
 * Parse a Swift `static let xMPRatio: Double = 1.25` declaration.
 * Returns the literal value.
 */
function parseSwiftConstant(source: string, name: string): number {
  const re = new RegExp(`static\\s+let\\s+${name}\\s*:\\s*Double\\s*=\\s*(\\d+\\.\\d+)`);
  const match = source.match(re);
  if (!match) {
    throw new Error(`Could not find Swift constant ${name} in source`);
  }
  return parseFloat(match[1]);
}

/**
 * Parse a `case` line in Swift `NamedPace.mpPaceMultipliers`, e.g.
 *   case .easy:      return (fast: 1.20, slow: 1.30)
 * Returns { fast, slow } as numbers.
 */
function parseMpPaceMultiplier(source: string, caseName: string): { fast: number; slow: number } {
  const re = new RegExp(
    `case\\s+\\.${caseName}\\s*:\\s*return\\s*\\(\\s*fast\\s*:\\s*(\\d+\\.\\d+)\\s*,\\s*slow\\s*:\\s*(\\d+\\.\\d+)\\s*\\)`,
  );
  const match = source.match(re);
  if (!match) {
    throw new Error(`Could not find mpPaceMultipliers case .${caseName} in PaceModels.swift`);
  }
  return { fast: parseFloat(match[1]), slow: parseFloat(match[2]) };
}
