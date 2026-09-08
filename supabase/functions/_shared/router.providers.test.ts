/**
 * Unit tests for the router's provider selection and failure handling.
 *
 * Run: deno test --allow-env supabase/functions/_shared/router.providers.test.ts
 *
 * What this guards against — all of it drawn from the 2026-09-08 outage,
 * where Groq retired `llama-3.1-8b-instant` and every simple coach
 * question returned "I'm having trouble connecting to my AI backend":
 *   1. A hard-coded Groq model sneaking back into the simple tier. Groq
 *      is opt-in via GROQ_SIMPLE_MODEL; unset means Gemini.
 *   2. The simple tier running Gemini on a 400-token output cap, which
 *      2.5 Flash can spend entirely on thinking and return nothing.
 *   3. A provider having no failover partner, which is what turned one
 *      dead model into a dead feature.
 *   4. Retrying a permanent error (404 retired model, 401 bad key) —
 *      two wasted seconds before failing identically.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";

import {
  getBestAvailableModel,
  getFallbackConfig,
  getModelConfig,
  isRetryableModelError,
} from "./router.ts";

// ── Helpers ──────────────────────────────────────────────

/** Run `fn` with the given env vars set, restoring the originals after. */
function withEnv(vars: Record<string, string | null>, fn: () => void): void {
  const previous = new Map<string, string | undefined>();
  for (const [key, value] of Object.entries(vars)) {
    previous.set(key, Deno.env.get(key));
    if (value === null) Deno.env.delete(key);
    else Deno.env.set(key, value);
  }
  try {
    fn();
  } finally {
    for (const [key, value] of previous) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  }
}

const GEMINI_ONLY = { GEMINI_API_KEY: "test-gemini", GROQ_API_KEY: null, GROQ_SIMPLE_MODEL: null };
const BOTH = { GEMINI_API_KEY: "test-gemini", GROQ_API_KEY: "test-groq", GROQ_SIMPLE_MODEL: "some-groq-model" };

// ── getModelConfig ───────────────────────────────────────

Deno.test("simple tier runs on Gemini when Groq is not opted in", () => {
  withEnv(GEMINI_ONLY, () => {
    const config = getModelConfig("simple");
    assertEquals(config.provider, "gemini");
  });
});

Deno.test("Gemini-backed simple tier leaves output budget for thinking tokens", () => {
  withEnv(GEMINI_ONLY, () => {
    // 400 was the Groq-era cap. On 2.5 Flash, thinking spends the same
    // budget, so anything that tight can return an empty answer.
    assert(getModelConfig("simple").maxTokens >= 1000);
  });
});

Deno.test("simple tier uses the Groq model named by GROQ_SIMPLE_MODEL", () => {
  withEnv(BOTH, () => {
    const config = getModelConfig("simple");
    assertEquals(config.provider, "groq");
    assertEquals(config.model, "some-groq-model");
  });
});

Deno.test("a blank GROQ_SIMPLE_MODEL is not an opt-in", () => {
  withEnv({ ...BOTH, GROQ_SIMPLE_MODEL: "   " }, () => {
    assertEquals(getModelConfig("simple").provider, "gemini");
  });
});

// ── getFallbackConfig ────────────────────────────────────

Deno.test("Groq fails over to Gemini", () => {
  withEnv(BOTH, () => {
    const fallback = getFallbackConfig(getModelConfig("simple"));
    assertEquals(fallback?.provider, "gemini");
  });
});

Deno.test("Gemini fails over to Groq when Groq is opted in", () => {
  withEnv(BOTH, () => {
    const fallback = getFallbackConfig(getModelConfig("moderate"));
    assertEquals(fallback?.provider, "groq");
    assertEquals(fallback?.model, "some-groq-model");
  });
});

Deno.test("no fallback is offered when the other provider has no key", () => {
  withEnv(GEMINI_ONLY, () => {
    assertEquals(getFallbackConfig(getModelConfig("moderate")), null);
  });
});

// ── getBestAvailableModel ────────────────────────────────

Deno.test("an unconfigured primary provider routes to the other one", () => {
  // Groq opted in, but only Gemini has a key.
  withEnv({ GEMINI_API_KEY: "test-gemini", GROQ_API_KEY: null, GROQ_SIMPLE_MODEL: "some-groq-model" }, () => {
    const { config } = getBestAvailableModel("simple");
    assertEquals(config.provider, "gemini");
  });
});

Deno.test("no providers configured is an error, not a silent bad call", () => {
  withEnv({ GEMINI_API_KEY: null, GROQ_API_KEY: null, GROQ_SIMPLE_MODEL: null }, () => {
    let threw = false;
    try {
      getBestAvailableModel("moderate");
    } catch {
      threw = true;
    }
    assert(threw);
  });
});

// ── isRetryableModelError ────────────────────────────────

Deno.test("permanent provider errors are not retried", () => {
  // The exact shape callGroq throws for a retired model.
  const retired = Object.assign(new Error("Groq API error: 404"), { status: 404 });
  assertEquals(isRetryableModelError(retired), false);
  assertEquals(isRetryableModelError(Object.assign(new Error("bad key"), { status: 401 })), false);
  // The Gemini SDK only reports the status in the message text.
  assertEquals(
    isRetryableModelError(new Error("[GoogleGenerativeAI Error]: [404 Not Found] model not found")),
    false,
  );
});

Deno.test("transient provider errors are retried", () => {
  assertEquals(isRetryableModelError(Object.assign(new Error("rate limited"), { status: 429 })), true);
  assertEquals(isRetryableModelError(Object.assign(new Error("upstream"), { status: 503 })), true);
  // Timeouts and network blips carry no status at all.
  assertEquals(isRetryableModelError(new Error("Gemini timed out after 20000ms")), true);
});
