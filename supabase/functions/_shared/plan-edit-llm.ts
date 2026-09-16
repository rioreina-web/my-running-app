/**
 * The model half of text-box plan edits.
 *
 * Same shape as `workout-shorthand-llm.ts`: schema-constrained call, no
 * `thinkingConfig` (gemini-3.5-flash-lite 400s on that field — see the note
 * in workout-shorthand-llm.ts), one retry with a temperature bump because a
 * temperature-0 retry reproduces the same failure, and every error path
 * returns null rather than throwing. A plan edit is a mutation the coach is
 * about to approve — if the model is unavailable the right behaviour is "the
 * text box didn't understand that", never a 500.
 */

import { GoogleGenerativeAI } from "https://esm.sh/@google/generative-ai@0.24.0";
import { buildPrompt } from "./prompts/plan-edit.v1.ts";
import type { RawPlanEditResponse } from "./plan-edit-schema.ts";
import type { ScheduledWorkoutRef } from "./plan-edit-schema.ts";
import { describeWorkout } from "./plan-edit-resolver.ts";
import { PACE_ZONE_SET } from "./workout-step-validator.ts";

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    ops: {
      type: "array",
      items: {
        type: "object",
        properties: {
          kind: {
            type: "string",
            enum: [
              "schedule_easy", "schedule_rest", "lighten", "scale_distance",
              "retarget_pace", "swap_session", "move_session",
            ],
          },
          targetHint: { type: "string", maxLength: 80 },
          toMiles: { type: "number", nullable: true },
          paceZone: { type: "string", enum: [...PACE_ZONE_SET], nullable: true },
          adjustmentType: { type: "string", enum: ["seconds_per_mile", "percent"], nullable: true },
          adjustmentValue: { type: "number", nullable: true },
          replacementHint: { type: "string", maxLength: 80, nullable: true },
          toDayHint: { type: "string", maxLength: 40, nullable: true },
        },
        required: ["kind", "targetHint"],
      },
    },
    unparsed: { type: "array", items: { type: "string" } },
  },
  required: ["ops"],
};

export interface PlanEditLlmOpts {
  apiKey?: string;
  todayHint?: string;
  model?: string;
  timeoutMs?: number;
}

export function formatWeekForPrompt(week: ScheduledWorkoutRef[]): string {
  if (!week.length) return "(no sessions in range)";
  return week.map((w) => `  - ${describeWorkout(w)}`).join("\n");
}

export async function parsePlanEdit(
  input: string,
  week: ScheduledWorkoutRef[],
  opts: PlanEditLlmOpts = {},
): Promise<RawPlanEditResponse | null> {
  return (await attempt(input, week, opts, 0)) ?? (await attempt(input, week, opts, 0.3));
}

async function attempt(
  input: string,
  week: ScheduledWorkoutRef[],
  opts: PlanEditLlmOpts,
  temperature: number,
): Promise<RawPlanEditResponse | null> {
  const apiKey = opts.apiKey ?? Deno.env.get("GEMINI_API_KEY");
  if (!apiKey) return null;

  try {
    const genAI = new GoogleGenerativeAI(apiKey);
    const model = genAI.getGenerativeModel({
      model: opts.model ?? Deno.env.get("PLAN_EDIT_MODEL") ?? "gemini-3.5-flash-lite",
      generationConfig: {
        temperature,
        maxOutputTokens: 4096,
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA,
      } as Record<string, unknown>,
    });

    const call = model.generateContent({
      contents: [{
        role: "user",
        parts: [{ text: buildPrompt(input, formatWeekForPrompt(week), opts.todayHint) }],
      }],
    });
    // Cleared in both outcomes — an uncleared timer outlives the call when
    // the API responds first, which Deno's test sanitizer (rightly) flags as
    // a leak and would otherwise keep a process alive past its work.
    // ReturnType<typeof setTimeout>: Node typings from npm:@sentry/deno make
    // setTimeout return `Timeout` under `deno check` (same fix as
    // workout-shorthand-llm.ts).
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
    const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
    if (fenced) text = fenced[1].trim();
    if (!text) return null;

    const parsed = JSON.parse(text) as { ops?: unknown; unparsed?: unknown };
    if (!Array.isArray(parsed.ops)) return null;

    return {
      ops: parsed.ops, // untyped here on purpose — plan-edit-validator.ts is the only trust boundary
      unparsed: Array.isArray(parsed.unparsed) ? parsed.unparsed.filter((u) => typeof u === "string") : [],
    };
  } catch (err) {
    console.error("[plan-edit-llm] falling back to nothing understood:", String(err));
    return null;
  }
}
