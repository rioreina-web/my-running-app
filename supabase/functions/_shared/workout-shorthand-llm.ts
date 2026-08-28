/**
 * The model half of `parse-workout-shorthand`.
 *
 * Layered on purpose:
 *
 *   1. the deterministic grammar answers first when it is confident — free,
 *      <10ms, offline, and unit-testable;
 *   2. this runs only on what the grammar could not fully consume;
 *   3. `validateSteps` re-checks whatever comes back before it can be a step.
 *
 * Output is schema-constrained (`responseSchema`), so the model cannot return
 * prose, a stray unit, or a pace zone outside the enum. That matters beyond
 * tidiness: `parse-training-plan` carries a hand-written `repairTruncatedJson`
 * that counts brackets to salvage malformed replies, which is the exact class
 * of problem a response schema removes.
 *
 * Failure is never fatal. No key, no budget, a timeout, a refusal — every path
 * returns null and the caller keeps the deterministic parse. This coach has
 * already lost a feature for two days to depleted Gemini credits; the parser
 * must get quieter when the model is unavailable, not break.
 */

import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { buildPrompt, PACE_ZONES } from "./prompts/workout-shorthand.v1.ts";
import type { RawStep } from "./workout-step-validator.ts";

export interface LlmParseResult {
  steps: RawStep[];
  unparsed: string[];
  workoutNote: string | null;
}

// Gemini's schema dialect (OpenAPI subset). `nullable` is load-bearing here:
// it is what lets the model say "the coach wrote no pace" instead of picking
// one, which is the single most important behaviour in this whole path.
const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    steps: {
      type: "array",
      items: {
        type: "object",
        properties: {
          stepType: { type: "string", enum: ["warmup", "active", "recovery", "rest", "cooldown"] },
          durationType: {
            type: "string",
            enum: ["distance_miles", "distance_km", "distance_meters", "time_seconds"],
          },
          durationValue: { type: "number" },
          paceZone: { type: "string", enum: [...PACE_ZONES], nullable: true },
          paceAdjustmentType: { type: "string", enum: ["seconds_per_mile", "percent"], nullable: true },
          paceAdjustmentValue: { type: "number", nullable: true },
          exactPaceSecPerMile: { type: "number", nullable: true },
          repeats: { type: "integer", nullable: true },
          recoveryDurationType: {
            type: "string",
            enum: ["distance_miles", "distance_km", "distance_meters", "time_seconds"],
            nullable: true,
          },
          recoveryDurationValue: { type: "number", nullable: true },
          recoveryIsJog: { type: "boolean", nullable: true },
          note: { type: "string", nullable: true, maxLength: 120 },
          // CLOSED vocabulary, deliberately. As free text this was where the
          // model looped: on "cutdown" inputs it wrote the same paragraph of
          // hedging over and over until it exhausted maxOutputTokens and
          // returned unterminated JSON. An enum makes that unrepresentable.
          unresolved: { type: "string", enum: ["no_pace_written", "effort_word_not_a_zone", "progression_without_paces", "ambiguous"], nullable: true },
        },
        required: ["stepType", "durationType", "durationValue"],
      },
    },
    workoutNote: { type: "string", nullable: true },
    unparsed: { type: "array", items: { type: "string" } },
  },
  required: ["steps"],
};

export interface LlmOpts {
  apiKey?: string;
  todayHint?: string;
  model?: string;
  timeoutMs?: number;
}

export async function parseWithModel(
  input: string,
  opts: LlmOpts = {},
): Promise<LlmParseResult | null> {
  // One retry, and it MUST vary the temperature. The observed failure is a
  // repetition loop that runs past maxOutputTokens and returns unterminated
  // JSON; at temperature 0 a retry reproduces the identical loop and buys
  // nothing. A small nudge breaks it. Never more than one retry — a coach is
  // waiting, and the grammar's answer is right there as a fallback.
  return (await attempt(input, opts, 0)) ?? (await attempt(input, opts, 0.3));
}

async function attempt(
  input: string,
  opts: LlmOpts,
  temperature: number,
): Promise<LlmParseResult | null> {
  const apiKey = opts.apiKey ?? Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return null;

  try {
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      // 2.5-flash-lite is closed to new API keys and 404s for this project.
      // Overridable so the eval can pin a model without a redeploy.
      model: opts.model ?? Deno.env.get("WORKOUT_PARSE_MODEL") ?? "gemini-3.5-flash-lite",
      generationConfig: {
        temperature,
        maxOutputTokens: 8192,
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA,
        // NOTE: no `thinkingConfig`. gemini-2.5 needed `thinkingBudget: 0`
        // because it spent thinking tokens out of maxOutputTokens before
        // emitting a character; 3.5-flash-lite rejects the field outright with
        // a bare "400 Request contains an invalid argument" that names nothing.
        // The 8192-token ceiling is ample for this task without it.
      } as Record<string, unknown>,
    });

    const call = model.generateContent({
      contents: [{ role: "user", parts: [{ text: buildPrompt(input, opts.todayHint) }] }],
    });
    // Cleared on both outcomes — an uncleared timer outlives a call that
    // resolves before the timeout, which is a real leak on a long-lived
    // Deno Deploy isolate (found while adding the same pattern in
    // plan-edit-llm.ts and Deno's test sanitizer caught it there).
    let timer: number | undefined;
    const timeout = new Promise<never>((_, reject) => {
      timer = setTimeout(() => reject(new Error("timeout")), opts.timeoutMs ?? 20_000);
    });
    let result: Awaited<typeof call>;
    try {
      result = await Promise.race([call, timeout]);
    } finally {
      clearTimeout(timer);
    }

    let text = result.response.text().trim();
    // The schema should make fences impossible; strip them anyway rather than
    // lose a good parse to a stray ```json.
    const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fenced) text = fenced[1].trim();
    if (!text) return null;

    const parsed = JSON.parse(text) as {
      steps?: unknown;
      unparsed?: unknown;
      workoutNote?: unknown;
    };
    if (!Array.isArray(parsed.steps)) return null;

    return {
      steps: parsed.steps as RawStep[],
      unparsed: Array.isArray(parsed.unparsed) ? parsed.unparsed.filter((u) => typeof u === "string") : [],
      workoutNote: typeof parsed.workoutNote === "string" && parsed.workoutNote.trim()
        ? parsed.workoutNote.trim()
        : null,
    };
  } catch (err) {
    console.error("[workout-shorthand-llm] falling back to grammar:", String(err));
    return null;
  }
}
