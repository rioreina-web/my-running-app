/**
 * Redis-backed sliding-window rate limiter using Upstash.
 *
 * Shared across all Vercel instances — works correctly under autoscale.
 * Falls back to a permissive no-op if UPSTASH_REDIS_REST_URL is not set
 * (local dev without Redis).
 *
 * Keeps the same `checkRateLimit(key, limit, windowMs)` signature so
 * call sites don't need to change.
 */

import { NextResponse } from "next/server";
import { Ratelimit } from "@upstash/ratelimit";
import { Redis } from "@upstash/redis";

// Cache of Ratelimit instances keyed by "limit:windowMs"
const limiters = new Map<string, Ratelimit>();

const redisConfigured =
  !!process.env.UPSTASH_REDIS_REST_URL && !!process.env.UPSTASH_REDIS_REST_TOKEN;

function getLimiter(limit: number, windowMs: number): Ratelimit | null {
  if (!redisConfigured) return null;

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
    // No Redis configured (local dev) — allow everything
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
