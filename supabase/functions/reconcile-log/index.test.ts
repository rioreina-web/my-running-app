/**
 * Handler tests for reconcile-log.
 *
 * This one's gate is different from every other function's: a shared secret
 * in `RECONCILE_SHARED_SECRET`, compared directly, because the pg_net trigger
 * that calls it presents an `sb_secret_*` key the JWT gateway cannot verify.
 * `verify_jwt = false` follows from that, which means this comparison is the
 * entire authorization story for an endpoint that reads any athlete's
 * training log and writes reconciliations.
 *
 * The secret is NOT stubbed here — these tests set the environment variable
 * and drive the real branch, because a test that injected a fake comparison
 * would assert nothing about the thing that actually protects the endpoint.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleReconcileLog, type ReconcileLogDeps } from "./index.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const SECRET = "reconcile-shared-secret-under-test";
const USER = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";
const LOG_ID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";

type Row = Record<string, unknown>;

async function withSecret(
  value: string | null,
  fn: () => Promise<void>,
): Promise<void> {
  const prev = Deno.env.get("RECONCILE_SHARED_SECRET");
  if (value === null) Deno.env.delete("RECONCILE_SHARED_SECRET");
  else Deno.env.set("RECONCILE_SHARED_SECRET", value);
  try {
    await fn();
  } finally {
    if (prev === undefined) Deno.env.delete("RECONCILE_SHARED_SECRET");
    else Deno.env.set("RECONCILE_SHARED_SECRET", prev);
  }
}

function fakeClient(
  tables: Record<string, Row[]> = {},
  writes?: Row[],
): SupabaseClient {
  const from = (table: string) => {
    const filters: Array<[string, unknown]> = [];
    const rows = () =>
      (tables[table] ?? []).filter((r) => filters.every(([c, v]) => r[c] === v));
    const chain: Record<string, unknown> = {
      select: () => chain,
      eq: (c: string, v: unknown) => {
        filters.push([c, v]);
        return chain;
      },
      gte: () => chain,
      lte: () => chain,
      order: () => chain,
      limit: () => chain,
      insert: (row: Row) => {
        writes?.push({ __table: table, ...row });
        return chain;
      },
      update: () => chain,
      upsert: (row: Row) => {
        writes?.push({ __table: table, ...row });
        return chain;
      },
      maybeSingle: () => Promise.resolve({ data: rows()[0] ?? null, error: null }),
      single: () => Promise.resolve({ data: rows()[0] ?? null, error: null }),
      then: (
        res: (v: { data: Row[]; error: null }) => unknown,
        rej?: (e: unknown) => unknown,
      ) => Promise.resolve({ data: rows(), error: null }).then(res, rej),
    };
    return chain;
  };
  return { from } as unknown as SupabaseClient;
}

function post(body: unknown, bearer: string | null = SECRET): Request {
  return new Request("http://localhost/reconcile-log", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(bearer === null ? {} : { Authorization: `Bearer ${bearer}` }),
    },
    body: JSON.stringify(body),
  });
}

const deps: ReconcileLogDeps = { buildClient: () => fakeClient() };

// ── The shared-secret gate ───────────────────────────────────────────

Deno.test("reconcile-log: OPTIONS preflight → 200, before any auth", async () => {
  const res = await handleReconcileLog(
    new Request("http://localhost", { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

Deno.test("reconcile-log: no Authorization header → 401", async () => {
  await withSecret(SECRET, async () => {
    const res = await handleReconcileLog(post({ training_log_id: LOG_ID }, null), deps);
    assertEquals(res.status, 401);
  });
});

Deno.test("reconcile-log: wrong secret → 401", async () => {
  await withSecret(SECRET, async () => {
    const res = await handleReconcileLog(
      post({ training_log_id: LOG_ID }, "not-the-secret"),
      deps,
    );
    assertEquals(res.status, 401);
  });
});

Deno.test("reconcile-log: a near-miss secret → 401", async () => {
  await withSecret(SECRET, async () => {
    const res = await handleReconcileLog(
      post({ training_log_id: LOG_ID }, SECRET.slice(0, -1) + "X"),
      deps,
    );
    assertEquals(res.status, 401);
  });
});

Deno.test("reconcile-log: a prefix of the secret → 401", async () => {
  await withSecret(SECRET, async () => {
    const res = await handleReconcileLog(
      post({ training_log_id: LOG_ID }, SECRET.slice(0, 8)),
      deps,
    );
    assertEquals(res.status, 401);
  });
});

Deno.test("reconcile-log: fails closed when the secret is unset", async () => {
  // An unset env var must not make an empty bearer match. This is the branch
  // that would turn the endpoint into an open door on a misconfigured deploy.
  await withSecret(null, async () => {
    for (const bearer of [SECRET, "", "anything"]) {
      const res = await handleReconcileLog(post({ training_log_id: LOG_ID }, bearer), deps);
      assertEquals(res.status, 401, `bearer=${JSON.stringify(bearer)}`);
    }
  });
});

Deno.test("reconcile-log: the Bearer prefix is optional and case-insensitive", async () => {
  // The handler strips /^Bearer\s+/i, so the raw secret is also accepted.
  // Pinned because the trigger's header format and this regex have to agree.
  await withSecret(SECRET, async () => {
    for (const header of [`Bearer ${SECRET}`, `bearer ${SECRET}`, SECRET]) {
      const req = new Request("http://localhost/reconcile-log", {
        method: "POST",
        headers: { Authorization: header },
        body: JSON.stringify({}),
      });
      const res = await handleReconcileLog(req, deps);
      // 400 (not 401) proves the gate was passed and we reached validation.
      assertEquals(res.status, 400, `header=${header}`);
    }
  });
});

// ── Past the gate ────────────────────────────────────────────────────

Deno.test("reconcile-log: missing training_log_id → 400", async () => {
  await withSecret(SECRET, async () => {
    const res = await handleReconcileLog(post({}), deps);
    assertEquals(res.status, 400);
  });
});

Deno.test("reconcile-log: unknown training_log_id → 404", async () => {
  await withSecret(SECRET, async () => {
    const res = await handleReconcileLog(post({ training_log_id: LOG_ID }), deps);
    assertEquals(res.status, 404);
  });
});

Deno.test("reconcile-log: the subject user comes from the log row, not the request", async () => {
  // There is no user_id in the request body by design — it is read off the
  // training_log. That is what stops a secret-holder from aiming the function
  // at one athlete's log while claiming to be another.
  await withSecret(SECRET, async () => {
    const writes: Row[] = [];
    const res = await handleReconcileLog(
      post({ training_log_id: LOG_ID, user_id: OTHER }),
      {
        buildClient: () =>
          fakeClient({
            training_logs: [{
              id: LOG_ID,
              user_id: USER,
              workout_date: "2026-08-20",
              workout_distance_miles: 6,
              workout_duration_minutes: 48,
            }],
          }, writes),
      },
    );
    assert(res.status < 500, `unexpected ${res.status}`);

    const recon = writes.filter((w) => w.__table === "workout_reconciliations");
    assert(recon.length > 0, "expected a reconciliation to be written");
    for (const w of recon) {
      assertEquals(
        w.user_id,
        USER,
        "the row must be filed under the log owner, never the caller-supplied user_id",
      );
      assert(w.user_id !== OTHER, "caller-supplied user_id must be ignored");
    }
  });
});
