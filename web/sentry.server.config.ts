// Server-side Sentry — Next.js API routes, server components, middleware.
// Uses the non-public SENTRY_DSN var (server-only).

import * as Sentry from "@sentry/nextjs";

const dsn = process.env.SENTRY_DSN || process.env.NEXT_PUBLIC_SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env.VERCEL_ENV || process.env.NODE_ENV,
    tracesSampleRate: 0.1,
    enabled: process.env.NODE_ENV === "production",
  });
}
