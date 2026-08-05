/**
 * Layer-2 narration guard — the mechanism that lets a model speak over
 * deterministic facts without being able to invent one.
 *
 * The number-token primitives were written for `compare-workouts` and live in
 * `workoutComparison.ts`. They are re-exported here, unchanged, because the
 * Ask registry generalizes the same two-layer contract to every analyzer:
 *
 *   Layer 1 (analyzers/*.ts) computes facts. Deterministic, auditable.
 *   Layer 2 (this guard) lets a model narrate them, and rejects the WHOLE
 *   response if it speaks a number Layer 1 didn't print.
 *
 * There is exactly one implementation of the token math, in
 * `workoutComparison.ts`. Do not copy it here — import it. When
 * `compare-workouts` is eventually folded into the registry, move the
 * implementation into this file and have `workoutComparison.ts` import it
 * back; until then this module is the shared front door.
 *
 * What IS new here: `validateNarration`, the generalization of
 * `compare-workouts`' private `validateVerdict`. Two differences that matter:
 *
 *   1. It returns a discriminated result, not `null`. The caller needs to know
 *      *why* a narration was rejected so `analysis_queries.guard_tripped` and
 *      the offending token can be logged — that row is the early-warning system
 *      for prompt drift.
 *   2. The field names are `text` / `caveat` rather than `verdict` / `caveat`,
 *      because an analyzer answer is not always a verdict.
 *
 * AI advises, never acts. Nothing in this module writes to the DB.
 */

import {
  allowedNumberTokens,
  firstDisallowedNumber,
  verdictNumbersAllowed,
} from "./workoutComparison.ts";

export { allowedNumberTokens, firstDisallowedNumber, verdictNumbersAllowed };

/** Narration is always ≤ 2 sentences plus at most one caveat. */
export interface Narration {
  text: string;
  caveat: string | null;
}

export interface NarrationLimits {
  maxTextChars?: number;
  maxCaveatChars?: number;
}

export const DEFAULT_NARRATION_LIMITS: Required<NarrationLimits> = {
  maxTextChars: 420,
  maxCaveatChars: 200,
};

export type NarrationRejection =
  | "unparseable"
  | "wrong_shape"
  | "too_long"
  | "disallowed_number";

export type NarrationResult =
  | { ok: true; narration: Narration }
  | { ok: false; reason: NarrationRejection; offendingNumber?: string };

/**
 * Parse + validate a Layer-2 response against the Layer-1 fact lines.
 *
 * Wholesale rejection, same discipline as `compare-workouts.validateVerdict`
 * and `suggest-workout-progression.validateRanking`: any violation kills the
 * entire narration rather than patching it. The facts always render; the
 * narration is a bonus, never a dependency.
 */
export function validateNarration(
  raw: string,
  factLines: string[],
  limits: NarrationLimits = {},
): NarrationResult {
  const { maxTextChars, maxCaveatChars } = {
    ...DEFAULT_NARRATION_LIMITS,
    ...limits,
  };

  let body = raw.trim();
  const fenced = body.match(/```(?:json)?\s*([\s\S]*?)```/);
  if (fenced) body = fenced[1].trim();

  let parsed: unknown;
  try {
    parsed = JSON.parse(body);
  } catch {
    return { ok: false, reason: "unparseable" };
  }
  if (!parsed || typeof parsed !== "object") {
    return { ok: false, reason: "wrong_shape" };
  }

  const { text, caveat } = parsed as { text?: unknown; caveat?: unknown };
  if (typeof text !== "string" || text.trim().length === 0) {
    return { ok: false, reason: "wrong_shape" };
  }
  const cleanText = text.trim();
  if (cleanText.length > maxTextChars) return { ok: false, reason: "too_long" };

  let cleanCaveat: string | null = null;
  if (caveat != null) {
    if (typeof caveat !== "string") return { ok: false, reason: "wrong_shape" };
    const t = caveat.trim();
    if (t.length > maxCaveatChars) return { ok: false, reason: "too_long" };
    cleanCaveat = t.length > 0 ? t : null;
  }

  // The hard Layer-2 rule: no number the facts don't contain.
  const allowed = allowedNumberTokens(factLines);
  const combined = cleanCaveat ? `${cleanText} ${cleanCaveat}` : cleanText;
  const bad = firstDisallowedNumber(combined, allowed);
  if (bad != null) {
    return { ok: false, reason: "disallowed_number", offendingNumber: bad };
  }

  return { ok: true, narration: { text: cleanText, caveat: cleanCaveat } };
}
