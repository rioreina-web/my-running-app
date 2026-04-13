/**
 * Rate Limiting Module
 * Uses Upstash Redis for fast, distributed rate limiting
 * Free tier: 5 questions/day, Pro: 25 questions/day
 *
 * Circuit breaker: after 3 consecutive Redis failures, temporarily allows
 * requests for 60 seconds before re-testing Redis. This prevents a Redis
 * outage from locking out all users while still failing closed under normal
 * transient errors.
 */

import { Redis } from "https://esm.sh/@upstash/redis@1.28.0";

const TIER_LIMITS: Record<string, number> = {
  free: 5,
  pro: 25,
  unlimited: 100,
};

let redis: Redis | null = null;

// Circuit breaker state
let consecutiveFailures = 0;
let circuitOpenUntil = 0;
const CIRCUIT_BREAKER_THRESHOLD = 3;
const CIRCUIT_BREAKER_RESET_MS = 60_000; // 60 seconds

function getRedis(): Redis | null {
  if (redis) return redis;

  const url = Deno.env.get("UPSTASH_REDIS_URL");
  const token = Deno.env.get("UPSTASH_REDIS_TOKEN");

  if (!url || !token) {
    console.log("Upstash Redis not configured - rate limiting disabled");
    return null;
  }

  redis = new Redis({ url, token });
  return redis;
}

/**
 * Check if the circuit breaker is open (Redis recently failed repeatedly).
 * When open, we allow requests through (degraded mode) rather than blocking everyone.
 */
function isCircuitOpen(): boolean {
  if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
    if (Date.now() < circuitOpenUntil) {
      return true;
    }
    // Reset — allow next request to test Redis
    consecutiveFailures = 0;
  }
  return false;
}

function recordRedisSuccess(): void {
  consecutiveFailures = 0;
}

function recordRedisFailure(): void {
  consecutiveFailures++;
  if (consecutiveFailures >= CIRCUIT_BREAKER_THRESHOLD) {
    circuitOpenUntil = Date.now() + CIRCUIT_BREAKER_RESET_MS;
    console.warn(`Circuit breaker OPEN — allowing requests for ${CIRCUIT_BREAKER_RESET_MS / 1000}s while Redis recovers`);
  }
}

export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetAt: Date;
  current: number;
  limit: number;
}

/**
 * Check and increment rate limit for a user
 * Returns whether the request is allowed and remaining quota
 */
export async function checkRateLimit(
  userId: string,
  tier: string = "free"
): Promise<RateLimitResult> {
  const client = getRedis();
  const limit = TIER_LIMITS[tier] || TIER_LIMITS.free;

  // Calculate reset time (midnight UTC)
  const resetAt = new Date();
  resetAt.setUTCHours(24, 0, 0, 0);

  // If Redis not configured, deny requests in production to prevent abuse
  if (!client) {
    console.warn("Rate limit: Redis unavailable — denying request (fail-closed)");
    return {
      allowed: false,
      remaining: 0,
      resetAt,
      current: limit,
      limit,
    };
  }

  // Circuit breaker open — allow through in degraded mode
  if (isCircuitOpen()) {
    console.warn("Rate limit: circuit breaker open — allowing request (degraded mode)");
    return { allowed: true, remaining: 1, resetAt, current: 0, limit };
  }

  try {
    const today = new Date().toISOString().split("T")[0];
    const key = `ratelimit:${userId}:${today}`;

    // Increment counter
    const current = await client.incr(key);

    // Set expiry at midnight UTC if this is first request of day
    if (current === 1) {
      const secondsUntilMidnight = Math.floor((resetAt.getTime() - Date.now()) / 1000);
      await client.expire(key, secondsUntilMidnight);
    }

    recordRedisSuccess();

    const remaining = Math.max(0, limit - current);
    const allowed = current <= limit;

    if (!allowed) {
      console.log(`Rate limit exceeded for user ${userId}: ${current}/${limit}`);
    }

    return {
      allowed,
      remaining,
      resetAt,
      current,
      limit,
    };
  } catch (error) {
    console.error("Rate limit check failed:", error);
    recordRedisFailure();
    // Fail closed on transient error — deny this request
    return {
      allowed: false,
      remaining: 0,
      resetAt,
      current: limit,
      limit,
    };
  }
}

/**
 * Get current usage without incrementing
 */
export async function getCurrentUsage(userId: string): Promise<number> {
  const client = getRedis();
  if (!client) return 0;

  try {
    const today = new Date().toISOString().split("T")[0];
    const key = `ratelimit:${userId}:${today}`;
    const current = await client.get<number>(key);
    return current || 0;
  } catch (error) {
    console.error("Failed to get current usage:", error);
    return 0;
  }
}

/**
 * Check if rate limiting is enabled (Redis configured)
 */
export function isRateLimitEnabled(): boolean {
  return !!Deno.env.get("UPSTASH_REDIS_URL") && !!Deno.env.get("UPSTASH_REDIS_TOKEN");
}

/**
 * Get the limit for a given tier
 */
export function getTierLimit(tier: string): number {
  return TIER_LIMITS[tier] || TIER_LIMITS.free;
}

/**
 * Per-feature rate limits (daily)
 */
const FEATURE_LIMITS: Record<string, Record<string, number>> = {
  coaching: { free: 5, pro: 25, unlimited: 100 },
  predictor: { free: 10, pro: 25, unlimited: 100 },
  analysis: { free: 10, pro: 25, unlimited: 100 },
  transcribe: { free: 20, pro: 50, unlimited: 200 },
  parse: { free: 10, pro: 25, unlimited: 100 },
  form_check_analysis: { free: 10, pro: 25, unlimited: 100 },
};

/**
 * Check and increment rate limit for a specific feature
 */
export async function checkFeatureRateLimit(
  userId: string,
  feature: string,
  tier: string = "free"
): Promise<RateLimitResult> {
  const limits = FEATURE_LIMITS[feature] || FEATURE_LIMITS.coaching;
  const limit = limits[tier] || limits.free;

  const resetAt = new Date();
  resetAt.setUTCHours(24, 0, 0, 0);

  const client = getRedis();
  if (!client) {
    console.warn(`Rate limit: Redis unavailable for ${feature} — denying request (fail-closed)`);
    return { allowed: false, remaining: 0, resetAt, current: limit, limit };
  }

  // Circuit breaker open — allow through in degraded mode
  if (isCircuitOpen()) {
    console.warn(`Rate limit: circuit breaker open for ${feature} — allowing request (degraded mode)`);
    return { allowed: true, remaining: 1, resetAt, current: 0, limit };
  }

  try {
    const today = new Date().toISOString().split("T")[0];
    const key = `ratelimit:${feature}:${userId}:${today}`;

    const current = await client.incr(key);
    if (current === 1) {
      const secondsUntilMidnight = Math.floor(
        (resetAt.getTime() - Date.now()) / 1000
      );
      await client.expire(key, secondsUntilMidnight);
    }

    recordRedisSuccess();

    const remaining = Math.max(0, limit - current);
    const allowed = current <= limit;

    if (!allowed) {
      console.log(
        `Rate limit exceeded for ${feature} user ${userId}: ${current}/${limit}`
      );
    }

    return { allowed, remaining, resetAt, current, limit };
  } catch (error) {
    console.error(`Rate limit check failed for ${feature}:`, error);
    recordRedisFailure();
    return { allowed: false, remaining: 0, resetAt, current: limit, limit };
  }
}
