/**
 * Unit tests for missed_workouts (cause-aware, rule 3a/3b).
 *
 * Run: deno test --allow-all _shared/rules/missedWorkouts.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { missedWorkouts } from "./missedWorkouts.ts";
import type { RuleContext, ScheduledWorkoutRow } from "./types.ts";
import type { CauseSource, SkipCause } from "../cause.ts";

const NOW = new Date("2026-08-21T12:00:00Z");

function sw(
  id: string,
  status: ScheduledWorkoutRow["status"],
  cause?: SkipCause,
  source: CauseSource = "inferred",
): ScheduledWorkoutRow {
  return {
    id,
    date: "2026-08-18",
    status,
    workout_type: "tempo",
    ...(cause ? { skip_cause: cause, skip_cause_source: source } : {}),
  };
}

function ctx(scheduledThisWeek: ScheduledWorkoutRow[]): RuleContext {
  return {
    athleteUserId: "athlete-1",
    coachId: "coach-1",
    now: NOW,
    logs: [],
    scheduledThisWeek,
  };
}

/** A full week with `skips` skipped sessions, all sharing one cause. */
function week(skips: number, cause?: SkipCause, source?: CauseSource) {
  const rows: ScheduledWorkoutRow[] = [];
  for (let i = 0; i < skips; i++) {
    rows.push(sw(`skip-${i}`, "skipped", cause, source));
  }
  while (rows.length < 5) rows.push(sw(`done-${rows.length}`, "completed"));
  return ctx(rows);
}

// ─── The branch ──────────────────────────────────────────────────────────────

Deno.test("busy week and cooked week produce different asks", () => {
  const busy = missedWorkouts(week(2, "schedule"));
  const cooked = missedWorkouts(week(2, "fatigue"));

  assert(busy && cooked);
  assertEquals(busy.action_type, "monitor");
  assertEquals(cooked.action_type, "suggest_extra_recovery");
  assertEquals(busy.severity, "low");
  assertEquals(cooked.severity, "med");
});

Deno.test("the loudest cause drives the week, not the most common one", () => {
  // One niggle skip, two "work was mad" skips — it's a niggle week.
  const m = missedWorkouts(ctx([
    sw("a", "skipped", "niggle"),
    sw("b", "skipped", "schedule"),
    sw("c", "skipped", "schedule"),
    sw("d", "completed"),
  ]));
  assert(m);
  assertEquals(m.severity, "high");
  assertEquals(m.action_type, "recommend_evaluation");
});

// ─── Thresholds ──────────────────────────────────────────────────────────────

Deno.test("a single unexplained miss stays quiet", () => {
  assertEquals(missedWorkouts(week(1)), null);
  assertEquals(missedWorkouts(week(1, "schedule")), null);
  assertEquals(missedWorkouts(week(1, "fatigue")), null);
});

Deno.test("a single miss around a body mention fires immediately", () => {
  // Waiting for a second miss defeats the point of catching it early.
  const m = missedWorkouts(week(1, "niggle"));
  assert(m, "niggle should fire on one miss");
  assertEquals(m.severity, "high");
});

Deno.test("no skips, no moment", () => {
  assertEquals(missedWorkouts(week(0)), null);
});

Deno.test("a quiet cause escalates when it keeps happening", () => {
  const twice = missedWorkouts(week(2, "schedule"));
  const thrice = missedWorkouts(week(3, "schedule"));
  assert(twice && thrice);
  assertEquals(twice.severity, "low");
  // Three missed sessions to "work was mad" is a plan that doesn't fit the
  // athlete's life — which is the coach's problem, not the athlete's.
  assertEquals(thrice.severity, "med");
});

// ─── Provenance ──────────────────────────────────────────────────────────────

Deno.test("unattributed skips ask rather than assume", () => {
  const m = missedWorkouts(week(2));
  assert(m);
  assertEquals(m.action_type, "send_check_in");
  assert(m.summary.includes("No reason captured"));
});

Deno.test("summary distinguishes an inference from a confirmation", () => {
  const inferred = missedWorkouts(week(2, "fatigue", "inferred"));
  const confirmed = missedWorkouts(week(2, "fatigue", "coach_confirmed"));
  assert(inferred && confirmed);
  assert(inferred.summary.includes("inferred — correctable"));
  assert(confirmed.summary.includes("confirmed"));
  assert(!confirmed.summary.includes("inferred"));
});

Deno.test("summary keeps the spec's source-count suffix", () => {
  const m = missedWorkouts(week(2, "fatigue"));
  assert(m);
  assert(m.summary.includes("Source: 0 voice logs, 2 workouts."));
  assert(m.summary.startsWith("2 of 5 scheduled workouts skipped this week."));
});

Deno.test("illness reports and stops — it never routes to medical care", () => {
  const m = missedWorkouts(week(2, "illness"));
  assert(m);
  assertEquals(m.action_type, "monitor");
  const s = m.summary.toLowerCase();
  for (const banned of ["doctor", "physio", "stop training", "stop running"]) {
    assert(!s.includes(banned), `illness summary must not contain "${banned}"`);
  }
});
