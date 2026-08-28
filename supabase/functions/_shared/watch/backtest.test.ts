/**
 * Unit tests for the watch backtest.
 *
 * Run: deno test --allow-all _shared/watch/backtest.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { backtestAll, backtestWatch, stateAsOf, summarize } from "./backtest.ts";
import { easyDayDiscipline } from "./easyDayDiscipline.ts";
import { niggleFlare } from "./niggleFlare.ts";
import { recoveryTrend } from "./recoveryTrend.ts";
import { ALL_WATCHES } from "./index.ts";
import type { WatchStateInput } from "./context.ts";

const NOW = new Date("2026-08-26T12:00:00Z");
const ago = (n: number) => new Date(NOW.getTime() - n * 86_400_000).toISOString().slice(0, 10);

// ─── No look-ahead ───────────────────────────────────────────────────────────

Deno.test("a replayed day cannot see the future", () => {
  const state: WatchStateInput = {
    user_id: "a-1",
    recent_workouts: [
      { date: ago(1), type: "easy", mood: "tired", pace: "8:00/mi" },
      { date: ago(40), type: "easy", mood: "positive", pace: "9:20/mi" },
    ],
  };
  const { state: past } = stateAsOf(state, new Date(NOW.getTime() - 20 * 86_400_000));
  assertEquals(past.recent_workouts?.length, 1);
  assertEquals(past.recent_workouts?.[0].date, ago(40));
});

Deno.test("aggregates are dropped rather than carried backwards", () => {
  // Today's zone_pct_7d is not what it was six weeks ago; pretending otherwise
  // would make the backtest agree with itself for the wrong reason.
  const { state, caveats } = stateAsOf({
    user_id: "a-1",
    load_distribution: { zone_pct_7d: { easy: 50, moderate: 30, threshold: 15, hard: 5 } },
  }, NOW);
  assertEquals(state.load_distribution, null);
  assert(caveats.some((c) => c.includes("Time-in-zone")));
});

Deno.test("scheduled work ahead of a past date is not knowable", () => {
  const { state } = stateAsOf({
    user_id: "a-1",
    upcoming_workouts: [{ date: ago(1), workout_type: "tempo" }],
  }, NOW);
  assertEquals(state.upcoming_workouts, null);
});

// ─── Counting ────────────────────────────────────────────────────────────────

/** An athlete whose easy running is consistently 40s/mi too quick. */
function fastEasyAthlete(): WatchStateInput {
  const runs = [];
  for (let d = 1; d <= 56; d += 2) {
    runs.push({ date: ago(d), type: "easy", mood: "neutral", pace: "8:20/mi" });
  }
  return {
    user_id: "a-1",
    recent_workouts: runs,
    pace_zone_ranges: { easy: { paceFast: 540, paceSlow: 600 } }, // 9:00–10:00
  };
}

Deno.test("a persistently true condition fires repeatedly without a cooldown", () => {
  const r = backtestWatch(easyDayDiscipline, fastEasyAthlete(), {
    to: NOW,
    cooldownDays: 0,
  });
  assert(r.raw_fired_count > 20, `expected many raw fires, got ${r.raw_fired_count}`);
});

Deno.test("cooldown is what turns a standing truth into a manageable count", () => {
  const state = fastEasyAthlete();
  const noCooldown = backtestWatch(easyDayDiscipline, state, { to: NOW, cooldownDays: 0 });
  const weekly = backtestWatch(easyDayDiscipline, state, { to: NOW, cooldownDays: 7 });

  assert(weekly.fired_count < noCooldown.fired_count);
  assert(weekly.fired_count <= 9, `8 weeks at a 7-day cooldown caps out near 9, got ${weekly.fired_count}`);
  // The raw count is preserved so the honesty of "this is always true" survives.
  assertEquals(weekly.raw_fired_count, noCooldown.raw_fired_count);
  assert(weekly.summary.includes("cooldown held back"));
});

Deno.test("fires never land closer together than the cooldown", () => {
  const r = backtestWatch(easyDayDiscipline, fastEasyAthlete(), {
    to: NOW,
    cooldownDays: 10,
  });
  for (let i = 1; i < r.fires.length; i++) {
    const gap = (Date.parse(r.fires[i].date) - Date.parse(r.fires[i - 1].date)) / 86_400_000;
    assert(gap >= 10, `fires ${r.fires[i - 1].date} → ${r.fires[i].date} only ${gap}d apart`);
  }
});

Deno.test("a disciplined athlete produces a clean backtest", () => {
  const runs = [];
  for (let d = 1; d <= 56; d += 2) {
    runs.push({ date: ago(d), type: "easy", mood: "positive", pace: "9:30/mi" });
  }
  const r = backtestWatch(easyDayDiscipline, {
    user_id: "a-1",
    recent_workouts: runs,
    pace_zone_ranges: { easy: { paceFast: 540, paceSlow: 600 } },
  }, { to: NOW });

  assertEquals(r.fired_count, 0);
  assert(r.summary.includes("Wouldn't have said anything"));
});

// ─── Fidelity ────────────────────────────────────────────────────────────────

Deno.test("row-level history replays at full fidelity", () => {
  const r = backtestWatch(recoveryTrend, {
    user_id: "a-1",
    recent_workouts: Array.from({ length: 20 }, (_, i) => ({
      date: ago(i * 3 + 1),
      type: "easy",
      mood: i < 5 ? "tired" : "positive",
    })),
  }, { to: NOW });
  assertEquals(r.fidelity, "full");
  assertEquals(r.caveats.length, 0);
});

Deno.test("aggregate-dependent backtests declare themselves partial", () => {
  const r = backtestWatch(easyDayDiscipline, {
    ...fastEasyAthlete(),
    load_distribution: { zone_pct_7d: { easy: 50, moderate: 30, threshold: 15, hard: 5 } },
  }, { to: NOW });
  assertEquals(r.fidelity, "partial");
  assert(r.caveats.length > 0);
});

Deno.test("niggle counts declare their aggregation caveat", () => {
  const r = backtestWatch(niggleFlare, {
    user_id: "a-1",
    niggle_recurrence: [{
      body_area: "calf",
      side: "left",
      occurrences: 3,
      first_seen: ago(40),
      last_seen: ago(2),
      worst_severity: "sore",
      status: "active",
      resolved_at: null,
    }],
  }, { to: NOW });
  assertEquals(r.fidelity, "partial");
  assert(r.caveats.some((c) => c.includes("aggregated to today")));
});

// ─── Blindness is not innocence ──────────────────────────────────────────────

Deno.test("an athlete with no history reports blindness, not an all-clear", () => {
  const r = backtestWatch(recoveryTrend, { user_id: "new-1" }, { to: NOW });
  assertEquals(r.fired_count, 0);
  assert(r.blind_days > 0);
  assert(r.summary.includes("isn't enough history"));
  assert(!r.summary.includes("Wouldn't have said anything"));
});

// ─── The sentence a person reads ─────────────────────────────────────────────

Deno.test("summary calls out a watch that would be noise", () => {
  const s = summarize(20, 40, 0, 56, 7);
  assert(s.includes("background noise"));
});

Deno.test("summary calls out a watch that never fires", () => {
  const s = summarize(0, 0, 0, 56, 7);
  assert(s.includes("threshold is set too far out"));
});

Deno.test("summary treats a mostly-blind window as a floor", () => {
  const s = summarize(2, 2, 40, 56, 7);
  assert(s.includes("treat the count as a floor"));
});

// ─── Roster ──────────────────────────────────────────────────────────────────

Deno.test("backtestAll covers every watch in the registry", () => {
  const results = backtestAll(ALL_WATCHES, fastEasyAthlete(), { to: NOW });
  assertEquals(results.length, ALL_WATCHES.length);
  for (const r of results) {
    assert(r.summary.length > 0);
    assertEquals(r.window_days, 56);
  }
});

Deno.test("the same watch reads differently per athlete — the roster problem", () => {
  const quick = backtestWatch(easyDayDiscipline, fastEasyAthlete(), { to: NOW });
  const disciplined = backtestWatch(easyDayDiscipline, {
    user_id: "b-1",
    recent_workouts: Array.from({ length: 28 }, (_, i) => ({
      date: ago(i * 2 + 1),
      type: "easy",
      pace: "9:30/mi",
    })),
    pace_zone_ranges: { easy: { paceFast: 540, paceSlow: 600 } },
  }, { to: NOW });

  assert(quick.fired_count > disciplined.fired_count);
  assertEquals(disciplined.fired_count, 0);
});
