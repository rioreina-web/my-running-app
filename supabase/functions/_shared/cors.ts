/**
 * Shared CORS headers for all edge functions.
 *
 * Production: ALLOWED_ORIGIN MUST be set (e.g. https://app.postrundrip.com).
 * The module throws on import if it's missing — fail closed beats falling
 * back to "*" silently.
 *
 * Production is detected by DENO_DEPLOYMENT_ID being present (Deno Deploy /
 * Supabase Edge sets this; local serve does not). See TASKS.md W1.2.
 */

const isProduction = Boolean(Deno.env.get("DENO_DEPLOYMENT_ID"));
const ALLOWED_ORIGIN_ENV = Deno.env.get("ALLOWED_ORIGIN");

if (isProduction && !ALLOWED_ORIGIN_ENV) {
  throw new Error(
    "[cors] ALLOWED_ORIGIN must be set in production. Refusing to fall back to '*'."
  );
}

const ALLOWED_ORIGIN = ALLOWED_ORIGIN_ENV || "*";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Max-Age": "86400",
};
