import { defineConfig, globalIgnores } from "eslint/config";
import nextVitals from "eslint-config-next/core-web-vitals";
import nextTs from "eslint-config-next/typescript";

const eslintConfig = defineConfig([
  ...nextVitals,
  ...nextTs,
  // Override default ignores of eslint-config-next.
  globalIgnores([
    // Default ignores of eslint-config-next:
    ".next/**",
    "out/**",
    "build/**",
    "next-env.d.ts",
  ]),
  // TASKS.md W1.3 — service-role key flows through src/lib/env.server.ts only.
  // Any direct `process.env.SUPABASE_SERVICE_ROLE_KEY` read elsewhere fails lint.
  {
    files: ["src/**/*.{ts,tsx,js,jsx}"],
    ignores: ["src/lib/env.server.ts"],
    rules: {
      "no-restricted-syntax": [
        "error",
        {
          selector:
            "MemberExpression[object.object.name='process'][object.property.name='env'][property.name='SUPABASE_SERVICE_ROLE_KEY']",
          message:
            "Import SUPABASE_SERVICE_ROLE_KEY from '@/lib/env.server' instead of reading process.env directly (TASKS.md W1.3).",
        },
      ],
    },
  },
]);

export default eslintConfig;
