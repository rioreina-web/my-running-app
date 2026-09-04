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
import { buildPrompt, RESPONSE_SCHEMA } from "./prompts/workout-shorthand.v1.ts";
import type { RawStep } from "./workout-step-validator.ts";

export interface LlmParseResult {
  steps: RawStep[];
  unparsed: string[];
  workoutNote: string | null;
}

// Gemini's schema dialect (OpenAPI subset). `nullable` is load-bearing here:
// it is what lets the model say "the coach wrote no pace" instead of picking
// one, which is the single most important behaviour in this whole path.

export interface LlmOpts {
  apiKey?: string;
  todayHint?: string;
  model?: string;
  timeoutMs?: number;
}

/**
 * Did this answer keep every offset the coach wrote?
 *
 * `RawStep` carries the model's flat schema fields, so this reads those rather
 * than the validated shape — the point is to catch a bad answer BEFORE it is
 * accepted, not after.
 */
function keptItsOffsets(input: string, steps: RawStep[]): boolean {
  const carried = steps.map((s) => {
    const v = (s as { paceAdjustmentValue?: number | null }).paceAdjustmentValue;
    const t = (s as { paceAdjustmentType?: string | null }).paceAdjustmentType;
    if (v == null || v === 0) return null;
    return `${v > 0 ? "+" : "-"}${Math.abs(v)}${t === "percent" ? "%" : ""}`;
  });
  const written = input.matchAll(
    /(?:MP|HMP?|LT|5k|10k|3k|mile|marathon|threshold|tempo)?\s*(?<![\d])([+-])(\d+(?:\.\d+)?)\s*(%)?(?!['′"″\d])/gi,
  );
  for (const m of written) {
    if (!carried.includes(`${m[1]}${m[2]}${m[3] ? "%" : ""}`)) return false;
  }
  return true;
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
  //
  // The retry now also fires on a SILENTLY WRONG answer, not just an unparseable
  // one. Measured 2026-08-28: on "16 x K alternating MP-3% & MP+5%" — its own
  // worked example — flash-lite returned sixteen steps at plain MP on two runs
  // of three, and flash did the same, every time reporting no error. A dropped
  // offset is not a cosmetic loss: it turns eight hard kilometres and eight
  // floats into sixteen identical ones. Since the same call succeeds sometimes,
  // a second roll at a different temperature is worth one round trip.
  const first = await attempt(input, opts, 0);
  if (first && keptItsOffsets(input, first.steps)) return first;

  const second = await attempt(input, opts, 0.3);
  if (second && keptItsOffsets(input, second.steps)) return second;

  // Neither kept them. Prefer whichever answered at all — the caller marks the
  // affected steps unresolved rather than presenting this as a clean parse.
  return second ?? first;
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
    // ReturnType<typeof setTimeout>, not `number`: _shared/sentry.ts pulls in
    // npm:@sentry/deno, whose Node typings make setTimeout return `Timeout`
    // under `deno check` — which is what turned the Edge CI job red.
    let timer: ReturnType<typeof setTimeout> | undefined;
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
