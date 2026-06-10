/**
 * Gemini provider adapter for live-mode eval recording.
 *
 * Why a thin shim and not the GoogleGenerativeAI client directly: the
 * provider interface lets us swap implementations (mock for tests,
 * Anthropic for fitness-predictor, Groq for `coaching-agent-simple`)
 * without changing the runner. Each provider exports `callModel`
 * matching the `ProviderCall` contract in ../types.ts.
 *
 * Default model: `gemini-2.5-flash`. Override per cassette via the
 * `model` field — when the cassette pins a model, that's used.
 *
 * Cost note: this is called by `record.ts` only, never by CI. The $50
 * Cloud Billing budget is the hard ceiling. A full re-record of every
 * cassette in this repo is < 50 calls × ~$0.001/call = $0.05.
 */

import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.21.0";
import type { ProviderCall } from "../types.ts";

export const callGemini: ProviderCall = async ({ prompt, model = "gemini-2.5-flash", temperature = 0.2 }) => {
  const apiKey = Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) {
    throw new Error(
      "GEMINI_API_KEY is required for live eval recording. " +
        "Set it in your local env (it should NOT be in CI — live recordings are manual).",
    );
  }

  const genAI = new GoogleGenerativeAI(apiKey);
  const m = genAI.getGenerativeModel({
    model,
    generationConfig: {
      temperature,
      // Mirror the cap most production callers use. Cassettes that need
      // a longer response (training-analysis Pro) can lift this via the
      // cassette's `model` field once we add per-prompt overrides.
      maxOutputTokens: 4096,
    },
  });

  const result = await m.generateContent(prompt);
  return {
    text: result.response.text(),
    model_used: model,
  };
};
