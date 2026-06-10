import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async redirects() {
    return [
      { source: "/coach", destination: "/coach-portal", permanent: true },
      { source: "/coach/:path*", destination: "/coach-portal/:path*", permanent: true },
    ];
  },
  async headers() {
    return [
      {
        source: "/(.*)",
        headers: [
          {
            key: "X-Frame-Options",
            value: "DENY",
          },
          {
            key: "X-Content-Type-Options",
            value: "nosniff",
          },
          {
            key: "Referrer-Policy",
            value: "strict-origin-when-cross-origin",
          },
          {
            key: "Permissions-Policy",
            value: "camera=(), microphone=(), geolocation=()",
          },
          {
            key: "Strict-Transport-Security",
            value: "max-age=63072000; includeSubDomains; preload",
          },
          // CSP is set dynamically in middleware.ts with per-request nonces.
          // Do NOT set a static CSP header here — it would conflict.
        ],
      },
    ];
  },
};

// Wrap with Sentry — uploads source maps and adds tunneling.
// Only kicks in when SENTRY_AUTH_TOKEN + SENTRY_ORG + SENTRY_PROJECT are set
// (i.e., production builds). In dev, it's a no-op pass-through.
export default withSentryConfig(nextConfig, {
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  silent: !process.env.CI,
  widenClientFileUpload: true,
  tunnelRoute: "/monitoring",
  disableLogger: true,
  automaticVercelMonitors: false,
});
