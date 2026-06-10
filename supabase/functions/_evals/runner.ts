/**
 * Eval runner — walks cassette files, applies rubrics, aggregates into
 * a per-prompt report.
 *
 * Replay mode (default): cassette's `recorded_response` is scored
 * against the rubric. No network. Fast. CI uses this.
 *
 * Live mode (Day 2 work — not yet wired): re-invokes the model against
 * the prompt template + vars, writes the new response back to the
 * cassette, then scores. Manual / scheduled only.
 */

import { applyRubric } from "./rubric.ts";
import { assertCassetteShape, type Cassette, type CassetteResult, type EvalReport } from "./types.ts";

const CASSETTES_DIR = new URL("./cassettes/", import.meta.url).pathname;

/** Load every cassette under `cassettes/<prompt_name>/`. */
export async function loadCassettesForPrompt(promptName: string): Promise<Cassette[]> {
  const dir = `${CASSETTES_DIR}${promptName}`;
  const cassettes: Cassette[] = [];

  let entries: AsyncIterable<Deno.DirEntry>;
  try {
    entries = Deno.readDir(dir);
  } catch (err) {
    if (err instanceof Deno.errors.NotFound) {
      return []; // No cassettes yet — surfaced as warning by the report.
    }
    throw err;
  }

  for await (const entry of entries) {
    if (!entry.isFile || !entry.name.endsWith(".json")) continue;
    const path = `${dir}/${entry.name}`;
    const raw = JSON.parse(await Deno.readTextFile(path));
    cassettes.push(assertCassetteShape(raw, entry.name));
  }

  // Stable order — reports are easier to diff this way.
  cassettes.sort((a, b) => a.id.localeCompare(b.id));
  return cassettes;
}

/**
 * Run every cassette for one prompt against its rubric in replay mode.
 *
 * Cassettes with an empty `recorded_response` are treated as STUBS —
 * pending live recording via `_evals/record.ts`. Stubs warn but don't
 * fail. This lets a developer check in the rubric + vars + input shape
 * for review before paying for a live recording.
 *
 * Once `recorded_response` is filled in, the rubric assertions kick in
 * normally. The aggregate report exposes `skipped` for visibility.
 */
export function runReportForCassettes(
  promptName: string,
  cassettes: Cassette[],
): EvalReport {
  const results: CassetteResult[] = cassettes.map((c) => {
    if (c.recorded_response.length === 0) {
      return {
        cassette_id: c.id,
        prompt_name: c.prompt_name,
        result: {
          pass: true,
          failures: [],
          warnings: [
            `cassette is a stub (empty recorded_response). Run \`_evals/record.ts ${c.prompt_name} --only ${c.id}\` with GEMINI_API_KEY set to record.`,
          ],
          skipped: true,
        },
      };
    }
    return {
      cassette_id: c.id,
      prompt_name: c.prompt_name,
      result: applyRubric(c.rubric, c.recorded_response),
    };
  });

  return {
    prompt_name: promptName,
    total: results.length,
    passed: results.filter((r) => r.result.pass && !("skipped" in r.result && r.result.skipped)).length,
    failed: results.filter((r) => !r.result.pass).length,
    skipped: results.filter((r) => "skipped" in r.result && r.result.skipped).length,
    cassettes: results,
  };
}

/** Pretty-print a report for logs / CI output. */
export function formatReport(report: EvalReport): string {
  const lines: string[] = [
    `Eval report — ${report.prompt_name}`,
    `  Total: ${report.total}  Passed: ${report.passed}  Failed: ${report.failed}  Skipped: ${report.skipped}`,
    "",
  ];

  for (const r of report.cassettes) {
    const skipped = "skipped" in r.result && r.result.skipped;
    const marker = skipped ? "STUB" : r.result.pass ? "PASS" : "FAIL";
    lines.push(`  [${marker}] ${r.cassette_id}`);
    for (const f of r.result.failures) {
      lines.push(`    └─ ${f}`);
    }
    for (const w of r.result.warnings) {
      lines.push(`    └─ (warn) ${w}`);
    }
  }

  return lines.join("\n");
}

/**
 * One-shot helper — load + score + format. Intended for the Deno.test
 * entry; not for general programmatic use (callers there want the
 * pieces separately so they can assert per-cassette).
 */
export async function runReplay(promptName: string): Promise<EvalReport> {
  const cassettes = await loadCassettesForPrompt(promptName);
  return runReportForCassettes(promptName, cassettes);
}
