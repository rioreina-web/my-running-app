/**
 * HOTFIX-H.4 contract tests for rate-limit wiring on the web API surface.
 *
 * Run: cd web && node --test tests/rate-limit.contract.test.mjs
 *
 * What this guards against:
 *   1. Per-route limits getting accidentally loosened (e.g. from 5 → 5000).
 *   2. The auth gate getting reordered after the rate-limit gate (which would
 *      let unauth'd requests burn buckets via undefined user.id keys).
 *   3. Rate-limit running AFTER an upstream fetch (which would let a flood
 *      burn LLM/edge-function calls before getting blocked).
 *   4. A new API route being added without rate-limit protection or an
 *      explicit exemption.
 *
 * Why a static contract test rather than a runtime integration test:
 *   The rate-limit helper itself is 12 lines and provably correct from
 *   reading. The actual regression risk is the call-site wiring in 5+ route
 *   files, which is a static property a contract test catches faithfully
 *   without spinning up Redis/Next.js.
 */

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE = path.dirname(fileURLToPath(import.meta.url));
const API_DIR = path.resolve(HERE, "..", "src", "app", "api");
const HELPER_PATH = path.resolve(HERE, "..", "src", "lib", "rate-limit.ts");

// ── Pinned per-route contract ────────────────────────────
// Every entry below: file, HTTP method, the key tag we expect, and the
// (limit, windowMs) pair pinned at H.4 close. Loosening a limit here
// without reviewing this file means the loosening was unconscious.
const PROTECTED_ROUTES = [
  { file: "coach/route.ts",            method: "POST", tag: "coach",            limit: 20, windowMs: 60_000 },
  { file: "assign-plan/route.ts",      method: "POST", tag: "assign-plan",      limit: 10, windowMs: 60_000 },
  { file: "weekly-report/route.ts",    method: "POST", tag: "weekly-report",    limit:  5, windowMs: 60_000 },
  { file: "retry-processing/route.ts", method: "POST", tag: "retry-processing", limit:  5, windowMs: 60_000 },
  { file: "vital-stream/route.ts",     method: "GET",  tag: "vital-stream",     limit: 60, windowMs: 60_000 },
  { file: "shift-day/route.ts",        method: "POST", tag: "shift-day",        limit: 30, windowMs: 60_000 },
];

// ── Per-route wiring assertions ──────────────────────────

for (const route of PROTECTED_ROUTES) {
  test(`route ${route.file}: enforceRateLimit wired with key=user.id:${route.tag}, limit=${route.limit}, windowMs=${route.windowMs}`, async () => {
    const src = await readFile(path.join(API_DIR, route.file), "utf8");

    // Imports the helper.
    assert.match(
      src,
      /import\s*\{[^}]*\benforceRateLimit\b[^}]*\}\s*from\s*["']@\/lib\/rate-limit["']/,
      `${route.file} must import enforceRateLimit from @/lib/rate-limit`,
    );

    // Exports the expected method handler.
    assert.match(
      src,
      new RegExp(`export\\s+async\\s+function\\s+${route.method}\\b`),
      `${route.file} must export an async ${route.method} handler`,
    );

    // Calls enforceRateLimit with the canonical key shape and pinned limits.
    // 60_000 is the source spelling; we accept both 60_000 and 60000.
    const limitN = String(route.limit);
    const windowN = String(route.windowMs);
    const windowAlt = String(route.windowMs).replace(/(\d{3})$/, "_$1"); // 60000 → 60_000
    const callRegex = new RegExp(
      `enforceRateLimit\\(\\s*\`\\$\\{user\\.id\\}:${route.tag}\`\\s*,\\s*${limitN}\\s*,\\s*(?:${windowN}|${windowAlt})\\s*\\)`,
    );
    assert.match(
      src,
      callRegex,
      `${route.file} must call enforceRateLimit(\`\${user.id}:${route.tag}\`, ${route.limit}, ${route.windowMs}). ` +
        `If you intentionally changed limits, update PROTECTED_ROUTES in this test file.`,
    );

    // Auth gate must appear BEFORE the rate-limit call. Otherwise an
    // unauth'd request hits the limiter with `undefined:tag` as the key
    // and can DOS the bucket for legitimate users hitting the same route
    // before they've signed in (rare but possible with shared keys).
    const authIdx = src.search(/supabase\.auth\.getUser\b/);
    const rlIdx = src.search(/enforceRateLimit\s*\(/);
    assert.ok(authIdx >= 0, `${route.file} must call supabase.auth.getUser() to scope the rate-limit key`);
    assert.ok(
      rlIdx > authIdx,
      `${route.file}: auth check must run BEFORE enforceRateLimit (so the key is scoped to the authenticated user.id)`,
    );

    // Rate-limit must run BEFORE any upstream fetch(). Otherwise a flood
    // of requests burns expensive upstream calls (LLM, edge functions)
    // before the limiter rejects them.
    const fetchIdx = src.search(/\bfetch\s*\(/);
    if (fetchIdx >= 0) {
      assert.ok(
        rlIdx < fetchIdx,
        `${route.file}: enforceRateLimit must run BEFORE the first upstream fetch() so blocked requests don't burn upstream calls`,
      );
    }

    // The helper's return value must be checked + early-returned. Without
    // this, the 429 Response is produced but discarded and the request
    // continues into the handler.
    assert.match(
      src,
      /if\s*\(\s*rateLimited\s*\)\s*return\s+rateLimited\b/,
      `${route.file} must early-return when enforceRateLimit produces a 429 (\`if (rateLimited) return rateLimited;\`)`,
    );
  });
}

// ── Helper module exports the public API ──────────────────

test("rate-limit.ts exports enforceRateLimit and checkRateLimit", async () => {
  const src = await readFile(HELPER_PATH, "utf8");
  assert.match(src, /export\s+async\s+function\s+enforceRateLimit\b/, "must export enforceRateLimit");
  assert.match(src, /export\s+async\s+function\s+checkRateLimit\b/, "must export checkRateLimit");

  // Permissive fallback when Redis env vars are absent (local dev).
  // If this branch goes away silently, every dev machine starts hitting
  // a real Redis or crashing.
  assert.match(
    src,
    /UPSTASH_REDIS_REST_URL/,
    "permissive-fallback path must check UPSTASH_REDIS_REST_URL env var",
  );

  // 429 response shape — Retry-After header per RFC 9110.
  assert.match(src, /["']Retry-After["']/, "blocked response must set Retry-After header");
  assert.match(src, /status:\s*429/, "blocked response must use status 429");
});

// ── No silently unprotected routes ───────────────────────

test("HOTFIX-H.4: every API route is rate-limited or explicitly exempt", async () => {
  const allRouteFiles = await walkRouteFiles(API_DIR);
  const protectedSet = new Set(
    PROTECTED_ROUTES.map((r) => r.file.replace(/\\/g, "/")),
  );

  /** @type {Array<{ file: string; reason: string }>} */
  const offenders = [];
  for (const rel of allRouteFiles) {
    if (protectedSet.has(rel)) continue;

    const src = await readFile(path.join(API_DIR, rel), "utf8");

    // Already wires the helper but isn't in our pinned list. That's not a
    // bug — the route is protected. We just don't have its limits pinned
    // here yet. Flag for the maintainer to add a pinned entry above.
    if (/\benforceRateLimit\b/.test(src)) {
      offenders.push({
        file: rel,
        reason:
          "uses enforceRateLimit but isn't pinned in PROTECTED_ROUTES — add an entry above so its (limit, window) is regression-protected",
      });
      continue;
    }

    // Explicit opt-out: a comment of the form `// @rate-limit-exempt: <reason>`.
    // Use this for routes that genuinely can't be user-keyed (e.g. webhook
    // callbacks where the caller isn't an authenticated user).
    if (/@rate-limit-exempt\s*:/.test(src)) continue;

    offenders.push({
      file: rel,
      reason:
        "no enforceRateLimit call and no `// @rate-limit-exempt: <reason>` comment. Either wire rate-limiting or document the exemption.",
    });
  }

  assert.deepStrictEqual(
    offenders,
    [],
    "Rate-limit contract violations:\n" +
      offenders.map((o) => `  - ${o.file}: ${o.reason}`).join("\n"),
  );
});

/**
 * Walk the api/ tree and return every route.ts/tsx/js/mjs file as a
 * forward-slash-relative path from API_DIR.
 * @param {string} dir
 * @returns {Promise<string[]>}
 */
async function walkRouteFiles(dir) {
  const out = [];
  async function walk(curr, rel) {
    const entries = await readdir(curr, { withFileTypes: true });
    for (const e of entries) {
      const abs = path.join(curr, e.name);
      const r = rel ? `${rel}/${e.name}` : e.name;
      if (e.isDirectory()) {
        await walk(abs, r);
      } else if (e.isFile() && /^route\.(ts|tsx|js|mjs)$/.test(e.name)) {
        out.push(r);
      }
    }
  }
  await walk(dir, "");
  return out.sort();
}
