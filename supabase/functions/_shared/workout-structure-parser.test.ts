/**
 * Tests for the declared-workout parser (athlete's words → structure).
 * Run: deno test _shared/workout-structure-parser.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  formatDeclared,
  parseDeclaredWorkout,
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
