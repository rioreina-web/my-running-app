/**
 * Unit tests for the watch registry.
 *
 * Run: deno test --allow-all _shared/watch/watch.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { ALL_WATCHES, runWatches } from "./index.ts";
import { easyDayDiscipline } from "./easyDayDiscipline.ts";
import { niggleFlare } from "./niggleFlare.ts";
import { recoveryTrend } from "./recoveryTrend.ts";
import type { WatchContext } from "./types.ts";

const NOW = new Date("2026-08-24T12:00:00Z");

/** ISO date `n` days before NOW. */
function ago(n: number): string {
  return new Date(NOW.getTime() - n * 86_400_000).toISOString().slice(0, 10);
}

function ctx(over: Partial<WatchContext> = {}): WatchContext {
  return { athleteUserId: "a-1", now: NOW, moodHistory: [], ...over };
}

// ─── Recovery: the slope, not the cliff ──────────────────────────────────────

Deno.test("recovery: catches a slide that never trips a low-mood streak", () => {
  // energized → positive → neutral. No two consecutive lows anywhere, so
  // lowMoodStreak stays silent. The slope is the whole point.
  const r = recoveryTrend.evaluate(ctx({
    moodHistory: [
      { date: ago(1), mood: "neutral" },
      { date: ago(3), mood: "tired" },
      { date: ago(5), mood: "neutral" },
      { date: ago(8), mood: "neutral" },
      { date: ago(14), mood: "positive" },
      { date: ago(17), mood: "energized" },
      { date: ago(21), mood: "positive" },
      { date: ago(25), mood: "energized" },
      { date: ago(30), mood: "positive" },
    ],
  }));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  assert(r.finding.headline.includes("trending down"));
  assert(r.finding.evidence.some((e) => e.includes("mood mean")));
});

Deno.test("recovery: steady good weeks stay quiet", () => {
  const r = recoveryTrend.evaluate(ctx({
    moodHistory: [
      { date: ago(1), mood: "positive" },
      { date: ago(4), mood: "energized" },
      { date: ago(7), mood: "positive" },
      { date: ago(13), mood: "positive" },
      { date: ago(18), mood: "neutral" },
      { date: ago(24), mood: "positive" },
      { date: ago(29), mood: "energized" },
    ],
  }));
  assertEquals(r.kind, "clear");
});

Deno.test("recovery: sliding AND low escalates and proposes easing the week", () => {
  const r = recoveryTrend.evaluate(ctx({
    moodHistory: [
      { date: ago(1), mood: "struggling" },
      { date: ago(3), mood: "tired" },
      { date: ago(6), mood: "struggling" },
      { date: ago(9), mood: "tired" },
      { date: ago(15), mood: "positive" },
      { date: ago(20), mood: "energized" },
      { date: ago(26), mood: "positive" },
      { date: ago(31), mood: "positive" },
    ],
  }));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  assertEquals(r.finding.severity, "high");
  assertEquals(r.finding.suggested, "reduce_volume");
  assert(r.finding.defer_to_human);
});

Deno.test("recovery: thin data reports a gap, never an all-clear", () => {
  const r = recoveryTrend.evaluate(ctx({
    moodHistory: [{ date: ago(2), mood: "tired" }],
  }));
  assertEquals(r.kind, "gap");
  if (r.kind !== "gap") return;
  assert(r.gap.gap.includes("not enough"));
});

// ─── Pace: easy days ─────────────────────────────────────────────────────────

const EASY_BAND = { paceFast: 540, paceSlow: 600 }; // 9:00–10:00/mi

Deno.test("pace: flags easy days run quick, with the size of the drift", () => {
  const r = easyDayDiscipline.evaluate(ctx({
    easyBand: EASY_BAND,
    easyRuns: [
      { date: ago(1), paceSecPerMile: 500, workoutType: "easy" }, // 8:20
      { date: ago(3), paceSecPerMile: 505, workoutType: "easy" },
      { date: ago(5), paceSecPerMile: 560, workoutType: "easy" }, // in band
      { date: ago(8), paceSecPerMile: 495, workoutType: "easy" },
    ],
    zonePct7d: { easy: 55, moderate: 30, threshold: 10, hard: 5 },
  }));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  assertEquals(r.finding.severity, "med");
  assert(r.finding.evidence.some((e) => e.includes("s/mi too quick")));
  // Not a plan edit — the paces are right, the running isn't.
  assertEquals(r.finding.suggested, null);
});

Deno.test("pace: disciplined easy running stays quiet", () => {
  const r = easyDayDiscipline.evaluate(ctx({
    easyBand: EASY_BAND,
    easyRuns: [
      { date: ago(1), paceSecPerMile: 570, workoutType: "easy" },
      { date: ago(3), paceSecPerMile: 585, workoutType: "easy" },
      { date: ago(6), paceSecPerMile: 560, workoutType: "easy" },
    ],
    zonePct7d: { easy: 82, moderate: 10, threshold: 5, hard: 3 },
  }));
  assertEquals(r.kind, "clear");
});

Deno.test("pace: small drift inside tolerance is not a finding", () => {
  const r = easyDayDiscipline.evaluate(ctx({
    easyBand: EASY_BAND,
    easyRuns: [
      { date: ago(1), paceSecPerMile: 535, workoutType: "easy" }, // 5s quick
      { date: ago(3), paceSecPerMile: 538, workoutType: "easy" },
      { date: ago(5), paceSecPerMile: 545, workoutType: "easy" },
    ],
    zonePct7d: { easy: 78, moderate: 12, threshold: 6, hard: 4 },
  }));
  assertEquals(r.kind, "clear");
});

Deno.test("pace: no band means a gap, never a default pace", () => {
  // feedback_no_hardcoded_paces — the watch goes blind rather than inventing.
  const r = easyDayDiscipline.evaluate(ctx({
    easyBand: null,
    easyRuns: [{ date: ago(1), paceSecPerMile: 500, workoutType: "easy" }],
  }));
  assertEquals(r.kind, "gap");
});

Deno.test("pace: aggregate read still speaks when the band is missing", () => {
  const r = easyDayDiscipline.evaluate(ctx({
    easyBand: null,
    zonePct7d: { easy: 40, moderate: 40, threshold: 15, hard: 5 },
  }));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  assertEquals(r.finding.confidence, "low");
});

Deno.test("pace: too few easy runs is a gap", () => {
  const r = easyDayDiscipline.evaluate(ctx({
    easyBand: EASY_BAND,
    easyRuns: [{ date: ago(1), paceSecPerMile: 500, workoutType: "easy" }],
  }));
  assertEquals(r.kind, "gap");
});

// ─── Niggles ─────────────────────────────────────────────────────────────────

function niggle(over: Record<string, unknown> = {}) {
  return {
    body_area: "calf",
    side: "left" as const,
    occurrences: 1,
    first_seen: ago(3),
    last_seen: ago(2),
    worst_severity: "sore",
    status: "active" as const,
    resolved_at: null,
    ...over,
  };
}

Deno.test("niggles: a live mention proposes the day off", () => {
  const r = niggleFlare.evaluate(ctx({ niggles: [niggle()] }));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  assertEquals(r.finding.suggested, "insert_rest");
  assertEquals(r.finding.severity, "med");
});

Deno.test("niggles: quality close by holds quality instead", () => {
  const r = niggleFlare.evaluate(ctx({
    niggles: [niggle()],
    upcomingQualityWithinDays: 2,
  }));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  assertEquals(r.finding.suggested, "pause_quality");
});

Deno.test("niggles: recurrence outranks a single flare and wants a human", () => {
  const r = niggleFlare.evaluate(ctx({
    niggles: [niggle({ occurrences: 3, first_seen: ago(38), last_seen: ago(2) })],
  }));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  assertEquals(r.finding.severity, "high");
  assert(r.finding.defer_to_human);
  assert(r.finding.headline.includes("keeps coming back"));
});

Deno.test("niggles: resolved areas stay quiet", () => {
  const r = niggleFlare.evaluate(ctx({
    niggles: [niggle({ status: "resolved", resolved_at: ago(5) })],
  }));
  assertEquals(r.kind, "clear");
});

Deno.test("niggles: an old unresolved mention is not a flare", () => {
  const r = niggleFlare.evaluate(ctx({
    niggles: [niggle({ first_seen: ago(60), last_seen: ago(40) })],
  }));
  assertEquals(r.kind, "clear");
});

Deno.test("niggles: never diagnoses, never routes to medical care", () => {
  const r = niggleFlare.evaluate(ctx({
    niggles: [niggle({ occurrences: 4, first_seen: ago(40), last_seen: ago(1),
      worst_severity: "sharp" })],
  }));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  const text = `${r.finding.headline} ${r.finding.detail}`.toLowerCase();
  for (const banned of ["stop training", "stop running", "doctor", "physio", "strain", "tendin", "itbs"]) {
    assert(!text.includes(banned), `niggle output must not contain "${banned}"`);
  }
});

// ─── The sweep ───────────────────────────────────────────────────────────────

Deno.test("sweep: orders findings loudest-first", () => {
  const sweep = runWatches(ctx({
    // niggle recurrence → high; easy drift → med
    niggles: [niggle({ occurrences: 3, first_seen: ago(38), last_seen: ago(1) })],
    easyBand: EASY_BAND,
    easyRuns: [
      { date: ago(1), paceSecPerMile: 500, workoutType: "easy" },
      { date: ago(3), paceSecPerMile: 505, workoutType: "easy" },
      { date: ago(5), paceSecPerMile: 495, workoutType: "easy" },
    ],
  }));
  assert(sweep.findings.length >= 2);
  assertEquals(sweep.findings[0].severity, "high");
  assertEquals(sweep.findings[0].domain, "niggles");
});

Deno.test("sweep: separates gaps from all-clears", () => {
  const sweep = runWatches(ctx({ niggles: [] })); // clear; others blind
  assert(sweep.clear.includes("niggle_flare"));
  assert(sweep.gaps.length > 0, "blind watches must report gaps");
  assert(!sweep.clear.includes("recovery_trend"), "a blind watch is not an all-clear");
});

Deno.test("sweep: one broken watch degrades to a gap, not a dead sweep", () => {
  const exploding = {
    id: "boom",
    domain: "load" as const,
    question: "?",
    reads: [],
    evaluate: () => {
      throw new Error("kaboom");
    },
  };
  const sweep = runWatches(ctx({ niggles: [] }), [exploding, niggleFlare]);
  assert(sweep.gaps.some((g) => g.watch_id === "boom"));
  assert(sweep.clear.includes("niggle_flare"), "other watches still ran");
});

Deno.test("registry: every watch declares a question and its inputs", () => {
  for (const w of ALL_WATCHES) {
    assert(w.question.trim().endsWith("?"), `${w.id} question must be a question`);
    assert(w.reads.length > 0, `${w.id} must declare what it reads`);
  }
});
