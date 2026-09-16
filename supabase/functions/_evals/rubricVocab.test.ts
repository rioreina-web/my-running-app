/**
 * Tests for the plain-English rubric layer (must_not / must /
 * respond_as_json_with). These are the friendly names that let a rubric be
 * written in words instead of regex.
 *
 * Run: deno test --allow-read _evals/rubricVocab.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { applyRubric, listMustNotRules, listMustRules, normalizeRubric } from "./rubric.ts";

Deno.test("must_not / must expand into the catalogued pattern groups", () => {
  const { rubric, errors } = normalizeRubric({
    must_not: ["diagnose", "tell_to_stop_training"],
    must: ["include_disclaimer"],
  });
  assertEquals(errors, []);
  assert(rubric.forbidden_pattern_groups?.includes("diagnosis_terms"));
  assert(rubric.forbidden_pattern_groups?.includes("stop_training_bans"));
  assert(rubric.required_pattern_groups?.includes("medical_disclaimer"));
});

Deno.test("a plain-English rubric catches a diagnosis", () => {
  const res = applyRubric(
    { must_not: ["diagnose"] },
    "Based on the pattern, this is ITBS and you should manage it accordingly.",
  );
  assertEquals(res.pass, false);
  assert(res.failures.some((f) => f.includes("forbidden pattern matched")));
});

Deno.test("a clean response passes the same plain-English rubric", () => {
  const res = applyRubric(
    { must_not: ["diagnose", "prescribe_action", "tell_to_stop_training"] },
    "Your calf has come up a few times lately. Worth mentioning to your coach so they can take a look.",
  );
  assertEquals(res.pass, true, res.failures.join("; "));
});

Deno.test("an unknown rule name fails loudly with the valid options", () => {
  const res = applyRubric({ must_not: ["diagnoze"] }, "anything");
  assertEquals(res.pass, false);
  const msg = res.failures.find((f) => f.includes("unknown must_not rule"))!;
  assert(msg.includes("diagnose"), "error should list the real rule names");
});

Deno.test("cite_a_number requires a concrete number", () => {
  const fail = applyRubric({ must: ["cite_a_number"] }, "The plan is working.");
  assertEquals(fail.pass, false);
  const ok = applyRubric(
    { must: ["cite_a_number"] },
    "Tempo locked in — 7:29 average vs 7:35 four weeks ago.",
  );
  assertEquals(ok.pass, true, ok.failures.join("; "));
});

Deno.test("overstate_confidence bans false certainty", () => {
  const res = applyRubric(
    { must_not: ["overstate_confidence"] },
    "You will definitely hit your BQ in October.",
  );
  assertEquals(res.pass, false);
});

Deno.test("respond_as_json_with turns on JSON parsing + key checks", () => {
  const bad = applyRubric({ respond_as_json_with: ["risk_level"] }, "not json");
  assertEquals(bad.pass, false);
  const ok = applyRubric(
    { respond_as_json_with: ["risk_level"] },
    '{"risk_level":"low"}',
  );
  assertEquals(ok.pass, true, ok.failures.join("; "));
});

Deno.test("the vocab lists are discoverable (for docs / error messages)", () => {
  assert(listMustNotRules().includes("diagnose"));
  assert(listMustRules().includes("include_disclaimer"));
});
