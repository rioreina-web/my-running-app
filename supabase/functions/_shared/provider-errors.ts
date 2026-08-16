/**
 * _shared/provider-errors.ts — "is this failure the upstream model's fault?"
 *
 * One classifier, shared by every retry path, for the single question that
 * decides whether a failed job should burn its retry budget:
 *
 *   Did WE do something wrong, or did the model provider run out of money?
 *
 * WHY THIS EXISTS (2026-08-13). Gemini prepay credits ran dry at ~14:00 UTC.
 * `process-training-memo` collapsed the provider's 429 into its catch-all
 * HTTP 500, so `drain-voice-processing-jobs` saw a generic server error,
 * treated it as retryable-but-countable, and burned all three attempts in
 * three minutes (14:00 / 14:01 / 14:03) on a 30s→60s backoff. The job went
 * permanently `failed`, the athlete got "we couldn't transcribe it. Tap to
 * try again" — for an outage no retry of theirs could fix — and the memo sat
 * dead for seven hours until it was retried by hand. The same lapse stranded
 * five `workout_parse_jobs` at `attempts = 3`. Second occurrence in a week
 * (the first was 2026-08-06).
 *
 * The rule this encodes: **a provider billing/quota outage is not the job's
 * fault, so it must not consume the job's finite retry budget.** Callers
 * still back off — hard, because an outage is minutes-to-hours, not seconds
 * — but the attempt counter stays put, so the work is still claimable when
 * credits come back and self-heals with nobody watching.
 *
 * THE TRAP THIS AVOIDS. Matching a bare "429" would be wrong. Our own
 * `rateLimit.ts` (`enforceFeatureRateLimit`) and `llm-budget.ts` both return
 * 429 on purpose — those are deliberate app-level ceilings and they SHOULD
 * count as attempts, since retrying doesn't help and the athlete really has
 * hit a limit. Conflating the two was called out explicitly in the
 * 2026-08-06 outage runbook. So a bare 429 is never enough on its own: we
 * require either an unambiguous billing/quota phrase, or a provider marker
 * (their hostname / SDK error tag) alongside the 429.
 */

/** Marker written into `training_logs.processing_error`, job `last_error`, and
 *  the `reason` field of the 503 body, so downstream readers — the drain, and
 *  the iOS failure classifier — can tell an outage from a genuine
 *  transcription failure without parsing provider prose.
 *  Grep for this string before changing it; iOS matches on it too. */
export const PROVIDER_EXHAUSTED_MARKER = "provider_unavailable";

/** Billing- or quota-exhaustion phrases that are unambiguous on their own,
 *  across Gemini / OpenAI / Groq. None of these strings can be produced by
 *  our own rate limiters. */
const EXHAUSTION_PHRASES = [
  // Our own canonical marker — so a re-classified 503 body (which carries the
  // marker rather than the provider's prose) is still recognised downstream.
  PROVIDER_EXHAUSTED_MARKER,
  "prepayment credits are depleted",
  "credits are depleted",
  "out of credits",
  "insufficient_quota",
  "insufficient quota",
  "exceeded your current quota",
  "quota exceeded",
  "resource_exhausted",
  "billing account",
  "billing hard limit",
];

/** Markers that identify the text as coming FROM a model provider rather than
 *  from our own stack. Only these license a bare 429 to count as exhaustion. */
const PROVIDER_MARKERS = [
  "generativelanguage.googleapis.com",
  "googlegenerativeai error",
  "api.openai.com",
  "api.groq.com",
  "api.anthropic.com",
];

/**
 * True when `text` is a model provider telling us we are out of money or
 * quota. Deliberately conservative: our own 429s must return false.
 */
export function isProviderExhaustedText(text: string | null | undefined): boolean {
  if (!text) return false;
  const t = text.toLowerCase();

  if (EXHAUSTION_PHRASES.some((p) => t.includes(p))) return true;

  // A bare 429 counts only when it demonstrably came from a provider.
  const has429 = t.includes("429") || t.includes("too many requests");
  return has429 && PROVIDER_MARKERS.some((m) => t.includes(m));
}

/** `isProviderExhaustedText` for a caught value of unknown shape. */
export function isProviderExhausted(err: unknown): boolean {
  if (err == null) return false;
  const text = err instanceof Error
    ? `${err.message} ${(err as { stack?: string }).stack ?? ""}`
    : typeof err === "string"
    ? err
    : (() => {
      try {
        return JSON.stringify(err);
      } catch {
        return String(err);
      }
    })();
  return isProviderExhaustedText(text);
}

/**
 * The status a handler should return when a model provider is exhausted.
 *
 * 503, not 500 and not 429. 500 is what caused this bug — indistinguishable
 * from a real code fault. 429 would collide with our own rate-limit ceilings,
 * which callers must keep treating as countable. 503 + `Retry-After` says
 * exactly what is true: the dependency is down, come back later.
 */
export const PROVIDER_EXHAUSTED_STATUS = 503;
