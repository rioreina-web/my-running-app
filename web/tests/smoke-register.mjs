// Registers the @/-path resolver with Node's ES module loader. Used as
// the entry-point for `node --import` so the smoke tests can resolve
// `@/components/coach/workout-helpers` (and similar) without going
// through Next.js's bundler.

import { register } from "node:module";
import { pathToFileURL, fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

const HERE = dirname(fileURLToPath(import.meta.url));
const SRC_ROOT = resolve(HERE, "..", "src");
const LOADER_URL = pathToFileURL(resolve(HERE, "smoke-loader.mjs")).href;

register(LOADER_URL, {
  data: { srcRoot: SRC_ROOT },
});
