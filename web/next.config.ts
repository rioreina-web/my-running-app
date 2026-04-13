import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";

const nextConfig: NextConfig = {
  poweredByHeader: false,
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
          {
            key: "Content-Security-Policy",
            value: [
              "default-src 'self'",
              "script-src 'self' 'unsafe-inline' 'unsafe-eval'",
              "style-src 'self' 'unsafe-inline'",
              "img-src 'self' blob: data: https:",
              "font-src 'self' data:",
              `connect-src 'self' ${process.env.NEXT_PUBLIC_SUPABASE_URL || ""} https://*.supabase.co`,
              "frame-ancestors 'none'",
            ].join("; "),
          },
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
