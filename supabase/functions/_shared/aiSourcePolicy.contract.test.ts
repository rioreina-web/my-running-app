/**
 * Contract tests for the AI data-provenance gates.
 *
 * These pin two obligations that are invisible in ordinary code review,
 * because the failure looks exactly like working software:
 *
 *   Strava §5.3 — Strava-sourced rows must be filterable out of model context
 *                 at ONE chokepoint, not re-implemented per function.
 *   App Review 5.1.3 — HealthKit biometrics must not reach a model without
 *                 per-athlete consent.
 *
 * Same two-direction shape as production-guardrails.contract.test.ts: nothing
 * outside the punch list may have the problem, and everything on it must still
 * have it, so an exemption cannot rot into a permanent excuse.
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

const FUNCTIONS_DIR = new URL("..", import.meta.url).pathname;

function read(p: string): string {
  return Deno.readTextFileSync(p);
}

function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
}

function listFunctionDirs(): string[] {
  const dirs: string[] = [];
  for (const e of Deno.readDirSync(FUNCTIONS_DIR)) {
    if (!e.isDirectory || e.name.startsWith("_")) continue;
    try {
      Deno.statSync(`${FUNCTIONS_DIR}/${e.name}/index.ts`);
      dirs.push(e.name);
    } catch { /* not deployable */ }
  }
  return dirs.sort();
}

const LLM_RE =
  /generativelanguage|api\.anthropic|api\.openai|callLLM|callGemini|loadPrompt/;

// ---------------------------------------------------------------------------
// The default must stay inert
// ---------------------------------------------------------------------------
//
// Turning the source policy on is a legal/product decision with a real cost
// (excluding Strava took the coach from 307 context rows to 103 as of
// 2026-08-24). It must never arrive as a side effect of an unrelated change.
Deno.test("source policy ships inert — flipping it is a deliberate act", () => {
  const src = read(`${FUNCTIONS_DIR}/_shared/aiSourcePolicy.ts`);
  const block = src.match(
    /const DEFAULT_EXCLUDED_SOURCES[\s\S]*?\];/,
  );
  assert(block, "DEFAULT_EXCLUDED_SOURCES declaration not found");
  const live = stripComments(block[0]).match(/"[^"]+"/g) ?? [];
  assertEquals(
    live,
    [],
    `DEFAULT_EXCLUDED_SOURCES is no longer empty: ${live.join(", ")}.\n` +
      `If that was intentional, update this test in the same commit and say ` +
      `why in the message — it changes what every AI surface can see.`,
  );
});

// ---------------------------------------------------------------------------
// Biometrics may not reach a model without the consent gate
// ---------------------------------------------------------------------------
//
// Empty today because no LLM-calling function reads daily_biometrics —
// detectorsC is a scaffold returning no cards. The moment that changes, this
// test fires and the implementer has to route through aiBiometricsAllowed().
const KNOWN_UNGATED_BIOMETRIC_READERS = new Set<string>([]);

Deno.test("no LLM function reads daily_biometrics without the consent gate", () => {
  const offenders: string[] = [];
  for (const fn of listFunctionDirs()) {
    if (KNOWN_UNGATED_BIOMETRIC_READERS.has(fn)) continue;
    let readsBiometrics = false;
    let callsLlm = false;
    let gated = false;
    for (const e of Deno.readDirSync(`${FUNCTIONS_DIR}/${fn}`)) {
      if (!e.isFile || !e.name.endsWith(".ts") || e.name.endsWith(".test.ts")) continue;
      const src = stripComments(read(`${FUNCTIONS_DIR}/${fn}/${e.name}`));
      if (/daily_biometrics/.test(src)) readsBiometrics = true;
      if (LLM_RE.test(src)) callsLlm = true;
      if (/aiBiometricsAllowed/.test(src)) gated = true;
    }
    if (readsBiometrics && callsLlm && !gated) offenders.push(fn);
  }
  assertEquals(
    offenders,
    [],
    `These functions put HealthKit-derived biometrics in reach of a model ` +
      `with no consent check:\n  ${offenders.join(", ")}\n` +
      `Gate the read with aiBiometricsAllowed(settings) from ` +
      `_shared/aiSourcePolicy.ts — it fails closed on a missing consent row — ` +
      `and ship the iOS consent sheet in the same change. App Review 5.1.3.`,
  );
});

Deno.test("stale exemptions: a gated biometric reader must leave the punch list", () => {
  const stale: string[] = [];
  for (const fn of KNOWN_UNGATED_BIOMETRIC_READERS) {
    let exists = false;
    let gated = false;
    try {
      Deno.statSync(`${FUNCTIONS_DIR}/${fn}/index.ts`);
      exists = true;
    } catch { /* deleted */ }
    if (!exists) {
      stale.push(`${fn} (function no longer exists)`);
      continue;
    }
    for (const e of Deno.readDirSync(`${FUNCTIONS_DIR}/${fn}`)) {
      if (!e.isFile || !e.name.endsWith(".ts")) continue;
      if (/aiBiometricsAllowed/.test(read(`${FUNCTIONS_DIR}/${fn}/${e.name}`))) gated = true;
    }
    if (gated) stale.push(`${fn} (now gated — nice!)`);
  }
  assertEquals(
    stale,
    [],
    `Remove these from KNOWN_UNGATED_BIOMETRIC_READERS:\n  ${stale.join("\n  ")}`,
  );
});

// ---------------------------------------------------------------------------
// athlete_state is the chokepoint and must stay wired
// ---------------------------------------------------------------------------
//
// Every athlete-facing AI surface narrates from athlete_state, so this one
// call site is what makes the switch meaningful. If it is removed, the policy
// silently stops applying to the surface that matters most.
Deno.test("athlete-state filters its recent logs through the source policy", () => {
  const src = stripComments(read(`${FUNCTIONS_DIR}/_shared/athlete-state.ts`));
  assert(
    /rowsForAiContext\s*\(/.test(src),
    "athlete-state.ts no longer calls rowsForAiContext — the source policy " +
      "has stopped applying to coaching-agent, the daily read and Ask.",
  );
  assert(
    /withheldCount\s*\(/.test(src),
    "athlete-state.ts no longer logs withheldCount — a context that shrank " +
      "by two-thirds would leave no trace for whoever debugs it.",
  );
});
