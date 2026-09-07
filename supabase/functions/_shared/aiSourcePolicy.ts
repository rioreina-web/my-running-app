/**
 * One chokepoint deciding which workout rows may enter an LLM context.
 *
 * WHY THIS EXISTS
 * ---------------
 * Two separate obligations land on the same question — "where did this row
 * come from, and am I allowed to put it in a prompt?" — so they share one
 * gate rather than growing two:
 *
 *   1. Strava API Agreement §5.3 (effective 2026-06-01) prohibits using
 *      Strava API data "in connection with the development, training,
 *      evaluation, or operation of any AI Application", and explicitly names
 *      "ingestion into a context window or working memory". As of 2026-08-24,
 *      204 of 307 training_logs rows are `strava` or `strava_backfill`, and
 *      every one of them reaches coaching-agent, the daily read, workout
 *      insights and Ask narration.
 *
 *   2. App Review 5.1.3 requires explicit consent before HealthKit-derived
 *      data goes to a third party. HealthKit workout rows land as
 *      `auto_sync`; HealthKit biometrics are gated separately (they do not
 *      flow through training_logs at all — see aiBiometricsAllowed).
 *
 * DEFAULT IS OFF, DELIBERATELY
 * ----------------------------
 * `AI_EXCLUDED_SOURCES` ships EMPTY, so this is a no-op and today's behaviour
 * is bit-for-bit unchanged. Turning it on is a product/legal decision with a
 * real cost — excluding Strava drops the coach from 307 context rows to 103 —
 * and that call is the owner's, not this module's. What this module provides
 * is the switch, in one place, already threaded through the callers.
 *
 * HOW TO FLIP IT
 * --------------
 * Either edit the set below, or set the env var without a code change:
 *
 *     supabase secrets set AI_EXCLUDED_SOURCES="strava,strava_backfill"
 *
 * The env var wins when present. An empty string means "exclude nothing" and
 * is distinct from unset — both currently behave the same, but the explicit
 * empty value is how you pin "we decided: no exclusions".
 *
 * WHAT THIS IS NOT
 * ----------------
 * This filters what goes INTO a prompt. It does not delete rows, does not
 * touch what the athlete sees, and does not affect any deterministic maths —
 * fitness prediction, pace zones, load, ACWR and every Ask analyzer keep
 * reading the full history. Excluding a source from the model's context does
 * not exclude it from the product.
 */

/** Compile-time default. Empty = no exclusions = today's behaviour. */
const DEFAULT_EXCLUDED_SOURCES: readonly string[] = [
  // "strava",
  // "strava_backfill",
];

function readEnvOverride(): string[] | null {
  // deno-lint-ignore no-explicit-any
  const env = (globalThis as any).Deno?.env;
  if (!env?.get) return null;
  const raw = env.get("AI_EXCLUDED_SOURCES");
  if (raw === undefined || raw === null) return null;
  return raw.split(",").map((s: string) => s.trim()).filter((s: string) => s.length > 0);
}

/** The active exclusion set. Read fresh so tests and secrets both take effect. */
export function excludedSources(): ReadonlySet<string> {
  return new Set(readEnvOverride() ?? DEFAULT_EXCLUDED_SOURCES);
}

/** True when at least one source is being withheld from model context. */
export function aiSourcePolicyActive(): boolean {
  return excludedSources().size > 0;
}

/**
 * Filter rows before they reach a prompt builder.
 *
 * A row with a null/undefined/empty `source` is KEPT. Unknown provenance is
 * not evidence of a prohibited provenance, and silently dropping unlabelled
 * rows would quietly degrade the coach for a reason nobody could see. If you
 * need the opposite, make the source NOT NULL first.
 */
export function rowsForAiContext<T extends { source?: string | null }>(
  rows: readonly T[] | null | undefined,
): T[] {
  if (!rows || rows.length === 0) return [];
  const excluded = excludedSources();
  if (excluded.size === 0) return [...rows];
  return rows.filter((r) => {
    const s = r?.source;
    if (s === null || s === undefined || s === "") return true;
    return !excluded.has(s);
  });
}

/**
 * How many rows the policy withheld. Log this next to any filtered read —
 * a context that silently shrank by two-thirds must be visible in the logs,
 * or the next person debugging "why did the coach get vague" has no thread
 * to pull. Never log the rows themselves.
 */
export function withheldCount<T extends { source?: string | null }>(
  rows: readonly T[] | null | undefined,
): number {
  if (!rows || rows.length === 0) return 0;
  return rows.length - rowsForAiContext(rows).length;
}

/**
 * Whether HealthKit-derived biometrics (sleep, HRV, resting HR) may be sent
 * to a model for this athlete.
 *
 * Separate from the source set on purpose: biometrics never pass through
 * training_logs, so they carry no `source` column to filter on, and the
 * obligation is different — Apple wants per-athlete CONSENT, not a blanket
 * policy. Consent lives in athlete_settings.ai_health_consent_at.
 *
 * Fails CLOSED: no consent row, no consent. A missing record is not
 * permission, and the failure mode of being too cautious is a slightly less
 * specific paragraph, while the failure mode of being too permissive is
 * shipping health data to a third party without the consent Apple requires.
 */
export function aiBiometricsAllowed(
  settings: { ai_health_consent_at?: string | null } | null | undefined,
): boolean {
  return Boolean(settings?.ai_health_consent_at);
}
