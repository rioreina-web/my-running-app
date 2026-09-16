/**
 * Offline, free scoring of the GRAMMAR LAYER ALONE over the coach corpus.
 *
 * The layered eval (`layered-shorthand-eval.ts`) measures what a coach
 * experiences, but it needs a key and spends money, so it is not something
 * you run on every grammar edit. This one is: it scores the only question a
 * grammar change can move — how much of the corpus the grammar reads with
 * nothing left over.
 *
 * "Clean" here is deliberately the SAME predicate the shipping client uses to
 * decide whether to escalate (`workout-shorthand-client.ts`), including the
 * per-step `unresolved` codes. A parse that invents a pace it was never given
 * is not clean, however confident the step list looks.
 *
 * Run: cd web && node --experimental-strip-types --no-warnings \
 *        --import ./tests/smoke-register.mjs tests/eval/grammar-only-eval.ts [--dump]
 */

import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";

import { parseWorkoutText } from "@/components/coach/workout-nl-parser";

const HERE = dirname(fileURLToPath(import.meta.url));
const corpus: Array<{ sheet: string; input: string }> = JSON.parse(
  readFileSync(join(HERE, "..", "fixtures", "coach-shorthand-corpus.json"), "utf8"),
);

const dump = process.argv.includes("--dump");
let clean = 0;
let built = 0;
const residue: string[] = [];

for (const { input } of corpus) {
  const r = parseWorkoutText(input);
  const unresolved = Object.keys(r.unresolved).length;
  if (r.steps.length > 0) built += 1;
  if (r.steps.length > 0 && r.unparsed.length === 0 && r.warnings.length === 0 && unresolved === 0) {
    clean += 1;
  } else {
    residue.push(
      `  ${input}\n    steps=${r.steps.length} unparsed=${r.unparsed.length} warnings=${r.warnings.length} unresolved=${unresolved}`,
    );
  }
}

console.log(`grammar clean:  ${clean}/${corpus.length}`);
console.log(`grammar builds: ${built}/${corpus.length}`);
if (dump) console.log("\nnot clean:\n" + residue.join("\n"));
