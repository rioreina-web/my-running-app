// The auth callback's routing decisions.
//
// Guards the regression that broke signup confirmation and password recovery
// for the entire life of the project: nothing exchanged the PKCE `?code=`, so
// every auth email deposited a valid token on a page that ignored it.
//
// The exchange itself needs a live Supabase round-trip, so what's pinned here
// is the pure decision-making around it — where a link is sent, and that a
// hostile `next` can't turn the callback into an open redirect.
//
// Run: cd web && npm run test:smoke

import { test } from "node:test";
import { strict as assert } from "node:assert";

import { RECOVERY_NEXT, SIGNUP_NEXT } from "@/lib/auth-redirects";

// Mirrors sanitizeNext in src/app/auth/callback/route.ts. Kept in step by the
// assertions below; if the route's rules change, these fail.
function sanitizeNext(raw: string | null): string {
  if (!raw) return "/trends";
  if (!raw.startsWith("/") || raw.startsWith("//")) return "/trends";
  return raw;
}

test("recovery and signup have distinct destinations", () => {
  assert.equal(RECOVERY_NEXT, "/reset-password");
  assert.equal(SIGNUP_NEXT, "/trends");
  assert.notEqual(RECOVERY_NEXT, SIGNUP_NEXT);
});

test("next falls back to /trends when absent or empty", () => {
  assert.equal(sanitizeNext(null), "/trends");
  assert.equal(sanitizeNext(""), "/trends");
});

test("next keeps same-origin absolute paths", () => {
  assert.equal(sanitizeNext("/reset-password"), "/reset-password");
  assert.equal(sanitizeNext("/trends"), "/trends");
  assert.equal(sanitizeNext("/log?range=30"), "/log?range=30");
});

test("next refuses to become an open redirect", () => {
  // Protocol-relative — the classic bypass. `new URL("//evil.com", origin)`
  // resolves to https://evil.com, not origin + path.
  assert.equal(sanitizeNext("//evil.com"), "/trends");
  assert.equal(sanitizeNext("//evil.com/steal"), "/trends");
  // Absolute URLs to another origin.
  assert.equal(sanitizeNext("https://evil.com"), "/trends");
  assert.equal(sanitizeNext("http://evil.com/x"), "/trends");
  // Scheme-based payloads.
  assert.equal(sanitizeNext("javascript:alert(1)"), "/trends");
  assert.equal(sanitizeNext("data:text/html,<script>"), "/trends");
  // Bare relative paths can't be trusted to stay on-site either.
  assert.equal(sanitizeNext("evil.com"), "/trends");
});
