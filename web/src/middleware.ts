import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import "@/lib/env.server"; // validates required env vars at startup

// Marketing routes render for signed-out visitors. /api/beta-invite is here
// because the invite form on /beta posts to it before anyone has an account.
const PUBLIC_PATHS = [
  "/",
  "/how-it-works",
  "/principles",
  "/beta",
  "/blog",
  "/login",
  "/studio",
  "/api/beta-invite",
];

function isPublicPath(pathname: string): boolean {
  if (PUBLIC_PATHS.includes(pathname)) return true;
  if (pathname.startsWith("/blog/")) return true;
  if (pathname.startsWith("/studio/")) return true;
  return false;
}

function generateNonce(): string {
  const array = new Uint8Array(16);
  crypto.getRandomValues(array);
  return Buffer.from(array).toString("base64");
}

export async function middleware(request: NextRequest) {
  const nonce = generateNonce();
  let response = NextResponse.next({ request });
  const { pathname } = request.nextUrl;

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Authenticated user on public landing or login → redirect to dashboard
  if (user && (pathname === "/" || pathname === "/login")) {
    return NextResponse.redirect(new URL("/dashboard", request.url));
  }

  // Unauthenticated user on protected path → redirect to login
  if (!user && !isPublicPath(pathname)) {
    return NextResponse.redirect(new URL("/login", request.url));
  }

  // Nonce-based CSP — no 'unsafe-inline' or 'unsafe-eval' on scripts.
  //
  // style-src carries 'unsafe-inline' deliberately: Next injects inline
  // <style> for fonts and route CSS that it does not nonce, so a nonce-only
  // style-src blocks every stylesheet on the site. This mirrors the CSP
  // example in the Next.js docs. Scripts stay strict.
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
  const csp = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data: https:",
    "font-src 'self' data:",
    `connect-src 'self' ${supabaseUrl} https://*.supabase.co https://*.ingest.us.sentry.io`,
    "frame-ancestors 'none'",
  ].join("; ");

  // The policy has to go back on the *request* as well as the response. Next
  // reads the nonce out of the request's Content-Security-Policy header and
  // stamps it onto the script tags it renders; without this its own chunks
  // are blocked by the policy above and nothing on the site hydrates.
  request.headers.set("Content-Security-Policy", csp);
  request.headers.set("x-nonce", nonce);
  response = NextResponse.next({ request });

  response.headers.set("Content-Security-Policy", csp);
  response.headers.set("x-nonce", nonce);

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
