/**
 * Contract test: every Gemini 2.5 Flash call site must DECIDE about thinking.
 *
 * Run: deno test --allow-read supabase/functions/_shared/geminiThinking.contract.test.ts
 *
 * Why (2026-09-04): gemini-2.5-flash runs dynamic "thinking" by default. On
 * process-training-memo that was 1.7-2.2k thought tokens and 10-13s of a
 * 15.3s analysis call, on every memo, for months — and the memo-to-memo
 * variance of that budget was the pipeline's inconsistency. The fix
 * (`thinkingConfig: { thinkingBudget: 0 }`) had already been discovered and
 * documented in ask / parse-workout-structure / parse-training-week; it never
 * propagated to the two functions on the memo hot path. This test makes the
 * omission a failing build instead of a spinner.
 *
 * The rule is "decide", not "always zero": a coaching read may legitimately
 * want the model to reason. So a call site passes when EITHER
 *   - `thinkingBudget` appears in its generationConfig, OR
 *   - the file is listed in THINKING_LEFT_ON with a reason.
 * Files pinned in THINKING_MUST_BE_ZERO may not take the allowlist route.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const FUNCTIONS_DIR = new URL("..", import.meta.url).pathname;

/** Interactive extraction paths: thinking off is a hard requirement. */
const THINKING_MUST_BE_ZERO = [
  "process-training-memo/index.ts",
  "process-check-in/index.ts",
  "extract-rpe/index.ts",
  "parse-workout-structure/index.ts",
  "parse-training-week/index.ts",
  // ask/index.ts is pinned in spirit but runs gemini-2.5-flash-lite (thinking
  // off by default, and it zeroes the budget anyway), so it has no 2.5-flash
  // call site for this scan to find.
];

/**
 * Call sites that leave thinking ON — each a deliberate per-function call,
 * not an oversight. Removing an entry here means you have zeroed the budget
 * in that file. Adding one means you have decided the model should reason
 * there and accepted ~10s and a variable latency for it.
 */
const THINKING_LEFT_ON: Record<string, string> = {
  "compare-workouts/index.ts":            "coaching prose over two sessions; not yet measured (2026-09-04 audit)",
  "suggest-workout-progression/index.ts": "plan reasoning; not yet measured",
  "coach-workout-read/index.ts":          "coach-facing read; not yet measured",
  "coaching-daily-read/index.ts":         "The Read; cron-driven, latency not user-visible",
  "draft-block-rewrite/index.ts":         "plan rewrite; coach-portal, once per athlete per day",
  "ingest-manual-workout/index.ts":       "not yet measured",
  "interpret-goal/index.ts":              "not yet measured",
  "weekly-coaching-report/index.ts":      "weekly report; cron-driven",
  "_shared/router.ts":                    "not yet measured",
  "post-run-analysis/index.ts":           "not yet measured",
  "reschedule-plan/index.ts":             "plan reasoning; not yet measured",
  "block-review/index.ts":                "coach-facing; not yet measured",
  "injury-early-warning/index.ts":        "not yet measured",
  "race-readiness/index.ts":              "not yet measured",
};

const MODEL_RE = /model:\s*["'`]gemini-2\.5-flash["'`]/g;
/** How far below the `model:` line a generationConfig may declare the budget. */
const LOOKAHEAD_LINES = 25;

async function* walk(dir: string): AsyncGenerator<string> {
  for await (const e of Deno.readDir(dir)) {
    const p = `${dir}${e.name}`;
    if (e.isDirectory) {
      // _evals is the offline eval harness — it pins models on purpose and
      // never runs in prod.
      if (e.name === "node_modules" || e.name.startsWith(".") || e.name === "_evals") continue;
      yield* walk(`${p}/`);
    } else if (e.isFile && p.endsWith(".ts") && !p.endsWith(".test.ts")) {
      yield p;
    }
  }
}

type Site = { file: string; line: number; decided: boolean };

async function collectSites(): Promise<Site[]> {
  const sites: Site[] = [];
  for await (const path of walk(FUNCTIONS_DIR)) {
    const src = await Deno.readTextFile(path);
    if (!MODEL_RE.test(src)) { MODEL_RE.lastIndex = 0; continue; }
    MODEL_RE.lastIndex = 0;
    const lines = src.split("\n");
    lines.forEach((l, i) => {
      if (!/model:\s*["'`]gemini-2\.5-flash["'`]/.test(l)) return;
      // Look back a few lines too: some sites put generationConfig first.
      const window = lines.slice(Math.max(0, i - 8), i + LOOKAHEAD_LINES).join("\n");
      sites.push({
        file: path.slice(FUNCTIONS_DIR.length),
        line: i + 1,
        decided: /thinkingBudget/.test(window),
      });
    });
  }
  return sites;
}

Deno.test("every gemini-2.5-flash call site sets thinkingBudget or is allowlisted with a reason", async () => {
  const sites = await collectSites();
  assert(sites.length > 0, "found no gemini-2.5-flash call sites — regex drifted?");
  const undecided = sites.filter((s) => !s.decided && !(s.file in THINKING_LEFT_ON));
  assertEquals(
    undecided.map((s) => `${s.file}:${s.line}`),
    [],
    "gemini-2.5-flash call sites with thinking silently left on. Either add " +
      "`thinkingConfig: { thinkingBudget: 0 }` to generationConfig (extraction / " +
      "classification — the usual answer) or list the file in THINKING_LEFT_ON with a reason.",
  );
});

Deno.test("memo hot-path functions never take the allowlist route", async () => {
  const sites = await collectSites();
  for (const pinned of THINKING_MUST_BE_ZERO) {
    assert(!(pinned in THINKING_LEFT_ON), `${pinned} is pinned to thinking-off and may not be allowlisted`);
    const mine = sites.filter((s) => s.file === pinned);
    assert(mine.length > 0, `${pinned}: expected a gemini-2.5-flash call site (model changed? update the pin)`);
    const on = mine.filter((s) => !s.decided);
    assertEquals(on.map((s) => `${s.file}:${s.line}`), [], `${pinned}: thinking left on`);
  }
});

Deno.test("THINKING_LEFT_ON has no stale entries", async () => {
  const sites = await collectSites();
  const stale = Object.keys(THINKING_LEFT_ON).filter((f) => {
    const mine = sites.filter((s) => s.file === f);
    return mine.length === 0 || mine.every((s) => s.decided);
  });
  assertEquals(stale, [], "these files no longer have an undecided call site — remove them from THINKING_LEFT_ON");
});
