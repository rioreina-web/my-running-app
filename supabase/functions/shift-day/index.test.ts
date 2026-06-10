/**
 * Tests for shift-day. Runs against a minimal in-memory supabase fake.
 *
 * Run: deno test --allow-env --allow-net shift-day/index.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleShiftDay, type ShiftDayDeps } from "./index.ts";

// ── Fake supabase client ────────────────────────────────

type Row = Record<string, unknown>;

interface FakeDB {
  scheduled_workouts: Row[];
  training_plans: Row[];
  plan_adjustments: Row[];
}

function buildFakeClient(db: FakeDB) {
  const from = (table: keyof FakeDB) => {
    const filters: Array<[string, unknown]> = [];
    const chain: Record<string, unknown> = {};

    chain.select = (_cols: string) => chain;
    chain.eq = (col: string, val: unknown) => {
      filters.push([col, val]);
      return chain;
    };
    chain.maybeSingle = async () => {
      const row = db[table].find((r) =>
        filters.every(([c, v]) => r[c] === v),
      );
      return { data: row ?? null, error: null };
    };
    chain.single = chain.maybeSingle;
    chain.insert = async (rows: Row | Row[]) => {
      const arr = Array.isArray(rows) ? rows : [rows];
      db[table].push(...arr);
      return { error: null };
    };
    chain.update = (patch: Row) => ({
      eq: async (col: string, val: unknown) => {
        const target = db[table].find((r) => r[col] === val);
        if (target) Object.assign(target, patch);
        return { error: null };
      },
    });
    chain.delete = () => ({
      eq: async (_col: string, _val: unknown) => ({ error: null }),
    });
    return chain;
  };
  return { from } as unknown as ReturnType<
    // deno-lint-ignore no-explicit-any
    (typeof import("https://esm.sh/@supabase/supabase-js@2"))["createClient"] extends (...a: any) => infer R ? () => R : never
  >;
}

// ── Helpers ─────────────────────────────────────────────

const USER = "11111111-1111-1111-1111-111111111111";
const PLAN = "22222222-2222-2222-2222-222222222222";

function baseDB(): FakeDB {
  return {
    scheduled_workouts: [],
    training_plans: [{ id: PLAN, user_id: USER }],
    plan_adjustments: [],
  };
}

function buildReq(body: unknown, method = "POST"): Request {
  return new Request("http://localhost/shift-day", {
    method,
    headers: { "Content-Type": "application/json", Authorization: "Bearer fake" },
    body: JSON.stringify(body),
  });
}

// Fix "now" so the same-week + past-date logic is deterministic.
// 2026-04-27 is a Monday → Mon-Sun window runs through 2026-05-03.
const FROZEN_NOW = new Date(2026, 3, 27); // Apr 27, 2026 local midnight

function deps(db: FakeDB): ShiftDayDeps {
  return {
    resolveUser: async () => USER,
    buildClient: () => buildFakeClient(db),
    now: () => FROZEN_NOW,
  };
}

// ── Tests ───────────────────────────────────────────────

Deno.test("OPTIONS returns CORS preflight", async () => {
  const res = await handleShiftDay(
    new Request("http://localhost", { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
});

Deno.test("non-POST returns 405", async () => {
  const res = await handleShiftDay(
    new Request("http://localhost", { method: "GET" }),
  );
  assertEquals(res.status, 405);
});

Deno.test("missing scheduled_workout_id returns 400", async () => {
  const db = baseDB();
  const res = await handleShiftDay(buildReq({ new_date: "2026-04-28" }), deps(db));
  assertEquals(res.status, 400);
});

Deno.test("invalid date format returns 400", async () => {
  const db = baseDB();
  const res = await handleShiftDay(
    buildReq({ scheduled_workout_id: "abc", new_date: "April 28" }),
    deps(db),
  );
  assertEquals(res.status, 400);
});

Deno.test("happy path: simple move (no dest workout)", async () => {
  const db = baseDB();
  const wId = "aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  db.scheduled_workouts.push({
    id: wId,
    user_id: USER,
    plan_id: PLAN,
    scheduled_date: "2026-04-28", // Tue
    day_of_week: 2,
    week_number: 1,
    workout_type: "tempo",
    workout_data: null,
  });
  const res = await handleShiftDay(
    buildReq({ scheduled_workout_id: wId, new_date: "2026-04-30" }), // Thu
    deps(db),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.swapped_with, null);
  assertEquals(body.new_date, "2026-04-30");
  assertEquals(db.scheduled_workouts[0].scheduled_date, "2026-04-30");
  assertEquals(db.scheduled_workouts[0].day_of_week, 4);
  // plan_adjustments row written
  assertEquals(db.plan_adjustments.length, 1);
  assertEquals(db.plan_adjustments[0].tier, "green");
  assertEquals(db.plan_adjustments[0].action_type, "shift_day");
});

Deno.test("happy path: swap with existing workout on destination", async () => {
  const db = baseDB();
  const a = "aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  const b = "bbbb2222-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
  db.scheduled_workouts.push(
    {
      id: a, user_id: USER, plan_id: PLAN,
      scheduled_date: "2026-04-28", day_of_week: 2, week_number: 1,
      workout_type: "tempo", workout_data: null,
    },
    {
      id: b, user_id: USER, plan_id: PLAN,
      scheduled_date: "2026-04-30", day_of_week: 4, week_number: 1,
      workout_type: "easy", workout_data: null,
    },
  );
  const res = await handleShiftDay(
    buildReq({ scheduled_workout_id: a, new_date: "2026-04-30" }),
    deps(db),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.swapped_with, b);
  const rowA = db.scheduled_workouts.find((r) => r.id === a)!;
  const rowB = db.scheduled_workouts.find((r) => r.id === b)!;
  assertEquals(rowA.scheduled_date, "2026-04-30");
  assertEquals(rowA.day_of_week, 4);
  assertEquals(rowB.scheduled_date, "2026-04-28");
  assertEquals(rowB.day_of_week, 2);
});

Deno.test("cross-week move is rejected", async () => {
  const db = baseDB();
  const wId = "aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  db.scheduled_workouts.push({
    id: wId, user_id: USER, plan_id: PLAN,
    scheduled_date: "2026-04-28", day_of_week: 2, week_number: 1,
    workout_type: "tempo", workout_data: null,
  });
  const res = await handleShiftDay(
    buildReq({ scheduled_workout_id: wId, new_date: "2026-05-05" }), // next week
    deps(db),
  );
  assertEquals(res.status, 400);
});

Deno.test("past-date move is rejected", async () => {
  const db = baseDB();
  const wId = "aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  db.scheduled_workouts.push({
    id: wId, user_id: USER, plan_id: PLAN,
    scheduled_date: "2026-04-27", day_of_week: 1, week_number: 1,
    workout_type: "tempo", workout_data: null,
  });
  // Today is Apr 27, moving back to Apr 26 should be rejected — but that's
  // also cross-week, so test moving a past workout (Apr 25) is the past-
  // date path. Using Apr 28 target from an Apr 25 source: cross-week.
  // Test: source is in the past.
  db.scheduled_workouts[0].scheduled_date = "2026-04-25"; // Sat of prior week
  const res = await handleShiftDay(
    buildReq({ scheduled_workout_id: wId, new_date: "2026-04-26" }),
    deps(db),
  );
  // Source is past → 403
  assertEquals(res.status, 403);
});

Deno.test("ownership check: wrong user → 403", async () => {
  const db = baseDB();
  const wId = "aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  db.scheduled_workouts.push({
    id: wId,
    user_id: "99999999-9999-9999-9999-999999999999",
    plan_id: "33333333-3333-3333-3333-333333333333", // different plan
    scheduled_date: "2026-04-28", day_of_week: 2, week_number: 1,
    workout_type: "tempo", workout_data: null,
  });
  const res = await handleShiftDay(
    buildReq({ scheduled_workout_id: wId, new_date: "2026-04-30" }),
    deps(db),
  );
  assertEquals(res.status, 403);
});

Deno.test("same-date move is rejected (nothing to do)", async () => {
  const db = baseDB();
  const wId = "aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
  db.scheduled_workouts.push({
    id: wId, user_id: USER, plan_id: PLAN,
    scheduled_date: "2026-04-28", day_of_week: 2, week_number: 1,
    workout_type: "tempo", workout_data: null,
  });
  const res = await handleShiftDay(
    buildReq({ scheduled_workout_id: wId, new_date: "2026-04-28" }),
    deps(db),
  );
  assertEquals(res.status, 400);
});

Deno.test("missing workout returns 404", async () => {
  const db = baseDB();
  const res = await handleShiftDay(
    buildReq({
      scheduled_workout_id: "00000000-0000-0000-0000-000000000000",
      new_date: "2026-04-30",
    }),
    deps(db),
  );
  assertEquals(res.status, 404);
});

Deno.test("unauthenticated returns 401", async () => {
  const db = baseDB();
  const res = await handleShiftDay(
    buildReq({ scheduled_workout_id: "abc", new_date: "2026-04-30" }),
    { ...deps(db), resolveUser: async () => null },
  );
  assertEquals(res.status, 401);
});
