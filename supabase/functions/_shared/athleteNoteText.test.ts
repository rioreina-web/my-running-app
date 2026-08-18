/**
 * Tests for the athlete-voice filter.
 *
 * Run: deno test _shared/athleteNoteText.test.ts
 *
 * Fixtures are verbatim values pulled from `training_logs` on 2026-08-18 —
 * both the boilerplate that has to be dropped and the real memos that must
 * survive. The asymmetry is the whole contract: dropping a title is cosmetic,
 * dropping a real note silently removes the signal the recent-log block exists
 * to carry.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { firstAthleteNote, isBoilerplateNote } from "./athleteNoteText.ts";

// ── Boilerplate that must be dropped (verbatim from real rows) ────────────

Deno.test("drops bare activity titles", () => {
  for (const t of ["Morning Run", "Afternoon Run", "Evening Run", "Treadmill"]) {
    assert(isBoilerplateNote(t), `expected boilerplate: ${t}`);
  }
});

Deno.test("drops title variants we have not seen yet but will", () => {
  for (
    const t of [
      "Lunch Run", "Midday Run", "Night Run", "Early Morning Run",
      "Late Night Run", "Treadmill Run", "Indoor Run", "Morning Ride",
      "Morning Walk", "Workout", "Activity", "Untitled", "run",
    ]
  ) {
    assert(isBoilerplateNote(t), `expected boilerplate: ${t}`);
  }
});

Deno.test("drops the imported stat dump", () => {
  assert(isBoilerplateNote(
    "Morning Run\nDistance: 6.01 mi\nDuration: 44:04\nAvg pace: 7:20/mi",
  ));
  assert(isBoilerplateNote(
    "Treadmill\nDistance: 4 mi\nDuration: 31:04\nAvg pace: 7:46/mi",
  ));
});

Deno.test("drops empty and whitespace-only values", () => {
  assert(isBoilerplateNote(""));
  assert(isBoilerplateNote("   \n  "));
  assert(isBoilerplateNote(null));
  assert(isBoilerplateNote(undefined));
});

// ── Real athlete voice that must survive ─────────────────────────────────

Deno.test("keeps real memos (verbatim from real rows)", () => {
  const real = [
    "I struggled a lot with today's 3x2 mile workout. It was hot and humid, and I've been feeling run down.",
    "Completed a steady long run, but the heat and humidity became a significant factor after about 10 miles.",
    "I did a steady 11-miler and felt under control, aerobically decent, and solid. My left knee felt a little bit tight.",
  ];
  for (const t of real) {
    assertEquals(isBoilerplateNote(t), false, `should keep: ${t.slice(0, 40)}`);
  }
});

Deno.test("keeps SHORT real notes — the threshold trap", () => {
  // Any word-count or length heuristic tuned to kill "Morning Run" (2 words,
  // 11 chars) would also kill these. That is why the filter is exact-match.
  for (const t of ["Legs felt heavy today", "knee is back", "rough one", "hot"]) {
    assertEquals(isBoilerplateNote(t), false, `should keep: ${t}`);
  }
});

Deno.test("keeps a note that merely CONTAINS a title word", () => {
  assertEquals(isBoilerplateNote("Morning run felt awful, calf tight"), false);
  assertEquals(isBoilerplateNote("Treadmill because of the storm, legs fine"), false);
});

Deno.test("keeps a note mentioning distance without being a stat dump", () => {
  // Needs BOTH Distance: and Duration: to count as an import dump.
  assertEquals(
    isBoilerplateNote("Cut it short. Distance: felt like plenty in that heat."),
    false,
  );
});

// ── firstAthleteNote precedence ──────────────────────────────────────────

Deno.test("skips a boilerplate title to reach a real later candidate", () => {
  // The exact shape of an imported row: cleaned_notes is the title, the real
  // content is behind it. A null-coalesce would have returned "Morning Run".
  assertEquals(
    firstAthleteNote("Morning Run", "8x1000m at threshold", "Morning Run\nDistance: 6 mi\nDuration: 40:00"),
    "8x1000m at threshold",
  );
});

Deno.test("prefers the earliest real candidate", () => {
  assertEquals(
    firstAthleteNote("Felt strong throughout", "8x1000m"),
    "Felt strong throughout",
  );
});

Deno.test("collapses whitespace so the block stays one line per run", () => {
  assertEquals(
    firstAthleteNote("Felt strong.\n\n  Knee   fine."),
    "Felt strong. Knee fine.",
  );
});

Deno.test("returns empty string when every candidate is boilerplate", () => {
  assertEquals(firstAthleteNote("Morning Run", "", null, undefined), "");
});
