/**
 * Tests for the declared-workout parser (athlete's words → structure).
 * Run: deno test _shared/workout-structure-parser.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  formatDeclared,
  parseDeclaredWorkout,
  parsePace,
  parseDistanceMeters,
  type PaceSpec,
} from "./workout-structure-parser.ts";

const MILE = 1609.344;
const near = (a: number, b: number, tol = 1) => Math.abs(a - b) <= tol;

Deno.test("alternation: total-distance form → reps from cycle", () => {
  const w = parseDeclaredWorkout("8mi alternation, mile at 104% MP / mile at 90% MP");
  assertEquals(w.kind, "alternation");
  assertEquals(w.reps, 4); // 8mi / (1mi + 1mi)
  assertEquals(w.block.length, 2);
  assertEquals(w.block[0].pace, { kind: "pct", ofZone: "mp", pct: 104 } as PaceSpec);
  assertEquals(w.block[1].pace, { kind: "pct", ofZone: "mp", pct: 90 } as PaceSpec);
  assert(formatDeclared(w).includes("104% MP"));
  assert(formatDeclared(w).includes("alternation"));
});

Deno.test("alternation: explicit Nx(...) form", () => {
  const w = parseDeclaredWorkout("4x(1mi @ HMP / 1mi @ MP)");
  assertEquals(w.kind, "alternation");
  assertEquals(w.reps, 4);
  assert(near(w.block[0].distanceMeters!, MILE));
});

Deno.test("intervals: reps + distance + pace + recovery", () => {
  const w = parseDeclaredWorkout("6x800m @ 5K w/ 90s jog");
  assertEquals(w.kind, "intervals");
  assertEquals(w.reps, 6);
  assert(near(w.block[0].distanceMeters!, 800));
  assertEquals(w.block[0].pace, { kind: "zone", zone: "5k" } as PaceSpec);
  assertEquals(w.recovery?.durationSeconds, 90);
});

Deno.test("threshold: long reps read as threshold, not intervals", () => {
  const w = parseDeclaredWorkout("2x3mi at threshold");
  assertEquals(w.kind, "threshold");
  assertEquals(w.reps, 2);
  assert(near(w.block[0].distanceMeters!, 3 * MILE, 2));
});

Deno.test("explicit pace 5:07 parses to seconds/mile", () => {
  const w = parseDeclaredWorkout("9x1k @ 5:07");
  assertEquals(w.reps, 9);
  assertEquals(w.block[0].pace, { kind: "explicit", secPerMile: 307 } as PaceSpec);
});

Deno.test("continuous tempo with distance + pace", () => {
  const w = parseDeclaredWorkout("4 mile tempo at MP");
  assertEquals(w.kind, "tempo");
  assertEquals(w.reps, 1);
  assertEquals(w.block[0].pace, { kind: "zone", zone: "mp" } as PaceSpec);
});

Deno.test("time-based tempo", () => {
  const w = parseDeclaredWorkout("20 min tempo");
  assertEquals(w.reps, 1);
  assertEquals(w.block[0].durationSeconds, 1200);
});

Deno.test("easy run is not a tempo", () => {
  assertEquals(parseDeclaredWorkout("easy 6 miles").kind, "easy");
});

Deno.test("long run", () => {
  assertEquals(parseDeclaredWorkout("16 mile long run").kind, "long_run");
});

Deno.test("unrecognized text degrades to unknown (never throws)", () => {
  const w = parseDeclaredWorkout("felt sluggish, legs heavy");
  assertEquals(w.kind, "unknown");
});

// ── regressions from real athlete notes (2026-08-17) ───────────────────────
//
// These strings are verbatim from prod. Every one of them parsed WRONG, and
// most reported high confidence while doing it — which is worse than not
// parsing, because a confident wrong prescription would have had the fitness
// model judge threshold sessions against recovery pace.

Deno.test("a leading decimal is not dropped — '.25 mile' is not 25 miles", () => {
  assert(near(parseDistanceMeters(".25 mile recoveries")!, 0.25 * MILE, 2));
  assert(near(parseDistanceMeters(".5k float")!, 500, 2));
  // The real note that exposed it read as a 40 km block.
  const w = parseDeclaredWorkout(
    "six miles, starting at marathon pace and dropping to half marathon pace, with .25 mile recoveries",
  );
  assert(
    (w.totalDistanceMeters ?? 0) < 20000,
    `parsed ${Math.round((w.totalDistanceMeters ?? 0) / 1000)}km from a six-mile session`,
  );
});

Deno.test("the REST being easy does not make the SESSION easy", () => {
  const w = parseDeclaredWorkout("4 x 3mi @ MP-5 w/800m easy");
  assertEquals(w.kind, "threshold");
  assertEquals(w.reps, 4);
  assert(near(w.block[0].distanceMeters!, 3 * MILE, 3));
});

Deno.test("the REST being recovery does not make the SESSION a recovery run", () => {
  for (const s of [
    "four repeated sets of 1 mile at a 6-minute pace followed by 2 miles at a 6:25 pace, with 400m recovery after each segment",
    "a threshold session today with 5x4 minute efforts and jog recovery",
    "2 × ~2mi tempo/threshold efforts with standing recovery",
  ]) {
    const w = parseDeclaredWorkout(s);
    assert(w.kind !== "recovery", `"${s.slice(0, 40)}…" read as a recovery run`);
    assert(
      w.block.every((b) => !(b.pace?.kind === "zone" && b.pace.zone === "recovery")),
      `"${s.slice(0, 40)}…" assigned recovery pace to the WORK`,
    );
  }
});

Deno.test("a genuine recovery run still parses as one", () => {
  const w = parseDeclaredWorkout("easy 5 mile recovery run");
  assertEquals(w.kind, "recovery");
});

// ── Offsets from a zone ─────────────────────────────────────────
//
// Regression pack for the silent pace drop: every form below used to come back
// as a bare `mp` zone at confidence "high", so an alternation's fast and float
// legs were stored as the SAME pace with nothing to signal the loss.

Deno.test("MP+N% / MP-N% keep the two legs of an alternation apart", () => {
  const w = parseDeclaredWorkout("1k @ MP+5% / 1k @ MP-5% for 20k");
  assertEquals(w.kind, "alternation");
  assertEquals(w.reps, 10);
  assertEquals(w.totalDistanceMeters, 20000);
  const [slow, fast] = w.block.map((b) => b.pace);
  assertEquals(slow?.kind, "pct");
  assertEquals(fast?.kind, "pct");
  // MINUS IS FASTER. `pct` is a percentage of zone SPEED, so the fast leg must
  // exceed 100 and the slow leg must fall below it.
  assert((fast as { pct: number }).pct > 100, "MP-5% must be faster than MP");
  assert((slow as { pct: number }).pct < 100, "MP+5% must be slower than MP");
  assert((fast as { pct: number }).pct !== (slow as { pct: number }).pct);
});

Deno.test("MP-N / MP+N read as seconds per mile, minus being faster", () => {
  assertEquals(parsePace("MP-10"), { kind: "relative", ofZone: "mp", deltaSec: 10, faster: true });
  assertEquals(parsePace("MP+30"), { kind: "relative", ofZone: "mp", deltaSec: 30, faster: false });
  assertEquals(parsePace("MP minus 10"), { kind: "relative", ofZone: "mp", deltaSec: 10, faster: true });
});

Deno.test("a minute suffix is minutes, not seconds", () => {
  // "w/800 float MP+1'" — the float is 60s/mi slower, not 1s/mi.
  assertEquals(parsePace("MP+1'"), { kind: "relative", ofZone: "mp", deltaSec: 60, faster: false });
});

Deno.test("an offset relative to MP is still MP work for kind inference", () => {
  assertEquals(parseDeclaredWorkout("4 x 3mi @ MP-5 w/800m easy").kind, "threshold");
});

Deno.test("an undecodable offset degrades loudly, never to a bare zone", () => {
  const p = parsePace("MP+about a minute");
  assertEquals(p?.kind, "effort", "an operator we cannot decode must not return a confident zone");
  const w = parseDeclaredWorkout("6 x 1 mile @ MP+about a minute");
  assert(w.confidence !== "high", `unparsed pace must not stay high, got ${w.confidence}`);
  assert((w.note ?? "").includes("unparsed pace"), `expected a note, got ${w.note}`);
});
