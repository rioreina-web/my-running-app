/**
 * Unit tests for the pure half of `coaching-daily-read`.
 *
 * Uses `node:assert` (built into Deno) rather than deno.land/std so the
 * suite runs fully offline — no remote fetch on `deno test`.
 */

import assert from "node:assert/strict";
import {
  formatWeeklyVolume,
  isRunningType,
  mondayOf,
  normalizeHeadline,
  normalizeQuestions,
  parseModelResponse,
  validateRead,
  weekdayName,
  weeklyRunningVolume,
} from "./daily-read-shape.ts";

const W1 = "aaaaaaaa-1111-1111-1111-111111111111";
const W2 = "aaaaaaaa-2222-2222-2222-222222222222";
const D1 = "bbbbbbbb-1111-1111-1111-111111111111";
const M1 = "cccccccc-1111-1111-1111-111111111111";

const ctx = {
  validWorkoutIds: new Set([W1]),
  validDocIds: new Set([D1]),
  validMemoLogIds: new Set([M1]),
};

// ── parseModelResponse ───────────────────────────────────────────────

Deno.test("parseModelResponse: strips ```json fences and reads questions", () => {
  const raw = "```json\n" + JSON.stringify({
    headline: "Tempos are coming down.",
    paragraph: ["Smooth week. ", { workout_id: W1 }, " came in at 7:29."],
    questions: ["How did Sunday's 16 feel?"],
    cant_see: null,
    sources: { workouts: [W1], docs: [], memos: [] },
    confidence: { level: "HIGH", sub: "6 runs and 3 memos" },
  }) + "\n```";
  const p = parseModelResponse(raw);
  assert.equal(p.headline, "Tempos are coming down.");
  assert.equal(p.paragraph.length, 3);
  assert.deepEqual(p.questions, ["How did Sunday's 16 feel?"]);
  assert.equal(p.confidence.level, "HIGH");
});

Deno.test("parseModelResponse: a v2-shaped response (no questions) still parses", () => {
  const p = parseModelResponse(JSON.stringify({
    headline: "Quiet week.",
    paragraph: ["Recovery week."],
    sources: { workouts: [], docs: [], memos: [] },
    confidence: { level: "MEDIUM", sub: "3 runs" },
  }));
  assert.deepEqual(p.questions, []);
  assert.equal(p.cant_see, null);
});

Deno.test("parseModelResponse: unknown confidence level falls back to LOW", () => {
  const p = parseModelResponse(JSON.stringify({
    headline: "x",
    paragraph: [],
    sources: {},
    confidence: { level: "VERY_HIGH" },
  }));
  assert.equal(p.confidence.level, "LOW");
  assert.equal(p.confidence.sub, "");
});

Deno.test("parseModelResponse: throws on a missing headline", () => {
  assert.throws(
    () => parseModelResponse(JSON.stringify({ paragraph: [], sources: {}, confidence: {} })),
    /headline/,
  );
});

// ── validateRead ─────────────────────────────────────────────────────

Deno.test("validateRead: strips unknown citations from paragraph and sources, backfills known ones", () => {
  const { payload, report } = validateRead({
    headline: "Tempos are coming down",
    paragraph: [
      "Smooth week. ",
      { workout_id: W1 },
      " and ",
      { workout_id: W2 }, // not in context
      " plus ",
      { doc_id: D1 },
      // deno-lint-ignore no-explicit-any
      { mystery: "x" } as any,
    ],
    questions: [],
    cant_see: null,
    sources: { workouts: [W2], docs: [], memos: [{ label: "L", excerpt: "E", log_id: "nope" }] },
    confidence: { level: "HIGH", sub: "" },
  }, ctx);

  assert.equal(report.droppedWorkoutCitations, 1);
  assert.equal(report.droppedDocCitations, 0);
  assert.equal(payload.paragraph.length, 5); // W2 and the mystery segment dropped
  assert.deepEqual(payload.sources.workouts, [W1]); // W2 filtered out, W1 backfilled from paragraph
  assert.deepEqual(payload.sources.docs, [D1]);
  assert.deepEqual(payload.sources.memos, []); // unknown log_id filtered
});

Deno.test("validateRead: keeps a memo whose log_id is in context, truncating label/excerpt", () => {
  const { payload } = validateRead({
    headline: "h.",
    paragraph: [],
    questions: [],
    cant_see: null,
    sources: {
      workouts: [],
      docs: [],
      memos: [{ label: "x".repeat(200), excerpt: "y".repeat(1000), log_id: M1 }],
    },
    confidence: { level: "LOW", sub: "" },
  }, ctx);
  assert.equal(payload.sources.memos.length, 1);
  assert.equal(payload.sources.memos[0].label.length, 80);
  assert.equal(payload.sources.memos[0].excerpt.length, 400);
});

Deno.test("validateRead: normalizes headline period, questions, and cant_see", () => {
  const { payload, report } = validateRead({
    headline: "  “Tempos are   coming down”  ",
    paragraph: [],
    // deno-lint-ignore no-explicit-any
    questions: ["  How did the 16 feel? ", "How did the 16 feel?", { workout_id: W1 } as any, "Q3", "Q4"],
    cant_see: { eyebrow: " one data point ", body: "  Mentioned once.  " },
    sources: { workouts: [], docs: [], memos: [] },
    confidence: { level: "MEDIUM", sub: "" },
  }, ctx);

  assert.equal(payload.headline, "Tempos are coming down.");
  // duplicate, non-string, and the 3rd question all dropped; cap is 2
  assert.deepEqual(payload.questions, ["How did the 16 feel?", "Q3"]);
  assert.equal(report.droppedQuestions, 3);
  assert.deepEqual(payload.cant_see, { eyebrow: "ONE DATA POINT", body: "Mentioned once." });
});

Deno.test("validateRead: an empty cant_see collapses to null", () => {
  const { payload } = validateRead({
    headline: "h.",
    paragraph: [],
    questions: [],
    cant_see: { eyebrow: "", body: "something" },
    sources: { workouts: [], docs: [], memos: [] },
    confidence: { level: "LOW", sub: "" },
  }, ctx);
  assert.equal(payload.cant_see, null);
});

// ── normalizeHeadline / normalizeQuestions ───────────────────────────

Deno.test("normalizeHeadline: adds a period, leaves existing terminal punctuation alone", () => {
  assert.equal(normalizeHeadline("The base is taking"), "The base is taking.");
  assert.equal(normalizeHeadline("The base is taking."), "The base is taking.");
  assert.equal(normalizeHeadline("Nothing to read yet…"), "Nothing to read yet…");
  assert.equal(normalizeHeadline("   "), "");
});

Deno.test("normalizeQuestions: non-array input yields no questions", () => {
  assert.deepEqual(normalizeQuestions(undefined), { questions: [], dropped: 0 });
  assert.deepEqual(normalizeQuestions("How?"), { questions: [], dropped: 0 });
});

// ── weekly volume ────────────────────────────────────────────────────

Deno.test("mondayOf / weekdayName: Monday-start weeks, UTC-safe", () => {
  assert.equal(mondayOf("2026-09-15"), "2026-09-14"); // Tuesday → Monday
  assert.equal(mondayOf("2026-09-14"), "2026-09-14"); // Monday stays
  assert.equal(mondayOf("2026-09-13"), "2026-09-07"); // Sunday → previous Monday
  assert.equal(weekdayName("2026-09-15"), "Tuesday");
});

Deno.test("isRunningType: cross-training and strength are excluded, unknowns count as runs", () => {
  assert.equal(isRunningType("tempo"), true);
  assert.equal(isRunningType("Cross_Training"), false);
  assert.equal(isRunningType("strength"), false);
  assert.equal(isRunningType("rest"), false);
  assert.equal(isRunningType(null), true);
  assert.equal(isRunningType("fartlek"), true);
});

Deno.test("weeklyRunningVolume: buckets runs by week, excludes cross-training, marks the current week partial", () => {
  const logs = [
    { workout_date: "2026-09-15", workout_type: "tempo", workout_distance_miles: 6 },       // this week
    { workout_date: "2026-09-14", workout_type: "easy", workout_distance_miles: "5.2" },     // this week (string miles)
    { workout_date: "2026-09-14", workout_type: "strength", workout_distance_miles: 0 },     // ignored
    { workout_date: "2026-09-13", workout_type: "long_run", workout_distance_miles: 16 },    // last week (Sunday)
    { workout_date: "2026-09-09", workout_type: "cycling", workout_distance_miles: 25 },     // ignored
    { workout_date: "2026-09-08", workout_type: "easy", workout_distance_miles: 26.1 },      // last week
    { workout_date: "2026-07-01", workout_type: "easy", workout_distance_miles: 5 },         // outside window
    { workout_date: null, workout_type: "easy", workout_distance_miles: 5 },                 // no date
  ];
  const rows = weeklyRunningVolume(logs, "2026-09-15", 3);
  assert.equal(rows.length, 3);
  assert.deepEqual(rows[0], { weekStart: "2026-09-14", miles: 11.2, runs: 2, partial: true });
  assert.deepEqual(rows[1], { weekStart: "2026-09-07", miles: 42.1, runs: 2, partial: false });
  assert.deepEqual(rows[2], { weekStart: "2026-08-31", miles: 0, runs: 0, partial: false });

  const text = formatWeeklyVolume(rows);
  assert.match(text, /Week of 2026-09-14: 11\.2 mi · 2 runs \(this week so far\)/);
  assert.match(text, /Week of 2026-08-31: 0\.0 mi · 0 runs/);
});
