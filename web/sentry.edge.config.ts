// Edge runtime Sentry (middleware, edge route handlers).
// Subset of Node API — no replay, no profiling.

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
