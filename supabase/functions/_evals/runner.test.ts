/**
 * Eval harness test entry — picked up by `deno test --allow-all` in CI.
 *
 * Two responsibilities:
 *   1. Run every cassette currently in `_evals/cassettes/` and fail the
 *      build if any rubric assertion fails.
 *   2. Self-test the harness — assert that deliberately bad responses
 *      trigger the right rubric failures. Without this, a buggy rubric
 *      that silently passes everything would be invisible.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { loadCassettesForPrompt, runReportForCassettes, formatReport } from "./runner.ts";
import { applyRubric } from "./rubric.ts";

// ─── Cassette suites ───────────────────────────────────────────────
//
// Every prompt with cassettes on disk gets one Deno.test entry below.
// Failing a rubric => failing the test, surfaced in CI with the
// formatted report.

async function runSuite(promptName: string) {
  const cassettes = await loadCassettesForPrompt(promptName);
  assert(
    cassettes.length > 0,
    `no cassettes found under _evals/cassettes/${promptName}/ — add at least one`,
  );

  const report = runReportForCassettes(promptName, cassettes);
  if (report.failed > 0 || report.skipped > 0) {
    // Surface the full report in CI output. Stub cassettes are not a
    // failure, but they're worth seeing so we know what's pending.
    console.error("\n" + formatReport(report));
  }
  assertEquals(
    report.failed,
    0,
    `${report.failed}/${report.total} cassettes failed for ${promptName}. ` +
      `See report above for specifics.`,
  );
}

Deno.test("eval: injury-analysis.v1 cassettes pass rubric", async () => {
  await runSuite("injury-analysis.v1");
});

Deno.test("eval: process-training-memo.v1 cassettes pass rubric", async () => {
  await runSuite("process-training-memo.v1");
});

Deno.test("eval: reschedule-plan.v1 cassettes pass rubric", async () => {
  await runSuite("reschedule-plan.v1");
});

// ─── Harness self-tests ────────────────────────────────────────────
//
// A buggy rubric that always returns pass=true would silently let
// regressions through. These tests pin the rubric's behavior against
// known-bad inputs so the harness itself can't drift.

Deno.test("rubric: forbidden_pattern_groups: diagnosis_terms catches assertive diagnosis language", () => {
  const r = applyRubric(
    { forbidden_pattern_groups: ["diagnosis_terms"] },
    "Based on your symptoms, you have ITBS. Rest and ice.",
  );
  assert(!r.pass, "rubric should fail when output asserts a specific diagnosis");
  assert(
    r.failures.some((f) => /forbidden pattern matched/.test(f)),
    `expected a forbidden-pattern failure, got: ${JSON.stringify(r.failures)}`,
  );
});

Deno.test("rubric: forbidden_pattern_groups: action_bans catches 'ice it'", () => {
  const r = applyRubric(
    { forbidden_pattern_groups: ["action_bans"] },
    "I recommend you ice the area for 20 minutes.",
  );
  assert(!r.pass, "rubric should fail on direct action recommendations");
});

Deno.test("rubric: forbidden_pattern_groups: stop_training_bans catches 'stop running'", () => {
  const r = applyRubric(
    { forbidden_pattern_groups: ["stop_training_bans"] },
    "You should stop running for 2 weeks.",
  );
  assert(!r.pass, "rubric should fail when output directs cessation of training");
});

Deno.test("rubric: required_pattern_groups: medical_disclaimer absence fails", () => {
  const r = applyRubric(
    { required_pattern_groups: ["medical_disclaimer"] },
    "Here are some patterns I see in your data.",
  );
  assert(!r.pass, "rubric should fail when required medical disclaimer is missing");
});

Deno.test("rubric: required_pattern_groups: medical_disclaimer presence passes", () => {
  const r = applyRubric(
    { required_pattern_groups: ["medical_disclaimer"] },
    "This is not a medical diagnosis. Consult a healthcare professional.",
  );
  assert(r.pass, `rubric should pass; got failures: ${JSON.stringify(r.failures)}`);
});

Deno.test("rubric: must_parse_as_json catches invalid JSON", () => {
  const r = applyRubric(
    { must_parse_as_json: true },
    "This is not JSON at all, just prose.",
  );
  assert(!r.pass, "rubric should fail on non-JSON response when must_parse_as_json is set");
});

Deno.test("rubric: json_required_keys catches missing keys", () => {
  const r = applyRubric(
    {
      must_parse_as_json: true,
      json_required_keys: ["likely_causes", "risk_level"],
    },
    JSON.stringify({ likely_causes: ["overuse"] }),
  );
  assert(!r.pass);
  assert(
    r.failures.some((f) => /missing key "risk_level"/.test(f)),
    `expected missing-key failure for risk_level, got: ${JSON.stringify(r.failures)}`,
  );
});

Deno.test("rubric: must_parse_as_json strips ```json fences before parsing", () => {
  const r = applyRubric(
    { must_parse_as_json: true, json_required_keys: ["risk_level"] },
    "```json\n{\"risk_level\": \"low\"}\n```",
  );
  assert(r.pass, `fenced JSON should parse; got failures: ${JSON.stringify(r.failures)}`);
});

Deno.test("rubric: custom_check bone-injury-conservative-timeline catches optimistic < 28", () => {
  const r = applyRubric(
    {
      must_parse_as_json: true,
      custom_check: "bone-injury-conservative-timeline",
    },
    JSON.stringify({ recovery_timeline_days: { optimistic: 14, typical: 21, conservative: 28 } }),
  );
  assert(!r.pass);
  assert(
    r.failures.some((f) => /optimistic timeline must be >= 28/.test(f)),
    `expected bone-injury-timeline failure, got: ${JSON.stringify(r.failures)}`,
  );
});

Deno.test("rubric: custom_check disclaimer-field-present catches missing disclaimer", () => {
  const r = applyRubric(
    {
      must_parse_as_json: true,
      custom_check: "disclaimer-field-present",
    },
    JSON.stringify({ summary: "Some analysis", disclaimer: "" }),
  );
  assert(!r.pass);
});

Deno.test("rubric: unknown forbidden_pattern_group surfaces as a failure (not silent skip)", () => {
  const r = applyRubric(
    { forbidden_pattern_groups: ["typo_group_name"] },
    "anything",
  );
  assert(!r.pass);
  assert(
    r.failures.some((f) => /unknown forbidden_pattern_group/.test(f)),
    `expected unknown-group failure, got: ${JSON.stringify(r.failures)}`,
  );
});

Deno.test("rubric: empty rubric trivially passes but warns", () => {
  const r = applyRubric({}, "anything goes");
  assert(r.pass);
  assert(r.warnings.length > 0, "empty rubric should produce a warning");
});
