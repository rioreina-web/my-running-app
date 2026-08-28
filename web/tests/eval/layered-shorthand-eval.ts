/**
 * Scores the SHIPPING behaviour of the workout-shorthand parser: the
 * deterministic grammar first, the model only on what the grammar cannot
 * fully consume, and the shared validator over whatever comes back.
 *
 * Measuring either layer alone is misleading in both directions. The grammar
 * alone leaves the tail unread. The model alone is asked to transcribe
 * "10-12 x K @ HM-5 w/1' rest" — a shape the grammar gets exactly right for
 * free, and one the model occasionally falls into a repetition loop on. Only
 * the layered number describes what a coach experiences.
 *
 * Run:
 *   cd web
 *   GEMINI_API_KEY=... npx tsx tests/eval/layered-shorthand-eval.ts [--limit N]
 *
 * Spends real money (gemini-2.5-flash-lite) on the tail only.
 */

import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { parseWorkoutText } from "../../src/components/coach/workout-nl-parser";
import { buildPrompt, PACE_ZONES } from "../../../supabase/functions/_shared/prompts/workout-shorthand.v1";
import { validateSteps } from "../../../supabase/functions/_shared/workout-step-validator";

const HERE = dirname(fileURLToPath(import.meta.url));
const corpus: Array<{ sheet: string; input: string }> = JSON.parse(
  readFileSync(join(HERE, "..", "fixtures", "coach-shorthand-corpus.json"), "utf8"),
);

const KEY = process.env.GEMINI_API_KEY;
if (!KEY) throw new Error("GEMINI_API_KEY required");

const limitArg = process.argv.indexOf("--limit");
const entries = limitArg >= 0 ? corpus.slice(0, Number(process.argv[limitArg + 1])) : corpus;

const SCHEMA = {
  type: "object",
  properties: {
    steps: {
      type: "array",
      items: {
        type: "object",
        properties: {
          stepType: { type: "string", enum: ["warmup", "active", "recovery", "rest", "cooldown"] },
          durationType: { type: "string", enum: ["distance_miles", "distance_km", "distance_meters", "time_seconds"] },
          durationValue: { type: "number" },
          paceZone: { type: "string", enum: [...PACE_ZONES], nullable: true },
          paceAdjustmentType: { type: "string", enum: ["seconds_per_mile", "percent"], nullable: true },
          paceAdjustmentValue: { type: "number", nullable: true },
          exactPaceSecPerMile: { type: "number", nullable: true },
          repeats: { type: "integer", nullable: true },
          recoveryDurationType: { type: "string", enum: ["distance_miles", "distance_km", "distance_meters", "time_seconds"], nullable: true },
          recoveryDurationValue: { type: "number", nullable: true },
          recoveryIsJog: { type: "boolean", nullable: true },
          note: { type: "string", nullable: true, maxLength: 120 },
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

async function callModel(input: string, temperature: number) {
  const url =
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${KEY}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: buildPrompt(input) }] }],
      generationConfig: {
        temperature,
        maxOutputTokens: 8192,
        responseMimeType: "application/json",
        responseSchema: SCHEMA,
        thinkingConfig: { thinkingBudget: 0 },
      },
    }),
  });
  if (!res.ok) return null;
  const body = await res.json();
  const text = body?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string" || !text.trim()) return null;
  try {
    const parsed = JSON.parse(text);
    return Array.isArray(parsed.steps) ? parsed : null;
  } catch {
    return null;
  }
}

type Layer = "grammar" | "model" | "grammar-fallback";
interface Row { input: string; sheet: string; layer: Layer; steps: number; warnings: number; unparsed: number; clean: boolean; empty: boolean }

async function scoreOne(e: { sheet: string; input: string }): Promise<Row> {
  const g = parseWorkoutText(e.input);
  // `unresolved` must count. When the "no pace" messages moved out of
  // `warnings` and became structured questions, leaving it out of this test
  // reported workouts as clean that still had an unanswered pace.
  const gUnresolved = Object.keys(g.unresolved).length;
  const grammarClean =
    g.steps.length > 0 && g.unparsed.length === 0 && g.warnings.length === 0 && gUnresolved === 0;

  if (grammarClean) {
    return { ...e, layer: "grammar", steps: g.steps.length, warnings: 0, unparsed: 0, clean: true, empty: false };
  }

  const llm = (await callModel(e.input, 0)) ?? (await callModel(e.input, 0.3));
  if (llm) {
    const v = validateSteps(llm.steps, { source: "model", unparsed: llm.unparsed ?? [] });
    // Only prefer the model when it actually did better than the grammar.
    const modelBetter = v.steps.length > 0 &&
      (v.warnings.length + v.unparsed.length) <=
        (g.warnings.length + g.unparsed.length + gUnresolved);
    if (modelBetter) {
      return {
        ...e, layer: "model", steps: v.steps.length,
        warnings: v.warnings.length, unparsed: v.unparsed.length,
        clean: v.warnings.length === 0 && v.unparsed.length === 0, empty: false,
      };
    }
  }

  return {
    ...e, layer: "grammar-fallback", steps: g.steps.length,
    warnings: g.warnings.length + gUnresolved, unparsed: g.unparsed.length,
    clean: false, empty: g.steps.length === 0,
  };
}

// Wrapped in main() rather than using top-level await: tsx transpiles this
// file to CJS, where top-level await is unavailable.
async function main() {
const rows: Row[] = [];
const CONC = 6;
for (let i = 0; i < entries.length; i += CONC) {
  rows.push(...await Promise.all(entries.slice(i, i + CONC).map(scoreOne)));
  process.stderr.write(`  ${Math.min(i + CONC, entries.length)}/${entries.length}\r`);
}

const pct = (n: number) => `${Math.round((n / rows.length) * 100)}%`;
const clean = rows.filter((r) => r.clean).length;
const built = rows.filter((r) => r.steps > 0).length;
const empty = rows.filter((r) => r.empty).length;

console.log(`\n\nLAYERED (grammar → model → grammar fallback) · ${rows.length} real workouts\n`);
console.log(`  built clean, nothing to report : ${clean}  (${pct(clean)})`);
console.log(`  built a workout at all         : ${built}  (${pct(built)})`);
console.log(`  produced nothing               : ${empty}`);
console.log(`  total steps emitted            : ${rows.reduce((n, r) => n + r.steps, 0)}`);
console.log(`\n  answered by grammar (free)     : ${rows.filter((r) => r.layer === "grammar").length}`);
console.log(`  answered by model              : ${rows.filter((r) => r.layer === "model").length}`);
console.log(`  model declined, grammar kept   : ${rows.filter((r) => r.layer === "grammar-fallback").length}`);

const stillEmpty = rows.filter((r) => r.empty);
if (stillEmpty.length) {
  console.log(`\nstill produce nothing (${stillEmpty.length}):`);
  for (const r of stillEmpty) console.log(`  [${r.sheet}] ${r.input.slice(0, 68)}`);
}
}

main();
