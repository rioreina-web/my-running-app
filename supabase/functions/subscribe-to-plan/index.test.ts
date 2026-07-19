/**
 * Regression tests for subscribe-to-plan.
 *
 * Original bug: `isAdaptive` was declared on line 167 but referenced inside
 * the training_plans insert on line 156. That threw ReferenceError: Cannot
 * access 'isAdaptive' before initialization on every call, so no plan —
 * adaptive OR fixed — ever got written.
 *
 * These tests invoke the handler with a minimal template for each plan_type
 * and assert that a training_plans row was actually inserted.
 *
 * Run: deno test --allow-env --allow-net subscribe-to-plan/index.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handler, type Deps } from "./index.ts";

// ── Test doubles ────────────────────────────────────────

interface CapturedInserts {
  [table: string]: Record<string, unknown>[];
}

function buildMockSupabase(template: Record<string, unknown>) {
  const inserts: CapturedInserts = {};

  const builder = (table: string) => {
    const filters: Array<[string, unknown]> = [];
    let _select: string | undefined;
    const api: Record<string, unknown> = {};

    api.select = (cols: string) => {
      _select = cols;
      return api;
    };
    api.eq = (col: string, val: unknown) => {
      filters.push([col, val]);
      return api;
    };
    api.maybeSingle = async () => resolveRead(table, "maybe");
    api.single = async () => resolveRead(table, "single");
    api.insert = async (rows: unknown) => {
      const arr = Array.isArray(rows) ? rows : [rows];
      inserts[table] = (inserts[table] ?? []).concat(arr as Record<string, unknown>[]);
      return { error: null };
    };
    api.delete = () => ({
      eq: async (_col: string, _val: unknown) => ({ error: null }),
    });

    const resolveRead = (tbl: string, _mode: "maybe" | "single") => {
      if (tbl === "plan_templates") return { data: template, error: null };
      // No existing subscription, no coach profile — force happy path
      return { data: null, error: null };
    };

    return api;
  };

  const client = {
    from: (table: string) => builder(table),
    rpc: (_fn: string, _args: unknown) => ({
      maybeSingle: async () => ({ data: null, error: null }),
    }),
  };

  return { client: client as unknown, inserts };
}

function buildDeps(template: Record<string, unknown>, athleteUserId: string) {
  const mock = buildMockSupabase(template);
  const deps: Deps = {
    createSupabaseClient: () => mock.client as never,
    getAuthenticatedUser: async () => athleteUserId,
    getOrBuildAthleteState: async () => ({
      pace_zones: { easy: 540, recovery: 600, mp: 450, threshold: 420 },
    }),
    // Mock the pace resolver directly so tests don't need to stand up
    // the full anchor → profile cascade. Returns the same paces the old
    // `pace_zones` source used to provide.
    resolveAthletePaces: async () => ({
      easy: 540,
      recovery: 600,
      mp: 450,
      threshold: 420,
    }),
  };
  return { deps, inserts: mock.inserts };
}

function buildRequest(body: Record<string, unknown>): Request {
  return new Request("http://localhost/subscribe-to-plan", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer fake-token",
    },
    body: JSON.stringify(body),
  });
}

// ── Minimal templates ───────────────────────────────────

const minimalWeeks = [
  {
    weekNumber: 1,
    targetMilesMin: 20,
    targetMilesMax: 24,
    workouts: [
      { dayOfWeek: 2, workoutType: "tempo", workoutData: { total_distance_km: 8 } },
      { dayOfWeek: 6, workoutType: "long_run", workoutData: { total_distance_km: 16 } },
    ],
  },
  {
    weekNumber: 2,
    targetMilesMin: 22,
    targetMilesMax: 26,
    workouts: [
      { dayOfWeek: 2, workoutType: "intervals", workoutData: { total_distance_km: 10 } },
      { dayOfWeek: 6, workoutType: "long_run", workoutData: { total_distance_km: 18 } },
    ],
  },
];

function fixedTemplate() {
  return {
    id: "plan-template-fixed",
    name: "Minimal Fixed Plan",
    plan_type: "fixed",
    target_distance: "marathon",
    duration_weeks: 2,
    coach_id: null,
    weeks: minimalWeeks,
  };
}

function adaptiveTemplate() {
  return { ...fixedTemplate(), id: "plan-template-adaptive", plan_type: "adaptive" };
}

// ── Tests ───────────────────────────────────────────────

Deno.test("fixed plan: training_plans row is inserted", async () => {
  const athleteUserId = "athlete-1";
  const { deps, inserts } = buildDeps(fixedTemplate(), athleteUserId);

  const res = await handler(
    buildRequest({
      planTemplateId: "plan-template-fixed",
      athleteUserId,
      startDate: "2026-05-01",
    }),
    deps
  );

  assertEquals(res.status, 200, "handler should return 200 on happy path");
  const body = await res.json();
  assert(body.trainingPlanId, "response must include trainingPlanId");

  const plans = inserts["training_plans"] ?? [];
  assertEquals(plans.length, 1, "exactly one training_plans row should be inserted");
  assertEquals(plans[0].plan_type, "fixed");
  assertEquals(plans[0].user_id, athleteUserId);
  assertEquals(plans[0].status, "active");
});

Deno.test("adaptive plan: training_plans row is inserted", async () => {
  const athleteUserId = "athlete-2";
  const { deps, inserts } = buildDeps(adaptiveTemplate(), athleteUserId);

  const res = await handler(
    buildRequest({
      planTemplateId: "plan-template-adaptive",
      athleteUserId,
      startDate: "2026-05-01",
    }),
    deps
  );

  assertEquals(res.status, 200, "handler should return 200 on happy path");
  const body = await res.json();
  assert(body.trainingPlanId, "response must include trainingPlanId");

  const plans = inserts["training_plans"] ?? [];
  assertEquals(plans.length, 1, "exactly one training_plans row should be inserted");
  assertEquals(plans[0].plan_type, "adaptive");
  assertEquals(plans[0].user_id, athleteUserId);
  assertEquals(plans[0].status, "active");

  // Adaptive plans also materialize quality_session_templates
  const qts = inserts["quality_session_templates"] ?? [];
  assert(qts.length > 0, "adaptive plan should insert quality_session_templates");
});

// ── AO-2: subscription_preferences regression coverage ─────────────────

Deno.test("subscription_preferences: rest_dows + preferred_quality_dows reshape the week", async () => {
  const athleteUserId = "athlete-prefs-1";
  const { deps, inserts } = buildDeps(adaptiveTemplate(), athleteUserId);

  // Coach template has quality on dow 2 (Wed) and 6 (Sun). Athlete wants
  // rest on dow 0 (Mon) and dow 4 (Fri); quality on dow 1 (Tue) and dow 3 (Thu);
  // long run on dow 5 (Sat).
  const res = await handler(
    buildRequest({
      planTemplateId: "plan-template-adaptive",
      athleteUserId,
      startDate: "2026-05-01",
      subscription_preferences: {
        rest_dows: [0, 4],
        preferred_quality_dows: [1, 3],
        long_run_dow: 5,
      },
    }),
    deps
  );
  assertEquals(res.status, 200);

  const workouts = inserts["scheduled_workouts"] ?? [];
  // day_of_week is 1-indexed (1=Mon..7=Sun) on the insert.
  const week1 = workouts.filter((w) => w.week_number === 1);
  const byDow = new Map<number, Record<string, unknown>>(
    week1.map((w) => [w.day_of_week as number, w])
  );

  // Mon (1) + Fri (5) → rest
  assertEquals(byDow.get(1)?.workout_type, "rest", "Mon should be rest");
  assertEquals(byDow.get(5)?.workout_type, "rest", "Fri should be rest");

  // Sat (6) → long_run (long_run_dow override)
  assertEquals(byDow.get(6)?.workout_type, "long_run", "Sat should be long run");

  // Tue (2) → tempo (the only non-long-run quality from the template)
  assertEquals(byDow.get(2)?.workout_type, "tempo", "Tue should be tempo");

  // Thu (4) → easy (athlete picked it as quality but template only has 1
  // non-long-run quality, so the slot stays as easy_fill)
  const thu = byDow.get(4);
  assert(thu?.workout_type !== "rest" && thu?.workout_type !== "long_run",
    "Thu should fall through to an easy fill");

  // Subscription row carries the prefs
  const subs = inserts["athlete_plan_subscriptions"] ?? [];
  assertEquals(subs.length, 1);
  assertEquals(subs[0].rest_dows, [0, 4]);
  assertEquals(subs[0].preferred_quality_dows, [1, 3]);
  assertEquals(subs[0].long_run_dow, 5);
});

Deno.test("subscription_preferences: volume_ramp scales week-1 mileage", async () => {
  const athleteUserId = "athlete-prefs-2";
  const { deps, inserts } = buildDeps(adaptiveTemplate(), athleteUserId);

  // Coach prescribes 22 mi avg in week 1 (min 20, max 24). Athlete starts
  // at 12 mi and ramps over 4 weeks, so week 1 should land at 12 mi
  // ((1-1)/(4-1) * (22-12) = 0).
  const res = await handler(
    buildRequest({
      planTemplateId: "plan-template-adaptive",
      athleteUserId,
      startDate: "2026-05-01",
      subscription_preferences: {
        volume_ramp: {
          start_mileage: 12,
          ramp_to_coach_target: true,
          ramp_weeks: 4,
        },
      },
    }),
    deps
  );
  assertEquals(res.status, 200);

  const workouts = inserts["scheduled_workouts"] ?? [];
  const week1 = workouts.filter((w) => w.week_number === 1);

  // Sum the mileage across easy days (week-1 quality miles come from the
  // template — long_run = 16/1.609 ≈ 9.94 mi, tempo = 8/1.609 ≈ 4.97 mi).
  const easyMiles = week1
    .filter((w) => w.workout_type === "easy" || w.workout_type === "recovery")
    .reduce((sum, w) => {
      const data = w.workout_data as Record<string, unknown> | null;
      const km = (data?.total_distance_km as number) ?? 0;
      return sum + km / 1.60934;
    }, 0);

  // Week 1 target = 12 mi, quality already pulls ~14.9 mi from the template,
  // so the easy fill is clamped to its 1-mile floor (Math.max(1, …)).
  // Sanity check: easy mileage is small (well under 12), confirming the
  // ramp's start_mileage is being applied to the materializer.
  assert(easyMiles < 8, `easy mileage should reflect ramp start (got ${easyMiles})`);

  const subs = inserts["athlete_plan_subscriptions"] ?? [];
  assertEquals(subs[0].volume_ramp, {
    start_mileage: 12,
    ramp_to_coach_target: true,
    ramp_weeks: 4,
  });
});

Deno.test("subscription_preferences: missing field leaves materialization unchanged", async () => {
  // Two parallel runs: with no preferences and with `subscription_preferences: undefined`
  // (representing a payload that omits the field). The materialized scheduled_workouts
  // must be identical to the existing adaptive happy path.
  const athleteUserId = "athlete-prefs-3";
  const { deps, inserts } = buildDeps(adaptiveTemplate(), athleteUserId);

  const res = await handler(
    buildRequest({
      planTemplateId: "plan-template-adaptive",
      athleteUserId,
      startDate: "2026-05-01",
      // intentionally no subscription_preferences key
    }),
    deps
  );
  assertEquals(res.status, 200);

  const workouts = inserts["scheduled_workouts"] ?? [];
  // Coach template puts quality on dow 2 (Wed = day_of_week 3) and dow 6 (Sun = 7).
  const week1 = workouts.filter((w) => w.week_number === 1);
  const byDow = new Map<number, Record<string, unknown>>(
    week1.map((w) => [w.day_of_week as number, w])
  );
  assertEquals(byDow.get(3)?.workout_type, "tempo", "Wed should keep coach's tempo");
  assertEquals(byDow.get(7)?.workout_type, "long_run", "Sun should keep coach's long run");

  // No prefs persisted to the subscription row beyond the existing fields.
  const subs = inserts["athlete_plan_subscriptions"] ?? [];
  assertEquals(subs.length, 1);
  assertEquals(subs[0].rest_dows, undefined);
  assertEquals(subs[0].preferred_quality_dows, undefined);
  assertEquals(subs[0].long_run_dow, undefined);
  assertEquals(subs[0].volume_ramp, undefined);
  assertEquals(subs[0].shape_prefs, undefined);
});

// ── Phase A (2026-07-03): plan-level skeleton + mileage ramp wiring ─────
// See outputs/adaptive-coach-plan-builder-spec-2026-07-03.md §R1/§R3.

Deno.test("day_structure: skeleton places quality when athlete has no prefs", async () => {
  const athleteUserId = "athlete-skeleton-1";
  // Coach's per-week grid puts quality on Wed (2) + Sun (6), but the
  // plan-level skeleton says Tue (1) = speed, Sat (5) = long run, Mon (0) = rest.
  const template = {
    ...adaptiveTemplate(),
    day_structure: [
      { dayOfWeek: 0, role: "rest" },
      { dayOfWeek: 1, role: "speed" },
      { dayOfWeek: 5, role: "long_run" },
    ],
  };
  const { deps, inserts } = buildDeps(template, athleteUserId);

  const res = await handler(
    buildRequest({
      planTemplateId: "plan-template-adaptive",
      athleteUserId,
      startDate: "2026-05-01",
    }),
    deps
  );
  assertEquals(res.status, 200);

  const week1 = (inserts["scheduled_workouts"] ?? []).filter((w) => w.week_number === 1);
  const byDow = new Map<number, Record<string, unknown>>(
    week1.map((w) => [w.day_of_week as number, w])
  );
  // day_of_week is 1-indexed on the insert: Tue=2, Sat=6, Mon=1.
  assertEquals(byDow.get(2)?.workout_type, "tempo", "Tue should carry the speed session");
  assertEquals(byDow.get(6)?.workout_type, "long_run", "Sat should carry the long run");
  assertEquals(byDow.get(1)?.workout_type, "rest", "Mon should be the skeleton rest day");
});

Deno.test("day_structure: athlete prefs still beat the skeleton", async () => {
  const athleteUserId = "athlete-skeleton-2";
  const template = {
    ...adaptiveTemplate(),
    day_structure: [
      { dayOfWeek: 1, role: "speed" },
      { dayOfWeek: 5, role: "long_run" },
    ],
  };
  const { deps, inserts } = buildDeps(template, athleteUserId);

  const res = await handler(
    buildRequest({
      planTemplateId: "plan-template-adaptive",
      athleteUserId,
      startDate: "2026-05-01",
      subscription_preferences: {
        preferred_quality_dows: [2, 6], // Wed + Sun
        long_run_dow: 6,
      },
    }),
    deps
  );
  assertEquals(res.status, 200);

  const week1 = (inserts["scheduled_workouts"] ?? []).filter((w) => w.week_number === 1);
  const byDow = new Map<number, Record<string, unknown>>(
    week1.map((w) => [w.day_of_week as number, w])
  );
  assertEquals(byDow.get(3)?.workout_type, "tempo", "Wed (athlete pick) should carry tempo");
  assertEquals(byDow.get(7)?.workout_type, "long_run", "Sun (athlete pick) should carry long run");
});

Deno.test("weekly_mileage_targets: fills mileage when week range is absent", async () => {
  const athleteUserId = "athlete-ramp-1";
  // Strip per-week ranges; provide the plan-level ramp instead.
  const weeksNoTargets = minimalWeeks.map((w) => ({
    weekNumber: w.weekNumber,
    workouts: w.workouts,
  }));
  const template = {
    ...adaptiveTemplate(),
    weeks: weeksNoTargets,
    weekly_mileage_targets: [
      { weekNumber: 1, targetMilesMin: 30, targetMilesMax: 34, phase: "base" },
      { weekNumber: 2, targetMilesMin: 32, targetMilesMax: 36, phase: "base" },
    ],
  };
  const { deps, inserts } = buildDeps(template, athleteUserId);

  const res = await handler(
    buildRequest({
      planTemplateId: "plan-template-adaptive",
      athleteUserId,
      startDate: "2026-05-01",
    }),
    deps
  );
  assertEquals(res.status, 200);

  const week1 = (inserts["scheduled_workouts"] ?? []).filter((w) => w.week_number === 1);
  const totalMiles = week1.reduce((sum, w) => {
    const data = w.workout_data as Record<string, unknown> | null;
    const km = (data?.total_distance_km as number) ?? 0;
    return sum + km / 1.60934;
  }, 0);
  // Target avg = 32 mi; quality contributes ~14.9, easy fill covers the
  // rest. Without the ramp fallback the easy budget would be 0 and total
  // would sit near 15. Assert it lands near the target.
  assert(totalMiles > 26 && totalMiles < 38,
    `week-1 total should track the 30–34 ramp target (got ${totalMiles.toFixed(1)})`);
});

// ── Phase 3: AM/PM doubles materialize as two scheduled_workouts ────────

Deno.test("fixed plan: a doubled day materializes AM (session 1) + PM (session 2)", async () => {
  const athleteUserId = "athlete-double-fixed";
  const template = {
    id: "plan-template-fixed",
    name: "Fixed With Double",
    plan_type: "fixed",
    target_distance: "marathon",
    duration_weeks: 1,
    coach_id: null,
    weeks: [
      {
        weekNumber: 1,
        targetMilesMin: 20,
        targetMilesMax: 24,
        workouts: [
          // Tue (dow 2): AM tempo + PM easy shakeout — a coach-authored double.
          { dayOfWeek: 2, workoutType: "tempo", workoutData: { total_distance_km: 8 } },
          { dayOfWeek: 2, session: "pm", workoutType: "easy", workoutData: { total_distance_km: 5 } },
          { dayOfWeek: 6, workoutType: "long_run", workoutData: { total_distance_km: 16 } },
        ],
      },
    ],
  };
  const { deps, inserts } = buildDeps(template, athleteUserId);

  const res = await handler(
    buildRequest({ planTemplateId: "plan-template-fixed", athleteUserId, startDate: "2026-05-01" }),
    deps,
  );
  assertEquals(res.status, 200);

  const workouts = inserts["scheduled_workouts"] ?? [];
  // Tue is dow 2 (0-indexed Mon-first) → day_of_week 3 on the insert.
  const tue = workouts.filter((w) => w.day_of_week === 3);
  assertEquals(tue.length, 2, "the doubled day should produce two rows");
  const am = tue.find((w) => w.session === 1);
  const pm = tue.find((w) => w.session === 2);
  assert(am, "AM session (1) must exist");
  assert(pm, "PM session (2) must exist");
  assertEquals(am!.workout_type, "tempo");
  assertEquals(pm!.workout_type, "easy");
  // No other day is doubled.
  const doubledDays = new Set(
    workouts
      .map((w) => w.day_of_week as number)
      .filter((d, _i, arr) => arr.filter((x) => x === d).length > 1),
  );
  assertEquals([...doubledDays], [3], "only Tue should be doubled");
});

Deno.test("adaptive plan: a coach-placed PM run appends a session-2 double", async () => {
  const athleteUserId = "athlete-double-adaptive";
  const template = {
    id: "plan-template-adaptive",
    name: "Adaptive With Double",
    plan_type: "adaptive",
    target_distance: "marathon",
    duration_weeks: 1,
    coach_id: null,
    weeks: [
      {
        weekNumber: 1,
        targetMilesMin: 30,
        targetMilesMax: 34,
        workouts: [
          { dayOfWeek: 2, workoutType: "tempo", workoutData: { total_distance_km: 10 } },
          // PM easy double on the same quality day.
          { dayOfWeek: 2, session: "pm", workoutType: "easy", workoutData: { total_distance_km: 5 } },
          { dayOfWeek: 6, workoutType: "long_run", workoutData: { total_distance_km: 18 } },
        ],
      },
    ],
  };
  const { deps, inserts } = buildDeps(template, athleteUserId);

  const res = await handler(
    buildRequest({ planTemplateId: "plan-template-adaptive", athleteUserId, startDate: "2026-05-01" }),
    deps,
  );
  assertEquals(res.status, 200);

  const workouts = inserts["scheduled_workouts"] ?? [];
  // The adaptive AM pipeline emits one row per day (session 1); the PM run
  // is appended as session 2 on its day (Tue, day_of_week 3).
  const pm = workouts.find((w) => w.session === 2);
  assert(pm, "a session-2 PM row should be materialized");
  assertEquals(pm!.day_of_week, 3, "PM double lands on Tue");
  assertEquals(pm!.workout_type, "easy");
  // The AM pipeline still emits exactly one session-1 row per calendar day.
  const amDays = workouts.filter((w) => w.session === 1).map((w) => w.day_of_week);
  assertEquals(new Set(amDays).size, amDays.length, "one AM row per day");
});
