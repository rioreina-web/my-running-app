/**
 * Tests for the Layer-2 SCOPE guard.
 * Run: deno test _shared/narration-guard.scope.test.ts
 *
 * The number guard (`firstDisallowedNumber`) asks whether a digit exists in
 * the facts. These tests cover the second question it cannot ask: whether the
 * sentence is telling the truth about WHAT WAS MEASURED.
 */
import {
  assertEquals,
  assertStringIncludes,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  describeScope,
  firstUnlicensedScopeClaim,
  scopeNumbersAllowed,
  validateNarration,
  type AnalysisScope,
} from "./narration-guard.ts";

// ── The regression ────────────────────────────────────────────────
// analysis_queries, 2026-08-08 16:19:38Z. Question: "Look at my long runs
// over 12 miles, heat, and heart rate - what do you see". Routed to
// `heat_effect`, which takes only `window_days` and applied no distance
// filter — it read all 127 runs in 90 days. The narration said "long runs
// over 12 miles" anyway, and shipped: 12 is a real fact ("12 s/mi").

const HEAT_FACTS = [
  "Actual pace · 90 days: 7:03/mi",
  "Cool-weather equivalent: 6:51/mi (−12s)",
  "What the conditions were worth: 12 s/mi",
  "Average dew point: 71 °F",
  "Runs above the heat threshold: 102 of 127",
  "Coverage: 127 sessions over 90 days (high confidence)",
];

const HEAT_SCOPE: AnalysisScope = {
  sessionsUsed: 127,
  windowDays: 90,
  params: { window_days: 90 },
};

const badNarration = JSON.stringify({
  text:
    "Your long runs over 12 miles show a significant impact from heat, with your cool-weather equivalent pace being 6:51/mi, 12 seconds faster than your actual pace.",
  caveat: null,
});

Deno.test("REGRESSION: the old number guard alone lets the scope lie through", () => {
  // No scope passed → today's behaviour before the fix. Still accepted,
  // which is precisely why the scope gate had to be a separate check.
  const r = validateNarration(badNarration, HEAT_FACTS);
  assertEquals(r.ok, true);
});

Deno.test("REGRESSION: with scope, 'over 12 miles' is rejected", () => {
  const r = validateNarration(badNarration, HEAT_FACTS, {}, HEAT_SCOPE);
  assertEquals(r.ok, false);
  if (r.ok) return;
  assertEquals(r.reason, "unlicensed_scope");
  assertStringIncludes(r.offendingScope ?? "", "12 mile");
});

// ── Unit families stay apart ──────────────────────────────────────

Deno.test("a 90-day window licenses '90 days' but not 'over 90 minutes'", () => {
  const allowed = scopeNumbersAllowed(HEAT_SCOPE);
  assertEquals(firstUnlicensedScopeClaim("across the past 90 days", allowed), null);
  assertEquals(
    firstUnlicensedScopeClaim("holds past 90 minutes", allowed),
    "past 90 minutes",
  );
});

Deno.test("windowDays also licenses its week and month phrasings", () => {
  const allowed = scopeNumbersAllowed(HEAT_SCOPE);
  assertEquals(firstUnlicensedScopeClaim("over 13 weeks", allowed), null); // 90/7
  assertEquals(firstUnlicensedScopeClaim("over 3 months", allowed), null); // 90/30
  assertEquals(firstUnlicensedScopeClaim("over 8 weeks", allowed), "over 8 weeks");
});

Deno.test("sessionsUsed licenses a count, not a distance", () => {
  const allowed = scopeNumbersAllowed(HEAT_SCOPE);
  assertEquals(firstUnlicensedScopeClaim("across more than 127 runs", allowed), null);
  assertEquals(
    firstUnlicensedScopeClaim("across more than 127 miles", allowed),
    "more than 127 miles",
  );
});

Deno.test("a distance param the analyzer DID apply licenses the claim", () => {
  const scoped: AnalysisScope = {
    sessionsUsed: 9,
    windowDays: 90,
    params: { window_days: 90, distance_min_miles: 12 },
  };
  const allowed = scopeNumbersAllowed(scoped);
  assertEquals(firstUnlicensedScopeClaim("your long runs over 12 miles", allowed), null);
  assertEquals(
    firstUnlicensedScopeClaim("your long runs over 16 miles", allowed),
    "over 16 miles",
  );
});

Deno.test("an unrecognised param name licenses every family rather than blocking truth", () => {
  const scoped: AnalysisScope = {
    sessionsUsed: 5,
    windowDays: 60,
    params: { wibble: 7 },
  };
  const allowed = scopeNumbersAllowed(scoped);
  assertEquals(firstUnlicensedScopeClaim("over 7 miles", allowed), null);
  assertEquals(firstUnlicensedScopeClaim("over 7 minutes", allowed), null);
});

// ── No false positives on ordinary narration ──────────────────────

Deno.test("plain fact sentences are untouched", () => {
  const allowed = scopeNumbersAllowed(HEAT_SCOPE);
  for (
    const line of [
      "Your cool-weather equivalent is 6:51/mi, 12 seconds faster than you actually ran.",
      "102 of 127 runs came in above the heat threshold.",
      "The dew point averaged 71 °F, and the adjustment is a model rather than a measurement.",
      "Pace is 7:03/mi and holding.",
    ]
  ) {
    assertEquals(firstUnlicensedScopeClaim(line, allowed), null, line);
  }
});

Deno.test("the caveat is checked too, not just the text", () => {
  const r = validateNarration(
    JSON.stringify({
      text: "Heat cost you 12 s/mi across the block.",
      caveat: "Based only on runs over 12 miles.",
    }),
    HEAT_FACTS,
    {},
    HEAT_SCOPE,
  );
  assertEquals(r.ok, false);
  if (!r.ok) assertEquals(r.reason, "unlicensed_scope");
});

// ── The prompt half ───────────────────────────────────────────────

Deno.test("describeScope tells the model, in words, that nothing was filtered", () => {
  const d = describeScope(HEAT_SCOPE);
  assertStringIncludes(d, "127 sessions");
  assertStringIncludes(d, "90 days");
  assertStringIncludes(d, "window_days=90");
});

Deno.test("describeScope names the filters when there are some", () => {
  const d = describeScope({
    sessionsUsed: 9,
    windowDays: 90,
    params: { distance_min_miles: 12 },
  });
  assertStringIncludes(d, "distance_min_miles=12");
});
