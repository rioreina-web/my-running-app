/**
 * Simple in-memory sliding-window rate limiter for API routes.
 *
 * Not shared across instances — suitable for single-process deployments.
 * For multi-instance deployments, swap to Redis/Upstash.
 */

interface RateLimitEntry {
  timestamps: number[];
}

const store = new Map<string, RateLimitEntry>();

// Clean up stale entries every 5 minutes
setInterval(() => {
  const cutoff = Date.now() - 120_000;
  for (const [key, entry] of store) {
    entry.timestamps = entry.timestamps.filter((t) => t > cutoff);
    if (entry.timestamps.length === 0) store.delete(key);
  }
}, 300_000);

/**
 * Check if a request is within the rate limit.
 *
 * @param key - Unique identifier (typically `userId:route`)
 * @param limit - Max requests allowed in the window
 * @param windowMs - Window size in milliseconds
 * @returns `{ allowed: true }` or `{ allowed: false, retryAfterMs }`
 */
export function checkRateLimit(
  key: string,
  limit: number,
  windowMs: number,
): { allowed: true } | { allowed: false; retryAfterMs: number } {
  const now = Date.now();
  const cutoff = now - windowMs;

  let entry = store.get(key);
  if (!entry) {
    entry = { timestamps: [] };
    store.set(key, entry);
  }

  // Drop timestamps outside the window
  entry.timestamps = entry.timestamps.filter((t) => t > cutoff);

  if (entry.timestamps.length >= limit) {
    const oldestInWindow = entry.timestamps[0];
    return { allowed: false, retryAfterMs: oldestInWindow + windowMs - now };
  }

  entry.timestamps.push(now);
  return { allowed: true };
}
