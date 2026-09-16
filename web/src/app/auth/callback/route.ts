import { NextResponse, type NextRequest } from "next/server";
import { createServerClient } from "@supabase/ssr";

// The single door every Supabase auth email comes back through.
//
// WHY THIS EXISTS. `@supabase/ssr` hardcodes `flowType: "pkce"`, so every auth
// email returns a `?code=` that must be exchanged for a session. Until
// 2026-08-19 nothing in this app called `exchangeCodeForSession` — not for
// recovery, not for signup confirmation. The links worked (the auth log shows
// `/verify 303 action=login`), deposited a valid code on whatever page the
// project's Site URL pointed at, and it was ignored. Signup confirmation was
// therefore broken for every user who ever created an account, and a forgotten
// password was unrecoverable.
//
// WHY SERVER-SIDE. Exchanging here lets us write the session cookie onto the
// redirect response, so the destination renders authenticated on first paint
// instead of flashing a logged-out shell and hydrating into a session. It also
// keeps one implementation for every email type.
//
// WHAT IT WILL NOT DO. PKCE binds the code to a `code_verifier` held by the
// browser that REQUESTED the email. A link generated in the Supabase dashboard
// has no verifier in the athlete's browser and cannot be exchanged — the
// failure is reported as such rather than dressed up as an expired link.

export async function GET(request: NextRequest) {
  const { searchParams, origin } = request.nextUrl;

  const code = searchParams.get("code");
  const next = sanitizeNext(searchParams.get("next"));

  // Supabase can redirect here with an error instead of a code — an expired
  // link, or one already spent. Carry its own words forward; the destination
  // renders them verbatim rather than guessing.
  const errorCode = searchParams.get("error_code") ?? searchParams.get("error");
  const errorDescription = searchParams.get("error_description");
  if (errorCode || errorDescription) {
    return NextResponse.redirect(
      failureUrl(origin, next, errorDescription ?? errorCode ?? "Link could not be used.")
    );
  }

  if (!code) {
    return NextResponse.redirect(
      failureUrl(origin, next, "That link is missing its sign-in code.")
    );
  }

  // Collect the cookies Supabase wants to set, then attach them to the
  // redirect we actually return. Writing them to an intermediate response
  // would drop the session on the floor.
  const cookiesToSet: Array<{ name: string; value: string; options: Record<string, unknown> }> = [];

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(pending) {
          for (const c of pending) {
            cookiesToSet.push({ name: c.name, value: c.value, options: c.options ?? {} });
          }
        },
      },
    }
  );

  const { error } = await supabase.auth.exchangeCodeForSession(code);

  if (error) {
    return NextResponse.redirect(failureUrl(origin, next, exchangeMessage(error.message)));
  }

  const response = NextResponse.redirect(new URL(next, origin));
  for (const c of cookiesToSet) {
    response.cookies.set(c.name, c.value, c.options);
  }
  return response;
}

// Only ever redirect to a path on this origin. `next` arrives from a URL the
// user clicked, so an unchecked value is an open redirect.
function sanitizeNext(raw: string | null): string {
  if (!raw) return "/trends";
  if (!raw.startsWith("/") || raw.startsWith("//")) return "/trends";
  return raw;
}

// Failures go to the page best able to explain them: recovery failures back to
// /reset-password (which can offer a fresh link), everything else to /login.
function failureUrl(origin: string, next: string, message: string): URL {
  const target = next === "/reset-password" ? "/reset-password" : "/login";
  const url = new URL(target, origin);
  url.searchParams.set("error_description", message);
  return url;
}

// The raw exchange error is accurate but not actionable. The overwhelmingly
// common cause is a link opened in a different browser from the one that
// requested it, which PKCE cannot support.
function exchangeMessage(raw: string): string {
  const lowered = raw.toLowerCase();
  if (lowered.includes("code verifier") || lowered.includes("code_verifier")) {
    return "This link has to be opened in the same browser that requested it. Start again from Forgot password on this device.";
  }
  if (lowered.includes("expired")) {
    return "That link has expired. Request a new one.";
  }
  return raw;
}
