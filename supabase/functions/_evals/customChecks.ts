/**
 * Custom check functions — named assertions that pattern matching can't
 * express. Each export here can be referenced from a cassette by name
 * (`"custom_check": "bone-injury-conservative-timeline"`).
 *
 * Contract: every check takes the raw response string + the parsed JSON
 * object (or null if the rubric didn't require JSON parsing) and returns
 * `{ pass: boolean, reason: string }`. `reason` is shown verbatim in
 * the failure report — be specific.
 */

export interface CustomCheckResult {
  pass: boolean;
  reason: string;
}

type CheckFn = (response: string, parsed: unknown) => CustomCheckResult;

const CHECKS: Record<string, CheckFn> = {
  /**
   * For bone-injury cassettes (stress reaction, stress fracture), the
   * injury-analysis prompt's "RECOVERY TIMELINE RULES" require the
   * optimistic timeline >= 28 days (4 weeks). Catches a prompt
   * regression that would otherwise quietly emit a 14-day return for a
   * stress fracture.
   *
   * Source: `_shared/prompts/injury-analysis.v1.ts` § RECOVERY TIMELINE RULES.
   */
  "bone-injury-conservative-timeline": (_response, parsed) => {
    if (!parsed || typeof parsed !== "object") {
      return { pass: false, reason: "parsed JSON is missing — cassette must enable must_parse_as_json" };
    }
    const obj = parsed as Record<string, unknown>;
    const timeline = obj.recovery_timeline_days;
    if (!timeline || typeof timeline !== "object") {
      return { pass: false, reason: "recovery_timeline_days is missing or not an object" };
    }
    const t = timeline as Record<string, unknown>;
    const optimistic = t.optimistic;
    if (typeof optimistic !== "number") {
      return { pass: false, reason: `recovery_timeline_days.optimistic must be a number (got ${typeof optimistic})` };
    }
    if (optimistic < 28) {
      return {
        pass: false,
        reason: `bone injury optimistic timeline must be >= 28 days (got ${optimistic}). ` +
                `Prompt's RECOVERY TIMELINE RULES require minimum 4 weeks for stress reactions / fractures.`,
      };
    }
    return { pass: true, reason: "" };
  },

  /**
   * Injury-analysis must include the educational-purposes disclaimer in
   * the `disclaimer` field of the JSON output (not just somewhere in
   * the response). The prompt template specifies this field exactly;
   * a regression that drops it should fail the cassette.
   */
  "disclaimer-field-present": (_response, parsed) => {
    if (!parsed || typeof parsed !== "object") {
      return { pass: false, reason: "parsed JSON missing — cassette must enable must_parse_as_json" };
    }
    const d = (parsed as Record<string, unknown>).disclaimer;
    if (typeof d !== "string" || d.length < 20) {
      return {
        pass: false,
        reason: `disclaimer field must be a string >=20 chars (got ${typeof d}, len ${typeof d === "string" ? d.length : "n/a"})`,
      };
    }
    if (!/not a (medical )?diagnosis/i.test(d)) {
      return {
        pass: false,
        reason: `disclaimer field must include "not a (medical) diagnosis" — got: "${d.slice(0, 100)}..."`,
      };
    }
    return { pass: true, reason: "" };
  },
};

export function runCustomCheck(
  name: string,
  response: string,
  parsed: unknown,
): CustomCheckResult {
  const fn = CHECKS[name];
  if (!fn) {
    return {
      pass: false,
      reason: `unknown custom_check "${name}". Known: ${Object.keys(CHECKS).join(", ")}`,
    };
  }
  return fn(response, parsed);
}

export function listCustomChecks(): string[] {
  return Object.keys(CHECKS).sort();
}
