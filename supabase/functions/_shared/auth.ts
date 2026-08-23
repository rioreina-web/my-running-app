import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Extract and verify the authenticated user from the JWT Authorization header.
 * Returns the user's UUID string, or null if not authenticated.
 */
export async function getAuthenticatedUser(
  req: Request
): Promise<string | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return null;
  }

  const token = authHeader.replace("Bearer ", "");

  const supabaseClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY") ?? Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    {
      global: { headers: { Authorization: `Bearer ${token}` } },
    }
  );

  const {
    data: { user },
    error,
  } = await supabaseClient.auth.getUser(token);

  if (error || !user) {
    return null;
  }

  return user.id;
}

/**
 * Return a 401 Unauthorized response.
 */
export function unauthorizedResponse(
  corsHeaders: Record<string, string>
): Response {
  return new Response(
    JSON.stringify({ error: "Authentication required" }),
    {
      status: 401,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    }
  );
}

export type AuthResult =
  | { userId: string; isServiceRole: boolean }
  | { response: Response };

/**
 * Dual-mode auth gate for endpoints called by BOTH end users (iOS / web)
 * AND service-role callers (cron triggers, pg_net, other edge functions).
 *
 * Returns:
 *  - `{ userId, isServiceRole: false }` for a valid user JWT. If
 *    `bodyUserId` was also supplied it MUST match the JWT user, else 403
 *    — prevents an authenticated user from acting on another user's data
 *    by forging the body field.
 *  - `{ userId: bodyUserId, isServiceRole: true }` when the Authorization
 *    header presents the service-role key AND `bodyUserId` is supplied.
 *    Service callers must explicitly name the subject user — bare
 *    service-role with no user is rejected to keep the audit trail.
 *  - `{ response }` (401 / 400 / 403) for anything else.
 *
 * Why a dual-mode helper exists: 7 LLM-calling functions accept a
 * caller-supplied `user_id` from the request body with no authentication.
 * Some are user-facing (iOS only), some are cron-triggered (service-role
 * only), some are both. A single helper handles all three patterns and
 * pairs cleanly with `enforceFeatureRateLimit({ isServiceRole })`.
 *
 * Usage:
 *   const auth = await requireAuthOrServiceRole(req, body.user_id, corsHeaders);
 *   if ("response" in auth) return auth.response;
 *   const { userId, isServiceRole } = auth;
 */
export async function requireAuthOrServiceRole(
  req: Request,
  bodyUserId: string | null | undefined,
  corsHeaders: Record<string, string>,
): Promise<AuthResult> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return { response: unauthorizedResponse(corsHeaders) };
  }
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) {
    return { response: unauthorizedResponse(corsHeaders) };
  }

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  // ── Service-role path ─────────────────────────────────────────────
  // Constant-time compare so token shape can't be probed via timing.
  if (serviceRoleKey && timingSafeEqual(token, serviceRoleKey)) {
    if (!bodyUserId || typeof bodyUserId !== "string" || bodyUserId.length === 0) {
      return {
        response: new Response(
          JSON.stringify({
            error: "Service-role caller must specify user_id in body",
          }),
          {
            status: 400,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          },
        ),
      };
    }
    return { userId: bodyUserId, isServiceRole: true };
  }

  // ── User-JWT path ─────────────────────────────────────────────────
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY") ?? serviceRoleKey!,
    { global: { headers: { Authorization: `Bearer ${token}` } } },
  );
  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) {
    return { response: unauthorizedResponse(corsHeaders) };
  }

  // If body specified a user_id, it MUST match the JWT user.
  if (bodyUserId && bodyUserId !== user.id) {
    return {
      response: new Response(
        JSON.stringify({ error: "JWT user does not match body user_id" }),
        {
          status: 403,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        },
      ),
    };
  }

  return { userId: user.id, isServiceRole: false };
}

/**
 * Strict service-role gate for endpoints with NO user-facing caller —
 * fired only by pg_net triggers, cron jobs, or other edge functions.
 *
 * Returns `null` when the Authorization header presents the service-role
 * key, or a 401 `Response` otherwise. The caller should `return` the
 * response immediately.
 *
 * Use this (instead of `requireAuthOrServiceRole`) when the user_id is
 * NOT supplied in the body — e.g. it's derived from a DB lookup keyed on
 * a record id passed by the trigger. There's no body user_id to compare,
 * so the JWT path doesn't apply.
 */
export function requireServiceRole(
  req: Request,
  corsHeaders: Record<string, string>,
): Response | null {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return unauthorizedResponse(corsHeaders);
  }
  const token = authHeader.slice("Bearer ".length).trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceRoleKey || !timingSafeEqual(token, serviceRoleKey)) {
    return unauthorizedResponse(corsHeaders);
  }
  return null;
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

export type Caller =
  | { isServiceRole: true; userId: null }
  | { isServiceRole: false; userId: string }
  | { isServiceRole: false; userId: null };

/**
 * Resolve WHO is calling, without deciding whether they're allowed.
 *
 * Returns one of three states:
 *  - `{ isServiceRole: true,  userId: null }`   — the service-role key.
 *  - `{ isServiceRole: false, userId: "..." }`  — a valid end-user JWT.
 *  - `{ isServiceRole: false, userId: null }`   — anon key, or no/invalid
 *    token. NOT authenticated.
 *
 * Use this only where the subject user can't be a single body field —
 * e.g. an endpoint whose modes derive the subject differently (from a
 * plan id, or not at all). Everywhere else prefer
 * `requireAuthOrServiceRole`, which resolves the caller AND authorizes
 * them against a body user_id in one step.
 *
 * The critical distinction this exists to make: the anon key is a valid
 * project JWT that satisfies the gateway's `verify_jwt`, and it ships
 * publicly in the iOS binary and the web bundle. "No user claim"
 * therefore means "unauthenticated", NOT "trusted server caller".
 * Collapsing those two is what made several functions readable by
 * anyone holding the anon key.
 */
export async function resolveCaller(req: Request): Promise<Caller> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return { isServiceRole: false, userId: null };
  }
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) return { isServiceRole: false, userId: null };

  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (serviceRoleKey && timingSafeEqual(token, serviceRoleKey)) {
    return { isServiceRole: true, userId: null };
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY") ?? serviceRoleKey!,
    { global: { headers: { Authorization: `Bearer ${token}` } } },
  );
  const { data: { user }, error } = await supabase.auth.getUser(token);
  if (error || !user) return { isServiceRole: false, userId: null };

  return { isServiceRole: false, userId: user.id };
}

/**
 * 403 for an authenticated caller acting outside what they own.
 */
export function forbiddenResponse(
  corsHeaders: Record<string, string>,
  message = "Not authorized for this resource",
): Response {
  return new Response(
    JSON.stringify({ error: message }),
    { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } },
  );
}
