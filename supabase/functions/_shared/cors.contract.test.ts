/**
 * W1.2 contract tests for the CORS boundary on every edge function.
 *
 * Run: deno test --allow-read supabase/functions/_shared/cors.contract.test.ts
 *
 * What this guards against:
 *   1. A new edge function being added that inlines `Access-Control-Allow-Origin: *`
 *      instead of importing from `_shared/cors.ts`. Inlined headers bypass the
 *      fail-fast guarantee — they silently revert to "*" in production.
 *   2. An existing function regressing back to an inlined header during a
 *      drive-by edit.
 *   3. The `_shared/cors.ts` fail-fast logic (`throw` when DENO_DEPLOYMENT_ID
 *      is set and ALLOWED_ORIGIN is missing) being weakened or removed.
 *
 * Exempt:
 *   - `process-training-memo` — called only server-to-server (iOS URLSession +
 *     a Next.js api route fetching from the server). Browsers never reach it.
 *
 * Add new exempt functions to SERVER_ONLY_FUNCTIONS below with a one-line
 * justification. Anything else MUST import `corsHeaders` from `_shared/cors`.
 */

import { assert, assertEquals, assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";

const FUNCTIONS_DIR = new URL("..", import.meta.url).pathname;
const CORS_SRC      = new URL("./cors.ts", import.meta.url).pathname;

/**
 * Functions that intentionally don't need CORS because they're only called
 * server-to-server. Adding a function here means: "I confirmed no browser
 * ever calls this directly." Document the reasoning inline.
 */
const SERVER_ONLY_FUNCTIONS: Record<string, string> = {
  "process-training-memo":
    "Called from iOS (URLSession, no CORS enforcement) and the Next.js " +
    "api/retry-processing route (server-to-server fetch). Never browser-direct.",
};

// ── cors.ts itself ────────────────────────────────────────

Deno.test("cors.ts: fail-fast in production when ALLOWED_ORIGIN is unset", async () => {
  const src = await Deno.readTextFile(CORS_SRC);

  // Production is detected via DENO_DEPLOYMENT_ID (Deno Deploy / Supabase Edge sets it).
  assertMatch(
    src,
    /DENO_DEPLOYMENT_ID/,
    "cors.ts must detect production via DENO_DEPLOYMENT_ID.",
  );

  // ALLOWED_ORIGIN missing in prod must throw, not fall back to "*".
  assertMatch(
    src,
    /if\s*\(\s*isProduction[^)]*&&\s*!ALLOWED_ORIGIN_ENV\s*\)\s*\{\s*\n\s*throw\s+new\s+Error/,
    "cors.ts must `throw new Error(...)` when in production and ALLOWED_ORIGIN is unset. " +
      "Falling back to '*' silently is the bug W1.2 was meant to close.",
  );

  // The "*" fallback must only be reachable when isProduction is false.
  assertMatch(
    src,
    /ALLOWED_ORIGIN_ENV\s*\|\|\s*["']\*["']/,
    "cors.ts may fall back to '*' in dev (when DENO_DEPLOYMENT_ID is absent). " +
      "If you remove this fallback, local `supabase functions serve` will break.",
  );
});

Deno.test("cors.ts: exports corsHeaders", async () => {
  const src = await Deno.readTextFile(CORS_SRC);
  assertMatch(
    src,
    /export\s+const\s+corsHeaders\b/,
    "cors.ts must export `const corsHeaders` — that's the public API every other function imports.",
  );
});

// ── No edge function inlines its own CORS header ─────────

Deno.test("no edge function inlines Access-Control-Allow-Origin", async () => {
  const offenders: Array<{ fn: string; line: string }> = [];
  const functions = await listFunctionDirs();

  for (const fn of functions) {
    const indexPath = `${FUNCTIONS_DIR}${fn}/index.ts`;
    let src: string;
    try {
      src = await Deno.readTextFile(indexPath);
    } catch {
      continue;
    }

    const match = src.match(/.*Access-Control-Allow-Origin.*/);
    if (match) {
      offenders.push({ fn, line: match[0].trim() });
    }
  }

  assertEquals(
    offenders,
    [],
    "Edge functions inlining `Access-Control-Allow-Origin` (must import corsHeaders from _shared/cors instead):\n" +
      offenders.map((o) => `  - ${o.fn}: ${o.line}`).join("\n") +
      "\n\nWhy this matters: inlined headers bypass the fail-fast guarantee in _shared/cors.ts. " +
      "In production they silently fall back to '*'. See TASKS.md W1.2.",
  );
});

// ── Every browser-reachable function imports corsHeaders from _shared/cors ─

Deno.test("every browser-reachable function imports corsHeaders from _shared/cors", async () => {
  const offenders: Array<{ fn: string; reason: string }> = [];
  const functions = await listFunctionDirs();

  for (const fn of functions) {
    if (fn in SERVER_ONLY_FUNCTIONS) continue; // explicit opt-out

    const indexPath = `${FUNCTIONS_DIR}${fn}/index.ts`;
    let src: string;
    try {
      src = await Deno.readTextFile(indexPath);
    } catch {
      continue;
    }

    const importsShared = /import\s*\{[^}]*\bcorsHeaders\b[^}]*\}\s*from\s*["']\.\.\/_shared\/cors(?:\.ts)?["']/
      .test(src);

    if (!importsShared) {
      offenders.push({
        fn,
        reason:
          "no `import { corsHeaders } from \"../_shared/cors.ts\"`. " +
          "Either add the import, or — if this function is genuinely server-only — " +
          "add it to SERVER_ONLY_FUNCTIONS in this test file with a justification.",
      });
    }
  }

  assertEquals(
    offenders,
    [],
    "Functions missing the canonical corsHeaders import:\n" +
      offenders.map((o) => `  - ${o.fn}: ${o.reason}`).join("\n"),
  );
});

// ── Server-only opt-outs have a non-empty justification ──

Deno.test("SERVER_ONLY_FUNCTIONS entries are justified", () => {
  for (const [fn, reason] of Object.entries(SERVER_ONLY_FUNCTIONS)) {
    assert(
      reason.trim().length >= 30,
      `SERVER_ONLY_FUNCTIONS[${fn}] needs a ≥30-char justification. ` +
        `Document who actually calls this function and why CORS isn't needed.`,
    );
  }
});

// ── Helpers ───────────────────────────────────────────────

async function listFunctionDirs(): Promise<string[]> {
  const out: string[] = [];
  for await (const entry of Deno.readDir(FUNCTIONS_DIR)) {
    if (!entry.isDirectory) continue;
    if (entry.name.startsWith("_")) continue; // _shared, _evals (future), etc.
    out.push(entry.name);
  }
  return out.sort();
}
