/**
 * Unit tests for `assembleWithBudget` (TASKS.md C.2).
 *
 * Run: deno test --allow-read supabase/functions/_shared/context.assembleWithBudget.test.ts
 *
 * What this guards against:
 *   1. The budget being silently exceeded by required blocks (we still log,
 *      but the test pins that required content is always present).
 *   2. Optional blocks slipping in when budget is tight (cost leak).
 *   3. Truncation losing the "[…truncated]" marker (model can't tell
 *      it's seeing partial content).
 *   4. Drop-vs-truncate threshold drift (we keep MIN_INCLUDE_TOKENS at 50
 *      so 30-token dribble doesn't clutter prompts).
 *   5. Empty / whitespace-only blocks counting toward the budget.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  assembleWithBudget,
  estimateTokens,
  type PromptBlock,
} from "./context.ts";

// ── Helpers ──────────────────────────────────────────────

const block = (
  name: string,
  content: string,
  priority: PromptBlock["priority"] = "preferred",
  maxTokens?: number,
): PromptBlock => ({ name, content, priority, maxTokens });

const repeat = (s: string, n: number) => s.repeat(n);

// ── Required blocks always in ─────────────────────────────

Deno.test("required blocks are always included, even when over budget", () => {
  const result = assembleWithBudget(
    [
      block("essential1", "AAA".repeat(100), "required"), // ~75 tokens
      block("essential2", "BBB".repeat(100), "required"), // ~75 tokens
      block("nice",       "CCC".repeat(100), "optional"), // ~75 tokens
    ],
    100, // budget too small to fit both required + optional
  );

  assert(result.included.includes("essential1"));
  assert(result.included.includes("essential2"));
  assert(!result.included.includes("nice"));
  assert(result.dropped.includes("nice"));
});

Deno.test("preferred blocks fill remaining budget in declared order", () => {
  const result = assembleWithBudget(
    [
      block("first",  repeat("a", 200), "preferred"), // ~50 tokens
      block("second", repeat("b", 200), "preferred"), // ~50 tokens
      block("third",  repeat("c", 200), "preferred"), // ~50 tokens
    ],
    120, // fits ~2 of 3
  );

  assert(result.included.includes("first"));
  assert(result.included.includes("second"));
  assert(result.dropped.includes("third") || result.truncated.includes("third"));
});

Deno.test("optional blocks dropped before preferred", () => {
  const result = assembleWithBudget(
    [
      block("optional1",  repeat("a", 400), "optional"),  // ~100 tokens
      block("preferred1", repeat("b", 400), "preferred"), // ~100 tokens
    ],
    100,
  );

  assert(result.included.includes("preferred1"));
  assert(result.dropped.includes("optional1") || result.truncated.includes("optional1"));
});

// ── Truncation ────────────────────────────────────────────

Deno.test("oversized block gets truncated with marker", () => {
  const huge = repeat("x", 8000); // ~2000 tokens
  const result = assembleWithBudget(
    [block("big", huge, "preferred")],
    500, // budget is far smaller
  );

  assert(result.text.includes("[…truncated for budget]"));
  assert(result.truncated.includes("big"));
  assert(result.used <= 500);
});

Deno.test("per-block maxTokens caps the block before assembly", () => {
  const result = assembleWithBudget(
    [block("capped", repeat("y", 2000), "preferred", 50)], // ~500 tokens raw, capped to 50
    2000, // budget is large; cap is the binding constraint
  );

  assert(result.truncated.includes("capped"));
  // The result must respect the 50-token cap, with some allowance for marker.
  assert(result.used < 70);
});

// ── Drop threshold ────────────────────────────────────────

Deno.test("blocks dropped when less than ~50 tokens of budget remain", () => {
  const result = assembleWithBudget(
    [
      block("fits",  repeat("a", 360), "preferred"), // ~90 tokens
      block("dribble", "small note that wastes budget", "preferred"), // ~9 tokens
    ],
    100,
  );

  assert(result.included.includes("fits"));
  // Only ~10 tokens left after "fits"; the dribble block should drop.
  assert(result.dropped.includes("dribble"));
});

// ── Empty / whitespace handling ───────────────────────────

Deno.test("empty and whitespace-only blocks are filtered out silently", () => {
  const result = assembleWithBudget(
    [
      block("real",   "content here", "preferred"),
      block("empty",  "", "preferred"),
      block("blank",  "   \n\n  ", "preferred"),
    ],
    1000,
  );

  assert(result.included.includes("real"));
  assert(!result.included.includes("empty"));
  assert(!result.included.includes("blank"));
  // Empty blocks should not show up in dropped either — they were filtered.
  assert(!result.dropped.includes("empty"));
  assert(!result.dropped.includes("blank"));
});

// ── Telemetry ─────────────────────────────────────────────

Deno.test("used + dropped + truncated cover every non-empty input block", () => {
  const blocks = [
    block("a", "aaaaa", "required"),
    block("b", repeat("b", 8000), "preferred"),
    block("c", "ccccc", "optional"),
    block("d", "", "optional"), // filtered, not counted
  ];

  const result = assembleWithBudget(blocks, 300);

  const accountedFor = new Set([
    ...result.included,
    ...result.dropped,
  ]);

  // a, b, c are non-empty and should be tracked.
  for (const name of ["a", "b", "c"]) {
    assert(
      accountedFor.has(name),
      `${name} should appear in included or dropped`,
    );
  }
  // d was filtered (empty) and should NOT appear.
  assert(!accountedFor.has("d"));
});

Deno.test("budget echoed in result for downstream telemetry", () => {
  const result = assembleWithBudget([block("x", "x")], 2500);
  assertEquals(result.budget, 2500);
});

// ── Composition with estimateTokens ───────────────────────

Deno.test("used is bounded by budget for required-fits cases", () => {
  const result = assembleWithBudget(
    [
      block("req", repeat("a", 100), "required"),  // ~25 tokens
      block("p1",  repeat("b", 200), "preferred"), // ~50 tokens
      block("p2",  repeat("c", 200), "preferred"), // ~50 tokens
      block("o1",  repeat("d", 200), "optional"),  // ~50 tokens
    ],
    150,
  );

  // Required (~25) + first preferred (~50) + second preferred (~50) = 125. o1 = 50 wouldn't fit.
  assert(result.used <= result.budget + 5, // 5-token estimator slop
    `used (${result.used}) should be ≤ budget (${result.budget}) for required-fits case`);
  assert(result.included.includes("req"));
});

Deno.test("estimateTokens roughly matches used for whole assembly", () => {
  const result = assembleWithBudget(
    [
      block("a", repeat("a", 400)),
      block("b", repeat("b", 400)),
    ],
    1000,
  );

  const reEstimated = estimateTokens(result.text);
  // Allow small drift (the marker, join behavior, etc.)
  const diff = Math.abs(reEstimated - result.used);
  assert(diff < 10, `result.used (${result.used}) should match estimateTokens(text) (${reEstimated})`);
});
