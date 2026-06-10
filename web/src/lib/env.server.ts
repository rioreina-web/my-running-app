import "server-only";

/**
 * Server-only environment access + validation.
 *
 * Renamed from `env.ts` per TASKS.md W1.3 — the `.server.ts` suffix and the
 * `server-only` import together ensure this module cannot be imported into a
 * "use client" component (Next.js build fails at the import edge).
 *
 * The service-role key is exported from here so every server-side reader
 * pulls from a single audited surface. The ESLint `no-restricted-imports`
 * rule in eslint.config.mjs bans direct `process.env.SUPABASE_SERVICE_ROLE_KEY`
 * reads to keep that surface honest.
 */

const REQUIRED = {
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
} as const;

const OPTIONAL = {
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
  VITAL_API_KEY: process.env.VITAL_API_KEY,
} as const;

let validated = false;

export function validateEnv(): void {
  if (validated) return;

  const missing = Object.entries(REQUIRED)
    .filter(([, v]) => !v)
    .map(([k]) => k);

  if (missing.length > 0) {
    const msg = `Missing required environment variables: ${missing.join(", ")}`;
    if (process.env.NODE_ENV === "production") {
      throw new Error(msg);
    } else {
      console.error(`[env] ${msg}`);
    }
  }

  const optionalMissing = Object.entries(OPTIONAL)
    .filter(([, v]) => !v)
    .map(([k]) => k);

  if (optionalMissing.length > 0 && process.env.NODE_ENV === "production") {
    console.warn(`[env] Optional vars not set: ${optionalMissing.join(", ")}`);
  }

  validated = true;
}

/**
 * The Supabase service-role key. Bypasses RLS — server-side use only.
 * Throws at access time if unset rather than allowing a silent empty string
 * to be used as a credential.
 */
export const SUPABASE_SERVICE_ROLE_KEY: string = (() => {
  const v = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!v) {
    throw new Error(
      "[env.server] SUPABASE_SERVICE_ROLE_KEY is not set. Required for server routes that bypass RLS."
    );
  }
  return v;
})();

// Run validation on import
validateEnv();
