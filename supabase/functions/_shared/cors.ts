/**
 * Shared CORS headers for all edge functions.
 *
 * Set the ALLOWED_ORIGIN env var in production to your web app domain
 * (e.g., https://app.postrundrip.com). Falls back to "*" in dev.
 */

const ALLOWED_ORIGIN = Deno.env.get("ALLOWED_ORIGIN") || "*";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Max-Age": "86400",
};
