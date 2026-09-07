/**
 * Unit tests for skip-cause attribution and the adjustment it implies.
 *
 * The test that matters most is the first one: the same missed session must
 * branch to opposite moves depending on why it was missed. Everything else
 * guards the edges around that.
 *
 * Run: deno test --allow-all _shared/cause.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CAUSE_RESPONSES,
  CAUSE_VOCAB,
  inferCauseHints,
  isSkipCause,
  moodSuggestsFatigue,
  proposeForSkip,
  type AttributedCause,
  type SkipContext,
} from "./cause.ts";

const CTX: SkipContext = {
  scheduledWorkoutId: "sw-1",
  date: "2026-08-18",
  workoutType: "tempo",
  missedThisWeek: 1,
};

function attributed(
  cause: AttributedCause["cause"],
  over: Partial<AttributedCause> = {},
): AttributedCause {
  return {
    cause,
    source: "inferred",
    confidence: "high",
    evidence: [{ kind: "memo", ref: "m-1", excerpt: "…" }],
    ...over,
  };
}

// ─── The branch ──────────────────────────────────────────────────────────────

Deno.test("same miss, opposite moves — schedule keeps the load, fatigue sheds it", () => {
  const busy = proposeForSkip(attributed("schedule"), CTX);
  const cooked = proposeForSkip(attributed("fatigue"), CTX);

  assertEquals(busy.action_type, "shift_day");
  assertEquals(busy.secondary_action, null);

  assertEquals(cooked.action_type, "insert_rest");
  assertEquals(cooked.secondary_action, "reduce_volume");

  // The distinction is the product; if these ever converge something is wrong.
  assert(busy.action_type !== cooked.action_type);
});

Deno.test("fatigue routes through the fatigue trigger, not missed_sessions", () => {
  // There was no fatigue trigger before this work — the most common reason a
  // coach touches a plan was inexpressible.
  assertEquals(proposeForSkip(attributed("fatigue"), CTX).trigger_type, "fatigue_signal");
  assertEquals(proposeForSkip(attributed("schedule"), CTX).trigger_type, "missed_sessions");
});

// ─── Hard rule #2: never diagnose, never prescribe stopping ─────────────────

Deno.test("illness and niggle both hand the decision to a human", () => {
  for (const c of ["illness", "niggle"] as const) {
    const p = proposeForSkip(attributed(c), CTX);
    assert(p.defer_to_human, `${c} must defer to a human`);
  }
});

Deno.test("no rationale prescribes stopping, resting up, or names a condition", () => {
  // The output guard in insight-safety.ts is the backstop for generated prose.
  // These strings are authored, so they get checked at the source instead.
  const banned = [
    "stop training", "stop running", "see a doctor", "physio", "physical therapist",
    "rest up", "take time off", "injury", "injured", "diagnos",
  ];
  for (const cause of CAUSE_VOCAB) {
    const text = CAUSE_RESPONSES[cause].rationale.toLowerCase();
    for (const phrase of banned) {
      assert(
        !text.includes(phrase),
        `${cause} rationale contains banned phrase "${phrase}": ${text}`,
      );
    }
  }
});

Deno.test("every cause in the vocabulary has a response", () => {
  for (const cause of CAUSE_VOCAB) {
    assert(CAUSE_RESPONSES[cause], `no response for ${cause}`);
    assert(CAUSE_RESPONSES[cause].rationale.trim().length > 0);
  }
});

// ─── Asking rather than guessing ─────────────────────────────────────────────

Deno.test("unknown asks instead of acting", () => {
  const p = proposeForSkip(attributed("unknown", { confidence: "low" }), CTX);
  assert(p.ask_to_confirm_cause);
  assert(p.defer_to_human);
});

Deno.test("a confirmed cause is never re-litigated", () => {
  for (const source of ["coach_confirmed", "athlete_confirmed"] as const) {
    const p = proposeForSkip(
      attributed("fatigue", { source, confidence: "low" }),
      CTX,
    );
    assertEquals(
      p.ask_to_confirm_cause,
      false,
      `${source} should not be asked again`,
    );
  }
});

Deno.test("low-confidence inference asks; high-confidence proposes", () => {
  assert(proposeForSkip(attributed("fatigue", { confidence: "low" }), CTX).ask_to_confirm_cause);
  assert(proposeForSkip(attributed("fatigue", { confidence: "medium" }), CTX).ask_to_confirm_cause);
  assertEquals(
    proposeForSkip(attributed("schedule", { confidence: "high" }), CTX).ask_to_confirm_cause,
    false,
  );
});

// ─── Repetition ──────────────────────────────────────────────────────────────

Deno.test("a second miss in the week escalates a low branch", () => {
  const once = proposeForSkip(attributed("schedule"), CTX);
  const twice = proposeForSkip(attributed("schedule"), { ...CTX, missedThisWeek: 2 });

  assertEquals(once.severity, "low");
  assertEquals(twice.severity, "med");
  assert(twice.defer_to_human, "a repeated inferred miss wants a human read");
});

Deno.test("repetition never de-escalates a high branch", () => {
  const p = proposeForSkip(attributed("niggle"), { ...CTX, missedThisWeek: 3 });
  assertEquals(p.severity, "high");
});

// ─── Hinting ─────────────────────────────────────────────────────────────────

Deno.test("body mentions outrank a busy week", () => {
  // "calf is sore but also work was mad" must not resolve to schedule.
  const hits = inferCauseHints("calf was sore all day and work was mad");
  assertEquals(hits[0].cause, "niggle");
});

Deno.test("reads fatigue and schedule out of the athlete's own words", () => {
  assertEquals(inferCauseHints("legs are trashed")[0].cause, "fatigue");
  assertEquals(inferCauseHints("meeting ran over, no time")[0].cause, "schedule");
  assertEquals(inferCauseHints("thunderstorm all evening")[0].cause, "weather");
});

Deno.test("both causes surface when a memo names both", () => {
  const hits = inferCauseHints("shattered after a bad sleep and a deadline at work");
  const causes = hits.map((h) => h.cause);
  assert(causes.includes("fatigue"));
  assert(causes.includes("schedule"));
});

Deno.test("silence yields no hint rather than a guess", () => {
  assertEquals(inferCauseHints(""), []);
  assertEquals(inferCauseHints(null), []);
  assertEquals(inferCauseHints("solid session, felt good"), []);
});

Deno.test("mood corroborates fatigue using the labels the app already writes", () => {
  assert(moodSuggestsFatigue("tired"));
  assert(moodSuggestsFatigue("struggling"));
  assertEquals(moodSuggestsFatigue("energized"), false);
  assertEquals(moodSuggestsFatigue(null), false);
});

Deno.test("model output is validated against the closed vocabulary", () => {
  assert(isSkipCause("fatigue"));
  assertEquals(isSkipCause("burnout"), false);
  assertEquals(isSkipCause("ITBS"), false);
  assertEquals(isSkipCause(null), false);
});
