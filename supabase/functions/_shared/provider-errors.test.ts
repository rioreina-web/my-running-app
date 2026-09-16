/**
 * Tests for the provider-exhaustion classifier.
 *
 * Run: deno test _shared/provider-errors.test.ts
 *
 * The contract that matters: a model provider running out of credit must be
 * recognised (so retry budgets survive an outage), and OUR OWN deliberate
 * 429s must NOT be (so real ceilings still count as attempts). The second
 * half is the one that bites — see the runbook note about conflating
 * `enforceFeatureRateLimit` 429s with provider errors.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isProviderExhausted, isProviderExhaustedText } from "./provider-errors.ts";

// ── The real thing: verbatim text from the 2026-08-13 outage ─────────────

const GEMINI_CREDITS_DEPLETED =
  "[GoogleGenerativeAI Error]: Error fetching from " +
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent: " +
  "[429 Too Many Requests] Your prepayment credits are depleted. Please go to AI Studio at " +
  "https://ai.studio/projects to manage your project and billing.";

Deno.test("recognises the verbatim Gemini credits-depleted 429", () => {
  assert(isProviderExhaustedText(GEMINI_CREDITS_DEPLETED));
});

Deno.test("recognises it wrapped in an Error, as the drain sees it", () => {
  assert(isProviderExhausted(new Error(GEMINI_CREDITS_DEPLETED)));
});

Deno.test("recognises it after the drain's HTTP-prefix wrapping", () => {
  // What actually lands in voice_processing_jobs.last_error.
  assert(isProviderExhaustedText(
    `process-training-memo HTTP 503: {"error":"${GEMINI_CREDITS_DEPLETED}"}`,
  ));
});

Deno.test("recognises OpenAI and Groq exhaustion shapes", () => {
  assert(isProviderExhaustedText(
    "429 insufficient_quota: You exceeded your current quota, please check your plan and billing details.",
  ));
  assert(isProviderExhaustedText(
    "Error fetching from https://api.groq.com/openai/v1/chat/completions: [429 Too Many Requests]",
  ));
});

Deno.test("recognises RESOURCE_EXHAUSTED without a status code", () => {
  assert(isProviderExhaustedText("RESOURCE_EXHAUSTED: quota exceeded for model"));
});

Deno.test("recognises our own 503 body, which carries the marker not the prose", () => {
  // What process-training-memo now answers. The drain classifies the body
  // text, so if this stopped matching, the retry budget would burn again.
  assert(isProviderExhaustedText(
    '{"error":"Analysis provider unavailable.","reason":"provider_unavailable"}',
  ));
});

// ── The trap: our own 429s must NOT match ────────────────────────────────

Deno.test("does NOT match our own feature rate limiter", () => {
  // enforceFeatureRateLimit — a deliberate app ceiling. Retrying won't help
  // and the attempt SHOULD count, so this must stay false.
  assertEquals(
    isProviderExhaustedText(
      '{"error":"Rate limit reached","retry_after_seconds":3600,"limit":20}',
    ),
    false,
  );
});

Deno.test("does NOT match the LLM budget guard's block response", () => {
  assertEquals(
    isProviderExhaustedText("blocked by LLM budget guard at 2026-08-13 14:00:00"),
    false,
  );
  assertEquals(
    isProviderExhaustedText('HTTP 429: {"error":"Daily LLM budget reached"}'),
    false,
  );
});

Deno.test("does NOT match a bare 429 with no provider marker", () => {
  assertEquals(isProviderExhaustedText("HTTP 429 Too Many Requests"), false);
});

Deno.test("does NOT match unrelated failures", () => {
  assertEquals(isProviderExhaustedText("HTTP 500: Processing failed."), false);
  assertEquals(isProviderExhaustedText("network: TypeError: connection refused"), false);
  assertEquals(isProviderExhaustedText("no speech detected in audio"), false);
});

// ── Shape robustness ─────────────────────────────────────────────────────

Deno.test("handles null, undefined and empty input", () => {
  assertEquals(isProviderExhaustedText(null), false);
  assertEquals(isProviderExhaustedText(undefined), false);
  assertEquals(isProviderExhaustedText(""), false);
  assertEquals(isProviderExhausted(null), false);
  assertEquals(isProviderExhausted(undefined), false);
});

Deno.test("handles non-Error thrown values", () => {
  assert(isProviderExhausted({ message: GEMINI_CREDITS_DEPLETED }));
  assert(isProviderExhausted(GEMINI_CREDITS_DEPLETED));
  assertEquals(isProviderExhausted({ code: "ECONNRESET" }), false);
});

Deno.test("is case-insensitive", () => {
  assert(isProviderExhaustedText("YOUR PREPAYMENT CREDITS ARE DEPLETED"));
});
