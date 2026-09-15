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

  /**
   * The v3 Daily Read has a fixed editorial shape (see
   * `_shared/prompts/daily-read.v3.ts` § The shape). This check pins
   * the parts regexes can't: headline length + terminal period,
   * paragraph sentence count, every sentence carrying a number or a
   * cited chip, 0-2 soft questions that aren't directives, and no
   * exclamation points anywhere (hype register).
   *
   * Empty-state Reads (headline "Nothing to read yet.") are exempt
   * from the sentence-count and number rules — the prompt fixes their
   * copy exactly.
   */
  "daily-read-v3-shape": (_response, parsed) => {
    if (!parsed || typeof parsed !== "object") {
      return { pass: false, reason: "parsed JSON is missing — cassette must enable must_parse_as_json" };
    }
    const obj = parsed as Record<string, unknown>;
    const problems: string[] = [];

    // Headline: string, ≤ 8 words, ends with a period, not a question.
    const headline = typeof obj.headline === "string" ? obj.headline.trim() : "";
    if (!headline) {
      problems.push("headline missing");
    } else {
      const words = headline.split(/\s+/).filter(Boolean).length;
      if (words > 8) problems.push(`headline is ${words} words (max 8): "${headline}"`);
      if (!/[.…]$/.test(headline)) problems.push(`headline must end with a period: "${headline}"`);
      if (/\?/.test(headline)) problems.push(`headline must not be a question: "${headline}"`);
    }
    const isEmptyState = /^nothing to read yet/i.test(headline);

    // Paragraph: array; join string segments; count sentences.
    const paragraph = Array.isArray(obj.paragraph) ? (obj.paragraph as unknown[]) : null;
    if (!paragraph) {
      problems.push("paragraph is not an array");
    } else {
      const text = paragraph.filter((s) => typeof s === "string").join("");
      const citations = paragraph.filter((s) => s && typeof s === "object").length;
      const sentences = text.split(/(?<=[.!?…])\s+/).map((s) => s.trim()).filter((s) => /\w/.test(s)).length;
      if (!isEmptyState) {
        if (sentences < 3 || sentences > 5) {
          problems.push(`paragraph has ${sentences} sentences (want 3-5)`);
        }
        if (!/\d/.test(text) && citations === 0) {
          problems.push("paragraph carries no number and no citation — 'numbers over adjectives'");
        }
      }
      if (/!/.test(text)) problems.push("paragraph contains an exclamation point (hype register)");
      if (/\b(you should|you need to|make sure to|i recommend|i'd suggest|i would suggest|try to|consider|focus on)\b/i.test(text)) {
        problems.push("paragraph contains directive language (you should / I recommend / make sure to / try to / consider / focus on)");
      }
    }

    // Questions: 0-2 strings, non-directive, non-leading.
    const questions = obj.questions;
    if (!Array.isArray(questions)) {
      problems.push("questions is not an array");
    } else {
      if (questions.length > 2) problems.push(`questions has ${questions.length} entries (max 2)`);
      if (!isEmptyState && questions.length === 0) problems.push("questions is empty on a non-empty Read (want 1-2)");
      if (isEmptyState && questions.length > 0) problems.push("questions must be empty on the empty-state Read");
      questions.forEach((q, i) => {
        if (typeof q !== "string") {
          problems.push(`questions[${i}] is not a string`);
          return;
        }
        if (/^\s*(have you considered|why don't you|why not|should you|shouldn't you|you should|will you)\b/i.test(q)) {
          problems.push(`questions[${i}] is leading or directive: "${q}"`);
        }
        if (/!/.test(q)) problems.push(`questions[${i}] contains an exclamation point`);
      });
    }

    return problems.length === 0
      ? { pass: true, reason: "" }
      : { pass: false, reason: problems.join("; ") };
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
