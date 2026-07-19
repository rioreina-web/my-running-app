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
 *     canonical SPEED midpoints (§6): easy/long 1.3333, moderate 1.1765,
 *     steady 1.0526, recovery 1.5385 — MP÷ratio, NOT the band's arithmetic
 *     (pace) midpoint, which ran ~3 s/mi off.
 *
 * Historical note: this file used to also pin Swift
 * PaceCalculator.calculateTrainingPaces multipliers, but that function was
 * deleted when PaceChartView migrated to consume PaceZonesService (the
 * engine) directly. Multipliers now live in exactly one place: pace-engine.ts.
 */

import { assert, assertEquals, assertAlmostEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { TRAINING_PACE_MULTIPLIERS } from "./pace-engine.ts";

// Swift constants are written as 4-decimal literals (e.g. 1.3333), so the
// comparison against the exact speed midpoints needs a one-unit-in-the-4th-
// decimal tolerance, not exact float equality (e.g. 1/0.75 = 1.33333 → 1.3333).
const SWIFT_LITERAL_TOLERANCE = 0.0001;

// The canonical single-number training pace (§6): the SPEED midpoint of the
// band, expressed as a pace ratio. Engine TRAINING_PACE_MULTIPLIERS are pace
// ratios (1/speed); the speed midpoint pace ratio is 1 / average-of-speeds.
// e.g. easy band [1.25, 1.4286] → speeds [0.80, 0.70] → 1/0.75 = 1.3333.
// (The old convention took the arithmetic mean of the pace ratios — 1.3393 —
// which is ~3 s/mi slower and was the §6 drift.)
function speedMidpointPaceRatio(band: { fast: number; slow: number }): number {
  const avgSpeed = (1 / band.fast + 1 / band.slow) / 2;
  return 1 / avgSpeed;
}

// Resolve repo root from this file's directory: _shared/.. → functions/.. → supabase/.. → repo root
import { dirname, fromFileUrl, join } from "https://deno.land/std@0.224.0/path/mod.ts";
const HERE = dirname(fromFileUrl(import.meta.url));
const REPO_ROOT = join(HERE, "..", "..", "..");

const PACE_MODELS_PATH = join(
  REPO_ROOT,
  "RunningLog/RunningLog/Models/PaceModels.swift",
);

// ── PaceModels.swift midpoint anchors ────────────────────

Deno.test("contract: iOS PaceModels easyMPRatio is the SPEED midpoint of engine easy band (§6)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const swiftValue = parseSwiftConstant(swift, "easyMPRatio");
  const expected = speedMidpointPaceRatio(TRAINING_PACE_MULTIPLIERS.easy);
  assertAlmostEquals(
    swiftValue,
    expected,
    SWIFT_LITERAL_TOLERANCE,
    `PaceModels easyMPRatio (${swiftValue}) must equal the speed midpoint of the engine easy band (${expected.toFixed(4)})`,
  );
});

Deno.test("contract: iOS PaceModels moderateMPRatio is the SPEED midpoint of engine moderate band (§6)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const swiftValue = parseSwiftConstant(swift, "moderateMPRatio");
  assertAlmostEquals(swiftValue, speedMidpointPaceRatio(TRAINING_PACE_MULTIPLIERS.moderate), SWIFT_LITERAL_TOLERANCE);
});

Deno.test("contract: iOS PaceModels steadyMPRatio is the SPEED midpoint of engine steady band (§6)", async () => {
  const swift = await Deno.readTextFile(PACE_MODELS_PATH);
  const swiftValue = parseSwiftConstant(swift, "steadyMPRatio");
  assertAlmostEquals(swiftValue, speedMidpointPaceRatio(TRAINING_PACE_MULTIPLIERS.steady), SWIFT_LITERAL_TOLERANCE);
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

// ── Race-equivalence ratio + raceKeyForInput parity: web ↔ server ───
//
// web workout-helpers.ts RACE_RATIOS_TO_10K is a DUPLICATED literal of the
// server paces.ts table (not an import), so it can silently drift — pin it
// (§10 note). Also pin the raceKeyForInput normalizer: web used to exact-match
// 5 strings and silently default "5K"/"HM"/"3k" to marathon (§8).

function parseWebRaceRatios(src: string): Record<string, number> {
  const block = src.match(/RACE_RATIOS_TO_10K = \{([\s\S]*?)\} as const/);
  assert(block, "web workout-helpers.ts must declare RACE_RATIOS_TO_10K");
  const out: Record<string, number> = {};
  const re = /["']?([a-zA-Z0-9]+)["']?:\s*([0-9.]+)/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(block[1])) !== null) out[m[1]] = parseFloat(m[2]);
  return out;
}

Deno.test("contract: web RACE_RATIOS_TO_10K is digit-identical to server paces.ts (§10)", async () => {
  const { RACE_RATIOS_TO_10K: server } = await import("./paces.ts");
  const web = parseWebRaceRatios(await Deno.readTextFile(WORKOUT_HELPERS_PATH));
  for (const [key, val] of Object.entries(server)) {
    assertEquals(web[key], val, `RACE_RATIOS_TO_10K.${key} differs — web ${web[key]} vs server ${val}`);
  }
});

Deno.test("contract: server raceKeyForInput normalizes case + aliases (§8)", async () => {
  const { raceKeyForInput } = await import("./paces.ts");
  assertEquals(raceKeyForInput("5K"), "fiveK");
  assertEquals(raceKeyForInput("HM"), "half");
  assertEquals(raceKeyForInput("half-marathon"), "half");
  assertEquals(raceKeyForInput("3k"), "threeK");
  assertEquals(raceKeyForInput("10mi"), "tenMi");
  assertEquals(raceKeyForInput("1500"), "1500m");
  assertEquals(raceKeyForInput("  Marathon "), "marathon");
});

Deno.test("contract: web raceKeyForInput lowercases + trims, not exact-match (§8)", async () => {
  const web = await Deno.readTextFile(WORKOUT_HELPERS_PATH);
  const fn = web.match(/function raceKeyForInput\([\s\S]*?\n\}/);
  assert(fn, "web must declare raceKeyForInput");
  assert(
    /toLowerCase\(\)\.trim\(\)/.test(fn[0]),
    "web raceKeyForInput must lowercase+trim (ported from edge) — the old exact-match version silently defaulted 5K/HM/3k to marathon",
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
