// Module-resolution hook (resolve-hook form) that maps `@/...` to the
// matching path under `src/`. Designed for use with `module.register()`
// from a register script — see `smoke-register.mjs`.

import { pathToFileURL } from "node:url";
import { resolve as resolvePath } from "node:path";
import { existsSync } from "node:fs";

let SRC_ROOT = "";

export async function initialize(data) {
  SRC_ROOT = data.srcRoot;
}

export async function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith("@/")) {
    const rel = specifier.slice(2);
    for (const ext of [".ts", ".tsx", "/index.ts", "/index.tsx"]) {
      const candidate = resolvePath(SRC_ROOT, rel + ext);
      if (existsSync(candidate)) {
        // Don't set `format` — let Node detect it from extension so
        // `--experimental-strip-types` can transform .ts files. Setting
        // format: "module" would force it to be loaded as plain JS and
        // SyntaxError on the first `export type`.
        return {
          url: pathToFileURL(candidate).href,
          shortCircuit: true,
        };
      }
    }
  }
  return nextResolve(specifier, context);
}
