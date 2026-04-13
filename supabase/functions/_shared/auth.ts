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
