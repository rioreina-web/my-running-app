/**
 * Self-test for the `daily-read-v3-shape` custom check. Uses
 * `node:assert` so it runs offline (the main runner.test.ts pulls
 * deno.land/std; this file deliberately doesn't).
 */

import assert from "node:assert/strict";
import { runCustomCheck } from "./customChecks.ts";

const W1 = "aaaaaaaa-1111-1111-1111-111111111111";

function check(obj: unknown) {
  return runCustomCheck("daily-read-v3-shape", JSON.stringify(obj), obj);
}

const good = {
  headline: "Tempos are coming down.",
  paragraph: [
    "Smooth and in rhythm, by your own account this week. ",
    { workout_id: W1 },
    " locked in at 7:29 — four weeks ago that was 7:35. ",
    "Third week above 40, settling in.",
  ],
  questions: ["How did Sunday's 16 feel next to the one three weeks ago?"],
  cant_see: null,
  sources: { workouts: [W1], docs: [], memos: [] },
  confidence: { level: "HIGH", sub: "6 runs and 3 memos, latest yesterday" },
};

Deno.test("daily-read-v3-shape: a well-formed Read passes", () => {
  const r = check(good);
  assert.equal(r.pass, true, r.reason);
});

Deno.test("daily-read-v3-shape: the empty-state Read passes with one sentence and no questions", () => {
  const r = check({
    headline: "Nothing to read yet.",
    paragraph: ["I need a run to read. Log one and I'll have something to say."],
    questions: [],
    cant_see: { eyebrow: "NEW ACCOUNT", body: "I haven't seen you run yet." },
    sources: { workouts: [], docs: [], memos: [] },
    confidence: { level: "LOW", sub: "first read — light evidence" },
  });
  assert.equal(r.pass, true, r.reason);
});

Deno.test("daily-read-v3-shape: headline without a period fails", () => {
  const r = check({ ...good, headline: "Tempos are coming down" });
  assert.equal(r.pass, false);
  assert.match(r.reason, /end with a period/);
});

Deno.test("daily-read-v3-shape: headline over 8 words fails", () => {
  const r = check({ ...good, headline: "This is a very long headline with far too many words." });
  assert.equal(r.pass, false);
  assert.match(r.reason, /words/);
});

Deno.test("daily-read-v3-shape: too few sentences fails", () => {
  const r = check({ ...good, paragraph: ["One sentence with 7:29 in it."] });
  assert.equal(r.pass, false);
  assert.match(r.reason, /sentences/);
});

Deno.test("daily-read-v3-shape: no numbers and no citations fails", () => {
  const r = check({
    ...good,
    paragraph: ["Things are looking good. The base is taking. Keep doing what you're doing."],
  });
  assert.equal(r.pass, false);
  assert.match(r.reason, /no number/);
});

Deno.test("daily-read-v3-shape: directive language in the paragraph fails", () => {
  const r = check({
    ...good,
    paragraph: ["Smooth week at 42 miles. Tempo was 7:29. You should hold steady this week."],
  });
  assert.equal(r.pass, false);
  assert.match(r.reason, /directive/);
});

Deno.test("daily-read-v3-shape: exclamation points fail (hype register)", () => {
  const r = check({
    ...good,
    paragraph: ["Smooth week at 42 miles. Tempo was 7:29! Third week above 40."],
  });
  assert.equal(r.pass, false);
  assert.match(r.reason, /exclamation/);
});

Deno.test("daily-read-v3-shape: leading questions and >2 questions fail", () => {
  const r = check({
    ...good,
    questions: ["Have you considered a rest day?", "How did the 16 feel?", "What's next?"],
  });
  assert.equal(r.pass, false);
  assert.match(r.reason, /leading or directive/);
  assert.match(r.reason, /max 2/);
});

Deno.test("daily-read-v3-shape: missing questions on a non-empty Read fails", () => {
  const r = check({ ...good, questions: [] });
  assert.equal(r.pass, false);
  assert.match(r.reason, /questions is empty/);
});

Deno.test("daily-read-v3-shape: unparsed JSON fails clearly", () => {
  const r = runCustomCheck("daily-read-v3-shape", "not json", null);
  assert.equal(r.pass, false);
  assert.match(r.reason, /must_parse_as_json/);
});
