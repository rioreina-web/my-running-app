/**
 * Redis-backed sliding-window rate limiter using Upstash.
 *
 * Shared across all Vercel instances — works correctly under autoscale.
 *
 * Missing Upstash config is a no-op in LOCAL DEV ONLY. In production it
 * fails CLOSED — see `shouldEnforce` below. This mirrors the edge-function
 * limiter (`supabase/functions/_shared/rateLimit.ts`,
 * `shouldEnforceRateLimits`); the two layers are one policy and should stay
 * recognisably the same.
 *
 * Keeps the same `checkRateLimit(key, limit, windowMs)` signature so
 * call sites don't need to change.
 */

import { NextResponse } from "next/server";
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

// Cache of Ratelimit instances keyed by "limit:windowMs"
const limiters = new Map<string, Ratelimit>();

// Read per call, not once at module load: a module-scope const freezes the
// value at import time, which makes the behaviour untestable and depends on
// import order relative to env setup.
function redisConfigured(): boolean {
  return (
    !!process.env.UPSTASH_REDIS_REST_URL && !!process.env.UPSTASH_REDIS_REST_TOKEN
  );
}

/**
 * Should the limiter gate at all?
 *
 *   dev  + no Redis   → skip (local development stays frictionless)
 *   prod + no Redis   → enforce, and `checkRateLimit` denies (fail closed)
 *   Redis configured  → enforce normally, anywhere
 *
 * Before 2026-09-03 an unset UPSTASH_REDIS_REST_URL meant "allow everything"
 * in every environment, so a deploy missing those two Vercel variables
 * silently removed the limits from all six API routes at once. Those routes
 * fan out to LLM-backed edge functions using the service-role key, which
 * bypasses the edge functions' own per-user quotas — so this was the only
 * ceiling on that spend, and it failed open.
 */
function shouldEnforce(): boolean {
  return redisConfigured() || process.env.NODE_ENV === "production";
}

function getLimiter(limit: number, windowMs: number): Ratelimit | null {
  if (!redisConfigured()) return null;

  const cacheKey = `${limit}:${windowMs}`;
  let rl = limiters.get(cacheKey);
  if (rl) return rl;

  const windowSec = Math.max(1, Math.round(windowMs / 1000));

  rl = new Ratelimit({
    redis: Redis.fromEnv(),
    limiter: Ratelimit.slidingWindow(limit, `${windowSec} s`),
    analytics: true,
    prefix: "ratelimit",
  });

  limiters.set(cacheKey, rl);
  return rl;
}

/**
 * Check if a request is within the rate limit.
 *
 * @param key - Unique identifier (typically `userId:route`)
 * @param limit - Max requests allowed in the window
 * @param windowMs - Window size in milliseconds
 * @returns `{ allowed: true }` or `{ allowed: false, retryAfterMs }`
 */
export async function checkRateLimit(
  key: string,
  limit: number,
  windowMs: number,
): Promise<{ allowed: true } | { allowed: false; retryAfterMs: number }> {
  const rl = getLimiter(limit, windowMs);

  if (!rl) {
    if (shouldEnforce()) {
      // Production with no Redis: deny rather than hand out a blank cheque.
      // A misconfigured deploy becomes loud 429s on the first request
      // instead of an unmetered bill.
      console.error(
        "[rate-limit] UPSTASH_REDIS_REST_URL/TOKEN unset in production — " +
          "denying request (fail-closed). Set both to restore service.",
      );
      return { allowed: false, retryAfterMs: windowMs };
    }
    // Local dev without Redis — allow everything.
    return { allowed: true };
  }

  const result = await rl.limit(key);

  if (result.success) {
    return { allowed: true };
  }

  return {
    allowed: false,
    retryAfterMs: Math.max(0, result.reset - Date.now()),
  };
}

/**
 * One-line rate-limit guard for route handlers. Returns `null` if the
 * request is allowed, or a 429 `NextResponse` to return immediately.
 *
 * The 429 carries:
 *   - `Retry-After` header (seconds, per RFC 9110)
 *   - JSON body `{ error: 'rate_limited', retry_after_seconds: N }`
 *
 * Usage:
 *   const blocked = await enforceRateLimit(`${user.id}:coach`, 20, 60_000);
 *   if (blocked) return blocked;
 */
export async function enforceRateLimit(
  key: string,
  limit: number,
  windowMs: number,
): Promise<NextResponse | null> {
  const rl = await checkRateLimit(key, limit, windowMs);
  if (rl.allowed) return null;

  const retryAfterSeconds = Math.max(1, Math.ceil(rl.retryAfterMs / 1000));
  return NextResponse.json(
    { error: "rate_limited", retry_after_seconds: retryAfterSeconds },
    {
      status: 429,
      headers: { "Retry-After": String(retryAfterSeconds) },
    },
  );
}
