/**
 * Tests for memory selection + the year-ago arc.
 *
 * Run: deno test --allow-net _shared/memorySelection.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildYearAgoArc, selectMemoriesForPrompt, StateMemory } from "./memorySelection.ts";

const NOW = "2026-07-02T12:00:00.000Z";
const daysAgo = (d: number) => new Date(new Date(NOW).getTime() - d * 86400000).toISOString();

function m(p: Partial<StateMemory> & { category: string; content: string }): StateMemory {
  return {
    their_words: null,
    importance: 5,
    memory_date: null,
    last_confirmed_at: daysAgo(5),
    mention_count: 1,
    ...p,
  };
}

Deno.test("selection: enforces per-category quotas (constraints ≤3, prefs ≤3, life ≤2, pr/race ≤2)", () => {
  const mems: StateMemory[] = [];
  for (let i = 0; i < 6; i++) mems.push(m({ category: "constraint", content: `constraint ${i}`, importance: 9 - i }));
  for (let i = 0; i < 6; i++) mems.push(m({ category: "preference", content: `pref ${i}`, importance: 9 - i }));
  for (let i = 0; i < 6; i++) mems.push(m({ category: "life", content: `life ${i}`, importance: 9 - i }));
  for (let i = 0; i < 4; i++) mems.push(m({ category: "pr", content: `pr ${i}`, importance: 9 - i }));

  const { general } = selectMemoriesForPrompt(mems, NOW);
  const count = (c: string) => general.filter((g) => g.category === c).length;
  assertEquals(count("constraint"), 3);
  assertEquals(count("preference"), 3);
  assertEquals(count("life"), 2);
  assertEquals(count("pr"), 2);
  assertEquals(general.length, 10); // 3+3+2+2
});

Deno.test("selection: pr and race share one 2-slot bucket", () => {
  const mems = [
    m({ category: "pr", content: "Marathon PR 3:28", importance: 8 }),
    m({ category: "race", content: "Ran Boston 2024", importance: 8 }),
    m({ category: "race", content: "Targeting CIM", importance: 3 }),
  ];
  const { general } = selectMemoriesForPrompt(mems, NOW);
  assertEquals(general.filter((g) => g.category === "pr" || g.category === "race").length, 2);
});

Deno.test("selection: gear is not surfaced in the prompt (Model of You only)", () => {
  const { general } = selectMemoriesForPrompt([m({ category: "gear", content: "Races in Vaporflys", importance: 9 })], NOW);
  assertEquals(general.length, 0);
});

Deno.test("selection: recency breaks ties — a re-confirmed fact outranks a stale higher-nominal one", () => {
  const mems = [
    m({ category: "preference", content: "stale-but-important", importance: 8, last_confirmed_at: daysAgo(360) }),
    m({ category: "preference", content: "fresh", importance: 7, last_confirmed_at: daysAgo(1) }),
    m({ category: "preference", content: "filler-a", importance: 2, last_confirmed_at: daysAgo(1) }),
    m({ category: "preference", content: "filler-b", importance: 1, last_confirmed_at: daysAgo(1) }),
  ];
  const { general } = selectMemoriesForPrompt(mems, NOW);
  // stale importance 8 × ~0.3 recency = ~2.4; fresh 7 × ~1.0 = ~7. Fresh wins.
  const prefs = general.filter((g) => g.category === "preference").map((g) => g.content);
  assertEquals(prefs[0], "fresh");
  assert(prefs.includes("stale-but-important"), "still within the 3-slot quota");
});

Deno.test("selection: episodes returned separately, capped at 2", () => {
  const mems = [
    m({ category: "episode", content: "the day it clicked", their_words: "the day it clicked", memory_date: "2026-01-14", importance: 8 }),
    m({ category: "episode", content: "first sub-7 mile", their_words: "finally cracked it", memory_date: "2026-03-02", importance: 7 }),
    m({ category: "episode", content: "meh run", their_words: "eh", memory_date: "2026-02-01", importance: 3 }),
    m({ category: "constraint", content: "night shifts", importance: 8 }),
  ];
  const { general, episodes } = selectMemoriesForPrompt(mems, NOW);
  assertEquals(episodes.length, 2);
  assert(!general.some((g) => g.category === "episode"), "episodes must not appear in general");
  assertEquals(episodes[0].memory_date, "2026-01-14");
});

// ── year-ago arc ──────────────────────────────────────────────────────────

Deno.test("buildYearAgoArc: summarizes the ~52-week-ago window into mpw + dominant mood", () => {
  const rows = [
    // Inside the window (days 336–364 ago): 4 runs, 40mi total → 10 mpw.
    { workout_date: daysAgo(350), workout_distance_miles: 10, mood: "neutral" },
    { workout_date: daysAgo(352), workout_distance_miles: 10, mood: "neutral" },
    { workout_date: daysAgo(345), workout_distance_miles: 12, mood: "positive" },
    { workout_date: daysAgo(360), workout_distance_miles: 8, mood: "neutral" },
    // Outside the window — must be ignored.
    { workout_date: daysAgo(10), workout_distance_miles: 100, mood: "energized" },
  ];
  const arc = buildYearAgoArc(rows, new Date(NOW));
  assert(arc !== null);
  assertEquals(arc!.weekly_avg_miles, 10); // 40 / 4
  assertEquals(arc!.mood_summary, "neutral");
});

Deno.test("buildYearAgoArc: null when history doesn't reach back a year", () => {
  const rows = [{ workout_date: daysAgo(30), workout_distance_miles: 8, mood: "neutral" }];
  assertEquals(buildYearAgoArc(rows, new Date(NOW)), null);
});
