/**
 * Tests for set-fitness-anchor. Minimal in-memory supabase fake.
 * Run: deno test --allow-env --allow-net set-fitness-anchor/index.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleSetFitnessAnchor, type SetAnchorDeps } from "./index.ts";

type Row = Record<string, unknown>;
interface FakeDB {
  athlete_pace_profiles: Row[];
}

function buildFakeClient(db: FakeDB) {
  const from = (table: keyof FakeDB) => {
    const chain: Record<string, unknown> = {};
    chain.update = (patch: Row) => ({
      eq: async (col: string, val: unknown) => {
        const target = db[table].find((r) => r[col] === val);
        if (target) Object.assign(target, patch);
        return { error: null };
      },
    });
    chain.upsert = async (row: Row, _opts?: unknown) => {
      const existing = db[table].find((r) => r.user_id === row.user_id);
      if (existing) Object.assign(existing, row);
      else db[table].push({ ...row });
      return { error: null };
    };
    return chain;
  };
  return { from } as unknown as ReturnType<
    // deno-lint-ignore no-explicit-any
    (typeof import("https://esm.sh/@supabase/supabase-js@2"))["createClient"] extends (...a: any) => infer R ? () => R : never
  >;
}

const USER = "11111111-1111-1111-1111-111111111111";

function req(body: unknown, method = "POST"): Request {
  return new Request("http://localhost/set-fitness-anchor", {
    method,
    headers: { "Content-Type": "application/json", Authorization: "Bearer fake" },
    body: JSON.stringify(body),
  });
}
function deps(db: FakeDB): SetAnchorDeps {
  return { resolveUser: async () => USER, buildClient: () => buildFakeClient(db) };
}

Deno.test("OPTIONS preflight", async () => {
  const res = await handleSetFitnessAnchor(new Request("http://localhost", { method: "OPTIONS" }));
  assertEquals(res.status, 200);
});

Deno.test("unauthenticated → 401", async () => {
  const res = await handleSetFitnessAnchor(req({ distance: "tenK", time_seconds: 2280 }), {
    resolveUser: async () => null,
  });
  assertEquals(res.status, 401);
});

Deno.test("invalid distance → 400", async () => {
  const db: FakeDB = { athlete_pace_profiles: [] };
  const res = await handleSetFitnessAnchor(req({ distance: "ultra", time_seconds: 2280 }), deps(db));
  assertEquals(res.status, 400);
});

Deno.test("out-of-range time → 400", async () => {
  const db: FakeDB = { athlete_pace_profiles: [] };
  const res = await handleSetFitnessAnchor(req({ distance: "tenK", time_seconds: 5 }), deps(db));
  assertEquals(res.status, 400);
});

Deno.test("happy path: upserts anchor + returns projection ladder", async () => {
  const db: FakeDB = { athlete_pace_profiles: [] };
  const res = await handleSetFitnessAnchor(
    req({ distance: "tenK", time_seconds: 38 * 60, effort_date: "2026-07-01" }),
    deps(db),
  );
  assertEquals(res.status, 200);
  const out = await res.json();
  assertEquals(out.ok, true);
  // Row written with the manual anchor.
  assertEquals(db.athlete_pace_profiles.length, 1);
  assertEquals(db.athlete_pace_profiles[0].manual_anchor_distance, "tenK");
  assertEquals(db.athlete_pace_profiles[0].manual_anchor_time_seconds, 2280);
  assertEquals(db.athlete_pace_profiles[0].manual_anchor_set_by, "athlete");
  // Projection is a coherent ladder: 5K faster than MP.
  assert(out.projection.fiveK < out.projection.marathon);
  assert(out.projection.marathon > 0);
});

Deno.test("clear: nulls the anchor", async () => {
  const db: FakeDB = {
    athlete_pace_profiles: [
      { user_id: USER, manual_anchor_distance: "tenK", manual_anchor_time_seconds: 2280 },
    ],
  };
  const res = await handleSetFitnessAnchor(req({ clear: true }), deps(db));
  assertEquals(res.status, 200);
  const out = await res.json();
  assertEquals(out.projection, null);
  assertEquals(db.athlete_pace_profiles[0].manual_anchor_distance, null);
});
