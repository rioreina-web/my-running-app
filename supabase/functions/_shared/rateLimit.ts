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
 * Production detection — same convention as `_shared/cors.ts` (W1.2):
 * DENO_DEPLOYMENT_ID is set on Supabase Edge / Deno Deploy and absent on
 * local `supabase functions serve`. Evaluated per call (not at module load)
 * so contract tests can toggle the env var.
 */
function isProductionEnv(): boolean {
  return Boolean(Deno.env.get("DENO_DEPLOYMENT_ID"));
}

/**
 * Should the per-user quota gates run at all?
 *
 * H1 fix (2026-07-15): "Redis env missing" used to mean "skip rate limiting
 * everywhere" — a production deploy without the Upstash secrets silently
 * removed every per-user LLM ceiling (unbounded Gemini bill, review item
 * H1/P0-2). Now the bypass applies ONLY in local dev:
 *
 *   - dev + no Redis        → skip (local serve stays frictionless)
 *   - prod + no Redis       → enforce; check* functions fail CLOSED, so a
 *                             misconfigured deploy turns into loud 429s the
 *                             first user hits, not a silent blank check
 *   - Redis configured      → enforce normally (anywhere)
 */
export function shouldEnforceRateLimits(): boolean {
  return isRateLimitEnabled() || isProductionEnv();
}

/**
 * Get the limit for a given tier
 */
export function getTierLimit(tier: string): number {
  return TIER_LIMITS[tier] || TIER_LIMITS.free;
}

/**
 * Per-feature daily rate limits, keyed on (feature, tier).
 *
 * Pinning principles:
 *   - User-typed paste flows (parse) cap low — wrong paste should not burn
 *     budget for the day.
 *   - Conversational chat (coaching) is the highest-cost surface, so the
 *     free tier is intentionally tight; pro unlocks meaningful use.
 *   - Reads / cheap LLM passes (predictor, race, post_run, reschedule)
 *     are more generous because users hit them passively while browsing.
 *   - Heavy multi-section analyses (analysis, weekly_review, plan_builder)
 *     sit in the middle.
 *   - Service-role calls bypass these limits — see `enforceFeatureRateLimit`
 *     below.
 *
 * If you add a new feature, also pin it in the contract test:
 * supabase/functions/_shared/rateLimit.contract.test.ts.
 */
const FEATURE_LIMITS: Record<string, Record<string, number>> = {
  coaching:        { free:  5, pro: 25, unlimited: 100 },
  predictor:       { free: 10, pro: 25, unlimited: 100 },
  analysis:        { free: 10, pro: 25, unlimited: 100 },
  // transcribe bucket removed 2026-06-10 — the transcribe function was
  // deleted (zero callers; process-training-memo owns transcription).
  parse:           { free: 10, pro: 25, unlimited: 100 },
  injury_analysis: { free:  5, pro: 25, unlimited: 100 },
  plan_builder:    { free:  3, pro: 10, unlimited:  50 },
  race:            { free: 10, pro: 25, unlimited: 100 },
  weekly_review:   { free:  5, pro: 25, unlimited: 100 },
  post_run:        { free: 20, pro: 50, unlimited: 200 },
  voice_memo:      { free: 20, pro: 50, unlimited: 200 },
  reschedule:      { free: 10, pro: 25, unlimited: 100 },
  // draft-block-rewrite (Phase E assisted rewrite) is keyed on the ATHLETE,
  // not the calling coach: one AI draft per athlete per day regardless of
  // who asks. The edge fn deliberately does NOT pass isServiceRole so the
  // limit applies even though the caller is the trusted Next.js route.
  draft_rewrite:   { free:  1, pro:  1, unlimited:   5 },
  workout_insight: { free: 20, pro: 50, unlimited: 200 },
  // Coach-portal smart-duplicate annotation (suggest-workout-progression).
  // Coach-facing authoring affordance — generous limits, cheap calls.
  workout_progression: { free: 20, pro: 50, unlimited: 200 },
  check_in:        { free: 10, pro: 25, unlimited: 100 },
  daily_read:      { free:  5, pro: 25, unlimited: 100 },
  // Session Ask — the athlete asks a question about one of their own runs.
  // Sized per-DAY across all sessions, not per session: the rail offers five
  // questions with ten more behind the disclosure, so a single interesting
  // workout can legitimately be worth several calls. Anything tighter turns
  // the feature's own rail into a wall.
  session_ask:     { free: 15, pro: 50, unlimited: 200 },
  // Coach-portal WorkoutDrawer "the read" — on-demand AI observation per key
  // session, keyed on the calling coach. Cheap, cached per log; modest caps.
  coach_workout_read: { free: 10, pro: 25, unlimited: 100 },
  // Trends "The Effort" comparison (compare-workouts). The diff itself is
  // deterministic; the gate bounds the cheap Gemini verdict on top. Athletes
  // hit this while browsing Trends — post_run-style generosity.
  workout_comparison: { free: 20, pro: 50, unlimited: 200 },
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

/**
 * Canonical one-call rate-limit gate for edge functions. Returns either
 * a `Response` (429) that the caller should `return` immediately, or `null`
 * meaning "allowed, keep going."
 *
 * Three short-circuits:
 *   1. `isServiceRole === true` — service-role callers (cron, triggers,
 *      other edge functions) bypass user-keyed limits. Auth check is the
 *      gate for those callers, not this.
 *   2. `shouldEnforceRateLimits() === false` — Redis env not configured AND
 *      not production (local serve / dev). In production a missing Redis
 *      config does NOT bypass: checkFeatureRateLimit fails closed and the
 *      caller gets a 429 (H1 fix, 2026-07-15).
 *   3. `rl.allowed === true` — normal accept path.
 *
 * Usage in an edge function:
 *
 *   const rlBlocked = await enforceFeatureRateLimit(userId, "coaching", corsHeaders);
 *   if (rlBlocked) return rlBlocked;
 *
 * Or when the function also accepts service-role:
 *
 *   const rlBlocked = await enforceFeatureRateLimit(
 *     userId, "workout_insight", corsHeaders, { isServiceRole }
 *   );
 *   if (rlBlocked) return rlBlocked;
 *
 * Why a helper instead of inlining: the 8 LLM functions that pre-dated
 * W2.3 each repeated a ~10-line block. Consolidating eliminates drift
 * (e.g. one site forgetting the Retry-After header) and makes the
 * contract test in rateLimit.contract.test.ts a one-liner search per
 * function.
 */
export async function enforceFeatureRateLimit(
  userId: string,
  feature: string,
  corsHeaders: Record<string, string>,
  opts: { isServiceRole?: boolean; tier?: string } = {},
): Promise<Response | null> {
  if (opts.isServiceRole) return null;
  // Dev-only bypass. In production this falls through even when Redis is
  // unconfigured, and checkFeatureRateLimit's missing-client branch DENIES.
  if (!shouldEnforceRateLimits()) return null;

  const rl = await checkFeatureRateLimit(userId, feature, opts.tier ?? "free");
  if (rl.allowed) return null;

  const retryAfterSeconds = Math.max(
    1,
    Math.ceil((rl.resetAt.getTime() - Date.now()) / 1000),
  );

  return new Response(
    JSON.stringify({
      error: "Rate limit exceeded",
      feature,
      remaining: rl.remaining,
      resetAt: rl.resetAt.toISOString(),
      limit: rl.limit,
    }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": String(retryAfterSeconds),
      },
    },
  );
}

/**
 * Per-feature MONTHLY ceilings (hard cost caps), keyed to match
 * FEATURE_LIMITS. Convention: ~10× the daily free limit — generous enough
 * that no legitimate athlete ever sees one, tight enough that a runaway
 * client loop or scripted abuse is bounded to pennies, not a bill.
 *
 * Every function pinned in rateLimit.contract.test.ts must call
 * `enforceMonthlyCap` with its feature — the contract test enforces the
 * wiring. If you add a feature to FEATURE_LIMITS, add its cap here too.
 */
export const MONTHLY_LLM_CAPS: Record<string, number> = {
  coaching:             50,
  predictor:           100,
  analysis:            100,
  parse:               100,
  injury_analysis:      50,
  plan_builder:         30,
  race:                100,
  weekly_review:        50,
  post_run:            200,
  voice_memo:          200,
  reschedule:          100,
  draft_rewrite:        10,
  workout_insight:     200,
  workout_progression: 200,
  check_in:            100,
  daily_read:           50,
  coach_workout_read:  100,
  workout_comparison:  200,
  session_ask:         150,
};

/** Fallback for features missing from MONTHLY_LLM_CAPS. */
const DEFAULT_MONTHLY_LLM_CAP = 100;

function monthlyCapResponse(
  feature: string,
  max: number,
  retryAfterSeconds: number,
  corsHeaders: Record<string, string>,
): Response {
  return new Response(
    JSON.stringify({ error: "Monthly limit reached", feature, limit: max, period: "month" }),
    {
      status: 429,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
        "Retry-After": String(retryAfterSeconds),
      },
    },
  );
}

/**
 * Hard MONTHLY ceiling for a feature, independent of the daily bucket. Use it
 * to cap expensive AI work per user per calendar month (e.g. 200 voice-memo
 * uploads). Increments only when the caller is about to do the work — call it
 * AFTER any cached-return short-circuit so re-opening existing data doesn't
 * burn quota.
 *
 * The cap comes from MONTHLY_LLM_CAPS by feature (override via `opts.max`).
 * Service-role callers bypass. In PRODUCTION, Redis-unavailable fails closed
 * (blocks) since this is a cost ceiling; local dev without Redis skips
 * (H1 fix, 2026-07-15 — previously unconfigured Redis skipped everywhere).
 */
export async function enforceMonthlyCap(
  userId: string,
  feature: string,
  corsHeaders: Record<string, string>,
  opts: { isServiceRole?: boolean; max?: number } = {},
): Promise<Response | null> {
  if (opts.isServiceRole) return null;
  // Dev-only bypass — see shouldEnforceRateLimits.
  if (!shouldEnforceRateLimits()) return null;

  const max = opts.max ?? MONTHLY_LLM_CAPS[feature] ?? DEFAULT_MONTHLY_LLM_CAP;

  // Reset at the first instant of next UTC month.
  const monthEnd = new Date();
  monthEnd.setUTCMonth(monthEnd.getUTCMonth() + 1, 1);
  monthEnd.setUTCHours(0, 0, 0, 0);
  const retryAfter = Math.max(1, Math.ceil((monthEnd.getTime() - Date.now()) / 1000));

  const client = getRedis();
  if (!client) {
    console.warn(`Monthly cap: Redis unavailable for ${feature} — denying (fail-closed)`);
    return monthlyCapResponse(feature, max, retryAfter, corsHeaders);
  }
  if (isCircuitOpen()) {
    console.warn(`Monthly cap: circuit open for ${feature} — allowing (degraded)`);
    return null;
  }

  try {
    const month = new Date().toISOString().slice(0, 7); // YYYY-MM (UTC)
    const key = `ratelimit:monthly:${feature}:${userId}:${month}`;
    const current = await client.incr(key);
    if (current === 1) {
      // Expire a few days past month end to absorb clock skew.
      await client.expire(key, retryAfter + 3 * 24 * 3600);
    }
    recordRedisSuccess();
    if (current > max) {
      console.log(`Monthly cap exceeded for ${feature} user ${userId}: ${current}/${max}`);
      return monthlyCapResponse(feature, max, retryAfter, corsHeaders);
    }
    return null;
  } catch (error) {
    console.error(`Monthly cap check failed for ${feature}:`, error);
    recordRedisFailure();
    return monthlyCapResponse(feature, max, retryAfter, corsHeaders);
  }
}
