/**
 * Production guardrail contract tests.
 *
 * Run: deno test --allow-all supabase/functions/_shared/production-guardrails.contract.test.ts
 * (CI already runs every *.test.ts under supabase/functions via `deno test --allow-all`.)
 *
 * What this file is
 * -----------------
 * Each test pins one of the failure points from
 * `outputs/beta-security-and-failure-review-2026-07-01.md` so it can never
 * regress silently — and so a NEW function/migration/upload path can't
 * reintroduce the same class of bug.
 *
 * The KNOWN_* lists below are the punch list of things that are still
 * broken today. The tests assert two directions:
 *
 *   1. Nothing OUTSIDE a KNOWN_* list may have the problem
 *      (stops new regressions cold).
 *   2. Everything INSIDE a KNOWN_* list must still have the problem
 *      (a "stale exemption" check — the moment you fix one, the test
 *      fails with instructions to delete the entry, so the list can
 *      never rot into a permanent excuse).
 *
 * Review-item map:
 *   C1 → "storage buckets" tests      (public voice-memo bucket)
 *   H1 → "rate limiting" tests        (fail-closed behavior — now fixed; locked in here)
 *   H3 → "edge function auth" tests   (functions missing a per-user auth gate)
 *   H4 → "timezone writer" test       (nothing writes athlete_settings.timezone)
 *   H5 → "check-in upload" test       (iOS uploadCheckIn uses the dead direct-storage path)
 *   M4 → "user_profiles ghost table" tests (queries against a table that doesn't exist)
 */

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";

// Paths are relative to this file: _shared → functions → supabase → repo root
const FUNCTIONS_DIR = new URL("..", import.meta.url).pathname;
const MIGRATIONS_DIR = new URL("../../migrations", import.meta.url).pathname;
const REPO_ROOT = new URL("../../..", import.meta.url).pathname;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function read(path: string): string {
  return Deno.readTextFileSync(path);
}

function listFunctionDirs(): string[] {
  const dirs: string[] = [];
  for (const entry of Deno.readDirSync(FUNCTIONS_DIR)) {
    if (!entry.isDirectory) continue;
    if (entry.name.startsWith("_")) continue; // _shared, _evals
    try {
      Deno.statSync(`${FUNCTIONS_DIR}/${entry.name}/index.ts`);
      dirs.push(entry.name);
    } catch {
      // no index.ts — not a deployable function
    }
  }
  return dirs.sort();
}

/** Strip line comments and block comments so we only match live code. */
function stripComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "") // block comments
    .replace(/^\s*\/\/.*$/gm, "") // line comments
    .replace(/^\s*--.*$/gm, ""); // SQL comments
}

function* walkFiles(root: string, exts: string[]): Generator<string> {
  const skip = new Set([
    "node_modules", ".git", ".claude", "build", "DerivedData", ".next",
  ]);
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop()!;
    let entries;
    try {
      entries = Deno.readDirSync(dir);
    } catch {
      continue;
    }
    for (const e of entries) {
      if (skip.has(e.name)) continue;
      const p = `${dir}/${e.name}`;
      if (e.isDirectory) stack.push(p);
      else if (exts.some((x) => e.name.endsWith(x))) yield p;
    }
  }
}

// ===========================================================================
// H3 — Edge function auth: every function must call a shared auth gate
// ===========================================================================
//
// The shared gates in `_shared/auth.ts` (requireAuthOrServiceRole /
// getAuthenticatedUser / requireServiceRole) are the codebase's own
// convention for making sure a caller can only act on THEIR user_id.
// A function without one relies on the API gateway's JWT check alone,
// which does NOT stop one logged-in user from passing another user's id
// — that's exactly the compute-workout-features bug (review item H3).

// Matches direct calls `helper(...)` AND the dependency-injection pattern
// `(deps.resolveUser ?? getAuthenticatedUser)(req)` / `(deps.authGate ??
// requireServiceRole)(req, ...)` used by edit-scheduled-workout,
// set-fitness-anchor, and rewrite-block — the name there is followed by `)`,
// not `(`. Import lines (`helper,`) still don't count as a gate.
const AUTH_GATE_RE =
  /\b(requireAuthOrServiceRole|getAuthenticatedUser|requireServiceRole)\s*[()]/;

/**
 * Functions that do NOT call a shared auth gate today.
 *
 * This is the audit punch list. Each entry needs one of:
 *   - a `requireAuthOrServiceRole(req, body.user_id, corsHeaders)` line
 *     (the pattern its sibling `correct-workout-structure` already uses), or
 *   - a documented reason it's safe (pure parser, cron-only + shared-secret).
 *
 * When you fix one, DELETE it from this list — the stale-exemption test
 * will remind you.
 */
const KNOWN_UNGATED_FUNCTIONS = new Set([
  "adaptive-workout", // 410 Gone tombstone — no DB access, no body parsing; delete with the dir
  "coaching-feedback",
  "compute-fitness-snapshot",
  // compute-workout-features — H3 FIXED 2026-07-15: requireAuthOrServiceRole gate added.
  "consolidate-memories", // hand-rolled Bearer check — migrate to the shared gate
  "drain-coach-insight-jobs", // cron drain — gate with requireServiceRole
  "drain-coachable-moment-jobs", // cron drain — gate with requireServiceRole
  "drain-voice-processing-jobs", // cron drain — gate with requireServiceRole
  "evaluate-coachable-moment",
  "generate-workout-insight",
  "ingest-documents",
  "parse-workout-shorthand", // pure text parser (no DB, no LLM) — likely safe; document + keep or gate
  "rebuild-athlete-state",
  "reconcile-log",
  // shift-day — removed 2026-07-15: it was ALWAYS gated via the DI pattern
  // `(deps.resolveUser ?? getAuthenticatedUser)(req)`; the old regex just
  // couldn't see it. The widened AUTH_GATE_RE now matches it.
  "strava-sync",
]);

Deno.test("H3 — no NEW edge function ships without a shared auth gate", () => {
  const offenders: string[] = [];
  for (const fn of listFunctionDirs()) {
    if (KNOWN_UNGATED_FUNCTIONS.has(fn)) continue;
    // A gate anywhere in the function's own files counts.
    let gated = false;
    for (const f of walkFiles(`${FUNCTIONS_DIR}/${fn}`, [".ts"])) {
      if (AUTH_GATE_RE.test(stripComments(read(f)))) {
        gated = true;
        break;
      }
    }
    if (!gated) offenders.push(fn);
  }
  assertEquals(
    offenders,
    [],
    `These edge functions have NO per-user auth gate and are not on the ` +
      `known punch list:\n  ${offenders.join(", ")}\n` +
      `Add requireAuthOrServiceRole(req, body.user_id, corsHeaders) near the ` +
      `top of the handler (see correct-workout-structure for the pattern), ` +
      `or — only if genuinely safe — add it to KNOWN_UNGATED_FUNCTIONS with a reason.`,
  );
});

Deno.test("H3 — stale exemptions: fixed functions must leave the punch list", () => {
  const stale: string[] = [];
  for (const fn of KNOWN_UNGATED_FUNCTIONS) {
    let exists = false;
    try {
      Deno.statSync(`${FUNCTIONS_DIR}/${fn}/index.ts`);
      exists = true;
    } catch { /* deleted function — also stale */ }
    if (!exists) {
      stale.push(`${fn} (function no longer exists)`);
      continue;
    }
    let gated = false;
    for (const f of walkFiles(`${FUNCTIONS_DIR}/${fn}`, [".ts"])) {
      if (AUTH_GATE_RE.test(stripComments(read(f)))) {
        gated = true;
        break;
      }
    }
    if (gated) stale.push(`${fn} (now has an auth gate — nice!)`);
  }
  assertEquals(
    stale,
    [],
    `Remove these from KNOWN_UNGATED_FUNCTIONS in this test file:\n  ` +
      stale.join("\n  "),
  );
});

// ===========================================================================
// C1 — Storage buckets: no user-data bucket may be public
// ===========================================================================
//
// A public bucket serves files at /storage/v1/object/public/... which
// bypasses RLS entirely. Voice memos are health data (review item C1).
// This test replays every migration in order and computes each bucket's
// final public/private state.

/** Buckets that are INTENTIONALLY public (non-user data only). */
const ALLOWED_PUBLIC_BUCKETS = new Set([
  "content-videos", // marketing/content library — not user data
]);

/** Buckets that are public today but MUST become private. Punch list. */
// C1 CLOSED 2026-07-15: training-memos + plan-attachments flipped private
// (20260715120000_make_user_storage_buckets_private.sql). Empty set kept so
// any future public user-data bucket lands back on this punch list.
const KNOWN_PUBLIC_BUCKETS_TO_FIX = new Set<string>([]);

function computeBucketPublicState(): Map<string, boolean> {
  const state = new Map<string, boolean>();
  const files: string[] = [];
  for (const e of Deno.readDirSync(MIGRATIONS_DIR)) {
    if (e.isFile && e.name.endsWith(".sql")) files.push(e.name);
  }
  files.sort(); // timestamp-prefixed names → chronological order
  for (const name of files) {
    const sql = stripComments(read(`${MIGRATIONS_DIR}/${name}`)).replace(
      /\s+/g,
      " ",
    );
    // INSERT INTO storage.buckets (id, name, public) VALUES ('x','x', true) [ON CONFLICT ...]
    const insertRe =
      /insert into storage\.buckets\s*\(id,\s*name,\s*public\)\s*values\s*\(\s*'([^']+)'\s*,\s*'[^']+'\s*,\s*(true|false)\s*\)(\s*on conflict\s*\(id\)\s*do\s+(nothing|update set public = (true|false)))?/gi;
    for (const m of sql.matchAll(insertRe)) {
      const id = m[1];
      const insertVal = m[2].toLowerCase() === "true";
      const conflict = (m[4] || "").toLowerCase();
      if (!state.has(id)) {
        state.set(id, insertVal);
      } else if (conflict.startsWith("update")) {
        state.set(id, (m[5] || "").toLowerCase() === "true");
      }
      // ON CONFLICT DO NOTHING → existing state wins
    }
    // UPDATE storage.buckets SET public = x WHERE id = 'y'
    const updateRe =
      /update storage\.buckets\s+set\s+public\s*=\s*(true|false)\s+where\s+id\s*=\s*'([^']+)'/gi;
    for (const m of sql.matchAll(updateRe)) {
      state.set(m[2], m[1].toLowerCase() === "true");
    }
  }
  return state;
}

Deno.test("C1 — no unexpected public storage bucket", () => {
  const state = computeBucketPublicState();
  const offenders: string[] = [];
  for (const [bucket, isPublic] of state) {
    if (!isPublic) continue;
    if (ALLOWED_PUBLIC_BUCKETS.has(bucket)) continue;
    if (KNOWN_PUBLIC_BUCKETS_TO_FIX.has(bucket)) continue;
    offenders.push(bucket);
  }
  assertEquals(
    offenders,
    [],
    `These buckets end up PUBLIC after replaying all migrations: ` +
      `${offenders.join(", ")}. Public buckets bypass RLS — anyone with a ` +
      `URL can download user files with no login. Write a migration setting ` +
      `public = false and switch reads to createSignedUrl().`,
  );
});

Deno.test("C1 — stale exemptions: privatized buckets must leave the punch list", () => {
  const state = computeBucketPublicState();
  const stale = [...KNOWN_PUBLIC_BUCKETS_TO_FIX].filter(
    (b) => state.get(b) !== true,
  );
  assertEquals(
    stale,
    [],
    `These buckets are no longer public — remove them from ` +
      `KNOWN_PUBLIC_BUCKETS_TO_FIX: ${stale.join(", ")}`,
  );
});

// ===========================================================================
// H1 — Rate limiting must fail CLOSED when Redis isn't configured
// ===========================================================================
//
// The review flagged that missing Upstash env vars silently disabled all
// rate limiting (unbounded LLM bill). The code now fails closed — these
// tests lock that behavior in so a future refactor can't regress it.

Deno.test("H1 — checkRateLimit denies when Redis is not configured", async () => {
  Deno.env.delete("UPSTASH_REDIS_URL");
  Deno.env.delete("UPSTASH_REDIS_TOKEN");
  const { checkRateLimit } = await import("./rateLimit.ts");
  const result = await checkRateLimit("guardrail-test-user");
  assertEquals(
    result.allowed,
    false,
    "With no Redis configured, checkRateLimit must DENY (fail closed), " +
      "not silently allow. Silently allowing = unbounded LLM bill.",
  );
});

Deno.test("H1 — checkFeatureRateLimit denies when Redis is not configured", async () => {
  Deno.env.delete("UPSTASH_REDIS_URL");
  Deno.env.delete("UPSTASH_REDIS_TOKEN");
  const { checkFeatureRateLimit } = await import("./rateLimit.ts");
  const result = await checkFeatureRateLimit("guardrail-test-user", "coaching");
  assertEquals(
    result.allowed,
    false,
    "With no Redis configured, checkFeatureRateLimit must DENY (fail closed).",
  );
});

Deno.test("H1 — enforceFeatureRateLimit fails CLOSED in production when Redis is not configured", async () => {
  // The enforce* wrappers used to short-circuit `return null` (= allow) when
  // the Upstash env was missing — the exact fail-open the review flagged.
  // In production (DENO_DEPLOYMENT_ID set) they must now fall through to the
  // fail-closed check and return a 429 Response.
  Deno.env.delete("UPSTASH_REDIS_URL");
  Deno.env.delete("UPSTASH_REDIS_TOKEN");
  Deno.env.set("DENO_DEPLOYMENT_ID", "guardrail-test-prod");
  try {
    const { enforceFeatureRateLimit } = await import("./rateLimit.ts");
    const res = await enforceFeatureRateLimit("guardrail-test-user", "coaching", {});
    assert(
      res instanceof Response && res.status === 429,
      "In production with no Redis configured, enforceFeatureRateLimit must " +
        "return a 429 Response (fail closed), not null. Null = every per-user " +
        "LLM ceiling silently gone (review item H1).",
    );
  } finally {
    Deno.env.delete("DENO_DEPLOYMENT_ID");
  }
});

Deno.test("H1 — enforceMonthlyCap fails CLOSED in production when Redis is not configured", async () => {
  Deno.env.delete("UPSTASH_REDIS_URL");
  Deno.env.delete("UPSTASH_REDIS_TOKEN");
  Deno.env.set("DENO_DEPLOYMENT_ID", "guardrail-test-prod");
  try {
    const { enforceMonthlyCap } = await import("./rateLimit.ts");
    const res = await enforceMonthlyCap("guardrail-test-user", "coaching", {});
    assert(
      res instanceof Response && res.status === 429,
      "In production with no Redis configured, enforceMonthlyCap must return " +
        "a 429 Response (fail closed) — it is a cost ceiling (review item H1).",
    );
  } finally {
    Deno.env.delete("DENO_DEPLOYMENT_ID");
  }
});

Deno.test("H1 — enforce* wrappers stay permissive in LOCAL DEV without Redis", async () => {
  // Local `supabase functions serve` has neither Upstash env nor
  // DENO_DEPLOYMENT_ID — the gates must skip so dev stays frictionless.
  Deno.env.delete("UPSTASH_REDIS_URL");
  Deno.env.delete("UPSTASH_REDIS_TOKEN");
  Deno.env.delete("DENO_DEPLOYMENT_ID");
  const { enforceFeatureRateLimit, enforceMonthlyCap } = await import("./rateLimit.ts");
  assertEquals(
    await enforceFeatureRateLimit("guardrail-test-user", "coaching", {}),
    null,
    "Dev (no DENO_DEPLOYMENT_ID, no Redis) must skip the daily gate.",
  );
  assertEquals(
    await enforceMonthlyCap("guardrail-test-user", "coaching", {}),
    null,
    "Dev (no DENO_DEPLOYMENT_ID, no Redis) must skip the monthly cap.",
  );
});

Deno.test("H1 — the unconfigured-Redis path never returns allowed:true", () => {
  // Belt and braces: the source of rateLimit.ts must not contain a branch
  // that returns { allowed: true } when the client is missing.
  const src = read(`${FUNCTIONS_DIR}/_shared/rateLimit.ts`);
  const noClientBranches = src.match(
    /if\s*\(\s*!client\s*\)\s*\{[\s\S]*?\}/g,
  ) ?? [];
  assert(
    noClientBranches.length > 0,
    "Expected rateLimit.ts to have explicit `if (!client)` branches.",
  );
  for (const branch of noClientBranches) {
    assert(
      !/allowed:\s*true/.test(branch),
      `A missing-Redis branch in rateLimit.ts returns allowed:true — that ` +
        `silently disables rate limiting (review item H1). Branch:\n${branch}`,
    );
  }
});

// ===========================================================================
// M4 — No live queries against the deleted `user_profiles` table
// ===========================================================================
//
// The table never shipped to prod. Queries against it error, the error is
// swallowed, and the feature silently no-ops (e.g. weather enrichment).

/** Files that still query user_profiles today. Punch list — repoint to athlete_settings. */
const KNOWN_USER_PROFILES_READERS = new Set([
  "post-run-reconciliation/index.ts",
  "reconcile-log/index.ts",
  "weekly-coaching-report/index.ts",
  "_shared/profile.ts",
]);

const USER_PROFILES_RE = /\.from\(\s*["'`]user_profiles["'`]\s*\)/;

function findUserProfilesReaders(): string[] {
  const hits: string[] = [];
  for (const f of walkFiles(FUNCTIONS_DIR, [".ts"])) {
    if (f.endsWith(".test.ts")) continue;
    if (f.includes("/_evals/")) continue;
    if (USER_PROFILES_RE.test(stripComments(read(f)))) {
      hits.push(f.slice(FUNCTIONS_DIR.length).replace(/^\//, ""));
    }
  }
  return hits.sort();
}

Deno.test("M4 — no NEW code queries the ghost table user_profiles", () => {
  const offenders = findUserProfilesReaders().filter(
    (f) => !KNOWN_USER_PROFILES_READERS.has(f),
  );
  assertEquals(
    offenders,
    [],
    `These files query user_profiles, a table that does NOT exist in prod ` +
      `(the query fails and the feature silently no-ops):\n  ` +
      `${offenders.join("\n  ")}\n` +
      `Read from athlete_settings instead (see coaching-daily-read for the pattern).`,
  );
});

Deno.test("M4 — stale exemptions: repointed files must leave the punch list", () => {
  const current = new Set(findUserProfilesReaders());
  const stale = [...KNOWN_USER_PROFILES_READERS].filter((f) => !current.has(f));
  assertEquals(
    stale,
    [],
    `These files no longer query user_profiles — remove them from ` +
      `KNOWN_USER_PROFILES_READERS: ${stale.join(", ")}`,
  );
});

// ===========================================================================
// H5 — iOS check-in upload must use the edge-function path
// ===========================================================================
//
// Direct client-SDK uploads to storage have been failing system-wide since
// 2026-06-02; voice memos were moved to the upload-voice-memo edge function
// but uploadCheckIn was missed, so check-ins are likely dead in the build.

/** Flip to false once uploadCheckIn is routed through uploadVoiceMemoAudio(). */
const CHECKIN_UPLOAD_STILL_DIRECT = true;

Deno.test("H5 — iOS uploadCheckIn upload path", () => {
  const swiftPath =
    `${REPO_ROOT}/RunningLog/RunningLog/Workouts/VoiceLogViewModel.swift`;
  const src = read(swiftPath);
  const start = src.indexOf("func uploadCheckIn");
  assert(start >= 0, "uploadCheckIn not found in VoiceLogViewModel.swift");
  // Body = from the func declaration to the next top-level func (or EOF).
  const rest = src.slice(start + 1);
  const nextFunc = rest.search(/\n    func /);
  const body = rest.slice(0, nextFunc === -1 ? undefined : nextFunc);

  const usesDirectUpload = /\.upload\(/.test(body);
  const usesEdgeFunction = /uploadVoiceMemoAudio\(/.test(body);

  if (CHECKIN_UPLOAD_STILL_DIRECT) {
    assert(
      usesDirectUpload && !usesEdgeFunction,
      "uploadCheckIn no longer uses the direct storage upload — the bug is " +
        "fixed! Flip CHECKIN_UPLOAD_STILL_DIRECT to false in this test so " +
        "the fix is locked in.",
    );
  } else {
    assert(
      usesEdgeFunction && !usesDirectUpload,
      "uploadCheckIn must upload via uploadVoiceMemoAudio() (the " +
        "upload-voice-memo edge function), not a direct client-SDK " +
        ".upload() call — direct uploads have been failing since 2026-06-02 " +
        "(review item H5).",
    );
  }
});

// ===========================================================================
// H4 — Something must write athlete_settings.timezone
// ===========================================================================
//
// Until a client writes the user's timezone, every athlete defaults to UTC:
// US users get their "morning" Daily Read at 1am, and all reads fire in one
// burst of simultaneous LLM calls.

/** Flipped 2026-07-16: AthleteSettingsService.syncDeviceTimezone (iOS)
 * upserts the device timezone on every launch (cached per user). */
const TIMEZONE_WRITER_STILL_MISSING = false;

Deno.test("H4 — a client writes athlete_settings (timezone)", () => {
  let found = false;
  const roots = [
    { dir: `${REPO_ROOT}/RunningLog`, exts: [".swift"] },
    { dir: `${REPO_ROOT}/web/src`, exts: [".ts", ".tsx"] },
  ];
  for (const { dir, exts } of roots) {
    for (const f of walkFiles(dir, exts)) {
      if (/athlete_settings/.test(stripComments(read(f)))) {
        found = true;
        break;
      }
    }
    if (found) break;
  }

  if (TIMEZONE_WRITER_STILL_MISSING) {
    assert(
      !found,
      "Client code now references athlete_settings — if it writes the " +
        "timezone, flip TIMEZONE_WRITER_STILL_MISSING to false in this test " +
        "to lock the fix in.",
    );
  } else {
    assert(
      found,
      "No client code references athlete_settings anymore. Without a " +
        "timezone writer every athlete defaults to UTC — wrong-time Daily " +
        "Reads plus a simultaneous burst of LLM calls (review item H4).",
    );
  }
});
