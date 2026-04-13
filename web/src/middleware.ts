import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import "@/lib/env"; // validates required env vars at startup

const PUBLIC_PATHS = ["/", "/blog", "/login", "/studio"];

function isPublicPath(pathname: string): boolean {
  if (PUBLIC_PATHS.includes(pathname)) return true;
  if (pathname.startsWith("/blog/")) return true;
  if (pathname.startsWith("/studio/")) return true;
  return false;
}

export async function middleware(request: NextRequest) {
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

  return response;
}

export const config = {
  matcher: [
    "/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
