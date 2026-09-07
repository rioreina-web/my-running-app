/**
 * Unit tests for authored watches and the metric registry.
 *
 * Run: deno test --allow-all _shared/watch/authored.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { describeCondition, WATCH_TEMPLATES, watchFromRow, type WatchRow } from "./authored.ts";
import { isMetricId, METRIC_IDS, METRICS } from "./metrics.ts";
import type { WatchContext } from "./types.ts";

const NOW = new Date("2026-08-30T12:00:00Z");
const ago = (n: number) => new Date(NOW.getTime() - n * 86_400_000).toISOString().slice(0, 10);

function row(over: Partial<WatchRow> = {}): WatchRow {
  return {
    id: "w-1",
    label: "Heart rate ceiling on easy runs",
    metric: "easy_run_hr",
    comparison: "above",
    threshold: 145,
    window_days: 14,
    min_observations: 2,
    cooldown_days: 7,
    severity: "med",
    suggested_action: null,
    source_sentence: null,
    enabled: true,
    ...over,
  };
}

function ctx(over: Partial<WatchContext> = {}): WatchContext {
  return { athleteUserId: "a-1", now: NOW, moodHistory: [], ...over };
}

const easyRun = (d: number, hr: number | null, pace = 460) => ({
  date: ago(d),
  paceSecPerMile: pace,
  workoutType: "easy",
  distanceMiles: 6,
  avgHeartRate: hr,
});

// ─── A row behaves like a shipped watch ──────────────────────────────────────

Deno.test("an authored row produces a finding with its own label and evidence", () => {
  const w = watchFromRow(row());
  const r = w.evaluate(ctx({
    easyRuns: [easyRun(1, 154), easyRun(3, 155), easyRun(5, 138), easyRun(7, 141)],
  }));
  assertEquals(r.kind, "finding");
  if (r.kind !== "finding") return;
  assertEquals(r.finding.headline, "Heart rate ceiling on easy runs");
  assertEquals(r.finding.severity, "med");
  assert(r.finding.evidence.some((e) => e.includes("over 145 bpm")));
});

Deno.test("min_observations is the 'so one hill doesn't count' control", () => {
  const runs = [easyRun(1, 154), easyRun(3, 138), easyRun(5, 140), easyRun(7, 139)];
  // One breach: silent at 2, speaks at 1.
  assertEquals(watchFromRow(row({ min_observations: 2 })).evaluate(ctx({ easyRuns: runs })).kind, "clear");
  assertEquals(watchFromRow(row({ min_observations: 1 })).evaluate(ctx({ easyRuns: runs })).kind, "finding");
});

Deno.test("a disabled row says nothing", () => {
  const r = watchFromRow(row({ enabled: false })).evaluate(ctx({
    easyRuns: [easyRun(1, 170), easyRun(3, 175)],
  }));
  assertEquals(r.kind, "clear");
});

Deno.test("the comparison direction is respected", () => {
  // Pace: faster = fewer seconds, so "below" is the concerning direction.
  const w = watchFromRow(row({
    metric: "easy_run_pace", comparison: "below", threshold: 480, min_observations: 2,
  }));
  const r = w.evaluate(ctx({
    easyRuns: [easyRun(1, null, 430), easyRun(3, null, 440), easyRun(5, null, 500)],
  }));
  assertEquals(r.kind, "finding");
});

// ─── Blindness ───────────────────────────────────────────────────────────────

Deno.test("an athlete with no heart-rate data gets a gap, never an all-clear", () => {
  // The failure that matters: a runner without a monitor must not read as
  // "heart rate is fine".
  const r = watchFromRow(row()).evaluate(ctx({
    easyRuns: [easyRun(1, null), easyRun(3, null), easyRun(5, null)],
  }));
  assertEquals(r.kind, "gap");
  if (r.kind !== "gap") return;
  assert(r.gap.gap.includes("no average heart rate"));
});

Deno.test("nothing logged in the window is a gap, not a pass", () => {
  const r = watchFromRow(row()).evaluate(ctx({ easyRuns: [] }));
  assertEquals(r.kind, "gap");
});

// ─── The row carries the person's intent ─────────────────────────────────────

Deno.test("the original sentence becomes the watch's question", () => {
  const w = watchFromRow(row({ source_sentence: "keep me under 145 on easy days" }));
  assertEquals(w.question, "keep me under 145 on easy days?");
});

Deno.test("without a sentence the condition is described in plain terms", () => {
  assertEquals(
    describeCondition(row()),
    "average heart rate on easy runs over 145 bpm",
  );
});

Deno.test("a row with no suggested move defers to a person", () => {
  const r = watchFromRow(row()).evaluate(ctx({
    easyRuns: [easyRun(1, 154), easyRun(3, 155)],
  }));
  if (r.kind !== "finding") throw new Error("expected finding");
  assertEquals(r.finding.suggested, null);
  assert(r.finding.defer_to_human);
});

// ─── The registry is closed ──────────────────────────────────────────────────

Deno.test("metric ids are validated, so a bad row can't invent a measurement", () => {
  assert(isMetricId("easy_run_hr"));
  assertEquals(isMetricId("vo2max_trend"), false);
  assertEquals(isMetricId(null), false);
});

Deno.test("every metric declares its inputs, unit and direction", () => {
  for (const id of METRIC_IDS) {
    const m = METRICS[id];
    assertEquals(m.id, id);
    assert(m.reads.length > 0, `${id} must declare what it reads`);
    assert(m.label.trim().length > 0);
    assert(m.format(100).length > 0);
  }
});

Deno.test("every metric returns null rather than [] when the data is absent", () => {
  // The distinction is the whole gap-vs-clear discipline, at metric level.
  const empty = ctx();
  for (const id of METRIC_IDS) {
    assertEquals(
      METRICS[id].read(empty, 28),
      null,
      `${id} must report blindness on an empty context`,
    );
  }
});

// ─── Templates ───────────────────────────────────────────────────────────────

Deno.test("every template is a valid, runnable row", () => {
  for (const t of WATCH_TEMPLATES) {
    assert(isMetricId(t.metric), `${t.label} has an unknown metric`);
    assert(t.window_days > 0 && t.cooldown_days >= 0);
    assert(t.min_observations >= 1);
    // Must construct without throwing.
    const w = watchFromRow({ ...t, id: t.metric, enabled: true });
    assert(w.question.endsWith("?"));
    assertEquals(w.domain, METRICS[t.metric].domain);
  }
});

Deno.test("templates cover every metric in the registry", () => {
  // A metric nobody can reach from the picker is a metric nobody will use.
  const covered = new Set(WATCH_TEMPLATES.map((t) => t.metric));
  for (const id of METRIC_IDS) {
    assert(covered.has(id), `no template offers ${id}`);
  }
});
