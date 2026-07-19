import "server-only";

import { createClient } from "@supabase/supabase-js";
import { SUPABASE_SERVICE_ROLE_KEY } from "@/lib/env.server";

/**
 * Service-role Supabase client — bypasses RLS. Use ONLY in server code, and
 * ALWAYS scope every query explicitly (e.g. `.eq("user_id", athleteId)`),
 * because RLS is not doing that for you here.
 *
 * Why the coach dashboard needs it: `athlete_state` is readable only by the
 * athlete + service_role, and `body_mentions` has no coach read policy
 * (spec §3). The coach page gates access first (coach owns the athlete's
 * subscription), then reads those two tables through this client for the
 * already-authorized athlete. Mirrors how the API routes read privileged data.
 */
export function createAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!url) throw new Error("[supabase/admin] NEXT_PUBLIC_SUPABASE_URL is not set.");
  return createClient(url, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
