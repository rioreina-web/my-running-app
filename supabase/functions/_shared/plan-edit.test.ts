/**
 * Tests for the text-box plan-edit engine: validator → resolver → diff.
 *
 * Built against REAL sessions from `session-library.json`, same reasoning as
 * `session-library.test.ts` — a fixture week of invented text would not
 * exercise the actual ambiguity and classification logic this coach's real
 * plans produce.
 *
 * Run: deno test --allow-read --allow-env --allow-net supabase/functions/_shared/plan-edit.test.ts
 * (--allow-net/--allow-env only needed for the optional live-model test,
 * which is skipped unless GEMINI_API_KEY is set.)
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { planEdits, resolveTarget, describeWorkout } from "./plan-edit-resolver.ts";
import { describePatch } from "./plan-edit-diff.ts";
import { validatePlanEditOps } from "./plan-edit-validator.ts";
import { parsePlanEdit } from "./plan-edit-llm.ts";
import type { ScheduledWorkoutRef } from "./plan-edit-schema.ts";
import type { LibrarySession } from "./session-library.ts";

const library: LibrarySession[] = JSON.parse(
  await Deno.readTextFile(new URL("./session-library.json", import.meta.url)),
);

// ── A realistic two-week fixture, built from real sessions ──────────────

function pick(day: import("./session-library.ts").DayRole, withVariant = false): LibrarySession {
  const s = withVariant
    ? library.find((x) => x.day === day && x.lightVariant)
    : library.find((x) => x.day === day);
  if (!s) throw new Error(`no fixture session for ${day} (withVariant=${withVariant})`);
  return s;
}

function week(): ScheduledWorkoutRef[] {
  const tue1 = pick("tuesday", true); // has a lightVariant on file
  // Deliberately WITHOUT a lightVariant, so the "no variant on file" path has
  // something real to exercise.
  const tue2 = library.find((x) => x.day === "tuesday" && x.text !== tue1.text && !x.lightVariant);
  if (!tue2) throw new Error("no Tuesday fixture without a lightVariant");
  const sat = pick("saturday");
  return [
    { id: "w1-tue", date: "2026-09-01", dayOfWeek: 2, weekNumber: 1, text: tue1.text, workoutType: "intervals", isKeySession: true },
    { id: "w1-wed", date: "2026-09-02", dayOfWeek: 3, weekNumber: 1, text: "Easy run", workoutType: "easy", isKeySession: false },
    { id: "w1-thu", date: "2026-09-03", dayOfWeek: 4, weekNumber: 1, text: "Rest day", workoutType: "rest", isKeySession: false },
    { id: "w1-sat", date: "2026-09-05", dayOfWeek: 6, weekNumber: 1, text: sat.text, workoutType: "long_run", isKeySession: true },
    { id: "w2-tue", date: "2026-09-08", dayOfWeek: 2, weekNumber: 2, text: tue2.text, workoutType: "intervals", isKeySession: true },
  ];
}

// ── resolveTarget ─────────────────────────────────────────

Deno.test("resolves by explicit weekday when only one match in range", () => {
  const w = week().filter((x) => x.weekNumber === 1); // exactly one Tuesday
  const r = resolveTarget("tuesday", w);
  assertEquals(r.status, "resolved");
  assertEquals(r.matches[0].id, "w1-tue");
});

Deno.test("'the long run' resolves to the Saturday session", () => {
  const r = resolveTarget("the long run", week());
  assertEquals(r.status, "resolved");
  assertEquals(r.matches[0].id, "w1-sat");
});

Deno.test("two Tuesdays in range makes a weekday reference ambiguous", () => {
  const r = resolveTarget("tuesday", week());
  assertEquals(r.status, "ambiguous");
  assertEquals(r.matches.length, 2);
});

Deno.test("a day with nothing in range is not_found, not a silent no-op", () => {
  const r = resolveTarget("friday", week());
  assertEquals(r.status, "not_found");
});

Deno.test("content words narrow an otherwise-ambiguous reference", () => {
  const w = week();
  const [t1, t2] = w.filter((x) => x.dayOfWeek === 2);
  const firstWord = t1.text.split(/\s+/).find((wd) => wd.length > 4) ?? t1.text;
  const r = resolveTarget(`the ${firstWord} one`, w);
  // Either it narrows to exactly the intended row, or (if the word is too
  // generic to discriminate) it safely falls back to asking — never resolves
  // to the WRONG row.
  if (r.status === "resolved") assertEquals(r.matches[0].id, t1.id);
  else assertEquals(r.status, "ambiguous");
});

// ── planEdits: straightforward ops ───────────────────────

Deno.test("schedule_easy on an unambiguous target resolves with no questions", () => {
  const w = week().filter((x) => x.weekNumber === 1);
  const plan = planEdits([{ kind: "schedule_easy", targetHint: "tuesday" }], w, library);
  assertEquals(plan.questions.length, 0);
  assertEquals(plan.resolved.length, 1);
  const diff = describePatch(plan.resolved[0], library);
  assertEquals(diff.after, "Easy run — same distance as before");
});

Deno.test("schedule_rest resolves the same way", () => {
  const w = week().filter((x) => x.weekNumber === 1);
  const plan = planEdits([{ kind: "schedule_rest", targetHint: "the long run" }], w, library);
  assertEquals(plan.resolved.length, 1);
  assertEquals(describePatch(plan.resolved[0], library).after, "Rest day");
});

Deno.test("a target matching nothing is reported, never dropped silently", () => {
  const w = week();
  const plan = planEdits([{ kind: "schedule_easy", targetHint: "friday" }], w, library);
  assertEquals(plan.resolved.length, 0);
  assertEquals(plan.questions.length, 0);
  assertEquals(plan.notFound.length, 1);
});

Deno.test("an ambiguous target becomes a question with one option per candidate", () => {
  const w = week();
  const plan = planEdits([{ kind: "schedule_easy", targetHint: "tuesday" }], w, library);
  assertEquals(plan.resolved.length, 0);
  assertEquals(plan.questions.length, 1);
  assertEquals(plan.questions[0].options.length, 2);
  // Options must be real rows, described in the coach's own words.
  for (const o of plan.questions[0].options) assert(o.value === "w1-tue" || o.value === "w2-tue");
});

// ── lighten: the coach's own variant, or real candidates, never invented ─

Deno.test("lighten resolves directly when a light variant is on file", () => {
  const w = week().filter((x) => x.weekNumber === 1);
  const plan = planEdits([{ kind: "lighten", targetHint: "tuesday" }], w, library);
  assertEquals(plan.questions.length, 0, "should not need to ask — the variant exists");
  assertEquals(plan.resolved.length, 1);
  const diff = describePatch(plan.resolved[0], library);
  const source = pick("tuesday", true);
  assertEquals(diff.after, source.lightVariant);
});

Deno.test("lighten with no variant on file asks, offering real sessions plus an easy fallback", () => {
  // week 2's Tuesday was picked deliberately without a lightVariant.
  const w2 = week().filter((x) => x.weekNumber === 2);
  const plan = planEdits([{ kind: "lighten", targetHint: "tuesday" }], w2, library);
  assertEquals(plan.resolved.length, 0);
  assertEquals(plan.questions.length, 1);
  const q = plan.questions[0];
  assert(q.options.some((o) => o.value === "__easy__"), "must always offer the safe easy fallback");
  assert(q.options.length > 1, "should offer real smaller sessions, not just the fallback");
});

// ── retarget_pace: never guesses a zone ──────────────────

Deno.test("retarget_pace with no zone asks, offering every real pace zone", () => {
  const w = week().filter((x) => x.weekNumber === 1);
  const plan = planEdits([{ kind: "retarget_pace", targetHint: "tuesday", paceZone: null }], w, library);
  assertEquals(plan.resolved.length, 0);
  assertEquals(plan.questions.length, 1);
  assert(plan.questions[0].options.length >= 10, "should offer the full zone list");
});

Deno.test("retarget_pace with a real zone resolves directly", () => {
  const w = week().filter((x) => x.weekNumber === 1);
  const plan = planEdits(
    [{ kind: "retarget_pace", targetHint: "tuesday", paceZone: "threshold" }],
    w,
    library,
  );
  assertEquals(plan.questions.length, 0);
  assertEquals(plan.resolved.length, 1);
  assert(describePatch(plan.resolved[0], library).after.includes("threshold"));
});

// ── swap_session: ALWAYS a tap, even with a hint ─────────

Deno.test("swap_session always asks, never silently picks a replacement", () => {
  const w = week().filter((x) => x.weekNumber === 1);
  const withHint = planEdits(
    [{ kind: "swap_session", targetHint: "tuesday", replacementHint: "something shorter" }],
    w, library,
  );
  const withoutHint = planEdits(
    [{ kind: "swap_session", targetHint: "tuesday", replacementHint: null }],
    w, library,
  );
  assertEquals(withHint.resolved.length, 0);
  assertEquals(withoutHint.resolved.length, 0);
  assert(withHint.questions.length === 1 && withoutHint.questions.length === 1);
  // Options must be verbatim library sessions, never synthetic codes.
  for (const o of withHint.questions[0].options) {
    assert(!/^[A-Z]{2,5}_\d/.test(o.value), `looks like a synthetic code: ${o.value}`);
  }
});

// ── move_session: conflict detection ─────────────────────

Deno.test("move_session to an empty day resolves directly", () => {
  const w = week().filter((x) => x.weekNumber === 1);
  const plan = planEdits([{ kind: "move_session", targetHint: "tuesday", toDayHint: "friday" }], w, library);
  assertEquals(plan.questions.length, 0);
  assertEquals(plan.resolved.length, 1);
  assert(describePatch(plan.resolved[0], library).after.startsWith("Moved to Fri"));
});

Deno.test("move_session onto an occupied day asks how to resolve the conflict", () => {
  const w = week().filter((x) => x.weekNumber === 1);
  const plan = planEdits([{ kind: "move_session", targetHint: "tuesday", toDayHint: "saturday" }], w, library);
  assertEquals(plan.resolved.length, 0);
  assertEquals(plan.questions.length, 1);
  assertEquals(plan.questions[0].options.length, 3);
});

Deno.test("move_session with an unparseable destination asks which day", () => {
  const w = week().filter((x) => x.weekNumber === 1);
  const plan = planEdits([{ kind: "move_session", targetHint: "tuesday", toDayHint: "later" }], w, library);
  assertEquals(plan.resolved.length, 0);
  assertEquals(plan.questions[0].options.length, 7);
});

// ── race week gate ────────────────────────────────────────

Deno.test("a race-week target always asks for confirmation, regardless of op", () => {
  const w: ScheduledWorkoutRef[] = [
    { id: "rw", date: "2026-10-12", dayOfWeek: 6, weekNumber: 5, text: "Marathon", workoutType: "race", isKeySession: true, isRaceWeek: true },
  ];
  const plan = planEdits([{ kind: "schedule_rest", targetHint: "saturday" }], w, library);
  assertEquals(plan.resolved.length, 0);
  assertEquals(plan.questions.length, 1);
  assert(plan.questions[0].question.includes("race week"));
});

// ── validator ─────────────────────────────────────────────

Deno.test("validator drops an unknown op kind with a warning, never throws", () => {
  const r = validatePlanEditOps([{ kind: "delete_everything", targetHint: "tuesday" }]);
  assertEquals(r.ops.length, 0);
  assert(r.warnings.length === 1);
});

Deno.test("validator drops an op with no target", () => {
  const r = validatePlanEditOps([{ kind: "schedule_easy" }]);
  assertEquals(r.ops.length, 0);
});

Deno.test("validator refuses scale_distance with no number or an absurd one", () => {
  const noNumber = validatePlanEditOps([{ kind: "scale_distance", targetHint: "saturday" }]);
  assertEquals(noNumber.ops.length, 0);

  const absurd = validatePlanEditOps([{ kind: "scale_distance", targetHint: "saturday", toMiles: 500 }]);
  assertEquals(absurd.ops.length, 0);

  const fine = validatePlanEditOps([{ kind: "scale_distance", targetHint: "saturday", toMiles: 14 }]);
  assertEquals(fine.ops.length, 1);
});

Deno.test("validator treats an unknown pace zone as unspecified rather than throwing", () => {
  const r = validatePlanEditOps([{ kind: "retarget_pace", targetHint: "tuesday", paceZone: "sprint" }]);
  assertEquals(r.ops.length, 1);
  assertEquals((r.ops[0] as { paceZone: unknown }).paceZone, null);
  assert(r.warnings.length === 1);
});

Deno.test("validator ignores an out-of-range pace offset but keeps the op", () => {
  const r = validatePlanEditOps([
    { kind: "retarget_pace", targetHint: "tuesday", paceZone: "mp", adjustmentType: "seconds_per_mile", adjustmentValue: 9999 },
  ]);
  assertEquals(r.ops.length, 1);
  assertEquals((r.ops[0] as { adjustment?: unknown }).adjustment, undefined);
});

Deno.test("never throws on garbage input", () => {
  for (const junk of [null, undefined, "ops", 42, {}, [null], [{}], [[]]]) {
    const r = validatePlanEditOps(junk as unknown);
    assert(Array.isArray(r.ops));
  }
});

// ── optional live check ──────────────────────────────────

Deno.test({
  name: "live: a simple instruction resolves end to end against the real model",
  ignore: !Deno.env.get("GEMINI_API_KEY"),
  fn: async () => {
    const w = week().filter((x) => x.weekNumber === 1);
    const raw = await parsePlanEdit("make tuesday an easy day", w);
    assert(raw, "model call failed");
    const validated = validatePlanEditOps(raw.ops, { unparsed: raw.unparsed });
    assert(validated.ops.length >= 1, `expected at least one op, got ${JSON.stringify(validated)}`);
    const plan = planEdits(validated.ops, w, library);
    assert(plan.resolved.length === 1, `expected a resolved edit, got ${JSON.stringify(plan)}`);
    assertEquals(plan.resolved[0].op.kind, "schedule_easy");
    console.log("  live diff:", describeWorkout(plan.resolved[0].target), "→", describePatch(plan.resolved[0], library).after);
  },
});
