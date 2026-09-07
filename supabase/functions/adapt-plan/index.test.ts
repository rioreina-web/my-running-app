/**
 * Handler tests for adapt-plan.
 *
 * `verify_jwt = false`, service-role Supabase client, and it writes
 * `plan_adjustments`. The gate in this file is therefore the only thing
 * between a caller and another athlete's training plan, and until now nothing
 * executed it — the H3 contract test greps for the call, which cannot tell a
 * working gate from one whose result is ignored.
 *
 * The rules engine itself (`_shared/adaptation-rules.ts`) has its own tests.
 * What is asserted here is the handler's contract: who gets in, what the
 * subject user is, and that "no proposals" is a clean 200 rather than a crash.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type AdaptPlanDeps, handleAdaptPlan } from "./index.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const USER = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";

type Row = Record<string, unknown>;

/**
 * Thenable query fake. supabase-js builders resolve when awaited at whatever
 * point the chain stops, so `.order()` and `.maybeSingle()` both have to be
 * valid endings. Empty tables are the interesting case here: they are what an
 * athlete with no plan looks like, and that path must not throw.
 */
function fakeClient(
  tables: Record<string, Row[]> = {},
  seen?: Array<[string, string, unknown]>,
): SupabaseClient {
  const from = (table: string) => {
    const filters: Array<[string, unknown]> = [];
    const rows = () => {
      const all = tables[table] ?? [];
      return all.filter((r) => filters.every(([c, v]) => r[c] === v));
    };
    const chain: Record<string, unknown> = {
      select: () => chain,
      eq: (c: string, v: unknown) => {
        filters.push([c, v]);
        seen?.push([table, c, v]);
        return chain;
      },
      gte: () => chain,
      lte: () => chain,
      order: () => chain,
      limit: () => chain,
      insert: () => chain,
      maybeSingle: () => Promise.resolve({ data: rows()[0] ?? null, error: null }),
      single: () => Promise.resolve({ data: rows()[0] ?? null, error: null }),
      // Awaiting the builder itself yields the row set.
      then: (
        res: (v: { data: Row[]; error: null }) => unknown,
        rej?: (e: unknown) => unknown,
      ) => Promise.resolve({ data: rows(), error: null }).then(res, rej),
    };
    return chain;
  };
  return { from } as unknown as SupabaseClient;
}

function post(body: unknown): Request {
  return new Request("http://localhost/adapt-plan", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: "Bearer t" },
    body: JSON.stringify(body),
  });
}

function passing(overrides: Partial<AdaptPlanDeps> = {}): AdaptPlanDeps {
  return {
    resolveAuth: () => Promise.resolve({ userId: USER, isServiceRole: false }),
    buildClient: () => fakeClient(),
    ...overrides,
  };
}

Deno.test("adapt-plan: OPTIONS preflight → 200", async () => {
  const res = await handleAdaptPlan(new Request("http://localhost", { method: "OPTIONS" }));
  assertEquals(res.status, 200);
});

Deno.test("adapt-plan: the gate's 401 is returned, not swallowed", async () => {
  const res = await handleAdaptPlan(post({ user_id: USER }), {
    resolveAuth: () => Promise.resolve({ response: new Response("no", { status: 401 }) }),
  });
  assertEquals(res.status, 401);
});

Deno.test("adapt-plan: a 403 from the gate reaches the caller", async () => {
  // An authenticated athlete naming someone else's user_id must not be able
  // to drive adaptations against that athlete's plan.
  const res = await handleAdaptPlan(post({ user_id: OTHER }), {
    resolveAuth: () => Promise.resolve({ response: new Response("mismatch", { status: 403 }) }),
  });
  assertEquals(res.status, 403);
});

Deno.test("adapt-plan: body user_id is forwarded to the gate", async () => {
  // The gate compares this against the JWT subject; if the handler stopped
  // passing it, every mismatch would silently become an allow.
  let seen: string | undefined = "unset";
  await handleAdaptPlan(post({ user_id: OTHER }), passing({
    resolveAuth: (_r, bodyUserId) => {
      seen = bodyUserId;
      return Promise.resolve({ userId: USER, isServiceRole: false });
    },
  }));
  assertEquals(seen, OTHER);
});

Deno.test("adapt-plan: a missing body still reaches the gate with undefined", async () => {
  // `req.json().catch(() => ({}))` means malformed input is not rejected here
  // — it becomes `user_id: undefined`, and the gate is what refuses it. That
  // is only safe while the gate rejects a bare service-role call with no
  // subject, which _shared/auth.test.ts pins.
  let seen: string | undefined = "unset";
  const res = await handleAdaptPlan(
    new Request("http://localhost/adapt-plan", {
      method: "POST",
      headers: { Authorization: "Bearer t" },
      body: "{{{",
    }),
    {
      resolveAuth: (_r, bodyUserId) => {
        seen = bodyUserId;
        return Promise.resolve({ response: new Response("no subject", { status: 400 }) });
      },
    },
  );
  assertEquals(seen, undefined);
  assertEquals(res.status, 400);
});

Deno.test("adapt-plan: an athlete with no plan gets a clean 200, not a crash", async () => {
  const res = await handleAdaptPlan(post({ user_id: USER }), passing());
  assertEquals(res.status, 200);
  const out = await res.json();
  assertEquals(out.ok, true);
  assertEquals(out.proposals, 0);
});

Deno.test("adapt-plan: every read is scoped to the user the gate returned", async () => {
  // reconcile-log → adapt-plan is exactly this path. The gate names OTHER, so
  // every user-scoped query must filter on OTHER — a handler that reached for
  // the body field again, or for a stale variable, would show up here.
  const seen: Array<[string, string, unknown]> = [];
  const res = await handleAdaptPlan(post({ user_id: OTHER, trigger: "reconcile" }), {
    resolveAuth: () => Promise.resolve({ userId: OTHER, isServiceRole: true }),
    buildClient: () =>
      fakeClient({ training_plans: [{ id: "p1", user_id: OTHER, status: "active" }] }, seen),
  });
  assertEquals(res.status, 200);

  const userFilters = seen.filter(([, col]) => col === "user_id");
  assert(userFilters.length > 0, "expected at least one user-scoped read");
  assertEquals(
    userFilters.filter(([, , val]) => val !== OTHER),
    [],
    `every user_id filter must be ${OTHER}; saw ${JSON.stringify(userFilters)}`,
  );
});
