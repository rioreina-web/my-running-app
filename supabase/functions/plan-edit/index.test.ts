/**
 * Tests for the plan-edit HTTP handler. Runs against a minimal in-memory
 * supabase fake and an injected `parseEdit`, so no network or DB is touched —
 * the engine itself (LLM call, resolver, validator) is already covered by
 * `_shared/plan-edit.test.ts` against real library data; this file checks the
 * HTTP-layer plumbing: auth, body validation, race-week gating, and that the
 * response shape is what it claims to be.
 *
 * Run: deno test --allow-env --allow-read --allow-net plan-edit/index.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handlePlanEdit, type PlanEditDeps } from "./index.ts";
import type { RawPlanEditResponse } from "../_shared/plan-edit-schema.ts";
import type { ScheduledWorkoutRef } from "../_shared/plan-edit-schema.ts";

// ── Fake supabase client — select/eq/gte/lte/in, awaited for all rows ────

type Row = Record<string, unknown>;
interface FakeDB {
  scheduled_workouts: Row[];
  training_plans: Row[];
  coach_profiles: Row[];
  athlete_plan_subscriptions: Row[];
  plan_templates: Row[];
}

function fakeDB(overrides: Partial<FakeDB> = {}): FakeDB {
  return {
    scheduled_workouts: [], training_plans: [],
    coach_profiles: [], athlete_plan_subscriptions: [], plan_templates: [],
    ...overrides,
  };
}

function buildFakeClient(db: FakeDB) {
  const from = (table: keyof FakeDB) => {
    const filters: Array<(r: Row) => boolean> = [];
    const chain: Record<string, unknown> = {};
    chain.select = () => chain;
    chain.eq = (col: string, val: unknown) => {
      filters.push((r) => {
        if (col === "plan_template.coach_id") {
          const tpl = db.plan_templates.find((t) => t.id === r.plan_template_id);
          return tpl?.coach_id === val;
        }
        return r[col] === val;
      });
      return chain;
    };
    chain.gte = (col: string, val: unknown) => { filters.push((r) => (r[col] as string) >= (val as string)); return chain; };
    chain.lte = (col: string, val: unknown) => { filters.push((r) => (r[col] as string) <= (val as string)); return chain; };
    chain.in = (col: string, vals: unknown[]) => { filters.push((r) => vals.includes(r[col])); return chain; };
    chain.order = () => chain;
    chain.limit = () => chain;
    const matched = () => db[table].filter((r) => filters.every((f) => f(r)));
    chain.maybeSingle = async () => ({ data: matched()[0] ?? null, error: null });
    chain.single = chain.maybeSingle;
    chain.then = (resolve: (v: { data: Row[]; error: null }) => unknown, reject?: (e: unknown) => unknown) => {
      let rowsMatched = matched();
      // Minimal support for the one nested select this handler uses:
      // athlete_plan_subscriptions -> plan_templates!inner(coach_id).
      if (table === "athlete_plan_subscriptions") {
        rowsMatched = rowsMatched
          .map((r): Row | null => {
            const tpl = db.plan_templates.find((t) => t.id === r.plan_template_id);
            return tpl ? { ...r, plan_template: { coach_id: tpl.coach_id } } as Row : null;
          })
          .filter((r): r is Row => r !== null);
      }
      return Promise.resolve({ data: rowsMatched, error: null }).then(resolve, reject);
    };
    return chain;
  };
  return { from } as unknown as ReturnType<
    // deno-lint-ignore no-explicit-any
    (typeof import("https://esm.sh/@supabase/supabase-js@2"))["createClient"] extends (...a: any) => infer R ? () => R : never
  >;
}

function baseDeps(db: FakeDB, overrides: Partial<PlanEditDeps> = {}): PlanEditDeps {
  return {
    resolveUser: async () => "athlete-1",
    buildClient: () => buildFakeClient(db),
    budgetAllows: async () => true,
    now: () => new Date("2026-09-01T12:00:00Z"),
    ...overrides,
  };
}

function req(body: unknown): Request {
  return new Request("http://localhost/plan-edit", {
    method: "POST",
    headers: { Authorization: "Bearer test", "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

const fakeParse = (ops: unknown[]): PlanEditDeps["parseEdit"] =>
  async (): Promise<RawPlanEditResponse> => ({ ops, unparsed: [] });

// `session` in the real schema is an integer (which session of the day),
// never text — deliberately absent here to match the live column list.
// The text a coach/athlete would actually recognize comes from workout_data
// steps (see scheduled-workout-text.ts), which is how the endpoint reads it.
function tuesdayRow(overrides: Partial<Row> = {}): Row {
  return {
    id: "sw-tue", user_id: "athlete-1", plan_id: "plan-1",
    date: "2026-09-01", day_of_week: 2, week_number: 1,
    workout_type: "intervals",
    workout_data: {
      steps: [{ stepType: "active", durationType: "distance_meters", durationValue: 800, paceZone: "fiveK", repeats: 6 }],
    },
    notes: null, is_key_session: true,
    ...overrides,
  };
}

// ── Auth + validation ─────────────────────────────────────

Deno.test("401 with no resolvable user", async () => {
  const res = await handlePlanEdit(req({ text: "x", start_date: "2026-09-01", end_date: "2026-09-07" }), {
    resolveUser: async () => null,
  });
  assertEquals(res.status, 401);
});

Deno.test("400 on missing text", async () => {
  const res = await handlePlanEdit(req({ start_date: "2026-09-01", end_date: "2026-09-07" }), baseDeps(fakeDB({ scheduled_workouts: [], training_plans: [] })));
  assertEquals(res.status, 400);
});

Deno.test("400 on malformed dates", async () => {
  const db = fakeDB({ scheduled_workouts: [], training_plans: [] });
  const res = await handlePlanEdit(req({ text: "x", start_date: "sept 1", end_date: "2026-09-07" }), baseDeps(db));
  assertEquals(res.status, 400);
});

Deno.test("400 when end_date precedes start_date", async () => {
  const db = fakeDB({ scheduled_workouts: [], training_plans: [] });
  const res = await handlePlanEdit(req({ text: "x", start_date: "2026-09-07", end_date: "2026-09-01" }), baseDeps(db));
  assertEquals(res.status, 400);
});

Deno.test("400 when the range exceeds the 21-day cap", async () => {
  const db = fakeDB({ scheduled_workouts: [], training_plans: [] });
  const res = await handlePlanEdit(req({ text: "x", start_date: "2026-09-01", end_date: "2026-10-15" }), baseDeps(db));
  assertEquals(res.status, 400);
});

Deno.test("429 when the budget guard declines", async () => {
  const db = fakeDB({ scheduled_workouts: [tuesdayRow()], training_plans: [] });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07" }),
    baseDeps(db, { budgetAllows: async () => false }),
  );
  assertEquals(res.status, 429);
});

Deno.test("empty range returns a clean empty response, not an error", async () => {
  const db = fakeDB({ scheduled_workouts: [], training_plans: [] });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07" }),
    baseDeps(db),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.resolved.length, 0);
});

// ── The happy path, with the model faked ─────────────────

Deno.test("an unambiguous instruction returns one resolved diff", async () => {
  const db = fakeDB({ scheduled_workouts: [tuesdayRow()], training_plans: [] });
  const res = await handlePlanEdit(
    req({ text: "make tuesday an easy day", start_date: "2026-09-01", end_date: "2026-09-07" }),
    baseDeps(db, { parseEdit: fakeParse([{ kind: "schedule_easy", targetHint: "tuesday" }]) }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.resolved.length, 1);
  assertEquals(body.resolved[0].workoutId, "sw-tue");
  assertEquals(body.resolved[0].after, "Easy run — same distance as before");
  assertEquals(body.questions.length, 0);
});

Deno.test("an ambiguous target returns a question, not a guess", async () => {
  const db = fakeDB({
    scheduled_workouts: [tuesdayRow(), tuesdayRow({
      id: "sw-tue2", date: "2026-09-08", week_number: 2,
      workout_data: { steps: [{ stepType: "active", durationType: "distance_meters", durationValue: 400, paceZone: "mile", repeats: 8 }] },
    })],
  });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-14" }),
    baseDeps(db, { parseEdit: fakeParse([{ kind: "schedule_easy", targetHint: "tuesday" }]) }),
  );
  const body = await res.json();
  assertEquals(body.resolved.length, 0);
  assertEquals(body.questions.length, 1);
  assertEquals(body.questions[0].options.length, 2);
});

Deno.test("a workout in the final 6 days before the plan's end_date asks before touching it", async () => {
  const db = fakeDB({
    scheduled_workouts: [tuesdayRow({ date: "2026-10-10", plan_id: "plan-1" })],
    training_plans: [{ id: "plan-1", end_date: "2026-10-12" }], // 2 days out — inside the 6-day window
  });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-10-08", end_date: "2026-10-14" }),
    baseDeps(db, { parseEdit: fakeParse([{ kind: "schedule_easy", targetHint: "tuesday" }]) }),
  );
  const body = await res.json();
  assertEquals(body.resolved.length, 0);
  assertEquals(body.questions.length, 1);
  assert(body.questions[0].question.includes("race week"));
});

Deno.test("a workout well before the race window is NOT gated", async () => {
  const db = fakeDB({
    scheduled_workouts: [tuesdayRow({ date: "2026-09-01", plan_id: "plan-1" })],
    training_plans: [{ id: "plan-1", end_date: "2026-10-12" }], // weeks out
  });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07" }),
    baseDeps(db, { parseEdit: fakeParse([{ kind: "schedule_easy", targetHint: "tuesday" }]) }),
  );
  const body = await res.json();
  assertEquals(body.resolved.length, 1);
});

Deno.test("a garbage op from the model is dropped and reported, not thrown", async () => {
  const db = fakeDB({ scheduled_workouts: [tuesdayRow()], training_plans: [] });
  const res = await handlePlanEdit(
    req({ text: "do something weird", start_date: "2026-09-01", end_date: "2026-09-07" }),
    baseDeps(db, { parseEdit: fakeParse([{ kind: "delete_everything", targetHint: "tuesday" }]) }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.resolved.length, 0);
  assert(body.warnings.length >= 1);
});

Deno.test("model unavailable degrades to a warning, never a 500", async () => {
  const db = fakeDB({ scheduled_workouts: [tuesdayRow()], training_plans: [] });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07" }),
    baseDeps(db, { parseEdit: async () => null }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.resolved.length, 0);
  assert(body.warnings[0].toLowerCase().includes("model"));
});

Deno.test("scoped to the caller — user_id is always part of the query", async () => {
  const db = fakeDB({ scheduled_workouts: [tuesdayRow({ user_id: "someone-else" })] });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07" }),
    baseDeps(db, { parseEdit: fakeParse([{ kind: "schedule_easy", targetHint: "tuesday" }]) }),
  );
  const body = await res.json();
  assertEquals(body.resolved.length, 0, "another athlete's row must not surface");
});

// ── Coach editing an athlete's plan ──────────────────────

Deno.test("athlete_user_id from a caller with no coach_profiles row is refused", async () => {
  const db = fakeDB({ scheduled_workouts: [tuesdayRow({ user_id: "athlete-9" })] });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07", athlete_user_id: "athlete-9" }),
    baseDeps(db),
  );
  assertEquals(res.status, 403);
});

Deno.test("a coach who does not own the athlete is refused, athlete's data never leaves the query", async () => {
  const db = fakeDB({
    scheduled_workouts: [tuesdayRow({ user_id: "athlete-9" })],
    coach_profiles: [{ id: "coach-a", user_id: "athlete-1" }],
    // no training_plans row and no subscription linking coach-a to athlete-9
  });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07", athlete_user_id: "athlete-9" }),
    baseDeps(db),
  );
  assertEquals(res.status, 403);
});

Deno.test("a coach who directly owns the athlete's active plan can edit it", async () => {
  const db = fakeDB({
    scheduled_workouts: [tuesdayRow({ user_id: "athlete-9" })],
    coach_profiles: [{ id: "coach-a", user_id: "athlete-1" }],
    training_plans: [{ id: "plan-9", user_id: "athlete-9", status: "active", coach_id: "coach-a", end_date: "2026-12-01" }],
  });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07", athlete_user_id: "athlete-9" }),
    baseDeps(db, { parseEdit: fakeParse([{ kind: "schedule_easy", targetHint: "tuesday" }]) }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.resolved.length, 1);
});

Deno.test("a coach who owns the athlete only via an active template subscription can edit it", async () => {
  const db = fakeDB({
    scheduled_workouts: [tuesdayRow({ user_id: "athlete-9" })],
    coach_profiles: [{ id: "coach-a", user_id: "athlete-1" }],
    plan_templates: [{ id: "tpl-1", coach_id: "coach-a" }],
    athlete_plan_subscriptions: [{ id: "sub-1", athlete_user_id: "athlete-9", status: "active", plan_template_id: "tpl-1" }],
  });
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07", athlete_user_id: "athlete-9" }),
    baseDeps(db, { parseEdit: fakeParse([{ kind: "schedule_easy", targetHint: "tuesday" }]) }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.resolved.length, 1);
});

Deno.test("without athlete_user_id, self-service mode is unaffected by coach tables", async () => {
  const db = fakeDB({ scheduled_workouts: [tuesdayRow()] }); // user_id: "athlete-1", the caller
  const res = await handlePlanEdit(
    req({ text: "make tuesday easy", start_date: "2026-09-01", end_date: "2026-09-07" }),
    baseDeps(db, { parseEdit: fakeParse([{ kind: "schedule_easy", targetHint: "tuesday" }]) }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.resolved.length, 1);
});
