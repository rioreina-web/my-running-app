/**
 * Scores the workout-shorthand parser against this coach's real plans.
 *
 * The corpus is 137 unique workouts lifted verbatim from six seasons of
 * spreadsheets (Fall23, Fall24, Spring24, SoS24, Spring25, Spring26), shared
 * with the web regression suite at
 * `web/tests/fixtures/coach-shorthand-corpus.json`. It is the only honest
 * measure this parser has: the grammar scored 24% against it on the day it was
 * first pointed at real data, having looked fine for months.
 *
 * Run:
 *   GEMINI_API_KEY=... deno run --allow-env --allow-net --allow-read \
 *     supabase/functions/_evals/workout-shorthand-eval.ts [--limit N] [--grammar]
 *
 * Costs real money (gemini-2.5-flash-lite, ~137 calls). --limit N samples.
 */

import { parseWithModel } from "../_shared/workout-shorthand-llm.ts";
import { validateSteps } from "../_shared/workout-step-validator.ts";

const CORPUS = new URL(
  "../../../web/tests/fixtures/coach-shorthand-corpus.json",
  import.meta.url,
);

interface Entry { sheet: string; input: string }

const args = Deno.args;
const limitFlag = args.indexOf("--limit");
const limit = limitFlag >= 0 ? Number(args[limitFlag + 1]) : Infinity;
const concurrency = 6;

const corpus: Entry[] = JSON.parse(await Deno.readTextFile(CORPUS)).slice(0, limit);

interface Row {
  input: string;
  sheet: string;
  steps: number;
  warnings: string[];
  unparsed: string[];
  ok: boolean;
  failed: boolean;
}

async function scoreOne(e: Entry): Promise<Row> {
  const llm = await parseWithModel(e.input);
  if (!llm) {
    return { ...e, steps: 0, warnings: ["model unavailable"], unparsed: [], ok: false, failed: true };
  }
  const v = validateSteps(llm.steps, { source: "model", unparsed: llm.unparsed });
  return {
    input: e.input,
    sheet: e.sheet,
    steps: v.steps.length,
    warnings: v.warnings,
    unparsed: v.unparsed,
    ok: v.steps.length > 0 && v.warnings.length === 0 && v.unparsed.length === 0,
    failed: v.steps.length === 0,
  };
}

const rows: Row[] = [];
for (let i = 0; i < corpus.length; i += concurrency) {
  const batch = corpus.slice(i, i + concurrency);
  rows.push(...await Promise.all(batch.map(scoreOne)));
  console.error(`  ${Math.min(i + concurrency, corpus.length)}/${corpus.length}`);
}

const clean = rows.filter((r) => r.ok).length;
const built = rows.filter((r) => r.steps > 0).length;
const nothing = rows.filter((r) => r.failed).length;
const pct = (n: number) => `${Math.round((n / rows.length) * 100)}%`;

console.log(`\n${rows.length} real workouts, model path\n`);
console.log(`  built clean, nothing to report : ${clean}  (${pct(clean)})`);
console.log(`  built a workout at all         : ${built}  (${pct(built)})`);
console.log(`  produced nothing               : ${nothing}`);
console.log(`  total steps emitted            : ${rows.reduce((n, r) => n + r.steps, 0)}`);

const reasons: Record<string, number> = {};
for (const r of rows) {
  for (const w of r.warnings) {
    const k = /no pace|set it before/.test(w) ? "asked about a missing pace"
      : /impossible|out-of-range|misread/.test(w) ? "validator rejected a value"
      : /unknown pace/.test(w) ? "named a zone outside the enum"
      : /dropped|no usable/.test(w) ? "step dropped as unusable"
      : "other";
    reasons[k] = (reasons[k] ?? 0) + 1;
  }
}
console.log("\nwarning reasons:");
for (const [k, v] of Object.entries(reasons).sort((a, b) => b[1] - a[1])) {
  console.log(`  ${String(v).padStart(3)}  ${k}`);
}

const bad = rows.filter((r) => r.failed || r.unparsed.length);
if (bad.length) {
  console.log(`\nneeds a look (${bad.length}):`);
  for (const r of bad.slice(0, 15)) {
    console.log(`  [${r.sheet}] ${r.input.slice(0, 66)}`);
    if (r.unparsed.length) console.log(`      unparsed: ${r.unparsed.join(" | ").slice(0, 70)}`);
  }
}

await Deno.writeTextFile(
  new URL("./workout-shorthand-eval.out.json", import.meta.url),
  JSON.stringify(rows, null, 1),
);
console.log("\nper-workout detail → _evals/workout-shorthand-eval.out.json");
