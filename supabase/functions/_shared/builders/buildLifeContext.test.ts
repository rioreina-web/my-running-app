/**
 * Unit tests for buildLifeContext.
 *
 * Run: deno test _shared/builders/buildLifeContext.test.ts
 *
 * Pins: null on no-life-signal, old-schema tolerance (rpe/sleep/weather only),
 * dense-memo rollups, window boundaries (7d/10d/28d), and verbatim illness
 * detail (never reinterpreted — hard rule #2).
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildLifeContext, type LifeContextLogRow } from "./buildLifeContext.ts";

const NOW = new Date("2026-07-02T12:00:00Z");

function daysAgo(n: number): string {
  return new Date(NOW.getTime() - n * 86400000).toISOString();
}

function row(n: number, ed: Record<string, unknown> | null): LifeContextLogRow {
  return { workout_date: daysAgo(n), source: "voice_log", extracted_data: ed };
}

Deno.test("returns null when no log carries any life field", () => {
  const logs: LifeContextLogRow[] = [
    row(1, { workout_type: "easy", distance_miles: 5 }), // old schema, no life fields
    row(3, null),                                        // no extracted_data at all
    { workout_date: daysAgo(2) },                        // missing column entirely
  ];
  assertEquals(buildLifeContext(logs, NOW), null);
});

Deno.test("returns null for an athlete with no memos", () => {
  assertEquals(buildLifeContext([], NOW), null);
});

Deno.test("old-schema rows (rpe + sleep_quality only) still produce a slice", () => {
  const logs = [
    row(1, { workout_type: "tempo", rpe: 7, sleep_quality: "poor" }),
    row(2, { workout_type: "easy", rpe: 4 }),
  ];
  const lc = buildLifeContext(logs, NOW);
  assert(lc !== null);
  assertEquals(lc.sleep.poor_mentions_7d, 1);
  assertEquals(lc.sleep.last?.quality, "poor");
  assertEquals(lc.sleep.last?.hours, null);
  assertEquals(lc.avg_rpe_7d, 5.5);
  assertEquals(lc.fatigue.length, 0);
  assertEquals(lc.stress.any_high_28d, 0);
  assertEquals(lc.illness.active, false);
});

Deno.test("dense memos roll up: stress, fatigue trail, felt_vs_looked, summary", () => {
  const logs = [
    row(1, {
      work_stress: "high", life_stress: "moderate", fatigue: "wiped",
      felt_vs_looked: "harder than it looks", sleep_quality: "poor", sleep_hours: 5,
    }),
    row(3, {
      work_stress: "high", fatigue: "tired",
      felt_vs_looked: "harder than it looks", sleep_quality: "poor",
    }),
    row(5, { fatigue: "normal", felt_vs_looked: "about right" }),
    row(12, { life_stress: "high", fatigue: "tired" }), // outside 7d, inside 28d
  ];
  const lc = buildLifeContext(logs, NOW);
  assert(lc !== null);
  assertEquals(lc.stress.work_high_7d, 2);
  assertEquals(lc.stress.life_high_7d, 0);       // day-1 life_stress is "moderate", not high
  assertEquals(lc.stress.any_high_28d, 3);       // day 1 (work), day 3 (work), day 12 (life)
  assertEquals(lc.stress.last_mention, daysAgo(1).slice(0, 10));
  assertEquals(lc.sleep.poor_mentions_7d, 2);
  assertEquals(lc.sleep.last?.hours, 5);
  assertEquals(lc.fatigue.length, 4);
  assertEquals(lc.fatigue[0], { date: daysAgo(1).slice(0, 10), label: "wiped" });
  assertEquals(lc.felt_vs_looked.length, 3);
  assertEquals(lc.felt_vs_looked[0].value, "harder than it looks");
  assert(lc.summary !== null);
  assert(lc.summary!.includes("sleep poor ×2"));
  assert(lc.summary!.includes("work stress high ×2"));
  assert(lc.summary!.includes("felt harder than it looked ×2"));
});

Deno.test("illness: active within 10d, inactive after, verbatim detail preserved", () => {
  const active = buildLifeContext([row(8, { illness: "fighting a cold" })], NOW);
  assert(active !== null);
  assertEquals(active.illness, {
    active: true, detail: "fighting a cold", date: daysAgo(8).slice(0, 10),
  });

  const stale = buildLifeContext([row(14, { illness: "fighting a cold" })], NOW);
  assert(stale !== null);
  assertEquals(stale.illness.active, false);
  assertEquals(stale.illness.detail, "fighting a cold"); // still visible, just not active
});

Deno.test("travel: recent within 7d only; most recent mention wins", () => {
  const lc = buildLifeContext([
    row(2, { travel: "work trip to Denver" }),
    row(20, { travel: "red-eye home" }),
  ], NOW);
  assert(lc !== null);
  assertEquals(lc.travel.recent, true);
  assertEquals(lc.travel.detail, "work trip to Denver");

  const old = buildLifeContext([row(9, { travel: "red-eye home" })], NOW);
  assert(old !== null);
  assertEquals(old.travel.recent, false);
});

Deno.test("rows older than 28d are ignored entirely", () => {
  const lc = buildLifeContext([row(30, { work_stress: "high", sleep_quality: "poor" })], NOW);
  assertEquals(lc, null);
});

Deno.test("rpe outside 1-10 and non-numeric rpe are discarded", () => {
  const lc = buildLifeContext([
    row(1, { rpe: 7 }),
    row(2, { rpe: 99 }),
    row(3, { rpe: "hard" }),
  ], NOW);
  assert(lc !== null);
  assertEquals(lc.avg_rpe_7d, 7);
});

Deno.test("effort_level (densest real field) builds an effort trail + hard_7d", () => {
  const logs = [
    row(1, { effort_level: "hard", rpe: 8 }),
    row(2, { effort_level: "max" }),
    row(4, { effort_level: "hard" }),
    row(6, { effort_level: "easy" }),
    row(20, { effort_level: "hard" }), // outside 7d — not counted in hard_7d
  ];
  const lc = buildLifeContext(logs, NOW);
  assert(lc !== null);
  assertEquals(lc.effort.length, 5);
  assertEquals(lc.effort[0], { date: daysAgo(1).slice(0, 10), label: "hard" });
  assertEquals(lc.hard_7d, 3); // hard, max, hard within 7d
  assert(lc.summary !== null && lc.summary!.includes("hard efforts ×3 this week"));
});

Deno.test("effort_level alone is enough signal (not null)", () => {
  const lc = buildLifeContext([row(2, { effort_level: "easy" })], NOW);
  assert(lc !== null);
  assertEquals(lc.effort[0].label, "easy");
  assertEquals(lc.hard_7d, 0);
});

Deno.test("check-in/legacy stress_level folds into life stress", () => {
  const lc = buildLifeContext([
    row(1, { stress_level: "high" }),   // check-in vocabulary
    row(3, { stress_level: "moderate" }),
  ], NOW);
  assert(lc !== null);
  assertEquals(lc.stress.life_high_7d, 1);
  assertEquals(lc.stress.any_high_28d, 1);
  assertEquals(lc.stress.last_mention, daysAgo(1).slice(0, 10));
});

Deno.test("two memos on the same day count as two mentions", () => {
  const lc = buildLifeContext([
    row(1, { sleep_quality: "poor" }),
    row(1, { sleep_quality: "poor", work_stress: "high" }),
  ], NOW);
  assert(lc !== null);
  assertEquals(lc.sleep.poor_mentions_7d, 2);
  assertEquals(lc.stress.work_high_7d, 1);
});
