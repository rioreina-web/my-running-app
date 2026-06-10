/**
 * Live re-record mode for eval cassettes.
 *
 * Reads every cassette under `_evals/cassettes/<prompt-name>/`, renders
 * the prompt via the prompt-library (substituting the cassette's
 * `vars`), calls the real model, writes the response back to the
 * cassette, scores it against the rubric, and prints a report.
 *
 * Usage:
 *   # Re-record one prompt's cassettes:
 *   GEMINI_API_KEY=... deno run --allow-net --allow-read --allow-write --allow-env \
 *     _evals/record.ts injury-analysis.v1
 *
 *   # Re-record everything:
 *   GEMINI_API_KEY=... deno run --allow-net --allow-read --allow-write --allow-env \
 *     _evals/record.ts --all
 *
 *   # Re-record one specific cassette:
 *   GEMINI_API_KEY=... deno run --allow-net --allow-read --allow-write --allow-env \
 *     _evals/record.ts injury-analysis.v1 --only 001-bone-stress-reaction
 *
 * Exit code:
 *   0 — all cassettes recorded AND all rubrics passed
 *   1 — provider error OR any rubric failed (cassettes still written —
 *       the developer can review the diff and decide)
 *
 * Cost: ~$0.001/call at Gemini Flash. A full re-record of every
 * cassette is < $0.05. The $50 Cloud Billing budget is the hard ceiling.
 *
 * Not wired into CI. Manual / scheduled only.
 */

import { loadPrompt } from "../_shared/prompt-library.ts";
import { applyRubric } from "./rubric.ts";
import { assertCassetteShape, type Cassette, type ProviderCall } from "./types.ts";
import { callGemini } from "./providers/gemini.ts";

const CASSETTES_DIR = new URL("./cassettes/", import.meta.url).pathname;

function pickProvider(model: string): ProviderCall {
  if (model.startsWith("gemini-")) return callGemini;
  throw new Error(
    `No provider adapter for model "${model}". ` +
      `Supported prefixes: "gemini-". Add an adapter in _evals/providers/ and route it here.`,
  );
}

async function recordOne(path: string, onlyId?: string): Promise<{ pass: boolean; cassetteId: string } | null> {
  const raw = JSON.parse(await Deno.readTextFile(path));
  const cassette: Cassette = assertCassetteShape(raw, path);

  if (onlyId && cassette.id !== onlyId) return null;

  console.log(`\n--- ${cassette.id} (${cassette.prompt_name}) ---`);
  console.log(`  ${cassette.description}`);

  // Stringify all vars — loadPrompt expects string|number; cassette vars
  // are already that type, but the type system can't always see it.
  const vars = cassette.vars as Record<string, string | number>;

  let prompt: string;
  try {
    prompt = loadPrompt(cassette.prompt_name, vars);
  } catch (err) {
    console.error(`  PROMPT LOAD FAILED: ${(err as Error).message}`);
    return { pass: false, cassetteId: cassette.id };
  }

  const provider = pickProvider(cassette.model);

  // The full model input is prompt + optional input (voice memo
  // transcript, chat message, etc.). Mirrors what production sends.
  const fullInput = cassette.input ? prompt + cassette.input : prompt;
  console.log(`  calling ${cassette.model} (prompt ${prompt.length} chars${cassette.input ? ` + input ${cassette.input.length} chars` : ""})...`);

  let response: string;
  let modelUsed: string;
  try {
    const out = await provider({ prompt: fullInput, model: cassette.model });
    response = out.text;
    modelUsed = out.model_used;
  } catch (err) {
    console.error(`  PROVIDER ERROR: ${(err as Error).message}`);
    return { pass: false, cassetteId: cassette.id };
  }

  // Write the fresh response back.
  const updated: Cassette = {
    ...cassette,
    recorded_response: response,
    recorded_at: new Date().toISOString(),
    model: modelUsed,
  };
  await Deno.writeTextFile(path, JSON.stringify(updated, null, 2) + "\n");
  console.log(`  recorded ${response.length} chars, wrote back to cassette`);

  // Score the fresh response.
  const result = applyRubric(cassette.rubric, response);
  if (result.pass) {
    console.log(`  ✓ rubric PASS`);
  } else {
    console.log(`  ✗ rubric FAIL`);
    for (const f of result.failures) console.log(`    └─ ${f}`);
  }
  for (const w of result.warnings) console.log(`    └─ (warn) ${w}`);

  return { pass: result.pass, cassetteId: cassette.id };
}

async function recordPrompt(promptName: string, onlyId?: string): Promise<{ total: number; passed: number; failed: number }> {
  const dir = `${CASSETTES_DIR}${promptName}`;

  let entries: Deno.DirEntry[];
  try {
    entries = [];
    for await (const e of Deno.readDir(dir)) entries.push(e);
  } catch (err) {
    if (err instanceof Deno.errors.NotFound) {
      console.error(`No cassettes directory at ${dir}`);
      return { total: 0, passed: 0, failed: 0 };
    }
    throw err;
  }

  const cassetteFiles = entries
    .filter((e) => e.isFile && e.name.endsWith(".json"))
    .map((e) => `${dir}/${e.name}`)
    .sort();

  let passed = 0, failed = 0, total = 0;
  for (const path of cassetteFiles) {
    const result = await recordOne(path, onlyId);
    if (result === null) continue;
    total++;
    if (result.pass) passed++;
    else failed++;
  }
  return { total, passed, failed };
}

async function listPromptDirs(): Promise<string[]> {
  const out: string[] = [];
  for await (const e of Deno.readDir(CASSETTES_DIR)) {
    if (e.isDirectory) out.push(e.name);
  }
  return out.sort();
}

// ─── CLI ──────────────────────────────────────────────────────────────

const args = Deno.args;
let targetPrompts: string[];
let onlyId: string | undefined;

const onlyIdx = args.indexOf("--only");
if (onlyIdx !== -1) {
  onlyId = args[onlyIdx + 1];
  if (!onlyId) {
    console.error("--only requires a cassette id");
    Deno.exit(2);
  }
}

if (args[0] === "--all") {
  targetPrompts = await listPromptDirs();
} else if (args[0] && !args[0].startsWith("--")) {
  targetPrompts = [args[0]];
} else {
  console.error("Usage:");
  console.error("  deno run --allow-net --allow-read --allow-write --allow-env _evals/record.ts <prompt-name>");
  console.error("  deno run --allow-net --allow-read --allow-write --allow-env _evals/record.ts --all");
  console.error("  deno run --allow-net --allow-read --allow-write --allow-env _evals/record.ts <prompt-name> --only <cassette-id>");
  Deno.exit(2);
}

let grandTotal = 0, grandPassed = 0, grandFailed = 0;
for (const p of targetPrompts) {
  console.log(`\n=== ${p} ===`);
  const r = await recordPrompt(p, onlyId);
  grandTotal += r.total;
  grandPassed += r.passed;
  grandFailed += r.failed;
}

console.log(`\n=== SUMMARY ===`);
console.log(`  ${grandPassed}/${grandTotal} passed  ${grandFailed} failed`);
Deno.exit(grandFailed > 0 ? 1 : 0);
