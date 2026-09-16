/**
 * Tests for rewrite-block. Runs against a minimal in-memory supabase fake.
 *
 * Run: deno test --allow-env --allow-net rewrite-block/index.test.ts
 *
 * The fake client covers exactly the query shapes handleRewriteBlock uses:
 *   from(t).select(c).eq(k,v).maybeSingle()
 *   from(t).select(c).in(k, arr)                       -> { data }
 *   from(t).insert(row).select(c).maybeSingle()        -> { data:{id} }
 *   from(t).update(patch).eq(k,v)
 * Ownership tests use the direct `training_plans.coach_id === coachId` path so
 * the subscription-join fallback isn't exercised here (it needs a live join).
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleRewriteBlock, type RewriteBlockDeps } from "./index.ts";

type Row = Record<string, unknown>;

interface FakeDB {
  scheduled_workouts: Row[];
  training_plans: Row[];
  athlete_plan_subscriptions: Row[];
  plan_adjustments: Row[];
}

let idSeq = 0;
function nextId(prefix: string): string {
  idSeq += 1;
  return `${prefix}-${String(idSeq).padStart(4, "0")}`;
}

function buildFakeClient(db: FakeDB) {
  const from = (table: keyof FakeDB) => {
    const filters: Array<[string, unknown]> = [];
    let inFilter: [string, unknown[]] | null = null;
    let pendingInsert: Row[] | null = null;

    const matches = (r: Row) =>
      filters.every(([c, v]) => r[c] === v) &&
      (!inFilter || (inFilter[1] as unknown[]).includes(r[inFilter[0]]));

    const chain: Record<string, unknown> = {};
    chain.select = (_cols?: string) => chain;
    chain.eq = (col: string, val: unknown) => {
      filters.push([col, val]);
      return chain;
    };
    chain.in = (col: string, vals: unknown[]) => {
      inFilter = [col, vals];
      // `.in()` is terminal (awaited) in the function under test.
      return Promise.resolve({ data: db[table].filter(matches), error: null });
    };
    chain.limit = (_n: number) => chain;
    chain.maybeSingle = async () => {
      // Insert-then-select path.
      if (pendingInsert) {
        const inserted = pendingInsert.map((r) => {
          const withId = { id: r.id ?? nextId(String(table)), ...r };
          db[table].push(withId);
          return withId;
        });
        return { data: inserted[0] ?? null, error: null };
      }
      const row = db[table].find(matches);
      return { data: row ?? null, error: null };
    };
    chain.single = chain.maybeSingle;
    chain.insert = (rows: Row | Row[]) => {
      pendingInsert = Array.isArray(rows) ? rows : [rows];
      // Support insert without a following .select() too.
      const p = chain as Record<string, unknown> & {
        then?: unknown;
      };
      p.then = (resolve: (v: unknown) => void) => {
        const inserted = pendingInsert!.map((r) => {
          const withId = { id: r.id ?? nextId(String(table)), ...r };
          db[table].push(withId);
          return withId;
        });
        pendingInsert = null;
        resolve({ data: inserted, error: null });
      };
      return chain;
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

// ── Fixtures ────────────────────────────────────────────
const COACH = "coach-1";
const ATHLETE = "athlete-1";
const PLAN = "plan-1";
const FROZEN_NOW = new Date(2026, 4, 1); // May 1 2026 local midnight

function baseDB(overrides: Partial<Row> = {}): FakeDB {
  return {
    scheduled_workouts: [],
    training_plans: [{
      id: PLAN,
      user_id: ATHLETE,
      coach_id: COACH,
      start_date: "2026-04-01",
      end_date: "2026-08-01", // race well beyond the test edits
      ...overrides,
    }],
    athlete_plan_subscriptions: [],
    plan_adjustments: [],
  };
}

function deps(db: FakeDB, extra: Partial<RewriteBlockDeps> = {}): RewriteBlockDeps {
  return {
    authGate: () => null, // bypass service-role check
    buildClient: () => buildFakeClient(db),
    now: () => FROZEN_NOW,
    ...extra,
  };
}

function req(body: unknown, method = "POST"): Request {
  return new Request("http://localhost/rewrite-block", {
    method,
    headers: { "Content-Type": "application/json", Authorization: "Bearer service" },
    body: JSON.stringify(body),
  });
}

function validBody(changes: unknown[], extra: Row = {}): Row {
  return {
    coachId: COACH,
    athleteUserId: ATHLETE,
    planId: PLAN,
    weekRange: { fromWeek: 7, toWeek: 8 },
    changes,
    reasonCode: "sickness",
    reasonText: "flu, 10 days off",
    ...extra,
  };
}

// ── Tests ───────────────────────────────────────────────

Deno.test("OPTIONS returns CORS preflight", async () => {
  const res = await handleRewriteBlock(new Request("http://x", { method: "OPTIONS" }));
  assertEquals(res.status, 200);
});

Deno.test("non-POST returns 405", async () => {
  const res = await handleRewriteBlock(new Request("http://x", { method: "GET" }));
  assertEquals(res.status, 405);
});

Deno.test("service-role gate rejects when authGate returns a response", async () => {
  const db = baseDB();
  const unauth = new Response(JSON.stringify({ error: "no" }), { status: 401 });
  const res = await handleRewriteBlock(
    req(validBody([])),
    { ...deps(db), authGate: () => unauth },
  );
  assertEquals(res.status, 401);
});

Deno.test("missing required fields returns 400", async () => {
  const db = baseDB();
  const res = await handleRewriteBlock(req({ coachId: COACH }), deps(db));
  assertEquals(res.status, 400);
});

Deno.test("empty changes returns 400", async () => {
  const db = baseDB();
  const res = await handleRewriteBlock(req(validBody([])), deps(db));
  assertEquals(res.status, 400);
});

Deno.test("invalid reasonCode returns 400", async () => {
  const db = baseDB();
  const res = await handleRewriteBlock(
    req(validBody(
      [{ date: "2026-05-19", weekNumber: 7, workoutType: "long_run" }],
      { reasonCode: "because" },
    )),
    deps(db),
  );
  assertEquals(res.status, 400);
});

Deno.test("past-dated change is rejected", async () => {
  const db = baseDB();
  const res = await handleRewriteBlock(
    req(validBody([{ date: "2026-04-15", weekNumber: 7, workoutType: "long_run" }])),
    deps(db),
  );
  assertEquals(res.status, 400);
});

Deno.test("weekNumber outside weekRange is rejected", async () => {
  const db = baseDB();
  const res = await handleRewriteBlock(
    req(validBody([{ date: "2026-05-19", weekNumber: 12, workoutType: "long_run" }])),
    deps(db),
  );
  assertEquals(res.status, 400);
});

Deno.test("plan not found returns 404", async () => {
  const db = baseDB();
  db.training_plans = [];
  const res = await handleRewriteBlock(
    req(validBody([{ date: "2026-05-19", weekNumber: 7, workoutType: "long_run" }])),
    deps(db),
  );
  assertEquals(res.status, 404);
});

Deno.test("plan belonging to another athlete returns 400", async () => {
  const db = baseDB({ user_id: "someone-else" });
  const res = await handleRewriteBlock(
    req(validBody([{ date: "2026-05-19", weekNumber: 7, workoutType: "long_run" }])),
    deps(db),
  );
  assertEquals(res.status, 400);
});

Deno.test("coach who does not own the plan gets 403", async () => {
  const db = baseDB({ coach_id: "other-coach" });
  const res = await handleRewriteBlock(
    req(validBody([{ date: "2026-05-19", weekNumber: 7, workoutType: "long_run" }])),
    deps(db),
  );
  assertEquals(res.status, 403);
});

Deno.test("race-week edit without confirm returns 409", async () => {
  const db = baseDB();
  // end_date 2026-05-24 → race week starts 2026-05-18; a change on 2026-05-20 hits it.
  db.training_plans[0].end_date = "2026-05-24";
  const res = await handleRewriteBlock(
    req(validBody([{ date: "2026-05-20", weekNumber: 7, workoutType: "long_run" }])),
    deps(db),
  );
  assertEquals(res.status, 409);
  const body = await res.json();
  assertEquals(body.code, "race_week_confirm_required");
});

Deno.test("race-week edit with confirm proceeds", async () => {
  const db = baseDB();
  db.training_plans[0].end_date = "2026-05-24";
  const wId = "sw-existing";
  db.scheduled_workouts.push({
    id: wId, plan_id: PLAN, user_id: ATHLETE, date: "2026-05-20",
    day_of_week: 3, week_number: 7, workout_type: "easy", workout_data: null,
    notes: null, status: "scheduled", source: "easy_fill",
  });
  const res = await handleRewriteBlock(
    req(validBody(
      [{ scheduledWorkoutId: wId, date: "2026-05-20", weekNumber: 7, workoutType: "long_run" }],
      { confirmRaceWeek: true },
    )),
    deps(db),
  );
  assertEquals(res.status, 200);
});

Deno.test("happy path: edit existing workout + ledger row per week", async () => {
  const db = baseDB();
  const wId = "sw-existing";
  db.scheduled_workouts.push({
    id: wId, plan_id: PLAN, user_id: ATHLETE, date: "2026-05-19",
    day_of_week: 2, week_number: 7, workout_type: "easy", workout_data: null,
    notes: null, status: "scheduled", source: "easy_fill",
  });
  const res = await handleRewriteBlock(
    req(validBody([{
      scheduledWorkoutId: wId,
      date: "2026-05-19",
      weekNumber: 7,
      workoutType: "long_run",
      workoutData: { name: "Long 14mi", total_distance_mi: 14 },
      notes: "build the aerobic base back gently",
    }])),
    deps(db),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.ok, true);
  assertEquals(body.updatedCount, 1);
  assertEquals(body.insertedCount, 0);
  assertEquals(body.changedWeeks, [7]);

  // Row was updated in place, coach-locked.
  const row = db.scheduled_workouts.find((r) => r.id === wId)!;
  assertEquals(row.workout_type, "long_run");
  assertEquals(row.source, "coach_locked");

  // Exactly one ledger row, correct vocab + tier + reason.
  assertEquals(db.plan_adjustments.length, 1);
  const adj = db.plan_adjustments[0];
  assertEquals(adj.trigger_type, "coach_rewrite");
  assertEquals(adj.action_type, "rewrite_block");
  assertEquals(adj.tier, "yellow");
  assertEquals(adj.reason_code, "sickness");
  assertEquals(adj.week_number, 7);
  assert(adj.action_payload && typeof adj.action_payload === "object");
});

Deno.test("happy path: insert a new day", async () => {
  const db = baseDB();
  const res = await handleRewriteBlock(
    req(validBody([{
      date: "2026-05-21",
      weekNumber: 7,
      workoutType: "recovery",
      workoutData: { name: "Recovery 4mi", total_distance_mi: 4 },
    }])),
    deps(db),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.insertedCount, 1);
  assertEquals(body.updatedCount, 0);
  // One new coach-locked workout exists for the athlete.
  const row = db.scheduled_workouts.find((r) => r.date === "2026-05-21")!;
  assert(row);
  assertEquals(row.user_id, ATHLETE);
  assertEquals(row.source, "coach_locked");
  assertEquals(row.status, "scheduled");
});

Deno.test("multi-week rewrite writes one ledger row per changed week", async () => {
  const db = baseDB();
  const res = await handleRewriteBlock(
    req(validBody([
      { date: "2026-05-19", weekNumber: 7, workoutType: "long_run" },
      { date: "2026-05-26", weekNumber: 8, workoutType: "long_run" },
    ])),
    deps(db),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.changedWeeks, [7, 8]);
  assertEquals(db.plan_adjustments.length, 2);
});

Deno.test("rationale regen hook is fired for changed weeks", async () => {
  const db = baseDB();
  let firedWeeks: number[] | null = null;
  const res = await handleRewriteBlock(
    req(validBody([
      { date: "2026-05-19", weekNumber: 7, workoutType: "long_run" },
      { date: "2026-05-26", weekNumber: 8, workoutType: "long_run" },
    ])),
    deps(db, {
      fireRationaleRegen: async (_planId, weeks) => { firedWeeks = weeks; },
    }),
  );
  assertEquals(res.status, 200);
  assertEquals(firedWeeks, [7, 8]);
});
