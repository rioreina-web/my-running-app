// Golden + corpus regression suite for the coach-shorthand parser.
//
// Two layers, deliberately different in kind:
//
//   1. GOLDENS (`coach-shorthand-goldens.json`) — hand-authored expectations,
//      one per behaviour we care about. These are exact. If one fails, a
//      real capability broke.
//
//   2. CORPUS (`coach-shorthand-corpus.json`) — 137 unique workouts lifted
//      verbatim from six seasons of this coach's real plans (Fall23, Fall24,
//      Spring24, SoS24, Spring25, Spring26). We do NOT assert exact output
//      for these — nobody has hand-expanded 137 workouts. Instead they carry
//      two guarantees:
//        a) INVARIANTS that must hold for every single one (no impossible
//           paces, no absurd distances, no invented pace zones, never throws)
//        b) A COVERAGE RATCHET — the count that parses with no warnings and
//           no unparsed fragments must not fall below CLEAN_FLOOR.
//
// READ THIS BEFORE CHANGING CLEAN_FLOOR. The invariants are the real gate,
// not the coverage number. "Clean" means the parser reported nothing — so a
// fix that turns a silent wrong answer into an honest warning makes the
// product BETTER and the coverage number WORSE. That happened during the
// August 2026 pass: teaching the parser that "6-7 x mile threshold" specifies
// a distance and not a pace moved 8 workouts from silently-mile-pace to
// correctly-warned, and clean coverage fell 63 → 55.
//
// So: never chase this number by removing a warning. Lower the floor only
// alongside a note saying which silence became a warning, and raise it when
// real grammar coverage improves.
//
// Run: cd web && npm run test:smoke

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

import { parseWorkoutText } from "@/components/coach/workout-nl-parser";
import type { WorkoutStep } from "@/components/coach/workout-helpers";

const HERE = dirname(fileURLToPath(import.meta.url));
const readFixture = (name: string) =>
  JSON.parse(readFileSync(join(HERE, "..", "fixtures", name), "utf8"));

// ── Bounds. Mirror the parser's own guards; if these drift the test is
//    no longer checking what the parser promises.
const MIN_PACE = 240;   // 4:00/mi
const MAX_PACE = 1200;  // 20:00/mi
const MAX_STEP_MILES = 30;

const MILES_PER = { distance_miles: 1, distance_km: 1 / 1.609344, distance_meters: 1 / 1609.344, time_seconds: 0 };
const stepMiles = (s: WorkoutStep) => s.durationValue * MILES_PER[s.durationType];

// ── Layer 1: goldens ─────────────────────────────────────

interface Golden {
  why: string;
  input: string;
  steps?: Array<Partial<WorkoutStep> & { recovery?: { durationValue?: number; durationType?: string } }>;
  unparsed?: string[];
  warnings?: string[];
  warningsInclude?: string[];
  /** number of steps whose pace the parser could not resolve */
  unresolvedCount?: number;
  stepCount?: number;
  /** when true, `steps` checks only the first N steps of a longer expansion */
  stepsArePrefix?: boolean;
  unparsedInclude?: string[];
  forbidUnparsedText?: string[];
  forbid?: { maxStepMiles?: number; exactPaceOutsideSecPerMile?: [number, number] };
}

const goldens: Golden[] = readFixture("coach-shorthand-goldens.json");

for (const g of goldens) {
  test(`golden: ${g.why}`, () => {
    const { steps, unparsed, warnings, unresolved } = parseWorkoutText(g.input);
    const ctx = `\n  input:    ${g.input}\n  unresolved: ${JSON.stringify(unresolved)}\n  steps:    ${JSON.stringify(steps)}\n  unparsed: ${JSON.stringify(unparsed)}\n  warnings: ${JSON.stringify(warnings)}`;

    if (g.stepCount != null) assert.equal(steps.length, g.stepCount, `step count${ctx}`);

    if (g.steps) {
      if (!g.stepsArePrefix) assert.equal(steps.length, g.steps.length, `step count${ctx}`);
      g.steps.forEach((want, i) => {
        const got = steps[i];
        for (const [k, v] of Object.entries(want)) {
          if (k === "recovery") {
            assert.ok(got.recovery, `step ${i} should have a recovery${ctx}`);
            for (const [rk, rv] of Object.entries(v as Record<string, unknown>)) {
              assert.equal(
                (got.recovery as unknown as Record<string, unknown>)[rk], rv,
                `step ${i} recovery.${rk}${ctx}`,
              );
            }
          } else {
            assert.equal((got as unknown as Record<string, unknown>)[k], v, `step ${i} .${k}${ctx}`);
          }
        }
      });
    }

    if (g.unresolvedCount != null) {
      assert.equal(Object.keys(unresolved).length, g.unresolvedCount, `unresolved count${ctx}`);
    }
    if (g.unparsed) assert.deepEqual(unparsed, g.unparsed, `unparsed${ctx}`);
    if (g.warnings) assert.deepEqual(warnings, g.warnings, `warnings${ctx}`);

    for (const frag of g.warningsInclude ?? []) {
      assert.ok(warnings.some((w) => w.includes(frag)), `expected a warning containing "${frag}"${ctx}`);
    }
    for (const frag of g.unparsedInclude ?? []) {
      assert.ok(unparsed.join(" ").includes(frag), `expected unparsed to mention "${frag}"${ctx}`);
    }
    for (const frag of g.forbidUnparsedText ?? []) {
      assert.ok(!unparsed.join(" ").includes(frag), `unparsed must NOT invent "${frag}"${ctx}`);
    }

    if (g.forbid?.maxStepMiles != null) {
      for (const s of steps) {
        assert.ok(stepMiles(s) <= g.forbid.maxStepMiles, `step of ${stepMiles(s).toFixed(1)}mi exceeds cap${ctx}`);
      }
    }
    if (g.forbid?.exactPaceOutsideSecPerMile) {
      const [lo, hi] = g.forbid.exactPaceOutsideSecPerMile;
      for (const s of steps) {
        if (s.exactPaceSecPerMile != null) {
          assert.ok(s.exactPaceSecPerMile >= lo && s.exactPaceSecPerMile <= hi, `pace ${s.exactPaceSecPerMile}s/mi out of bounds${ctx}`);
        }
      }
    }
  });
}

// ── Layer 2: corpus invariants ───────────────────────────

interface CorpusEntry { sheet: string; input: string }
const corpus: CorpusEntry[] = readFixture("coach-shorthand-corpus.json");

test("corpus: 137 real workouts, six seasons", () => {
  assert.ok(corpus.length >= 130, `corpus shrank to ${corpus.length} — did a fixture get truncated?`);
});

test("corpus invariant: never throws on real coach shorthand", () => {
  for (const { input, sheet } of corpus) {
    assert.doesNotThrow(() => parseWorkoutText(input), `[${sheet}] ${input}`);
  }
});

test("corpus invariant: no impossible pace ever reaches a step", () => {
  for (const { input, sheet } of corpus) {
    for (const s of parseWorkoutText(input).steps) {
      if (s.exactPaceSecPerMile == null) continue;
      assert.ok(
        s.exactPaceSecPerMile >= MIN_PACE && s.exactPaceSecPerMile <= MAX_PACE,
        `[${sheet}] "${input}" produced ${s.exactPaceSecPerMile}s/mi`,
      );
    }
  }
});

test("corpus invariant: no absurd step distance passes without a warning", () => {
  for (const { input, sheet } of corpus) {
    const { steps, warnings } = parseWorkoutText(input);
    for (const s of steps) {
      if (stepMiles(s) > MAX_STEP_MILES) {
        assert.ok(warnings.length > 0, `[${sheet}] "${input}" made a ${stepMiles(s).toFixed(0)}mi step silently`);
      }
    }
  }
});

// The rule the audit was built around: a pace zone the coach never wrote must
// never appear without the coach being told. `easy` is the declared fallback,
// so seeing it on an active step is only legal alongside a warning.
test("corpus invariant: an unwritten pace zone always comes with a warning", () => {
  const ZONE_TOKENS: Array<[RegExp, string]> = [
    [/\b5k\b/i, "fiveK"], [/\b10k\b/i, "tenK"], [/\b3k\b/i, "threeK"],
    [/\bmile\b/i, "mile"], [/\bmp\b|\bmarathon\b/i, "mp"], [/\bhmp?\b|\bhalf\b/i, "hm"],
    [/\blt\b|\bthreshold\b|\btempo\b/i, "threshold"],
    [/\brec\b|\brecovery\b/i, "recovery"], [/\beasy\b/i, "easy"],
    [/\bmod\b|\bmoderate\b|\bmedium\b/i, "moderate"], [/\bsteady\b/i, "steady"],
  ];
  for (const { input, sheet } of corpus) {
    const { steps, warnings, unresolved } = parseWorkoutText(input);
    for (const s of steps) {
      if (s.stepType !== "active") continue;
      const written = ZONE_TOKENS.some(([reg, zone]) => zone === s.paceZone && reg.test(input));
      const explicit = s.exactPaceSecPerMile != null;
      if (!written && !explicit) {
        // Either channel satisfies the rule: a prose warning, or a structured
        // question against this step id.
        const flagged = warnings.length > 0 || unresolved[s.id] != null;
        assert.ok(
          flagged,
          `[${sheet}] "${input}" assigned ${s.paceZone} with nothing in the text and no flag`,
        );
      }
    }
  }
});

// ── Layer 2b: the coverage ratchet ───────────────────────

// Raise this when you improve the parser. Never lower it to make a build pass.
//   2026-08-25  33/137 → 63/137 — bare-m miles, tempo→threshold, no invented
//               zones, ascending-range guard, plausibility bounds.
//   2026-08-25  63/137 → 55/137 (40%) — DELIBERATE DROP. The bare-unit-word
//               fix stopped "N x mile <zone>" from reading the distance word
//               as the pace; those 8 now warn instead of guessing.
//   2026-08-25  55/137 → 58/137 (42%) — compound sets expand leg by leg
//               instead of being refused outright.
//   2026-08-25  58/137 → 61/137 (45%) — ladders ("600/400 @ 5k/3k"),
//               progressions ("MP > HM" → note), parenthetical paces and
//               notes, "at" only before a pace, bare zone words in set legs,
//               "effort" suffix, trailing pace after a recovery clause.
//
// NOTE the more useful number, which this floor does not capture: 130/137
// (95%) now BUILD a complete workout. 69 of those carry a "confirm this pace"
// warning because the coach genuinely wrote no pace for that leg. Only 3
// produce nothing at all and 4 leave text unparsed.
const CLEAN_FLOOR = 58;

test(`corpus coverage: at least ${CLEAN_FLOOR} workouts parse with no warnings and nothing unparsed`, () => {
  const clean = corpus.filter(({ input }) => {
    const r = parseWorkoutText(input);
    // `unresolved` counts. When the "no pace" messages moved out of `warnings`
    // and became structured questions, omitting it here jumped the score from
    // 61 to 122 without a single workout parsing better.
    return r.steps.length > 0 && r.unparsed.length === 0 &&
      r.warnings.length === 0 && Object.keys(r.unresolved).length === 0;
  });
  const pct = Math.round((clean.length / corpus.length) * 100);
  assert.ok(
    clean.length >= CLEAN_FLOOR,
    `coverage fell to ${clean.length}/${corpus.length} (${pct}%), below the ${CLEAN_FLOOR} floor`,
  );
  console.log(`      corpus coverage: ${clean.length}/${corpus.length} (${pct}%)`);
});
