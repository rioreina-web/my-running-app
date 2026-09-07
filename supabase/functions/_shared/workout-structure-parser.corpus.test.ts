/**
 * Corpus test — the parser measured against the coach's ACTUAL notation.
 *
 * WHY THIS EXISTS. Unit tests only ever check the spellings someone thought to
 * write down, so the parser looked healthy while failing on the real sheets.
 * `session-library.json` is 148 sessions lifted verbatim from those sheets, and
 * its `kind` / `totalMiles` fields were authored independently of this parser —
 * which makes it a free labelled corpus and the only honest scoreboard we have.
 *
 * It found two things a unit test could not:
 *   1. The unparsed-pace guard fired on "2 x 4mi hilly steady - Lollipop",
 *      where " - " introduces a route name, not an offset. Hence the
 *      attached-sign-vs-spaced-hyphen rule in `parsePace`.
 *   2. A THIRD of the distances the parser is confident about are wrong by more
 *      than 2x, and 38% of the corpus does not parse at all.
 *
 * These are CEILINGS, not targets. Improving the parser lowers them and the
 * test still passes; regressing raises them and it fails. When you lower one,
 * update the number here in the same commit.
 *
 * Run: deno test _shared/workout-structure-parser.corpus.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { parseDeclaredWorkout, parsePace } from "./workout-structure-parser.ts";

const MILE = 1609.344;
const lib: Array<{ text: string; kind: string; totalMiles: number | null }> =
  JSON.parse(await Deno.readTextFile(new URL("./session-library.json", import.meta.url)));

Deno.test("corpus: the library is big enough to be a scoreboard", () => {
  assert(lib.length >= 148, `corpus shrank to ${lib.length}`);
});

Deno.test("corpus: unrecognized sessions do not grow past today's 56/148", () => {
  const unknown = lib.filter((s) => parseDeclaredWorkout(s.text).kind === "unknown");
  assert(
    unknown.length <= 56,
    `${unknown.length} of ${lib.length} unparsed (ceiling 56). New failures:\n` +
      unknown.slice(0, 5).map((s) => `  ${s.text}`).join("\n"),
  );
});

Deno.test("corpus: confident distances do not get wronger", () => {
  const bad: string[] = [];
  let comparable = 0;
  for (const s of lib) {
    const w = parseDeclaredWorkout(s.text);
    if (s.totalMiles == null || w.totalDistanceMeters == null) continue;
    comparable++;
    const ratio = w.totalDistanceMeters / MILE / s.totalMiles;
    if (ratio < 0.5 || ratio > 2) bad.push(`  ${s.text}  (sheet ${s.totalMiles}mi, parsed ${(w.totalDistanceMeters / MILE).toFixed(1)}mi)`);
  }
  assert(comparable >= 30, `only ${comparable} rows carry a sheet total`);
  assert(
    bad.length <= 12,
    `${bad.length}/${comparable} distances off by >2x (ceiling 12):\n${bad.slice(0, 6).join("\n")}`,
  );
});

Deno.test("corpus: a spaced hyphen is never read as a pace offset", () => {
  // Both of these end in a route name after " - ". Neither is an unparsed pace.
  for (const text of [
    "2 x 4mi hilly steady - Lollipop",
    "8m steady + 3 x 3mi w/1 mi float + 1-2m easy - PD",
  ]) {
    const w = parseDeclaredWorkout(text);
    assert(
      !(w.note ?? "").includes("unparsed pace"),
      `"${text}" flagged a pace it does not have: ${w.note}`,
    );
  }
});

Deno.test("corpus: a real offset never decodes as a bare zone", () => {
  // Token level — this is `parsePace`'s job. Session-level assembly is a
  // separate (and much weaker) concern, characterised further down.
  //
  // Sibling trap: in "4mi at MP + 2 x 1mi @ HM" the plus JOINS SEGMENTS, so a
  // naive /MP\s*[+-]\s*\d/ sweep flags 15 corpus rows carrying no offset at
  // all. Test the token, not the row.
  for (const [text, why] of [
    ["2mi tempo (MP-5)", "parenthesised"],
    ["3' medium (MP+45)", "float leg"],
    ["10-12 x K @ HM-5", "offset on HM"],
    ["MP+1'", "minute suffix"],
  ] as const) {
    const p = parsePace(text);
    assert(p != null, `${why}: "${text}" produced no pace`);
    assert(
      p!.kind === "relative" || p!.kind === "pct",
      `${why}: "${text}" lost its offset — got ${p!.kind}`,
    );
  }
});

Deno.test("corpus: a joining plus is not read as an offset", () => {
  // The inverse failure. These must NOT invent an offset.
  for (const text of ["4mi at MP + 2 x 1mi @ HM", "15' LT + 6x1k @ 10k w/90s rest"]) {
    const p = parsePace(text);
    assert(
      p?.kind !== "relative",
      `"${text}" joins two segments with a plus; it has no offset, got ${JSON.stringify(p)}`,
    );
  }
});

// ── Known gaps, characterised ───────────────────────────────────
//
// These assert the CURRENT BROKEN NUMBERS on purpose. If one fails because you
// improved the parser, that is the intended outcome: update the number here and
// keep going. They exist so the gaps stay visible instead of being rediscovered.

Deno.test("KNOWN GAP: only the first zone in a session survives", () => {
  // "4 x 2Mi cutdown - 3' rec - MP > HM-10" carries two zones and an offset on
  // the second. `parsePace` returns ONE spec, so the HM-10 is dropped. Cutdowns
  // and progressions are defined by having more than one zone, so this is the
  // gap that makes `progression` near-useless (3 detected in 148).
  const p = parsePace("4 x 2Mi cutdown - 3' rec - MP > HM-10");
  assertEquals(p?.kind, "zone", "multi-zone handling changed — update this test");
});

Deno.test("KNOWN GAP: alternations are detected 0/36", () => {
  // The coach's most common specific session is the one the parser cannot see.
  // "8-12m alternations (MP-10/MP+30)" returns kind `tempo` with 12 METRES —
  // paces now correct, geometry not: the range "8-12m" reads as a 12m distance.
  const labelled = lib.filter((s) => s.kind === "alternation");
  const detected = labelled.filter((s) => parseDeclaredWorkout(s.text).kind === "alternation");
  assertEquals(labelled.length, 36, "library alternation count moved");
  assertEquals(detected.length, 0, "alternation detection changed — update this number");
});

Deno.test("KNOWN GAP: 54 of 71 compound sessions collapse to one block", () => {
  // `block` is an array, but only the alternation matcher ever fills more than
  // one. So "2mi tempo (MP-5) + 4x400m @ 10k" keeps the 400s and discards the
  // tempo — a structural silent drop, the same shape as the pace one.
  const compound = lib.filter((s) => /\+/.test(s.text));
  const collapsed = compound.filter((s) => {
    const w = parseDeclaredWorkout(s.text);
    return w.kind !== "unknown" && w.block.length < 2;
  });
  assertEquals(compound.length, 71, "compound count moved");
  assertEquals(collapsed.length, 54, "compound handling changed — update this number");
});
