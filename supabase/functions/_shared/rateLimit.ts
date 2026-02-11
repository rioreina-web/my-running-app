/**
 * Rate Limiting Module
 * Uses Upstash Redis for fast, distributed rate limiting
 * Free tier: 5 questions/day, Pro: 25 questions/day
 */

import { Redis } from "https://esm.sh/@upstash/redis@1.28.0";

const TIER_LIMITS: Record<string, number> = {
  free: 5,
  pro: 25,
  unlimited: 100,
};

let redis: Redis | null = null;

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

  // If Redis not configured, allow all requests (for development)
  if (!client) {
    return {
      allowed: true,
      remaining: limit,
      resetAt,
      current: 0,
      limit,
    };
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
    // On error, allow the request but log it
    return {
      allowed: true,
      remaining: limit,
      resetAt,
      current: 0,
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
