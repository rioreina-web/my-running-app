/**
 * Environment variable validation.
 *
 * Imported by middleware.ts so it runs once at startup.
 * Throws on missing required vars, fails fast instead of failing silently
 * later when a request hits a route that needs them.
 */

const REQUIRED = {
  NEXT_PUBLIC_SUPABASE_URL: process.env.NEXT_PUBLIC_SUPABASE_URL,
  NEXT_PUBLIC_SUPABASE_ANON_KEY: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
} as const;

const OPTIONAL = {
  SUPABASE_SERVICE_ROLE_KEY: process.env.SUPABASE_SERVICE_ROLE_KEY,
  ML_SERVICE_URL: process.env.ML_SERVICE_URL,
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
    // In production, fail fast. In dev, console.error so the dev server keeps running.
    if (process.env.NODE_ENV === "production") {
      throw new Error(msg);
    } else {
      console.error(`[env] ${msg}`);
    }
  }

  // Warn on optional vars that are missing (helpful for catching deploy mistakes)
  const optionalMissing = Object.entries(OPTIONAL)
    .filter(([, v]) => !v)
    .map(([k]) => k);

  if (optionalMissing.length > 0 && process.env.NODE_ENV === "production") {
    console.warn(`[env] Optional vars not set: ${optionalMissing.join(", ")}`);
  }

  validated = true;
}

// Run on import
validateEnv();
