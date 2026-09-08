/**
 * Handler tests for coaching-daily-read.
 *
 * This function is `verify_jwt = false`, so the gateway validates nothing and
 * every authorization decision is made by the code in index.ts. The H3
 * contract test can only confirm a gate is *mentioned* in the source; these
 * call the handler and check what it actually returns.
 *
 * Everything here stops before the Gemini call. That is not a gap — the
 * branches that decide who may spend money, and whether we spend it at all,
 * all resolve earlier: auth, the per-user gates, the cached-read short
 * circuit, and the app-wide budget guard. The model call itself is exercised
 * by the prompt cassettes under `_evals/`.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  type DailyReadDeps,
  handleCoachingDailyRead,
} from "./index.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const USER = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";

type Row = Record<string, unknown>;

/** Today in UTC, matching resolveAthleteLocalDate when timezone is "UTC". */
function todayUtc(): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "UTC",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

/**
 * Fake supporting the two reads on the pre-model path:
 *   athlete_settings      .select().eq().maybeSingle()
 *   daily_coaching_reads  .select().eq().eq().maybeSingle()
 */
function fakeClient(tables: Record<string, Row[]>): SupabaseClient {
  const from = (table: string) => {
    const filters: Array<[string, unknown]> = [];
    const chain = {
      select: () => chain,
      eq: (col: string, val: unknown) => {
        filters.push([col, val]);
        return chain;
      },
      maybeSingle: () => {
        const rows = tables[table] ?? [];
        const hit = rows.find((r) => filters.every(([c, v]) => r[c] === v));
        return Promise.resolve({ data: hit ?? null, error: null });
      },
    };
    return chain;
  };
  return { from } as unknown as SupabaseClient;
}

function post(body: unknown, headers: Record<string, string> = {}): Request {
  return new Request("http://localhost/coaching-daily-read", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer t", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}

/** Deps that let a request through auth and both gates, with an empty DB. */
function passing(overrides: Partial<DailyReadDeps> = {}): DailyReadDeps {
  return {
    resolveAuth: () => Promise.resolve({ userId: USER, isServiceRole: false }),
    rateLimit: () => Promise.resolve(null),
    monthlyCap: () => Promise.resolve(null),
    // Deliberately false: every path that runs past the cache stops here with
    // a 429 instead of reaching upsertPendingRead and the model. A test that
    // needs to go further must say so explicitly.
    budgetAllows: () => Promise.resolve(false),
    buildClient: () => fakeClient({ athlete_settings: [{ user_id: USER, timezone: "UTC" }] }),
    ...overrides,
  };
}

// ── Method and body shape ────────────────────────────────────────────

Deno.test("daily-read: OPTIONS preflight → 200", async () => {
  const res = await handleCoachingDailyRead(
    new Request("http://localhost", { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

Deno.test("daily-read: GET → 405", async () => {
  const res = await handleCoachingDailyRead(
    new Request("http://localhost", { method: "GET" }),
  );
  assertEquals(res.status, 405);
});

Deno.test("daily-read: malformed JSON → 400, before auth runs", async () => {
  let authCalled = false;
  const res = await handleCoachingDailyRead(post("{not json"), {
    resolveAuth: () => {
      authCalled = true;
      return Promise.resolve({ userId: USER, isServiceRole: false });
    },
  });
  assertEquals(res.status, 400);
  assertEquals(authCalled, false);
});

Deno.test("daily-read: missing or non-string user_id → 400", async () => {
  for (const body of [{}, { user_id: 42 }, { user_id: "" }]) {
    const res = await handleCoachingDailyRead(post(body), passing());
    assertEquals(res.status, 400, `body=${JSON.stringify(body)}`);
  }
});

// ── Authorization ────────────────────────────────────────────────────

Deno.test("daily-read: the gate's rejection is returned verbatim", async () => {
  const res = await handleCoachingDailyRead(post({ user_id: USER }), {
    resolveAuth: () =>
      Promise.resolve({ response: new Response("nope", { status: 401 }) }),
  });
  assertEquals(res.status, 401);
});

Deno.test("daily-read: a 403 from the gate is not swallowed into a 500", async () => {
  // The IDOR shape: an authenticated athlete naming someone else's user_id.
  const res = await handleCoachingDailyRead(post({ user_id: OTHER }), {
    resolveAuth: () =>
      Promise.resolve({ response: new Response("mismatch", { status: 403 }) }),
  });
  assertEquals(res.status, 403);
});

Deno.test("daily-read: body user_id is handed to the gate for comparison", async () => {
  // If this stopped being forwarded, the gate could never catch a mismatch.
  let seen: string | undefined = "unset";
  const res = await handleCoachingDailyRead(post({ user_id: OTHER }), passing({
    resolveAuth: (_req, bodyUserId) => {
      seen = bodyUserId;
      return Promise.resolve({ userId: USER, isServiceRole: false });
    },
  }));
  assertEquals(seen, OTHER);
  assertEquals(res.status, 429, "should stop at the budget guard, not error");
});

Deno.test("daily-read: service-role flag reaches the quota gates", async () => {
  // Service callers are exempted by `{ isServiceRole }`; losing the flag would
  // silently start charging cron runs against the athlete's daily bucket.
  let sawServiceRole: boolean | null = null;
  const res = await handleCoachingDailyRead(post({ user_id: USER }), passing({
    resolveAuth: () => Promise.resolve({ userId: USER, isServiceRole: true }),
    rateLimit: (_u, svc) => {
      sawServiceRole = svc;
      return Promise.resolve(null);
    },
  }));
  assertEquals(sawServiceRole, true);
  assertEquals(res.status, 429, "should stop at the budget guard, not error");
});

// ── Quota gates ──────────────────────────────────────────────────────

Deno.test("daily-read: a blocked daily bucket short-circuits", async () => {
  let capChecked = false;
  const res = await handleCoachingDailyRead(post({ user_id: USER }), passing({
    rateLimit: () => Promise.resolve(new Response("slow down", { status: 429 })),
    monthlyCap: () => {
      capChecked = true;
      return Promise.resolve(null);
    },
  }));
  assertEquals(res.status, 429);
  assertEquals(capChecked, false, "must not keep checking after a block");
});

Deno.test("daily-read: the monthly cap is enforced after the daily bucket", async () => {
  const res = await handleCoachingDailyRead(post({ user_id: USER }), passing({
    monthlyCap: () => Promise.resolve(new Response("capped", { status: 429 })),
  }));
  assertEquals(res.status, 429);
});

Deno.test("daily-read: unknown triggered_by → 400", async () => {
  const res = await handleCoachingDailyRead(
    post({ user_id: USER, triggered_by: "whatever" }),
    passing(),
  );
  assertEquals(res.status, 400);
});

// ── Cache short circuit and the budget guard ─────────────────────────

function withCompletedRead(): DailyReadDeps {
  return passing({
    buildClient: () =>
      fakeClient({
        athlete_settings: [{ user_id: USER, timezone: "UTC" }],
        daily_coaching_reads: [
          { id: "r1", user_id: USER, read_date: todayUtc(), status: "completed" },
        ],
      }),
  });
}

Deno.test("daily-read: a completed read for today is returned from cache", async () => {
  const res = await handleCoachingDailyRead(post({ user_id: USER }), withCompletedRead());
  assertEquals(res.status, 200);
  const out = await res.json();
  assertEquals(out.cached, true);
  assertEquals(out.read.id, "r1");
});

Deno.test("daily-read: a cache hit spends no LLM budget", async () => {
  // The guard writes a ledger row per permitted call, so consulting it on a
  // cache hit would bill the day's ceiling for work never done.
  let budgetConsulted = false;
  const res = await handleCoachingDailyRead(post({ user_id: USER }), {
    ...withCompletedRead(),
    budgetAllows: () => {
      budgetConsulted = true;
      return Promise.resolve(true);
    },
  });
  assertEquals(res.status, 200);
  assertEquals(budgetConsulted, false);
});

Deno.test("daily-read: workout_trigger deliberately bypasses the cache", async () => {
  // A freshly logged quality session is the reason this trigger fires, so it
  // must regenerate. Reaching the budget guard proves the cache was skipped.
  let budgetConsulted = false;
  const res = await handleCoachingDailyRead(
    post({ user_id: USER, triggered_by: "workout_trigger" }),
    {
      ...withCompletedRead(),
      budgetAllows: () => {
        budgetConsulted = true;
        return Promise.resolve(false); // stop before the model call
      },
    },
  );
  assert(budgetConsulted, "workout_trigger must not return the cached read");
  assertEquals(res.status, 429);
});

Deno.test("daily-read: the budget guard applies to service-role callers too", async () => {
  // Unlike the per-user gates, this one does NOT bypass for machines — cron is
  // exactly the path a runaway loop rides in on.
  const res = await handleCoachingDailyRead(post({ user_id: USER }), passing({
    resolveAuth: () => Promise.resolve({ userId: USER, isServiceRole: true }),
    budgetAllows: () => Promise.resolve(false),
  }));
  assertEquals(res.status, 429);
});
