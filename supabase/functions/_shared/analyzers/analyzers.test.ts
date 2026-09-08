/**
 * Tests for the analyzer contract, the Layer-1 → Layer-2 seam, and the
 * router's param coercion.
 *
 * The load-bearing test in this file is `seam:` — that the strings the model
 * is shown and the tokens the guard licenses are derived from the SAME array.
 * Every other safety property in Ask rests on that identity holding.
 *
 * Pace zones are the same test athlete as workoutComparison.test.ts:
 * mile 272, 5K 302, 10K 314, HMP 328, MP 343, steady 362, moderate 405,
 * easy 429 (sec/mile).
 *
 * Run: deno test _shared/analyzers/analyzers.test.ts
 */
import {
  assert,
  assertEquals,
  assertNotEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  allowedNumberTokens,
  validateNarration,
} from "../narration-guard.ts";
import {
  coerceParams,
  factLinesToStrings,
  getAnalyzer,
  ANALYZER_IDS,
  analyzerCatalog,
} from "./index.ts";
import { confidenceFromSamples, fmtDelta, fmtPaceSec, fmtSecDelta, type AnalyzerResult } from "./types.ts";
import { loadBalance } from "./loadBalance.ts";
import { zoneTrend } from "./zoneTrend.ts";
import { weekStart } from "./data.ts";
import type { AnalyzerCtx, SupabaseLike } from "./types.ts";

// ── Fixtures ─────────────────────────────────────────────────────

const RESULT: AnalyzerResult = {
  facts: [
    { key: "recent_pace", label: "LT pace · last 3 sessions", value: "7:03", unit: "/mi", delta: "−9s", tone: "good" },
    { key: "early_pace", label: "LT pace · first 3 sessions", value: "7:12", unit: "/mi" },
    { key: "work_volume", label: "LT volume · recent average", value: "4.2", unit: " mi", delta: "in range" },
  ],
  series: null,
  coverage: { sessionsUsed: 9, windowDays: 120, missing: ["no HR on 2 of 9 sessions"], confidence: "high" },
  related: ["compare_session"],
};

/**
 * Minimal chainable Supabase stub. Every builder method returns `this`, and
 * the object is thenable so `await`ing the chain yields `{ data, error }`.
 * `tables` maps table name → rows.
 */
function stubSupabase(tables: Record<string, unknown[]>): SupabaseLike {
  return {
    from(table: string) {
      const rows = tables[table] ?? [];
      // deno-lint-ignore no-explicit-any
      const builder: any = {
        select: () => builder,
        eq: () => builder,
        gte: () => builder,
        lt: () => builder,
        in: () => builder,
        order: () => builder,
        limit: () => builder,
        insert: () => Promise.resolve({ data: null, error: null }),
        maybeSingle: () => Promise.resolve({ data: rows[0] ?? null, error: null }),
        then: (
          resolve: (v: { data: unknown[]; error: null }) => unknown,
        ) => resolve({ data: rows, error: null }),
      };
      return builder;
    },
  };
}

function ctxWith(tables: Record<string, unknown[]>, now = new Date("2026-08-05T12:00:00Z")): AnalyzerCtx {
  return {
    userId: "user-1",
    supabase: stubSupabase(tables),
    zones: { mile: 272, fiveK: 302, tenK: 314, hm: 328, mp: 343, steady: 362, moderate: 405, easy: 429 },
    zoneTable: { mile: 272, fiveK: 302, tenK: 314, hm: 328, lt: 320, mp: 343, steady: 362, moderate: 405, easy: 429 },
    now,
  };
}

// ── The seam ─────────────────────────────────────────────────────

Deno.test("seam: fact lines license exactly the numbers they print", () => {
  const lines = factLinesToStrings(RESULT);
  const allowed = allowedNumberTokens(lines);

  // Everything the athlete can see is speakable.
  for (const tok of ["7:03", "7:12", "9", "4.2", "9", "120", "2"]) {
    assert(allowed.has(tok), `expected "${tok}" to be licensed`);
  }
  // Nothing else is.
  assert(!allowed.has("6:58"), "an unprinted pace must not be licensed");
  assert(!allowed.has("47"), "an unprinted count must not be licensed");
});

Deno.test("seam: coverage line always appears, so sample size is never hidden", () => {
  const lines = factLinesToStrings(RESULT);
  const last = lines[lines.length - 1];
  assert(last.startsWith("Coverage:"), last);
  assert(last.includes("high confidence"), last);
  assert(last.includes("no HR on 2 of 9 sessions"), last);
});

Deno.test("seam: an analyzer with no facts still emits a coverage line", () => {
  const empty: AnalyzerResult = {
    facts: [],
    coverage: { sessionsUsed: 0, windowDays: 90, missing: [], confidence: "low" },
    related: [],
  };
  const lines = factLinesToStrings(empty);
  assertEquals(lines.length, 1);
  assert(lines[0].startsWith("Coverage:"));
});

// ── The guard ────────────────────────────────────────────────────

Deno.test("guard: a narration using only printed numbers survives", () => {
  const lines = factLinesToStrings(RESULT);
  const out = validateNarration(
    JSON.stringify({
      text: "Your LT band has come down to 7:03 from 7:12 across the block.",
      caveat: null,
    }),
    lines,
  );
  assert(out.ok, "expected the narration to pass");
  if (out.ok) assertEquals(out.narration.caveat, null);
});

Deno.test("guard: one invented number kills the whole narration", () => {
  const lines = factLinesToStrings(RESULT);
  const out = validateNarration(
    JSON.stringify({ text: "You are on track for a 3:21 marathon.", caveat: null }),
    lines,
  );
  assert(!out.ok);
  if (!out.ok) {
    assertEquals(out.reason, "disallowed_number");
    assertEquals(out.offendingNumber, "3:21");
  }
});

Deno.test("guard: an invented number in the CAVEAT is caught too", () => {
  const lines = factLinesToStrings(RESULT);
  const out = validateNarration(
    JSON.stringify({ text: "The band is holding.", caveat: "Only 14 sessions on file." }),
    lines,
  );
  assert(!out.ok);
  if (!out.ok) assertEquals(out.reason, "disallowed_number");
});

Deno.test("guard: fenced JSON is unwrapped, not rejected", () => {
  const lines = factLinesToStrings(RESULT);
  const out = validateNarration(
    "```json\n{\"text\":\"Holding at 7:03.\",\"caveat\":null}\n```",
    lines,
  );
  assert(out.ok);
});

Deno.test("guard: unparseable output degrades, it does not throw", () => {
  const out = validateNarration("I think you're doing great!", factLinesToStrings(RESULT));
  assert(!out.ok);
  if (!out.ok) assertEquals(out.reason, "unparseable");
});

Deno.test("guard: over-length text is rejected before the number check", () => {
  const out = validateNarration(
    JSON.stringify({ text: "7:03 ".repeat(200), caveat: null }),
    factLinesToStrings(RESULT),
  );
  assert(!out.ok);
  if (!out.ok) assertEquals(out.reason, "too_long");
});

Deno.test("guard: a missing text field is a shape violation", () => {
  const out = validateNarration(JSON.stringify({ caveat: "hi" }), factLinesToStrings(RESULT));
  assert(!out.ok);
  if (!out.ok) assertEquals(out.reason, "wrong_shape");
});

Deno.test("guard: rounded forms of a printed decimal are licensed", () => {
  const lines = ["Monotony · 7 day: 1.9"];
  const out = validateNarration(JSON.stringify({ text: "Monotony sits near 2.", caveat: null }), lines);
  assert(out.ok, "a rounded form of a printed decimal should pass");
});

// ── Router param coercion ────────────────────────────────────────

Deno.test("params: unknown keys are dropped, not rejected", () => {
  const out = coerceParams(zoneTrend, { system: "LT", nonsense: "x", drop_table: 1 });
  assertEquals(out, { system: "LT" });
});

Deno.test("params: a value outside the closed enum is dropped", () => {
  const out = coerceParams(zoneTrend, { system: "VO2MAX" });
  assertEquals(out, {});
});

Deno.test("params: numbers outside the declared range are dropped", () => {
  assertEquals(coerceParams(zoneTrend, { window_days: 9000 }), {});
  assertEquals(coerceParams(zoneTrend, { window_days: 1 }), {});
  assertEquals(coerceParams(zoneTrend, { window_days: 90 }), { window_days: 90 });
});

Deno.test("params: numeric strings coerce, junk does not", () => {
  assertEquals(coerceParams(loadBalance, { weeks: "8" }), { weeks: 8 });
  assertEquals(coerceParams(loadBalance, { weeks: "eight" }), {});
});

Deno.test("params: a workout_id that isn't id-shaped is dropped", () => {
  const cs = getAnalyzer("compare_session")!;
  assertEquals(coerceParams(cs, { workout_id: "'; DROP TABLE training_logs; --" }), {});
  const ok = coerceParams(cs, { workout_id: "0f8fad5b-d9cb-469f-a165-70867728950e" });
  assertEquals(ok.workout_id, "0f8fad5b-d9cb-469f-a165-70867728950e");
});

// ── Registry ─────────────────────────────────────────────────────

Deno.test("registry: getAnalyzer only ever resolves a registered id", () => {
  assertEquals(getAnalyzer("nope"), null);
  assertEquals(getAnalyzer(null), null);
  assertEquals(getAnalyzer(42), null);
  for (const id of ANALYZER_IDS) assertNotEquals(getAnalyzer(id), null);
});

Deno.test("registry: every analyzer's related ids are shaped like ids", () => {
  for (const entry of analyzerCatalog()) {
    assert(/^[a-z][a-z0-9_]*$/.test(entry.id), `bad id: ${entry.id}`);
    assert(entry.label.length > 0);
  }
});

// ── Empty states (hard rule #8: never an em-dash placeholder) ─────

Deno.test("zone_trend: no pace anchor → a real empty state, no facts", async () => {
  const ctx = ctxWith({});
  ctx.zoneTable = {};
  const out = await zoneTrend.run({}, ctx);
  assertEquals(out.facts.length, 0);
  assert(out.empty != null);
  assert(!out.empty!.nudge.includes("—"), "empty-state copy must not use an em-dash placeholder");
  assertEquals(out.coverage.confidence, "low");
});

Deno.test("zone_trend: nothing logged → empty state, not a zero trend", async () => {
  const out = await zoneTrend.run({}, ctxWith({ training_logs: [] }));
  assertEquals(out.facts.length, 0);
  assert(out.empty != null);
  assertEquals(out.coverage.sessionsUsed, 0);
});

Deno.test("load_balance: too little history → empty state, never a fake ratio", async () => {
  const out = await loadBalance.run({}, ctxWith({ training_logs: [], workout_features: [] }));
  assertEquals(out.facts.length, 0);
  assert(out.empty != null);
  assert(out.empty!.nudge.length > 0);
});

// ── Formatters ───────────────────────────────────────────────────

Deno.test("fmtPaceSec: rounds without producing a 60-second minute", () => {
  assertEquals(fmtPaceSec(423), "7:03");
  assertEquals(fmtPaceSec(419.6), "7:00");
  assertEquals(fmtPaceSec(479.7), "8:00");
  assertEquals(fmtPaceSec(60), "1:00");
});

Deno.test("fmtSecDelta: faster reads negative, and zero is not signed", () => {
  assertEquals(fmtSecDelta(-9), "−9s");
  assertEquals(fmtSecDelta(4), "+4s");
  assertEquals(fmtSecDelta(0.2), "0s");
});

Deno.test("fmtDelta: a delta that rounds to zero reads 'same', never '+0'", () => {
  // "+0" reads as a real, tiny change and invites the narration to describe a
  // difference the rounding just erased.
  assertEquals(fmtDelta(0.4), "same");
  assertEquals(fmtDelta(-0.4), "same");
  assertEquals(fmtDelta(0.04, { decimals: 1 }), "same");
  assertEquals(fmtDelta(2), "+2");
  assertEquals(fmtDelta(-3.2, { suffix: "°" }), "−3°");
  assertEquals(fmtDelta(-0.62, { decimals: 1 }), "−0.6");
});

Deno.test("confidenceFromSamples: tiers are monotonic", () => {
  assertEquals(confidenceFromSamples(1), "low");
  assertEquals(confidenceFromSamples(3), "moderate");
  assertEquals(confidenceFromSamples(6), "high");
});

Deno.test("weekStart: Monday-anchored, and a Sunday belongs to the week it ends", () => {
  // 2026-08-05 is a Wednesday.
  assertEquals(weekStart(new Date("2026-08-05T12:00:00Z")).toISOString().slice(0, 10), "2026-08-03");
  // 2026-08-09 is a Sunday — same week as the 3rd, not the start of a new one.
  assertEquals(weekStart(new Date("2026-08-09T23:59:00Z")).toISOString().slice(0, 10), "2026-08-03");
  // 2026-08-10 is the next Monday.
  assertEquals(weekStart(new Date("2026-08-10T00:00:00Z")).toISOString().slice(0, 10), "2026-08-10");
});
