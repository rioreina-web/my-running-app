/**
 * Tests for the float/recovery read.
 *
 * The fixtures are REAL `parsed_structure.blocks` pulled from the calibration
 * athlete's logs, trimmed to the fields the classifier reads. Two of them exist
 * specifically to stay NEGATIVE: ordinary interval sessions with a single slow
 * jog that grazes the threshold. If a future change to the line or the session
 * rule flips those, it has relabelled two rep sessions as alternations.
 *
 * Run: deno test _shared/floatLegs.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  floatPaceCeiling,
  paceStringToSeconds,
  readFloatLegs,
  type BlockInput,
} from "./floatLegs.ts";

/** athlete_pace_profiles.marathon_pace_seconds — 5:38/mi, confidence high. */
const MP = 338;

const w = (mi: number, s: number, p: string): BlockInput => ({
  role: "work_rep", distance_miles: mi, duration_s: s, avg_pace_per_mile: p,
});
const r = (mi: number, s: number, p: string, style = "jog"): BlockInput => ({
  role: "recovery", distance_miles: mi, duration_s: s, avg_pace_per_mile: p,
  recovery_style: style,
});

// 21 Jul 2026 — 6×1mi with .25 floats. The library writes this "5 x 3m w/.5 float".
const JUL_21: BlockInput[] = [
  w(1, 328, "5:28"), r(0.26, 98, "6:22"), w(1, 325, "5:25"), r(0.26, 103, "6:30"),
  w(1, 333, "5:33"), r(0.25, 108, "7:05"), w(1, 334, "5:34"), r(0.26, 100, "6:29"),
  w(1, 316, "5:16"), r(0.25, 102, "6:43"), w(1, 331, "5:31"),
];

// 1 Aug 2026 — a long run with eight segments and short floats between them.
const AUG_01: BlockInput[] = [
  w(1, 360, "6:00"), r(0.25, 109, "7:16"), w(2, 761, "6:21"), r(0.24, 110, "7:30"),
  w(1, 359, "5:59"), r(0.25, 108, "7:05"), w(2, 763, "6:22"), r(0.25, 112, "7:29"),
  w(1, 362, "6:02"), r(0.25, 105, "6:57"), w(2, 751, "6:16"), r(0.20, 91, "7:45"),
  w(1, 356, "5:56"), r(0.25, 115, "7:44"), w(2, 765, "6:23"),
];

// 14 Jul 2026 — REAL INTERVALS. Six 20-plus-minute jogs, and two ~9:00 legs that
// sit right on the line. Must NOT read as a float session.
const JUL_14: BlockInput[] = [
  w(0.75, 236, "5:16"), r(0.04, 65, "24:13"), w(0.5, 154, "5:08"), r(0.05, 64, "23:12"),
  w(0.25, 74, "4:53"), r(0.27, 145, "9:04"), w(0.75, 223, "4:56"), r(0.05, 62, "22:10"),
  w(0.5, 149, "4:57"), r(0.04, 61, "24:04"), w(0.25, 73, "4:52"), r(0.27, 153, "9:25"),
  w(0.75, 228, "5:06"), r(0.04, 60, "23:40"), w(0.5, 146, "4:52"), r(0.06, 71, "20:29"),
  w(0.26, 75, "4:49"),
];

// 15 May 2026 — intervals with two STANDING rests whose pace field is an em dash.
const MAY_15: BlockInput[] = [
  w(1, 446, "7:26"), r(0.25, 133, "8:59"), w(0.62, 210, "5:38"), r(0.03, 63, "30:43"),
  w(0.62, 208, "5:36"), r(0.04, 60, "26:23"), w(0.62, 206, "5:30"),
  r(0.25, 618, "—", "standing"), w(0.62, 202, "5:25"),
  r(0.11, 534, "—", "standing"), w(0.18, 48, "4:21"), r(0.08, 124, "27:29"),
  w(0.19, 47, "4:12"),
];

const mmss = (sec: number | null) =>
  sec == null ? null : `${Math.floor(sec / 60)}:${String(Math.round(sec % 60)).padStart(2, "0")}`;

Deno.test("the line sits in the gap between the two populations", () => {
  // Slowest observed float 9:04 (544s), fastest observed recovery 9:25 (565s).
  const ceiling = floatPaceCeiling(MP);
  assert(ceiling > 544, `ceiling ${ceiling} excludes a known float`);
  assert(ceiling < 565, `ceiling ${ceiling} swallows a known recovery`);
});

Deno.test("21 Jul reads as 7.28 continuous miles at 5:40", () => {
  const f = readFloatLegs(JUL_21, MP);
  assert(f.isFloatSession);
  assertEquals(f.fastMiles, 6);
  assertEquals(f.floatMiles, 1.28);
  assertEquals(f.continuousMiles, 7.28);
  assertEquals(mmss(f.fastPaceSec), "5:28");
  assertEquals(mmss(f.floatPaceSec), "6:39");
  assertEquals(mmss(f.aggregatePaceSec), "5:40");
  assertEquals(f.cycles, 6);
});

Deno.test("1 Aug is a 13.69 mile structured long run, not flat aerobic volume", () => {
  // The funnel drew this week's over-distance edge as a flat 6:38 long run.
  // Twelve of these miles are at 6:13.
  const f = readFloatLegs(AUG_01, MP);
  assert(f.isFloatSession);
  assertEquals(f.fastMiles, 12);
  assertEquals(f.floatMiles, 1.69);
  assertEquals(f.continuousMiles, 13.69);
  assertEquals(mmss(f.fastPaceSec), "6:13");
  assertEquals(mmss(f.aggregatePaceSec), "6:22");
});

Deno.test("a single grazing jog does not make an interval session an alternation", () => {
  for (const [name, blocks] of [["14 Jul", JUL_14], ["15 May", MAY_15]] as const) {
    const f = readFloatLegs(blocks, MP);
    assert(!f.isFloatSession, `${name} misread as a float session`);
    assertEquals(f.floatMiles, 0, `${name} counted float miles`);
    assert(f.legs.every((l) => !l.reclassified), `${name} reclassified a leg`);
  }
});

Deno.test("a standing rest is never a float, whatever its pace field says", () => {
  const blocks: BlockInput[] = [
    w(1, 328, "5:28"), r(0.26, 98, "6:22", "standing"),
    w(1, 325, "5:25"), r(0.26, 103, "6:30", "standing"),
  ];
  const f = readFloatLegs(blocks, MP);
  assert(!f.isFloatSession);
  assertEquals(f.floatMiles, 0);
});

Deno.test("no pace profile means no reclassification", () => {
  // A float is defined against the athlete's own MP. With no anchor there is no
  // line, so every leg keeps the role the parser gave it.
  const f = readFloatLegs(JUL_21, null);
  assert(!f.isFloatSession);
  assertEquals(f.floatMiles, 0);
  assertEquals(f.fastMiles, 6, "work legs must still total");
});

Deno.test("reclassifying adds nothing to MP-or-faster volume", () => {
  // Every float is slower than MP, so this read cannot inflate the specific
  // volume metric — it only changes session shape. Guards against a future
  // threshold that would let genuinely fast legs in through the float door.
  for (const blocks of [JUL_21, AUG_01]) {
    const f = readFloatLegs(blocks, MP);
    for (const leg of f.legs.filter((l) => l.kind === "float")) {
      assert(leg.paceSec! > MP, `a float at ${mmss(leg.paceSec)} is at or faster than MP`);
    }
  }
});

Deno.test("pace strings: em dashes, blanks and nonsense are not paces", () => {
  assertEquals(paceStringToSeconds("6:22"), 382);
  assertEquals(paceStringToSeconds("—"), null);
  assertEquals(paceStringToSeconds(""), null);
  assertEquals(paceStringToSeconds(null), null);
  assertEquals(paceStringToSeconds("0:00"), null, "implausibly fast");
  assertEquals(paceStringToSeconds("2:06"), null, "seen on a 0.04mi blip");
  assertEquals(paceStringToSeconds("45:00"), null, "implausibly slow");
});

Deno.test("empty and malformed input degrade quietly", () => {
  for (const bad of [null, undefined, []]) {
    const f = readFloatLegs(bad as never, MP);
    assertEquals(f.continuousMiles, 0);
    assertEquals(f.aggregatePaceSec, null);
  }
  const partial = readFloatLegs([{ role: "work_rep" }, { role: "recovery" }], MP);
  assertEquals(partial.continuousMiles, 0);
});
