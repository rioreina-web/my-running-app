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
import { getOrBuildAthleteState, stateToPromptContext } from "./athlete-state.ts";

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
