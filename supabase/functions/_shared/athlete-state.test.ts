/**
 * Regression tests for athlete-state.
 *
 * Run: deno test --allow-env _shared/athlete-state.test.ts
 *
 * ── HOTFIX-H.1 ────────────────────────────────────────────
 * user_goals had legacy rows with user_id = NULL (creation-flow bug).
 * The active_goals query had no user_id filter, so those orphans
 * silently leaked into every athlete's state. Fixed by scoping the
 * query (.eq("user_id", userId).not("user_id", "is", null)) and adding
 * a redundant client-side filter as defense-in-depth.
 *
 * The test below pins both protections by exercising getOrBuildAthleteState
 * against an in-memory fake supabase client.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { formatPace, getOrBuildAthleteState, stateToPromptContext } from "./athlete-state.ts";

// ── formatPace rounding-boundary regression ──────────────
// Pace values are seconds-per-mile and routinely fractional (distance ÷
// time, percentage-derived zone bounds, averaged efficiency baselines).
// The old impl did Math.round(sec % 60), which rounds the seconds part up
// to 60 at the boundary, emitting impossible strings like "7:60/mi" that
// then flow into the AI prompt. These pin M:SS correctness.
Deno.test("formatPace: fractional input that rounds the seconds part to 60 carries to the minute", () => {
  assertEquals(formatPace(479.6), "8:00"); // not "7:60"
  assertEquals(formatPace(359.7), "6:00"); // not "5:60"
  assertEquals(formatPace(299.6), "5:00"); // not "4:60"
});

Deno.test("formatPace: ordinary fractional and integer inputs round correctly", () => {
  assertEquals(formatPace(449.5), "7:30");
  assertEquals(formatPace(420), "7:00");
  assertEquals(formatPace(425.2), "7:05"); // seconds < 10 stay zero-padded
});

// ── Constants ───────────────────────────────────────────

const REAL_USER = "11111111-1111-1111-1111-111111111111";
const OTHER_USER = "22222222-2222-2222-2222-222222222222";
const ORPHAN_GOAL = "ORPHAN_GOAL_should_not_leak";
const LEGIT_GOAL = "sub-3 marathon";
const OTHER_USER_GOAL = "other_athletes_goal";

// ── Fake supabase client ────────────────────────────────
//
// Models the postgrest chainable API surface used by athlete-state.ts:
//   .select().eq().not().in().gt().gte().lt().lte().order().limit()
//   .maybeSingle() / .single() / await chain → { data, error }
//   .upsert() / .update().eq() / .insert() / .delete().eq()
//
// The chain itself is thenable so `await chain` resolves to all matching
// rows, while .maybeSingle() resolves to the first.

type Row = Record<string, unknown>;
type DB = Record<string, Row[]>;

type Filter =
  | { type: "eq"; col: string; val: unknown }
  | { type: "in"; col: string; vals: unknown[] }
  | { type: "gt"; col: string; val: unknown }
  | { type: "gte"; col: string; val: unknown }
  | { type: "lt"; col: string; val: unknown }
  | { type: "lte"; col: string; val: unknown }
  | { type: "notIsNull"; col: string };

function buildFakeClient(db: DB): SupabaseClient {
  function from(table: string) {
    if (!db[table]) db[table] = [];
    const filters: Filter[] = [];
    let orderCfg: { col: string; asc: boolean } | null = null;
    let limitN: number | null = null;

    function evalRows(): Row[] {
      let rows = [...(db[table] ?? [])];
      for (const f of filters) {
        switch (f.type) {
          case "eq":
            rows = rows.filter((r) => r[f.col] === f.val);
            break;
          case "in":
            rows = rows.filter((r) => f.vals.includes(r[f.col]));
            break;
          case "gt":
            rows = rows.filter((r) => compare(r[f.col], f.val) > 0);
            break;
          case "gte":
            rows = rows.filter((r) => compare(r[f.col], f.val) >= 0);
            break;
          case "lt":
            rows = rows.filter((r) => compare(r[f.col], f.val) < 0);
            break;
          case "lte":
            rows = rows.filter((r) => compare(r[f.col], f.val) <= 0);
            break;
          case "notIsNull":
            rows = rows.filter((r) => r[f.col] !== null && r[f.col] !== undefined);
            break;
        }
      }
      if (orderCfg) {
        const { col, asc } = orderCfg;
        rows.sort((a, b) => compare(a[col], b[col]) * (asc ? 1 : -1));
      }
      if (limitN !== null) rows = rows.slice(0, limitN);
      return rows;
    }

    // deno-lint-ignore no-explicit-any
    const chain: any = {};
    chain.select = (_cols?: string) => chain;
    chain.eq = (col: string, val: unknown) => {
      filters.push({ type: "eq", col, val });
      return chain;
    };
    chain.in = (col: string, vals: unknown[]) => {
      filters.push({ type: "in", col, vals });
      return chain;
    };
    chain.gt = (col: string, val: unknown) => {
      filters.push({ type: "gt", col, val });
      return chain;
    };
    chain.gte = (col: string, val: unknown) => {
      filters.push({ type: "gte", col, val });
      return chain;
    };
    chain.lt = (col: string, val: unknown) => {
      filters.push({ type: "lt", col, val });
      return chain;
    };
    chain.lte = (col: string, val: unknown) => {
      filters.push({ type: "lte", col, val });
      return chain;
    };
    chain.not = (col: string, op: string, val: unknown) => {
      if (op === "is" && val === null) filters.push({ type: "notIsNull", col });
      return chain;
    };
    chain.order = (col: string, opts?: { ascending?: boolean }) => {
      orderCfg = { col, asc: opts?.ascending ?? true };
      return chain;
    };
    chain.limit = (n: number) => {
      limitN = n;
      return chain;
    };
    chain.maybeSingle = () =>
      Promise.resolve({ data: evalRows()[0] ?? null, error: null });
    chain.single = chain.maybeSingle;
    // deno-lint-ignore no-explicit-any
    chain.then = (onFulfilled: any, onRejected?: any) =>
      Promise.resolve({ data: evalRows(), error: null }).then(
        onFulfilled,
        onRejected,
      );
    chain.upsert = (rows: Row | Row[], opts?: { onConflict?: string }) => {
      const arr = Array.isArray(rows) ? rows : [rows];
      const conflictKey = opts?.onConflict;
      if (!db[table]) db[table] = [];
      for (const row of arr) {
        if (conflictKey && conflictKey in row) {
          const idx = db[table].findIndex(
            (r) => r[conflictKey] === row[conflictKey],
          );
          if (idx >= 0) {
            db[table][idx] = { ...db[table][idx], ...row };
            continue;
          }
        }
        db[table].push({ ...row });
      }
      return Promise.resolve({ error: null });
    };
    chain.update = (patch: Row) => ({
      eq: (col: string, val: unknown) => {
        for (const r of db[table] ?? []) {
          if (r[col] === val) Object.assign(r, patch);
        }
        return Promise.resolve({ error: null });
      },
    });
    chain.insert = (rows: Row | Row[]) => {
      const arr = Array.isArray(rows) ? rows : [rows];
      if (!db[table]) db[table] = [];
      db[table].push(...arr);
      return Promise.resolve({ error: null });
    };
    chain.delete = () => ({
      eq: () => Promise.resolve({ error: null }),
    });
    return chain;
  }

  // claim_athlete_state_rebuild RPC: returning null (not strictly === false)
  // lets rebuildAthleteState skip the in-flight polling branch and proceed.
  const rpc = (_name: string, _args?: unknown) =>
    Promise.resolve({ data: null, error: null });

  return { from, rpc } as unknown as SupabaseClient;
}

function compare(a: unknown, b: unknown): number {
  if (a === b) return 0;
  if (a === null || a === undefined) return 1;
  if (b === null || b === undefined) return -1;
  // deno-lint-ignore no-explicit-any
  return (a as any) < (b as any) ? -1 : 1;
}

// ── Tests ───────────────────────────────────────────────

Deno.test(
  "HOTFIX-H.1: orphan user_goals row (user_id=null) does not leak into another athlete's state",
  async () => {
    // Future date so the post-fetch recency filter (target_date >= now-30d)
    // does not exclude either goal for the wrong reason.
    const futureDate = new Date(Date.now() + 60 * 86400000)
      .toISOString()
      .slice(0, 10);

    const db: DB = {
      user_goals: [
        // The orphan — legacy creation-flow bug. Pre-fix, this row matched
        // a query with no user_id filter and silently leaked into every
        // athlete's active_goals.
        {
          user_id: null,
          goal_title: ORPHAN_GOAL,
          target_date: futureDate,
          status: "active",
        },
        // Legitimate goal for the requesting user.
        {
          user_id: REAL_USER,
          goal_title: LEGIT_GOAL,
          target_date: futureDate,
          status: "active",
        },
        // A different athlete's goal — must also be excluded.
        {
          user_id: OTHER_USER,
          goal_title: OTHER_USER_GOAL,
          target_date: futureDate,
          status: "active",
        },
        // Inactive goal for the requesting user — must be excluded by
        // the .eq("status", "active") filter, not by H.1 logic.
        {
          user_id: REAL_USER,
          goal_title: "completed_goal",
          target_date: futureDate,
          status: "completed",
        },
      ],
      // All other source tables intentionally empty — rebuildAthleteState
      // tolerates this and produces a default state with no recent
      // training, no snapshot, no plan, etc.
    };

    const client = buildFakeClient(db);
    const state = await getOrBuildAthleteState(client, REAL_USER);

    const titles = state.active_goals.map((g) => g.title);
    assertEquals(
      titles.length,
      1,
      `expected exactly one active goal for the requesting user, got: ${
        JSON.stringify(titles)
      }`,
    );
    assertEquals(titles[0], LEGIT_GOAL);
    assert(
      !titles.includes(ORPHAN_GOAL),
      "TENANT LEAK: orphan user_id=null goal appeared in active_goals",
    );
    assert(
      !titles.includes(OTHER_USER_GOAL),
      "TENANT LEAK: another athlete's goal appeared in active_goals",
    );
  },
);

Deno.test(
  "HOTFIX-H.1: when ALL user_goals rows are orphans, active_goals is empty",
  async () => {
    const futureDate = new Date(Date.now() + 60 * 86400000)
      .toISOString()
      .slice(0, 10);

    const db: DB = {
      user_goals: [
        {
          user_id: null,
          goal_title: ORPHAN_GOAL,
          target_date: futureDate,
          status: "active",
        },
        {
          user_id: null,
          goal_title: "another orphan",
          target_date: futureDate,
          status: "active",
        },
      ],
    };

    const client = buildFakeClient(db);
    const state = await getOrBuildAthleteState(client, REAL_USER);

    assertEquals(
      state.active_goals.length,
      0,
      "no orphan should leak even when there are no legitimate goals",
    );
  },
);

// ── Pace consolidation Step 5 ────────────────────────────
//
// Pins the migration: rebuildAthleteState's `state.pace_zones` is now
// projected from the central PaceEngine, not from the deleted local
// multipliers. For a 2:20 marathoner with no observed runs, easy must
// equal 378 (engine's mp × 1.18 floor) and mp must equal 320.

Deno.test(
  "Step 5: state.pace_zones is sourced from PaceEngine (chart-aligned values, not legacy multipliers)",
  async () => {
    const db: DB = {
      fitness_snapshots: [
        {
          user_id: REAL_USER,
          predicted_marathon_seconds: 2 * 3600 + 20 * 60, // 2:20:00
          predicted_half_seconds: 66 * 60 + 51,
          predicted_10k_seconds: null,
          predicted_5k_seconds: 14 * 60 + 30,
          predicted_mile_seconds: null,
          created_at: new Date().toISOString(),
        },
      ],
      // Empty everywhere else — engine should produce race_derived zones
      // from the snapshot alone.
    };

    const client = buildFakeClient(db);
    const state = await getOrBuildAthleteState(client, REAL_USER);

    // Easy fast bound (80% MP speed → pace ratio 1/0.80 = 1.25): engine
    // produces mp × 1.25 = 320 × 1.25 = 400. See TRAINING_PACE_MULTIPLIERS
    // (the canonical calibration) + outputs/pace-chart-unified-spec-2026-06-04.md.
    // Legacy multipliers (mp × 1.28 = 410, mp × 1.18 = 378) must NOT appear.
    assertEquals(
      state.pace_zones.easy,
      400,
      "easy should be the engine's mp × 1.25 (80% MP speed = 400), not legacy mp × 1.28 (410) or mp × 1.18 (378)",
    );

    // MP and other race anchors flow through verbatim.
    assertEquals(state.pace_zones.mp, 320);
    assertEquals(state.pace_zones.fiveK, 280); // 870 / 3.1069 ≈ 280
    assertEquals(state.pace_zones.hm, 306);    // 4011 / 13.1094 ≈ 306

    // Source label maps from engine's "race_derived" → legacy "prediction".
    assertEquals(
      (state as unknown as { pace_zones_source?: string }).pace_zones_source ?? "prediction",
      "prediction",
    );
  },
);

Deno.test(
  "Step 7+: AI prompt renders Easy/Moderate/Steady as RANGES, not midpoints",
  async () => {
    const db: DB = {
      fitness_snapshots: [
        {
          user_id: REAL_USER,
          predicted_marathon_seconds: 2 * 3600 + 20 * 60,
          predicted_half_seconds: 66 * 60 + 51,
          predicted_10k_seconds: null,
          predicted_5k_seconds: 14 * 60 + 30,
          predicted_mile_seconds: null,
          created_at: new Date().toISOString(),
        },
      ],
    };

    const client = buildFakeClient(db);
    const state = await getOrBuildAthleteState(client, REAL_USER);
    const prompt = stateToPromptContext(state);

    // Easy must render as a range with effort %, not a single number.
    // Canonical bands for MP=320 (5:20): Easy 400–457 (80–70% MP speed),
    // Moderate 356–400 (90–80%), Steady 320–356 (100–90%).
    assert(
      prompt.includes("Easy: 6:40–7:37/mi (70-80% MP)"),
      `prompt missing Easy range. Got:\n${prompt}`,
    );
    assert(
      prompt.includes("Moderate: 5:56–6:40/mi (80-90% MP)"),
      `prompt missing Moderate range. Got:\n${prompt}`,
    );
    assert(
      prompt.includes("Steady: 5:20–5:56/mi (90-100% MP)"),
      `prompt missing Steady range. Got:\n${prompt}`,
    );
    // HMP rendered as a tight range around half-marathon pace (replaces fuzzy "Threshold").
    assert(
      prompt.includes("HMP: 5:01–5:11/mi (Half Marathon Pace)"),
      `prompt missing HMP range. Got:\n${prompt}`,
    );
    // Midpoint single-number and "Threshold" labels must NOT appear in the new format.
    assert(
      !prompt.includes("Easy: 6:40/mi"),
      "prompt regressed to single-number Easy (6:40)",
    );
    assert(
      !prompt.includes("Threshold:"),
      "prompt still has 'Threshold:' label — should be 'HMP:' now",
    );
    // Race anchors stay single.
    assert(prompt.includes("Marathon Pace: 5:20/mi"), "Marathon Pace anchor missing");
  },
);

// ── R6: rebuild orchestration — formerly-null fields ─────
// The refactor design flagged four fields that shipped as null/"maintaining"
// stubs (monotony_7d, strain_7d, week_compliance_pct, fitness_trend). They now
// have real implementations on the rebuild path, but that path had zero test
// coverage. These pin the population logic against the fake client so a future
// regression to the stub behavior fails loudly.

Deno.test(
  "R6 fitness_trend: two snapshots, faster latest 10K → 'improving'",
  async () => {
    const now = Date.now();
    const db: DB = {
      fitness_snapshots: [
        // Newest (created_at desc → index 0): faster (lower) predicted 10K.
        { user_id: REAL_USER, predicted_10k_seconds: 2500, created_at: new Date(now - 2 * 86400000).toISOString() },
        // Prior: slower. deltaPct = (2600-2500)/2600 ≈ +3.8% → improving.
        { user_id: REAL_USER, predicted_10k_seconds: 2600, created_at: new Date(now - 30 * 86400000).toISOString() },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
    assertEquals(state.fitness_trend, "improving");
  },
);

Deno.test(
  "R6 fitness_trend: slower latest 10K → 'declining'; single snapshot → 'maintaining'",
  async () => {
    const now = Date.now();
    // Declining: newest slower than prior.
    const declining: DB = {
      fitness_snapshots: [
        { user_id: REAL_USER, predicted_10k_seconds: 2600, created_at: new Date(now - 2 * 86400000).toISOString() },
        { user_id: REAL_USER, predicted_10k_seconds: 2500, created_at: new Date(now - 30 * 86400000).toISOString() },
      ],
    };
    assertEquals(
      (await getOrBuildAthleteState(buildFakeClient(declining), REAL_USER)).fitness_trend,
      "declining",
    );

    // Single snapshot: no prior to compare → "maintaining" (not null, not a guess).
    const single: DB = {
      fitness_snapshots: [
        { user_id: REAL_USER, predicted_10k_seconds: 2550, created_at: new Date(now - 2 * 86400000).toISOString() },
      ],
    };
    assertEquals(
      (await getOrBuildAthleteState(buildFakeClient(single), REAL_USER)).fitness_trend,
      "maintaining",
    );
  },
);

Deno.test(
  "R6 week_compliance_pct: 3 of 4 planned non-rest days trained → 75",
  async () => {
    const now = new Date();
    const dayAgo = (n: number) =>
      new Date(now.getTime() - n * 86400000).toISOString().slice(0, 10);
    const db: DB = {
      training_plans: [
        {
          id: "plan-1",
          user_id: REAL_USER,
          name: "Marathon block",
          target_race_distance: "marathon",
          target_time_seconds: 11400,
          status: "active",
          end_date: dayAgo(-60),
        },
      ],
      scheduled_workouts: [
        // 4 planned non-rest days in the trailing week + 1 rest day (excluded).
        { plan_id: "plan-1", date: dayAgo(1), workout_type: "easy", status: "scheduled" },
        { plan_id: "plan-1", date: dayAgo(2), workout_type: "tempo", status: "scheduled" },
        { plan_id: "plan-1", date: dayAgo(3), workout_type: "long", status: "scheduled" },
        { plan_id: "plan-1", date: dayAgo(4), workout_type: "intervals", status: "scheduled" },
        { plan_id: "plan-1", date: dayAgo(5), workout_type: "rest", status: "scheduled" },
      ],
      training_logs: [
        // Trained on 3 of the 4 non-rest planned days (missed dayAgo(4)).
        { user_id: REAL_USER, workout_date: dayAgo(1), distance_miles: 5 },
        { user_id: REAL_USER, workout_date: dayAgo(2), distance_miles: 6 },
        { user_id: REAL_USER, workout_date: dayAgo(3), distance_miles: 14 },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
    assertEquals(state.week_compliance_pct, 75);
  },
);

Deno.test(
  "R6 monotony_7d / strain_7d: passed through from latest workout_features row",
  async () => {
    const now = Date.now();
    const db: DB = {
      workout_features: [
        {
          user_id: REAL_USER,
          workout_date: new Date(now - 1 * 86400000).toISOString(),
          monotony_7d: 1.85,
          strain_7d: 4200,
          intensity_score: 70,
          total_duration_seconds: 3000,
        },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
    assertEquals(state.monotony_7d, 1.85);
    assertEquals(state.strain_7d, 4200);
  },
);

// ── Life context (audit fix #1, 2026-07-02) ─────────────
// Memo-sourced extracted_data must reach the state: the life_context slice
// populates, and the two qualitative pattern rules (life_load,
// effort_mismatch) fire on the joined signal. Pins the full path:
// training_logs.extracted_data → buildLifeContext → patterns → prompt.

Deno.test(
  "life_context: memo extracted_data reaches the state and fires life_load + effort_mismatch",
  async () => {
    const now = Date.now();
    const iso = (n: number) => new Date(now - n * 86400000).toISOString();
    const db: DB = {
      training_logs: [
        {
          id: "lc1", user_id: REAL_USER, workout_date: iso(1), source: "voice_log",
          workout_type: "easy", workout_distance_miles: 5, workout_duration_minutes: 45,
          mood: "tired",
          extracted_data: {
            sleep_quality: "poor", work_stress: "high",
            felt_vs_looked: "harder than it looks", fatigue: "wiped",
          },
        },
        {
          id: "lc2", user_id: REAL_USER, workout_date: iso(3), source: "voice_log",
          workout_type: "easy", workout_distance_miles: 6, workout_duration_minutes: 54,
          mood: "struggling",
          extracted_data: {
            sleep_quality: "poor",
            felt_vs_looked: "harder than it looks",
          },
        },
        {
          id: "lc3", user_id: REAL_USER, workout_date: iso(5), source: "voice_log",
          workout_type: "easy", workout_distance_miles: 4, workout_duration_minutes: 36,
          mood: "positive",
          extracted_data: { workout_type: "easy" },
        },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);

    // Slice populated from memo extracted_data.
    assert(state.life_context !== null, "life_context must populate from memos");
    assertEquals(state.life_context!.sleep.poor_mentions_7d, 2);
    assertEquals(state.life_context!.stress.work_high_7d, 1);
    assertEquals(state.life_context!.felt_vs_looked.length, 2);
    assertEquals(state.life_context!.fatigue[0].label, "wiped");

    // Pattern rules fire on the joined signal (3 life-load flags + 2 tired runs).
    const kinds = state.patterns.map((p) => p.kind);
    assert(kinds.includes("life_load"), `life_load must fire, got: ${kinds.join(",")}`);
    assert(kinds.includes("effort_mismatch"), `effort_mismatch must fire, got: ${kinds.join(",")}`);

    // Prompt renders the section; sleep data present so NO RECOVERY DATA gap absent.
    const prompt = stateToPromptContext(state);
    assert(prompt.includes("Life context"), "prompt must include life context section");
    assert(!state.data_gaps.some((g) => g.gap === "NO RECOVERY DATA"));
    assert(!state.data_gaps.some((g) => g.gap === "NO LIFE SIGNAL"));
  },
);

Deno.test(
  "life_context: quant-only athlete gets null slice, no patterns, and honest gaps",
  async () => {
    const now = Date.now();
    const iso = (n: number) => new Date(now - n * 86400000).toISOString();
    const db: DB = {
      training_logs: [
        {
          id: "q1", user_id: REAL_USER, workout_date: iso(1), source: "strava",
          workout_type: "easy", workout_distance_miles: 5, workout_duration_minutes: 45,
        },
        {
          id: "q2", user_id: REAL_USER, workout_date: iso(3), source: "strava",
          workout_type: "easy", workout_distance_miles: 8, workout_duration_minutes: 70,
        },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
    assertEquals(state.life_context, null);
    const kinds = state.patterns.map((p) => p.kind);
    assert(!kinds.includes("life_load"));
    assert(!kinds.includes("effort_mismatch"));
    assert(state.data_gaps.some((g) => g.gap === "NO LIFE SIGNAL"), "must admit missing life signal");
    assert(state.data_gaps.some((g) => g.gap === "NO RECOVERY DATA"), "must admit missing recovery data");
    assert(!stateToPromptContext(state).includes("Life context"));
  },
);

// ── Easy-session counting for auto-synced runs (fix 2026-07-02) ─────────
// Strava/HealthKit rows routinely carry workout_type = null but an
// Observer-parsed structure. The hard counter already read parsed_structure;
// the easy counter read only workout_type — so a fully-parsed week reported
// "3 hard, 0 easy" (falsely polarized). Mirrors the real prod week that
// exposed the bug: 4 parsed-easy + 1 progression + 2 intervals.
Deno.test(
  "easy_sessions_7d counts Observer-parsed easy runs when workout_type is null",
  async () => {
    const now = Date.now();
    const iso = (n: number) => new Date(now - n * 86400000).toISOString();
    const strava = (id: string, day: number, mi: number, parsedType: string) => ({
      id, user_id: REAL_USER, workout_date: iso(day), source: "strava",
      workout_type: null, workout_distance_miles: mi,
      workout_duration_minutes: mi * 8.5,
      parsed_structure: { type: parsedType },
    });
    const db: DB = {
      training_logs: [
        strava("e1", 0, 7.0, "easy"),
        strava("i1", 1, 4.0, "interval"),
        strava("e2", 1, 8.1, "easy"),
        strava("i2", 2, 7.0, "interval"),
        strava("e3", 2, 4.0, "easy"),
        strava("p1", 3, 7.1, "progression"),
        strava("e4", 5, 17.8, "easy"),
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
    assertEquals(state.hard_sessions_7d, 3, "intervals ×2 + progression = 3 hard");
    assertEquals(state.easy_sessions_7d, 4, "parsed-easy runs must count as easy");
  },
);

// ── Niggle recurrence: laterality (audit fix #2, 2026-07-02) ─────────
//
// The failure mode the classifier rewrite exists to kill: "left knee" and
// "right knee" merging into one false three-count "pattern." Recurrence
// must group by body_area + side, so two knees on the same athlete are two
// distinct patterns.

const isoDaysAgo = (n: number) => new Date(Date.now() - n * 86400000).toISOString().slice(0, 10);

Deno.test(
  "niggle_recurrence groups by body_area + side (left knee ×2 + right knee ×1 → two entries)",
  async () => {
    const db: DB = {
      body_mentions: [
        { user_id: REAL_USER, body_area: "knee", side: "left", severity_hint: "tight", mentioned_at: isoDaysAgo(40) },
        { user_id: REAL_USER, body_area: "knee", side: "left", severity_hint: "sore", mentioned_at: isoDaysAgo(12) },
        { user_id: REAL_USER, body_area: "knee", side: "right", severity_hint: "pain", mentioned_at: isoDaysAgo(6) },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);

    const knees = state.niggle_recurrence.filter((n) => n.body_area === "knee");
    assertEquals(knees.length, 2, "left and right knee must be two distinct patterns, not one merged count");

    const left = knees.find((n) => n.side === "left");
    const right = knees.find((n) => n.side === "right");
    assert(left && right, "both a left and a right knee entry must exist");
    assertEquals(left!.occurrences, 2);
    assertEquals(right!.occurrences, 1);
    assertEquals(left!.worst_severity, "sore"); // sore beats tight
    assertEquals(right!.worst_severity, "pain");

    // No merged three-count entry anywhere.
    assert(
      !state.niggle_recurrence.some((n) => n.body_area === "knee" && n.occurrences === 3),
      "the two knees must not collapse into a single 3× count",
    );

    // The prompt renders the side, not a bare "knee: 2×".
    const prompt = stateToPromptContext(state);
    assert(prompt.includes("left knee:"), `prompt should render sided niggle. Got:\n${prompt}`);
  },
);

Deno.test(
  "regex niggle scan skips voice-sourced rows (memo pipeline owns those)",
  async () => {
    // A voice_log row whose notes clearly name a niggle: the regex scan must
    // NOT flag it — the memo classifier is the writer for voice rows.
    const db: DB = {
      training_logs: [
        {
          id: "v1",
          user_id: REAL_USER,
          workout_date: new Date(Date.now() - 3 * 86400000).toISOString(),
          source: "voice_log",
          cleaned_notes: "left knee was really sore on today's run",
          workout_type: "easy",
          workout_distance_miles: 5,
        },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
    assertEquals(
      state.possible_injuries.filter((p) => p.body_area === "knee").length,
      0,
      "voice-sourced row must be skipped by the regex backfill scan",
    );
  },
);

Deno.test(
  "regex niggle scan still runs on typed/imported rows, with side populated",
  async () => {
    const db: DB = {
      training_logs: [
        {
          id: "s1",
          user_id: REAL_USER,
          workout_date: new Date(Date.now() - 3 * 86400000).toISOString(),
          source: "strava",
          cleaned_notes: "left knee was really sore on today's run",
          workout_type: "easy",
          workout_distance_miles: 5,
        },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
    const knee = state.possible_injuries.find((p) => p.body_area === "knee");
    assert(knee, "typed/imported row should still be scanned by the regex backfill");
    assertEquals(knee!.severity_hint, "sore");
    // Side flows into the durable recurrence view.
    const rec = state.niggle_recurrence.find((n) => n.body_area === "knee");
    assert(rec, "scanned mention should appear in niggle_recurrence");
    assertEquals(rec!.side, "left");
  },
);

// ── Niggle resolution: the "it's better now" watermark ───────────────

Deno.test(
  "a resolution after the last mention makes the niggle dormant (dropped from surfaced recurrence)",
  async () => {
    const db: DB = {
      body_mentions: [
        { user_id: REAL_USER, body_area: "knee", side: "left", severity_hint: "sore", mentioned_at: isoDaysAgo(40) },
        { user_id: REAL_USER, body_area: "knee", side: "left", severity_hint: "tight", mentioned_at: isoDaysAgo(20) },
      ],
      niggle_resolutions: [
        { user_id: REAL_USER, body_area: "knee", side: "left", resolved_at: isoDaysAgo(10) },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);

    const knee = state.niggle_recurrence.find((n) => n.body_area === "knee" && n.side === "left");
    assert(knee, "resolved knee should still exist in history");
    assertEquals(knee!.status, "resolved");
    assertEquals(knee!.occurrences, 0, "no active mentions after the all-clear");

    // It must NOT surface in the coaching prompt's recurrence section.
    const prompt = stateToPromptContext(state);
    assert(!prompt.includes("left knee:"), `resolved niggle must not surface as an active pattern. Got:\n${prompt}`);
  },
);

Deno.test(
  "a new mention AFTER a resolution reactivates the niggle and flags it flared-again",
  async () => {
    const db: DB = {
      body_mentions: [
        // pre-resolution history
        { user_id: REAL_USER, body_area: "knee", side: "left", severity_hint: "sore", mentioned_at: isoDaysAgo(40) },
        { user_id: REAL_USER, body_area: "knee", side: "left", severity_hint: "tight", mentioned_at: isoDaysAgo(30) },
        // post-resolution — these reactivate it
        { user_id: REAL_USER, body_area: "knee", side: "left", severity_hint: "pain", mentioned_at: isoDaysAgo(5) },
        { user_id: REAL_USER, body_area: "knee", side: "left", severity_hint: "sore", mentioned_at: isoDaysAgo(3) },
      ],
      niggle_resolutions: [
        { user_id: REAL_USER, body_area: "knee", side: "left", resolved_at: isoDaysAgo(20) },
      ],
    };
    const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);

    const knee = state.niggle_recurrence.find((n) => n.body_area === "knee" && n.side === "left");
    assert(knee, "reactivated knee should exist");
    assertEquals(knee!.status, "active");
    assertEquals(knee!.occurrences, 2, "only the two mentions AFTER the resolution count");
    assertEquals(knee!.worst_severity, "pain");
    assertEquals(knee!.resolved_at, isoDaysAgo(20), "carries the prior all-clear date as the flared-again signal");

    // The prompt surfaces it AND notes it came back after the all-clear.
    const prompt = stateToPromptContext(state);
    assert(prompt.includes("left knee: 2×"), `reactivated niggle should surface. Got:\n${prompt}`);
    assert(prompt.includes("flared again"), "prompt should note the niggle flared again after clearing");
  },
);

// ── Goal parsing: distance resolution + H:MM vs M:SS ─────
//
// Three bugs shipped together in the active_goals mapper, all found on
// 2026-08-20 against a real goal ("Run sub 2:20 at CIM"):
//
//   1. /\bmarathon\b/ was tested BEFORE the half pattern, and it matches
//      inside "half marathon" — so every half-marathon goal was filed as a
//      marathon and its pace gap computed over 26.2 miles.
//   2. A two-part time with no seconds group was always read as M:SS, so
//      "sub 2:20" on a marathon parsed as 140 seconds.
//   3. Named races never resolved to a distance, so a title that doesn't
//      literally say "marathon" had distMi = 0 and no gap at all.

const GOAL_FUTURE = new Date(Date.now() + 90 * 86400000).toISOString().slice(0, 10);

async function goalFor(title: string, snapshot?: Row) {
  const db: DB = {
    user_goals: [
      { user_id: REAL_USER, goal_title: title, target_date: GOAL_FUTURE, status: "active" },
    ],
    ...(snapshot ? { fitness_snapshots: [{ user_id: REAL_USER, ...snapshot }] } : {}),
  };
  const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
  return state.active_goals[0];
}

Deno.test("goal parse: 'sub 2:20 at CIM' is 2h20m for the marathon, not 140 seconds", async () => {
  const g = await goalFor("Run sub 2:20 at CIM");
  assertEquals(g.target_distance_key, "marathon", "CIM must resolve to the marathon distance");
  assertEquals(g.target_time_seconds, 8400, "2:20 on a marathon is hours:minutes");
  // 8400s / 26.2188mi = 320.4 s/mi — inside the 3:00-15:00 sanity window, so
  // the target pace now renders instead of being dropped as implausible.
  assertEquals(g.target_pace_per_mile, "5:20");
});

Deno.test("goal parse: half marathon is not swallowed by the marathon pattern", async () => {
  const g = await goalFor("break 1:30 half marathon");
  assertEquals(g.target_distance_key, "half", "'half marathon' must match half, not marathon");
  assertEquals(g.target_time_seconds, 5400, "1:30 on a half is hours:minutes");
  assertEquals(g.target_pace_per_mile, "6:52");
});

Deno.test("goal parse: short races keep MINUTES:SECONDS", async () => {
  const fiveK = await goalFor("sub 15:30 5k");
  assertEquals(fiveK.target_distance_key, "5K");
  assertEquals(fiveK.target_time_seconds, 930, "15:30 on a 5K is minutes:seconds");

  const mile = await goalFor("4:50 mile");
  assertEquals(mile.target_distance_key, "mile");
  assertEquals(mile.target_time_seconds, 290);
});

Deno.test("goal parse: an explicit H:MM:SS still wins over the distance heuristic", async () => {
  const g = await goalFor("sub 2:20:30 marathon");
  assertEquals(g.target_time_seconds, 8430);
});

Deno.test("goal parse: a named-race half beats the marathon alias", async () => {
  const g = await goalFor("Boston half in 1:12");
  assertEquals(g.target_distance_key, "half", "'Boston half' is a half, not the Boston Marathon");
});

// ── LT / threshold pace anchor ───────────────────────────
//
// The pace ladder ran Steady → HMP → 10K with no threshold entry, so a
// prescribed threshold session had no pace to quote and the prompt reached
// for HMP under the wrong name. LT is the 1-hour race pace from the shared
// `oneHourPaceSecPerMile`, and per CLAUDE.md race-pace zones are exact
// single targets — so it lands in pace_zones, not pace_zone_ranges.

Deno.test("LT pace is derived and sits between 10K and HM", async () => {
  const db: DB = {
    fitness_snapshots: [{
      user_id: REAL_USER,
      predicted_5k_seconds: 924,
      predicted_10k_seconds: 1920,
      predicted_half_seconds: 4232,
      predicted_marathon_seconds: 8953,
      created_at: new Date().toISOString(),
    }],
  };
  const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
  const z = state.pace_zones;

  assert(z.lt, `expected an lt pace zone, got keys: ${Object.keys(z).join(", ")}`);
  assert(
    z.lt > z.tenK && z.lt < z.hm,
    `LT (${z.lt}) must sit between 10K (${z.tenK}) and HM (${z.hm}) pace`,
  );

  // This athlete's half is ~1:10, so LT (5:21) falls INSIDE the HMP band
  // (5:18-5:28). The ladder must merge them rather than offering the model
  // two near-identical threshold targets.
  const prompt = stateToPromptContext(state);
  assert(
    prompt.includes("HMP / LT (same effort):"),
    `overlapping HMP and LT must collapse to one line. Got:\n${prompt}`,
  );
  assert(
    !prompt.includes("  LT / Threshold:"),
    "a separate LT line must NOT also render when it is inside the HMP band",
  );
});

Deno.test("LT renders as its own line when it is genuinely distinct from HMP", async () => {
  // A slower athlete: the half takes well over an hour, so 1-hour pace is
  // meaningfully faster than half pace and the two do NOT converge. This is
  // the case the legacy LT=HM collapse got wrong.
  const db: DB = {
    fitness_snapshots: [{
      user_id: REAL_USER,
      predicted_5k_seconds: 1500,
      predicted_10k_seconds: 3120,
      predicted_half_seconds: 6900,
      predicted_marathon_seconds: 14400,
      created_at: new Date().toISOString(),
    }],
  };
  const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
  const z = state.pace_zones;
  const r = state.pace_zone_ranges;

  assert(z.lt, "lt should still be derived");
  assert(
    !(r.hmp && z.lt >= r.hmp.paceFast && z.lt <= r.hmp.paceSlow),
    `for a slower athlete LT (${z.lt}) should fall OUTSIDE the HMP band`,
  );

  const prompt = stateToPromptContext(state);
  assert(prompt.includes("  LT / Threshold:"), `expected a distinct LT line. Got:\n${prompt}`);
  assert(prompt.includes("  HMP:"), "HMP keeps its own plain line when the two are distinct");
  assert(!prompt.includes("same effort"), "must not claim convergence when they are distinct");
});

// ── fitness_vs_6mo_ago deadband ──────────────────────────
//
// The band was a flat ±15s on the 10K prediction. At a 32:00 10K that is
// 0.8% — inside prediction noise — so a 16-second drift was narrated as
// "slower". The flat number also meant very different things across ability
// levels (0.4% for an hour 10K). Now scaled to the athlete's own 10K.

async function labelFor(current: number, prior: number) {
  const db: DB = {
    fitness_snapshots: [
      { user_id: REAL_USER, predicted_10k_seconds: current, created_at: new Date().toISOString() },
      {
        user_id: REAL_USER,
        predicted_10k_seconds: prior,
        created_at: new Date(Date.now() - 182 * 86400000).toISOString(),
      },
    ],
  };
  const state = await getOrBuildAthleteState(buildFakeClient(db), REAL_USER);
  return state.fitness_vs_6mo_ago_label;
}

Deno.test("fitness vs 6mo: 16s on a 32:00 10K reads as similar, not slower", async () => {
  assertEquals(await labelFor(1936, 1920), "similar");
});

Deno.test("fitness vs 6mo: a move past 1.5% still reads as a direction", async () => {
  assertEquals(await labelFor(1980, 1920), "slower", "+60s = 3.1%, past the deadband");
  assertEquals(await labelFor(1860, 1920), "faster", "-60s = 3.1%, past the deadband");
});

Deno.test("fitness vs 6mo: beyond 4% reads as a strong move", async () => {
  assertEquals(await labelFor(2020, 1920), "much slower", "+100s = 5.2%");
  assertEquals(await labelFor(1820, 1920), "much faster", "-100s = 5.2%");
});
