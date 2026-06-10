/**
 * W1.3 contract tests for the service-role-key boundary on the web surface.
 *
 * Run: cd web && node --test tests/env-server-boundary.contract.test.mjs
 *
 * What this guards against:
 *   1. The `import "server-only"` line at the top of env.server.ts being
 *      removed or moved — without it, Next.js will happily bundle the
 *      service-role key into the client JS payload on any naive import.
 *   2. A new client component (`"use client"` directive) importing
 *      `@/lib/env.server` (or any `*.server.ts` module that re-exports it).
 *      Next.js *should* catch this at build time via the server-only
 *      package, but a static contract test catches it in the editor / PR
 *      review and gives a clearer error message.
 *   3. A direct `process.env.SUPABASE_SERVICE_ROLE_KEY` read appearing
 *      anywhere outside `env.server.ts` — i.e. someone sidestepping the
 *      audited surface. The ESLint `no-restricted-syntax` rule should
 *      catch this; the contract test verifies the rule is still in place
 *      and that no existing file violates it.
 *   4. The expected server-side callers (api routes + middleware) drifting
 *      to a different import path or reading the key directly from
 *      `process.env`.
 *
 * Why a static contract test rather than relying purely on Next.js build:
 *   `server-only` is enforced at bundle time — the build fails *if* you
 *   import. But a developer can spend a long compile cycle hitting the
 *   error and chasing it. A node:test that runs in <1s gives the same
 *   guarantee at PR time. Matches the pattern of rate-limit.contract.test.mjs.
 */

import { test } from "node:test";
import { strict as assert } from "node:assert";
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const HERE       = path.dirname(fileURLToPath(import.meta.url));
const WEB_ROOT   = path.resolve(HERE, "..");
const SRC_DIR    = path.resolve(WEB_ROOT, "src");
const ENV_SERVER = path.resolve(SRC_DIR, "lib", "env.server.ts");
const ESLINT_CFG = path.resolve(WEB_ROOT, "eslint.config.mjs");

// ── Pinned canonical importers ────────────────────────────
// Every entry: a file that is allowed to import from @/lib/env.server,
// and what it imports. Adding a new server-side caller? Add it here.
const ALLOWED_CALLERS = [
  { file: "src/middleware.ts",                       imports: 'side-effect' },
  { file: "src/app/api/coach/route.ts",              imports: 'SUPABASE_SERVICE_ROLE_KEY' },
  { file: "src/app/api/assign-plan/route.ts",        imports: 'SUPABASE_SERVICE_ROLE_KEY' },
  { file: "src/app/api/weekly-report/route.ts",      imports: 'SUPABASE_SERVICE_ROLE_KEY' },
  { file: "src/app/api/retry-processing/route.ts",   imports: 'SUPABASE_SERVICE_ROLE_KEY' },
];

// ── env.server.ts structure ─────────────────────────────────

test("env.server.ts begins with `import \"server-only\"` on line 1", async () => {
  const src = await readFile(ENV_SERVER, "utf8");
  const firstNonBlank = src
    .split("\n")
    .find((l) => l.trim().length > 0);

  assert.match(
    firstNonBlank ?? "",
    /^import\s+["']server-only["']\s*;?\s*$/,
    `env.server.ts MUST start with \`import "server-only";\`. Found: ${JSON.stringify(firstNonBlank ?? "(empty file)")}. ` +
      `Without this import, Next.js will bundle the service-role key into the client JS payload on any naive import from a client component.`,
  );
});

test("env.server.ts exports SUPABASE_SERVICE_ROLE_KEY", async () => {
  const src = await readFile(ENV_SERVER, "utf8");
  assert.match(
    src,
    /export\s+const\s+SUPABASE_SERVICE_ROLE_KEY\b/,
    "env.server.ts must export const SUPABASE_SERVICE_ROLE_KEY so callers have a single audited surface.",
  );
});

test("env.server.ts throws on access when the key is unset", async () => {
  // Defends against the silent-empty-string failure mode: if the key is
  // missing in prod, the module should refuse to load rather than letting
  // a server-side caller wield an empty bearer credential.
  const src = await readFile(ENV_SERVER, "utf8");
  assert.match(
    src,
    /throw\s+new\s+Error\(/,
    "env.server.ts must `throw new Error(...)` when SUPABASE_SERVICE_ROLE_KEY is unset.",
  );
});

// ── ESLint rule still in place ─────────────────────────────

test("eslint.config.mjs bans direct process.env.SUPABASE_SERVICE_ROLE_KEY reads", async () => {
  const src = await readFile(ESLINT_CFG, "utf8");
  assert.match(
    src,
    /no-restricted-syntax/,
    "eslint.config.mjs must have a no-restricted-syntax rule. See TASKS.md W1.3.",
  );
  assert.match(
    src,
    /SUPABASE_SERVICE_ROLE_KEY/,
    "The no-restricted-syntax rule must reference SUPABASE_SERVICE_ROLE_KEY by name.",
  );
  assert.match(
    src,
    /env\.server/,
    "The rule's message must point developers to env.server as the canonical surface.",
  );
});

// ── No "use client" file imports env.server (or anything ending in .server) ─

test("no \"use client\" file imports a *.server module", async () => {
  const offenders = [];
  const files = await walkSrcFiles(SRC_DIR);

  for (const abs of files) {
    const src = await readFile(abs, "utf8");
    const isClient = /^\s*(["'])use client\1\s*;?\s*$/m.test(
      src.split("\n").slice(0, 5).join("\n"),
    );
    if (!isClient) continue;

    // Match any import of a path ending in `.server` (no extension required
    // because TS bundlers strip the .ts). Also catches the alias form.
    const badImport = src.match(
      /\bfrom\s+["']((?:@\/|\.\.?\/)[^"']*?\.server)["']/,
    );
    if (badImport) {
      const rel = path.relative(WEB_ROOT, abs).replace(/\\/g, "/");
      offenders.push({ file: rel, importPath: badImport[1] });
    }
  }

  assert.deepStrictEqual(
    offenders,
    [],
    "Client-side files MUST NOT import server-only modules:\n" +
      offenders.map((o) => `  - ${o.file} imports ${o.importPath}`).join("\n") +
      "\nThese imports will leak server secrets into the client bundle. Move the logic to a server component or an api/ route.",
  );
});

// ── No file outside env.server reads process.env.SUPABASE_SERVICE_ROLE_KEY ─

test("only env.server.ts reads process.env.SUPABASE_SERVICE_ROLE_KEY", async () => {
  const offenders = [];
  const files = await walkSrcFiles(SRC_DIR);

  for (const abs of files) {
    if (path.resolve(abs) === ENV_SERVER) continue;
    const src = await readFile(abs, "utf8");
    if (/process\.env\.SUPABASE_SERVICE_ROLE_KEY\b/.test(src)) {
      offenders.push(path.relative(WEB_ROOT, abs).replace(/\\/g, "/"));
    }
  }

  assert.deepStrictEqual(
    offenders,
    [],
    "Direct reads of process.env.SUPABASE_SERVICE_ROLE_KEY found outside env.server.ts:\n" +
      offenders.map((f) => `  - ${f}`).join("\n") +
      "\nImport SUPABASE_SERVICE_ROLE_KEY from '@/lib/env.server' instead. " +
      "The ESLint no-restricted-syntax rule should be catching this — if it isn't, the rule has drifted.",
  );
});

// ── Pinned callers actually import from the canonical path ─

for (const caller of ALLOWED_CALLERS) {
  test(`pinned caller ${caller.file} imports from @/lib/env.server`, async () => {
    const abs = path.resolve(WEB_ROOT, caller.file);
    const src = await readFile(abs, "utf8");

    if (caller.imports === "side-effect") {
      // Side-effect import: `import "@/lib/env.server";` (runs validateEnv).
      assert.match(
        src,
        /import\s+["']@\/lib\/env\.server["']\s*;?/,
        `${caller.file} must have a side-effect import: import "@/lib/env.server";`,
      );
    } else {
      // Named import.
      const named = caller.imports;
      const re = new RegExp(
        `import\\s*\\{[^}]*\\b${named}\\b[^}]*\\}\\s*from\\s*["']@\\/lib\\/env\\.server["']`,
      );
      assert.match(
        src,
        re,
        `${caller.file} must import { ${named} } from "@/lib/env.server".`,
      );
    }
  });
}

// ── Walker ─────────────────────────────────────────────────

/**
 * Walk src/ and return every .ts/.tsx file as an absolute path. Skips
 * .next/, node_modules/, and tests/.
 * @param {string} dir
 * @returns {Promise<string[]>}
 */
async function walkSrcFiles(dir) {
  const out = [];
  async function walk(curr) {
    const entries = await readdir(curr, { withFileTypes: true });
    for (const e of entries) {
      if (e.name.startsWith(".")) continue;
      if (e.name === "node_modules" || e.name === ".next") continue;
      const abs = path.join(curr, e.name);
      if (e.isDirectory()) {
        await walk(abs);
      } else if (e.isFile() && /\.(ts|tsx|js|jsx|mjs)$/.test(e.name)) {
        out.push(abs);
      }
    }
  }
  await walk(dir);
  return out.sort();
}
