import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import "@/lib/env.server"; // validates required env vars at startup

// /reset-password must be public: a recovery link arrives with no session, so
// gating it would bounce the user to /login and strand the token they came to
// spend. The page is safe unauthenticated — it can do nothing without a valid
// recovery session, which only Supabase can mint.
const PUBLIC_PATHS = ["/", "/blog", "/login", "/reset-password", "/studio"];

// /auth/callback must be reachable with no session — it is the thing that
// CREATES the session. Gating it would bounce every confirmation and recovery
// link to /login with the code unspent.

// Static design mockups served straight out of public/design/*.html. These
// are self-contained HTML from design-system/ — inline <style>, inline style
// attributes, and a small skin-toggle script — so the nonce-based CSP below
// would strip them and render the page unstyled. They stay BEHIND the auth
// gate (they are not in PUBLIC_PATHS); only the CSP header is skipped, and
// only for hand-authored static files with no user data in them.
function isDesignMockup(pathname: string): boolean {
  return pathname.startsWith("/design/") && pathname.endsWith(".html");
}

function isPublicPath(pathname: string): boolean {
  if (PUBLIC_PATHS.includes(pathname)) return true;
  if (pathname.startsWith("/blog/")) return true;
  if (pathname.startsWith("/studio/")) return true;
  if (pathname.startsWith("/auth/")) return true;
  return false;
}

// Nonce-based CSP: no 'unsafe-inline' / 'unsafe-eval' for scripts.
//
// style-src deliberately uses 'unsafe-inline' rather than the nonce: a nonce
// only covers <style> elements, never `style=""` attributes, and every chart
// (recharts) and several layout components emit those. Under CSP3 a nonce
// makes 'unsafe-inline' ignored, so the two cannot be combined — it is one or
// the other, and blocking every inline style attribute breaks the app while
// buying little (style injection needs an HTML injection first, which
// script-src already contains).
function buildCsp(nonce: string): string {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
  return [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'`,
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data: https:",
    "font-src 'self' data:",
    `connect-src 'self' ${supabaseUrl} https://*.supabase.co https://*.ingest.us.sentry.io`,
    "frame-ancestors 'none'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "upgrade-insecure-requests",
  ].join("; ");
}

function generateNonce(): string {
  const array = new Uint8Array(16);
  crypto.getRandomValues(array);
  return Buffer.from(array).toString("base64");
}

export async function middleware(request: NextRequest) {
  const nonce = generateNonce();
  const { pathname } = request.nextUrl;

  // Next.js reads the nonce from the *request* headers to stamp its own
  // inline hydration scripts (`x-nonce` / the CSP request header). Setting
  // the CSP on the response alone — what this file did until 2026-09-03 —
  // means Next never sees the nonce, so with 'strict-dynamic' and no
  // 'unsafe-inline' the framework's own scripts are the first thing the
  // policy blocks. The request copy is what makes the policy enforceable.
  const csp = buildCsp(nonce);
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-nonce", nonce);
  requestHeaders.set("Content-Security-Policy", csp);
  const nextInit = { request: { headers: requestHeaders } };

  let response = NextResponse.next(nextInit);

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
          response = NextResponse.next(nextInit);
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

  // Auth has already been enforced above. A design mockup renders as authored.
  if (isDesignMockup(pathname)) return response;

  response.headers.set("Content-Security-Policy", csp);
  response.headers.set("x-nonce", nonce);

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
