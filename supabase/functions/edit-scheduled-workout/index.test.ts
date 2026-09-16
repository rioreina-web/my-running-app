/**
 * Tests for edit-scheduled-workout. Minimal in-memory supabase fake, mirroring
 * shift-day/index.test.ts.
 *
 * Run: deno test --allow-env --allow-net edit-scheduled-workout/index.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleEditWorkout, type EditWorkoutDeps } from "./index.ts";

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
      const row = db[table].find((r) => filters.every(([c, v]) => r[c] === v));
      return { data: row ?? null, error: null };
    };
    chain.single = chain.maybeSingle;
    chain.then = (
      resolve: (v: { data: Row[]; error: null }) => unknown,
      reject?: (e: unknown) => unknown,
    ) => {
      const rows = db[table].filter((r) => filters.every(([c, v]) => r[c] === v));
      return Promise.resolve({ data: rows, error: null }).then(resolve, reject);
    };
    chain.insert = (rows: Row | Row[]) => {
      const arr = Array.isArray(rows) ? rows : [rows];
      // Real Postgres assigns the id; the fake mirrors that so
      // .insert().select("id").maybeSingle() has something to return.
      for (const r of arr) if (r.id === undefined) r.id = crypto.randomUUID();
      db[table].push(...arr);
      const insChain: Record<string, unknown> = {};
      insChain.select = (_cols: string) => insChain;
      insChain.maybeSingle = async () => ({ data: arr[0] ?? null, error: null });
      insChain.single = insChain.maybeSingle;
      // Awaitable directly (plan_adjustments inserts don't chain).
      insChain.then = (
        resolve: (v: { data: Row[]; error: null }) => unknown,
        reject?: (e: unknown) => unknown,
      ) => Promise.resolve({ data: arr, error: null }).then(resolve, reject);
      return insChain;
    };
    chain.update = (patch: Row) => ({
      eq: async (col: string, val: unknown) => {
        const target = db[table].find((r) => r[col] === val);
        if (target) Object.assign(target, patch);
        return { error: null };
      },
    });
    return chain;
  };
  return { from } as unknown as ReturnType<
    // deno-lint-ignore no-explicit-any
    (typeof import("https://esm.sh/@supabase/supabase-js@2"))["createClient"] extends (...a: any) => infer R ? () => R : never
  >;
}

const USER = "11111111-1111-1111-1111-111111111111";
const PLAN = "22222222-2222-2222-2222-222222222222";
const WID = "aaaa1111-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const FROZEN_NOW = new Date(2026, 3, 27); // Apr 27, 2026 local midnight

function baseDB(endDate = "2026-08-01"): FakeDB {
  return {
    scheduled_workouts: [],
    training_plans: [{ id: PLAN, user_id: USER, end_date: endDate }],
    plan_adjustments: [],
  };
}

function seedWorkout(db: FakeDB, over: Row = {}) {
  db.scheduled_workouts.push({
    id: WID,
    user_id: USER,
    plan_id: PLAN,
    date: "2026-04-30", // future relative to FROZEN_NOW
    day_of_week: 4,
    week_number: 1,
    session: 1,
    workout_type: "intervals",
    workout_data: { name: "10 x 1km", steps: [{ stepType: "active", reps: 10 }] },
    notes: null,
    ...over,
  });
}

function buildReq(body: unknown, method = "POST"): Request {
  return new Request("http://localhost/edit-scheduled-workout", {
    method,
    headers: { "Content-Type": "application/json", Authorization: "Bearer fake" },
    body: JSON.stringify(body),
  });
}

function deps(db: FakeDB): EditWorkoutDeps {
  return {
    resolveUser: async () => USER,
    buildClient: () => buildFakeClient(db),
    now: () => FROZEN_NOW,
  };
}

Deno.test("OPTIONS returns CORS preflight", async () => {
  const res = await handleEditWorkout(new Request("http://localhost", { method: "OPTIONS" }));
  assertEquals(res.status, 200);
});

Deno.test("non-POST returns 405", async () => {
  const res = await handleEditWorkout(new Request("http://localhost", { method: "GET" }));
  assertEquals(res.status, 405);
});

Deno.test("unauthenticated returns 401", async () => {
  const db = baseDB();
  const res = await handleEditWorkout(buildReq({ scheduled_workout_id: WID }), {
    ...deps(db),
    resolveUser: async () => null,
  });
  assertEquals(res.status, 401);
});

Deno.test("missing scheduled_workout_id returns 400", async () => {
  const db = baseDB();
  const res = await handleEditWorkout(buildReq({ workout_type: "easy" }), deps(db));
  assertEquals(res.status, 400);
});

Deno.test("nothing to change returns 400", async () => {
  const db = baseDB();
  seedWorkout(db);
  const res = await handleEditWorkout(buildReq({ scheduled_workout_id: WID }), deps(db));
  assertEquals(res.status, 400);
});

Deno.test("missing workout returns 404", async () => {
  const db = baseDB();
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: "00000000-0000-0000-0000-000000000000", workout_type: "easy" }),
    deps(db),
  );
  assertEquals(res.status, 404);
});

Deno.test("wrong owner returns 403", async () => {
  const db = baseDB();
  seedWorkout(db, { user_id: "99999999-9999-9999-9999-999999999999", plan_id: "33333333-3333-3333-3333-333333333333" });
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, workout_type: "easy" }),
    deps(db),
  );
  assertEquals(res.status, 403);
});

Deno.test("past workout is rejected", async () => {
  const db = baseDB();
  seedWorkout(db, { date: "2026-04-20" }); // before FROZEN_NOW
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, workout_type: "easy" }),
    deps(db),
  );
  assertEquals(res.status, 400);
  assertEquals(db.plan_adjustments.length, 0);
});

Deno.test("happy path: edit steps writes workout_data + yellow adjustment", async () => {
  const db = baseDB();
  seedWorkout(db);
  const newData = { name: "6 x 1km", steps: [{ stepType: "active", reps: 6 }] };
  const res = await handleEditWorkout(
    buildReq({
      scheduled_workout_id: WID,
      workout_data: newData,
      reason_code: "fatigue",
      reason_text: "legs are cooked",
    }),
    deps(db),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.scheduled_workout_id, WID);
  // workout_data updated
  assertEquals((db.scheduled_workouts[0].workout_data as Row).name, "6 x 1km");
  // yellow-tier adjustment flagged to coach
  assertEquals(db.plan_adjustments.length, 1);
  const adj = db.plan_adjustments[0];
  assertEquals(adj.tier, "yellow");
  assertEquals(adj.action_type, "edit_workout");
  assertEquals(adj.trigger_type, "user_action");
  assertEquals(adj.reason_code, "fatigue");
  assertEquals(adj.reason_text, "legs are cooked");
  // before/after captured
  assert(adj.action_payload !== undefined);
});

Deno.test("unknown reason_code is rejected with 400", async () => {
  const db = baseDB();
  seedWorkout(db);
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, workout_type: "easy", reason_code: "vibes" }),
    deps(db),
  );
  assertEquals(res.status, 400);
  assertEquals(db.plan_adjustments.length, 0);
});

Deno.test("edit with status applies it and logs", async () => {
  const db = baseDB();
  seedWorkout(db);
  const res = await handleEditWorkout(
    buildReq({
      scheduled_workout_id: WID,
      workout_data: { name: "6 x 1km", steps: [{ stepType: "active", reps: 6 }] },
      status: "modified",
    }),
    deps(db),
  );
  assertEquals(res.status, 200);
  assertEquals(db.scheduled_workouts[0].status, "modified");
  assertEquals(db.plan_adjustments.length, 1);
});

Deno.test("invalid status is rejected", async () => {
  const db = baseDB();
  seedWorkout(db);
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, status: "vaporized" }),
    deps(db),
  );
  assertEquals(res.status, 400);
  assertEquals(db.plan_adjustments.length, 0);
});

Deno.test("race-week edit needs confirm_race_week", async () => {
  // Plan ends 2026-05-01; race week starts 2026-04-25. Workout on 2026-04-30
  // is inside it.
  const db = baseDB("2026-05-01");
  seedWorkout(db, { date: "2026-04-30" });
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, workout_type: "easy" }),
    deps(db),
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.race_week, true);
  assertEquals(db.plan_adjustments.length, 0);
});

Deno.test("race-week edit applies with confirm_race_week", async () => {
  const db = baseDB("2026-05-01");
  seedWorkout(db, { date: "2026-04-30" });
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, workout_type: "easy", confirm_race_week: true }),
    deps(db),
  );
  assertEquals(res.status, 200);
  assertEquals(db.scheduled_workouts[0].workout_type, "easy");
  assertEquals(db.plan_adjustments.length, 1);
});

// ── DUPLICATE mode (2026-07-15) ─────────────────────────────────────────

Deno.test("duplicate happy path: inserts user_created row + green adjustment", async () => {
  const db = baseDB();
  seedWorkout(db, { source: "easy_fill" });
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, duplicate_to_date: "2026-05-04" }),
    deps(db),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.duplicated_from, WID);
  assert(body.scheduled_workout_id !== WID);
  // Source row untouched, new row landed.
  assertEquals(db.scheduled_workouts.length, 2);
  const dup = db.scheduled_workouts[1];
  assertEquals(dup.date, "2026-05-04");
  assertEquals(dup.day_of_week, 1); // 2026-05-04 is a Monday
  assertEquals(dup.source, "user_created");
  assertEquals(dup.is_movable, true);
  assertEquals(dup.status, "scheduled");
  assertEquals((dup.workout_data as Row).name, "10 x 1km");
  // Green-tier audit — own workout, routine customization.
  assertEquals(db.plan_adjustments.length, 1);
  const adj = db.plan_adjustments[0];
  assertEquals(adj.action_type, "duplicate_workout");
  assertEquals(adj.trigger_type, "user_action");
  assertEquals(adj.tier, "green");
});

Deno.test("duplicating a coach_locked workout logs yellow", async () => {
  const db = baseDB();
  seedWorkout(db, { source: "coach_locked" });
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, duplicate_to_date: "2026-05-04" }),
    deps(db),
  );
  assertEquals(res.status, 200);
  assertEquals(db.plan_adjustments.length, 1);
  assertEquals(db.plan_adjustments[0].tier, "yellow");
});

Deno.test("duplicate to a past date is rejected", async () => {
  const db = baseDB();
  seedWorkout(db);
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, duplicate_to_date: "2026-04-20" }),
    deps(db),
  );
  assertEquals(res.status, 400);
  assertEquals(db.scheduled_workouts.length, 1);
  assertEquals(db.plan_adjustments.length, 0);
});

Deno.test("duplicate with malformed date is rejected", async () => {
  const db = baseDB();
  seedWorkout(db);
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, duplicate_to_date: "next tuesday" }),
    deps(db),
  );
  assertEquals(res.status, 400);
  assertEquals(db.scheduled_workouts.length, 1);
});

Deno.test("duplicating a PAST workout to a future day is allowed", async () => {
  const db = baseDB();
  seedWorkout(db, { date: "2026-04-20" }); // before FROZEN_NOW — source can be history
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, duplicate_to_date: "2026-05-04" }),
    deps(db),
  );
  assertEquals(res.status, 200);
  assertEquals(db.scheduled_workouts.length, 2);
});

Deno.test("duplicate into race week needs confirm_race_week", async () => {
  const db = baseDB("2026-05-01"); // race week starts 2026-04-25
  seedWorkout(db, { date: "2026-04-28" });
  const res = await handleEditWorkout(
    buildReq({ scheduled_workout_id: WID, duplicate_to_date: "2026-04-30" }),
    deps(db),
  );
  assertEquals(res.status, 400);
  const body = await res.json();
  assertEquals(body.race_week, true);
  assertEquals(db.scheduled_workouts.length, 1);

  const confirmed = await handleEditWorkout(
    buildReq({
      scheduled_workout_id: WID,
      duplicate_to_date: "2026-04-30",
      confirm_race_week: true,
    }),
    deps(db),
  );
  assertEquals(confirmed.status, 200);
  assertEquals(db.scheduled_workouts.length, 2);
});
