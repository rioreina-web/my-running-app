/**
 * W2.3 contract tests for per-user rate limiting on LLM-calling edge functions.
 *
 * Run: deno test --allow-read supabase/functions/_shared/rateLimit.contract.test.ts
 *
 * What this guards against:
 *   1. A new LLM-calling edge function being added without per-user rate
 *      limiting. The Cloud-billing cap from W1.1 is the hard ceiling, but
 *      a single pathological user shouldn't be allowed to burn the whole
 *      daily budget — that's what per-user rate limits exist for.
 *   2. A pinned function's feature bucket being changed silently. Changing
 *      e.g. coaching-agent from `coaching` to a new untracked bucket
 *      would silently bypass FEATURE_LIMITS until someone noticed.
 *   3. FEATURE_LIMITS drifting away from the pinned function-to-feature
 *      mapping.
 *
 * Exemptions:
 *   - SERVER_ONLY_FUNCTIONS: fired only by triggers, cron, or other edge
 *     functions via service-role. The auth check is the gate; user-keyed
 *     rate limit would be a no-op (service-role bypasses).
 *   - AUTH_PATTERN_AUDIT_PENDING: LLM-calling functions that accept
 *     user_id from the request body with no `getAuthenticatedUser` gate.
 *     Adding a rate limit without fixing auth would be cosmetic — anyone
 *     could call them with a forged user_id and burn another user's
 *     quota. These need a security audit before rate-limiting.
 *
 * Pinned mapping (function → feature bucket):
 *   See `LLM_FUNCTIONS_RATE_LIMITED` below.
 */

import { assertEquals, assert, assertMatch } from "https://deno.land/std@0.224.0/assert/mod.ts";

const FUNCTIONS_DIR  = new URL("..", import.meta.url).pathname;
const RATE_LIMIT_SRC = new URL("./rateLimit.ts", import.meta.url).pathname;

/**
 * LLM-calling edge functions that ARE rate-limited per user.
 * Adding a new LLM call site? Add it here with its feature bucket and
 * the test will enforce the wiring.
 */
const LLM_FUNCTIONS_RATE_LIMITED: Array<{ fn: string; feature: string }> = [
  { fn: "coaching-agent",         feature: "coaching" },
  // injury-analysis, training-analysis, fitness-predictor — DELETED
  // 2026-06-11 (dead functions: zero usage_tracking rows ever; the first
  // two were the last Gemini callers among the dead set). Removed from
  // prod and repo together; see docs/ops-delivery-roadmap-2026-06-10.md.
  { fn: "parse-training-plan",    feature: "parse" },
  { fn: "parse-training-week",    feature: "parse" },
  { fn: "parse-workout-structure", feature: "parse" },
  // transcribe — DELETED 2026-06-10. Zero callers (iOS voice flow goes
  // through process-training-memo, which transcribes internally). Was
  // never deployed to prod. Same rationale as the C.1 cuts.
  { fn: "generate-training-plan", feature: "plan_builder" },
  { fn: "reschedule-plan",        feature: "reschedule" },
  { fn: "weekly-coaching-report", feature: "weekly_review" },
  // weekly-plan-review — CUT 2026-06-10. Never deployed to prod (cron from
  // 20260416400000 never scheduled). Untested LLM prompt making load
  // decisions + voice mismatch with the Maya observation-first posture.
  { fn: "generate-workout-insight", feature: "workout_insight" },
  // W2.3-follow-up — auth gated via requireAuthOrServiceRole, rate-limit
  // wired in the same PR. Service-role callers bypass the user-keyed
  // limit via isServiceRole=true; user-facing callers (iOS) pay it.
  { fn: "race-intel",             feature: "race" },
  { fn: "race-readiness",         feature: "race" },
  { fn: "block-review",           feature: "analysis" },
  { fn: "post-run-analysis",      feature: "post_run" },
  { fn: "injury-early-warning",   feature: "injury_analysis" },
  { fn: "process-training-memo",  feature: "voice_memo" },
  // 2026-06-09 — caught by this test: coaching-daily-read shipped (May)
  // with auth but no rate limit. Auth via requireAuthOrServiceRole;
  // cron/trigger callers bypass via isServiceRole, manual taps pay it.
  { fn: "coaching-daily-read",    feature: "daily_read" },
];

/**
 * LLM-calling functions that don't have per-user rate limits because they
 * have no user-controlled invocation path. Each must call out who the
 * actual caller is.
 */
const SERVER_ONLY_FUNCTIONS: Record<string, string> = {
  "process-check-in":
    "Fired by pg_net trigger on training_logs INSERT (auto_process_voice_logs migration). " +
    "Service-role only via requireServiceRole. user_id is derived from the inserted row, " +
    "not from request body, so there's no user-keyed quota to enforce.",
};

/**
 * LLM-calling functions accepting user_id from request body without a
 * `getAuthenticatedUser` gate. Rate-limiting without fixing auth would
 * be cosmetic — a forged user_id can burn another user's quota.
 *
 * These need a security audit (proper auth gate or service-role-only
 * verification) BEFORE we add user-keyed rate limits. Tracked as a
 * follow-up in TASKS.md (W2.3-follow-up).
 */
const AUTH_PATTERN_AUDIT_PENDING: Record<string, string> = {
  // All previously-pending functions audited and gated in W2.3-follow-up:
  //   - process-check-in       → SERVER_ONLY_FUNCTIONS (requireServiceRole)
  //   - post-run-analysis      → LLM_FUNCTIONS_RATE_LIMITED (requireAuthOrServiceRole + "post_run")
  //   - race-intel             → LLM_FUNCTIONS_RATE_LIMITED (requireAuthOrServiceRole + "race")
  //   - race-readiness         → LLM_FUNCTIONS_RATE_LIMITED (requireAuthOrServiceRole + "race")
  //   - block-review           → LLM_FUNCTIONS_RATE_LIMITED (requireAuthOrServiceRole + "analysis")
  //   - injury-early-warning   → LLM_FUNCTIONS_RATE_LIMITED (requireAuthOrServiceRole + "injury_analysis")
  //   - process-training-memo  → LLM_FUNCTIONS_RATE_LIMITED (requireAuthOrServiceRole + "voice_memo")
};

// ── rateLimit.ts: helper exists and FEATURE_LIMITS contains pinned features ─

Deno.test("rateLimit.ts exports enforceFeatureRateLimit", async () => {
  const src = await Deno.readTextFile(RATE_LIMIT_SRC);
  assertMatch(
    src,
    /export\s+async\s+function\s+enforceFeatureRateLimit\b/,
    "rateLimit.ts must export `enforceFeatureRateLimit`. " +
      "Without it, new functions can't wire rate limiting in one line.",
  );
});

Deno.test("rateLimit.ts: FEATURE_LIMITS contains every pinned feature", async () => {
  const src = await Deno.readTextFile(RATE_LIMIT_SRC);
  const pinnedFeatures = new Set(LLM_FUNCTIONS_RATE_LIMITED.map((r) => r.feature));

  for (const feature of pinnedFeatures) {
    const re = new RegExp(`["']?${feature}["']?\\s*:`);
    assert(
      re.test(src),
      `FEATURE_LIMITS is missing pinned feature "${feature}". ` +
        `Add it with {free, pro, unlimited} caps, or update the contract test.`,
    );
  }
});

Deno.test("rateLimit.ts: the deleted form_check_analysis feature is removed", async () => {
  const src = await Deno.readTextFile(RATE_LIMIT_SRC);
  assert(
    !/form_check_analysis/.test(src),
    "FEATURE_LIMITS still contains `form_check_analysis`, but the function " +
      "was deleted in C.1. Remove the dead entry.",
  );
});

// ── Every pinned function actually calls checkFeatureRateLimit or enforceFeatureRateLimit ─

for (const { fn, feature } of LLM_FUNCTIONS_RATE_LIMITED) {
  Deno.test(`${fn}: imports rateLimit and gates on user_id with feature="${feature}"`, async () => {
    const path = `${FUNCTIONS_DIR}${fn}/index.ts`;
    const src = await Deno.readTextFile(path);

    // Imports something from _shared/rateLimit.
    assertMatch(
      src,
      /from\s+["']\.\.\/_shared\/rateLimit(?:\.ts)?["']/,
      `${fn} must import from ../_shared/rateLimit.ts`,
    );

    // Calls one of the rate-limit functions with the pinned feature.
    // `[^)]*?` lets the args span multiple lines while staying within one call.
    const featureRe = new RegExp(
      `(?:enforceFeatureRateLimit|checkFeatureRateLimit)\\s*\\(` +
        `[^)]*?["']${feature}["']`,
    );
    assert(
      featureRe.test(src),
      `${fn} must call enforceFeatureRateLimit(userId, "${feature}", ...) ` +
        `or the older checkFeatureRateLimit(userId, "${feature}"). ` +
        `If you changed the feature bucket, update LLM_FUNCTIONS_RATE_LIMITED in this test.`,
    );
  });
}

// ── Coverage sanity ───────────────────────────────────────

Deno.test("no LLM-calling function is silently un-rate-limited", async () => {
  const pinned = new Set(LLM_FUNCTIONS_RATE_LIMITED.map((r) => r.fn));
  const audit  = new Set(Object.keys(AUTH_PATTERN_AUDIT_PENDING));
  const serverOnly = new Set(Object.keys(SERVER_ONLY_FUNCTIONS));

  const offenders: string[] = [];

  for await (const entry of Deno.readDir(FUNCTIONS_DIR)) {
    if (!entry.isDirectory) continue;
    if (entry.name.startsWith("_")) continue;

    if (pinned.has(entry.name) || audit.has(entry.name) || serverOnly.has(entry.name)) {
      continue;
    }

    const path = `${FUNCTIONS_DIR}${entry.name}/index.ts`;
    let src: string;
    try {
      src = await Deno.readTextFile(path);
    } catch {
      continue;
    }

    // Heuristic: function calls Gemini, OpenAI, or Anthropic.
    const looksLikeLLM = /GoogleGenerativeAI|@google\/generative-ai|@anthropic-ai|groq|openai/i.test(src);
    if (!looksLikeLLM) continue;

    offenders.push(entry.name);
  }

  assertEquals(
    offenders,
    [],
    "Functions calling an LLM that aren't pinned in LLM_FUNCTIONS_RATE_LIMITED " +
      "and aren't in SERVER_ONLY_FUNCTIONS or AUTH_PATTERN_AUDIT_PENDING:\n" +
      offenders.map((o) => `  - ${o}`).join("\n") +
      "\nEither wire rate limiting and add to LLM_FUNCTIONS_RATE_LIMITED, " +
      "or document the exemption with a justification.",
  );
});

Deno.test("audit-pending list has a non-empty justification for every entry", () => {
  for (const [fn, reason] of Object.entries(AUTH_PATTERN_AUDIT_PENDING)) {
    assert(
      reason.trim().length >= 20,
      `AUTH_PATTERN_AUDIT_PENDING[${fn}] needs a ≥20-char justification ` +
        `naming the caller and the auth gap.`,
    );
  }
});

// ── Auth-helper wiring: W2.3-follow-up functions ───────────────────────
//
// The 7 functions that previously accepted a body `user_id` with no auth
// check must each call one of two helpers from `_shared/auth.ts`:
//
//   - `requireAuthOrServiceRole` for dual-mode callers (iOS user JWT and/or
//     service-role chain calls). Returns either `{userId, isServiceRole}`
//     or a Response to return immediately.
//   - `requireServiceRole` for pure-server callers (pg_net triggers).
//     Rejects anything that isn't the service-role key.
//
// If a future edit drops the auth gate, the function name doesn't appear
// in either list — and this test fails, calling it out by name.

const AUTH_GATE_PINNED: Record<
  string,
  "requireAuthOrServiceRole" | "requireServiceRole" | "resolveCaller"
> = {
  "race-intel":            "requireAuthOrServiceRole",
  "race-readiness":        "requireAuthOrServiceRole",
  "block-review":          "requireAuthOrServiceRole",
  "post-run-analysis":     "requireAuthOrServiceRole",
  "injury-early-warning":  "requireAuthOrServiceRole",
  "process-training-memo": "requireAuthOrServiceRole",
  "process-check-in":      "requireServiceRole",

  // 2026-08 IDOR sweep. Each of these resolved its subject user as
  // "body user_id, or the JWT subject if there is one" — and the anon key,
  // which ships publicly in the iOS binary and web bundle, satisfies
  // `verify_jwt` while carrying no user claim. So the body always won and
  // any caller could name any athlete.
  "coaching-agent":           "requireAuthOrServiceRole",
  "compute-workout-features": "requireAuthOrServiceRole",
  "post-run-reconciliation":  "requireAuthOrServiceRole",
  "get-pace-zones":           "requireAuthOrServiceRole",
  // fetch-workout-weather resolves the caller once and authorizes per mode:
  // its four modes name their subject differently (none / from the plan row
  // / from the body), so a single body-user_id gate doesn't fit.
  "fetch-workout-weather":    "resolveCaller",
};

for (const [fn, helper] of Object.entries(AUTH_GATE_PINNED)) {
  Deno.test(`${fn}: imports ${helper} from _shared/auth.ts and calls it`, async () => {
    const path = `${FUNCTIONS_DIR}${fn}/index.ts`;
    const src = await Deno.readTextFile(path);

    const importRe = new RegExp(
      `import\\s*\\{[^}]*\\b${helper}\\b[^}]*\\}\\s*from\\s*["']\\.\\.\\/_shared\\/auth(?:\\.ts)?["']`,
    );
    assertMatch(
      src,
      importRe,
      `${fn} must import ${helper} from ../_shared/auth.ts. ` +
        `If you intentionally changed the auth pattern, update AUTH_GATE_PINNED.`,
    );

    const callRe = new RegExp(`\\b${helper}\\s*\\(`);
    assert(
      callRe.test(src),
      `${fn} imports ${helper} but doesn't call it. ` +
        `The auth gate must run before any LLM call or DB write.`,
    );
  });
}

// ── The IDOR pattern itself must not come back ─────────────────────────
//
// Pinning individual functions above only protects functions someone
// thought to pin. This test scans every function for the shape of the bug
// instead: resolving the subject user as "whatever the body says, falling
// back to the token" (or vice versa).
//
// Why the shape is always wrong: the anon key is a valid project JWT, it
// satisfies the gateway's `verify_jwt`, it carries no user claim, and it
// ships publicly inside the iOS binary and the web bundle. So "the token
// named no user" does NOT mean "a trusted server called this" — it means
// "unauthenticated". Any fallback to a body-supplied id on that branch is
// reachable by anyone.
//
// The correct helpers (`requireAuthOrServiceRole`, `resolveCaller`) decide
// on the token itself, comparing against the real service-role key.

const IDOR_PATTERNS: Array<{ re: RegExp; label: string }> = [
  {
    // const uid = body.user_id || (await getAuthenticatedUser(req));
    re: /=\s*(?:body\.)?\w*[Uu]ser_?[Ii]d\s*\|\|\s*\(?\s*await\s+getAuthenticatedUser/,
    label: "`body.user_id || await getAuthenticatedUser(req)` — the body wins outright",
  },
  {
    // let userId = await getAuthenticatedUser(req); ... userId = userId || body.user_id
    re: /await\s+getAuthenticatedUser\s*\([^)]*\)\s*(?:\|\||\?\?)\s*(?:body\.)?\w*[Uu]ser_?[Ii]d/,
    label: "`await getAuthenticatedUser(req) || body.user_id` — falls back to the body",
  },
  {
    // if (!userId && bodyUserId) userId = bodyUserId;
    re: /if\s*\(\s*!\s*\w*[Uu]ser_?[Ii]d\s*&&\s*\w*[Uu]ser_?[Ii]d\s*\)\s*\{?\s*\w*[Uu]ser_?[Ii]d\s*=/,
    label: "`if (!userId && bodyUserId) userId = bodyUserId` — same fallback, spelled long",
  },
];

Deno.test("no edge function resolves its subject user from the request body", async () => {
  const offenders: string[] = [];

  for await (const entry of Deno.readDir(FUNCTIONS_DIR)) {
    if (!entry.isDirectory || entry.name.startsWith("_")) continue;

    const path = `${FUNCTIONS_DIR}${entry.name}/index.ts`;
    let src: string;
    try {
      src = await Deno.readTextFile(path);
    } catch {
      continue;
    }

    // Strip comments so the explanatory write-ups left at each fix site
    // (which quote the old code) don't trip the scan.
    const code = src
      .replace(/\/\*[\s\S]*?\*\//g, "")
      .replace(/^\s*\/\/.*$/gm, "");

    for (const { re, label } of IDOR_PATTERNS) {
      if (re.test(code)) offenders.push(`  - ${entry.name}: ${label}`);
    }
  }

  assertEquals(
    offenders,
    [],
    "These functions resolve the acting user from the request body:\n" +
      offenders.join("\n") +
      "\n\nUse requireAuthOrServiceRole(req, body.user_id, corsHeaders) — or " +
      "resolveCaller(req) when the subject isn't a single body field. Both " +
      "compare against the real service-role key instead of inferring trust " +
      "from the absence of a user claim.",
  );
});
