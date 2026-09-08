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
  | "disallowed_number"
  | "unlicensed_scope";

export type NarrationResult =
  | { ok: true; narration: Narration }
  | {
    ok: false;
    reason: NarrationRejection;
    offendingNumber?: string;
    /** The scope phrase that tripped `unlicensed_scope` — "over 12 miles". */
    offendingScope?: string;
  };

// \u2500\u2500 Scope claims \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500

/**
 * WHY THIS EXISTS. On 2026-08-08 an athlete asked "Look at my long runs over
 * 12 miles, heat, and heart rate \u2014 what do you see". The question routed to
 * `heat_effect`, which has exactly one param (`window_days`) and therefore
 * applied no distance filter at all: it read all 127 runs in the last 90 days.
 * The narration came back "Your long runs over 12 miles show a significant
 * impact from heat" \u2014 and `firstDisallowedNumber` waved it through, because
 * 12 legitimately appears in the facts as "12 s/mi".
 *
 * That is the hole. The number guard asks "does this digit exist somewhere in
 * the facts?" It cannot ask "does this digit mean what the sentence says it
 * means?" A coincidental collision between a pace delta and a distance filter
 * was enough to let the card lie about what it had looked at \u2014 which is worse
 * than a wrong number, because the athlete has no way to detect it.
 *
 * So scope claims get their OWN, much narrower licence. A sentence may only
 * assert a filter ("over N miles", "the last N weeks", "past 90 minutes") when
 * N came from the analyzer\u2019s actual coverage or its actual params \u2014 never
 * merely from the fact lines, and never from the question. Unit families are
 * kept apart on purpose: a 90-day window must not license "over 90 minutes".
 */

export interface AnalysisScope {
  /** `coverage.sessionsUsed` \u2014 what the analyzer actually read. */
  sessionsUsed: number;
  /** `coverage.windowDays` \u2014 how far back it actually looked. */
  windowDays: number;
  /** The coerced params the analyzer actually ran with. */
  params?: Record<string, string | number>;
}

type UnitFamily = "distance" | "duration" | "time_window" | "count";

/** Filter phrases: a qualifier word, a number, a unit. */
const SCOPE_QUALIFIER =
  /\b(?:over|above|greater than|longer than|more than|at least|beyond|past|within|under|below|shorter than|less than|fewer than|only|just|top)\s+(\d+(?:\.\d+)?)\s*\+?\s*(miles?|mi|k|kms?|kilometers?|kilometres?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?|sessions?|runs?|workouts?)\b/gi;

/** The compound form \u2014 "12-mile runs", "20+ mile long runs". */
const HYPHEN_QUALIFIER =
  /\b(\d+(?:\.\d+)?)\s*\+?\s*[-\u2010-\u2015]\s*(miles?|mi|k|kms?|kilometers?|kilometres?|minutes?|mins?|hours?|hrs?|days?|weeks?|months?)\b/gi;

function unitFamily(unit: string): UnitFamily {
  const u = unit.toLowerCase().replace(/s$/, "");
  if (/^(mile|mi|k|km|kilometer|kilometre)$/.test(u)) return "distance";
  if (/^(minute|min|hour|hr)$/.test(u)) return "duration";
  if (/^(day|week|month)$/.test(u)) return "time_window";
  return "count";
}

/** Which family a param name is talking about, by its name. */
function paramFamily(key: string): UnitFamily | "any" {
  const k = key.toLowerCase();
  if (/(mile|distance|km|meter|metre)/.test(k)) return "distance";
  if (/(minute|hour|duration|sec)/.test(k)) return "duration";
  if (/(day|week|month|window|since|range)/.test(k)) return "time_window";
  if (/(count|limit|sessions|runs|top|n_)/.test(k)) return "count";
  // An unrecognised numeric param WAS applied by the analyzer, so licence it
  // everywhere rather than block a narration that is telling the truth.
  return "any";
}

/**
 * The numbers a narration is allowed to use as a FILTER, keyed by unit family.
 * Deliberately much smaller than `allowedNumberTokens` \u2014 that set licenses
 * every digit in the facts, which is exactly how "12 s/mi" licensed
 * "over 12 miles".
 */
export function scopeNumbersAllowed(
  scope: AnalysisScope,
): Record<UnitFamily, Set<string>> {
  const out: Record<UnitFamily, Set<string>> = {
    distance: new Set(),
    duration: new Set(),
    time_window: new Set(),
    count: new Set(),
  };
  const add = (fam: UnitFamily | "any", n: unknown) => {
    const v = typeof n === "number" ? n : Number(n);
    if (!isFinite(v)) return;
    const fams: UnitFamily[] = fam === "any"
      ? ["distance", "duration", "time_window", "count"]
      : [fam];
    for (const f of fams) {
      out[f].add(String(v));
      out[f].add(String(Math.round(v)));
    }
  };

  add("count", scope.sessionsUsed);
  // "90 days" is also "13 weeks" and "3 months" in an athlete\u2019s words.
  add("time_window", scope.windowDays);
  add("time_window", Math.round(scope.windowDays / 7));
  add("time_window", Math.round(scope.windowDays / 30));
  for (const [k, v] of Object.entries(scope.params ?? {})) {
    if (typeof v === "number") add(paramFamily(k), v);
  }
  return out;
}

/**
 * The first filter phrase the analyzer did not actually apply, or null.
 * Returns the phrase verbatim so `analysis_queries` can record what tripped.
 */
export function firstUnlicensedScopeClaim(
  text: string,
  allowed: Record<UnitFamily, Set<string>>,
): string | null {
  for (const re of [SCOPE_QUALIFIER, HYPHEN_QUALIFIER]) {
    re.lastIndex = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(text)) !== null) {
      const n = String(Number(m[1]));
      const fam = unitFamily(m[2]);
      if (!allowed[fam].has(n)) return m[0].trim();
    }
  }
  return null;
}

/**
 * A one-line description of what the analyzer actually covered, for the
 * narration prompt. Giving the model the true scope up front is the cheap
 * half of this fix; `firstUnlicensedScopeClaim` is the half that does not
 * depend on the model complying.
 */
export function describeScope(scope: AnalysisScope): string {
  const numeric = Object.entries(scope.params ?? {})
    .filter(([, v]) => v !== null && v !== undefined && v !== "")
    .map(([k, v]) => `${k}=${v}`);
  const filters = numeric.length > 0
    ? `Filters actually applied: ${numeric.join(", ")}.`
    : "No other filter was applied \u2014 this analysis was NOT narrowed to any distance, workout type, day of week, or subset of runs.";
  return `${scope.sessionsUsed} sessions over the last ${scope.windowDays} days. ${filters}`;
}

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
  scope?: AnalysisScope,
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

  // The second, narrower gate. A number can be present in the facts and still
  // be a lie about what was measured \u2014 see the header on `AnalysisScope`.
  if (scope) {
    const badScope = firstUnlicensedScopeClaim(
      combined,
      scopeNumbersAllowed(scope),
    );
    if (badScope != null) {
      return { ok: false, reason: "unlicensed_scope", offendingScope: badScope };
    }
  }

  return { ok: true, narration: { text: cleanText, caveat: cleanCaveat } };
}
