/**
 * Semantic Cache Module
 * Uses Upstash Vector for similarity-based caching of AI responses
 * Expected ~35% hit rate = 35% cost savings on LLM calls
 */

import { Index } from "https://esm.sh/@upstash/vector@1.1.1";

export interface CachedResponse {
  query: string;
  response: string;
  model: string;
  timestamp: number;
  /** Owner of the answer. Coaching answers embed the asker's personal data
   *  (paces, moods, injuries), so a hit is only valid for the same athlete.
   *  Entries without this field predate user scoping (2026-09-01) AND the
   *  pace readback guard — rejecting them doubles as the invalidation of
   *  every answer generated before paces were verified. */
  user_id?: string;
}

let cacheIndex: Index | null = null;

function getCache(): Index | null {
  if (cacheIndex) return cacheIndex;

  const url = Deno.env.get("UPSTASH_VECTOR_URL");
  const token = Deno.env.get("UPSTASH_VECTOR_TOKEN");

  if (!url || !token) {
    console.log("Upstash Vector not configured - caching disabled");
    return null;
  }

  cacheIndex = new Index({ url, token });
  return cacheIndex;
}

/**
 * Look up a similar query in the cache
 * Returns cached response if similarity > 0.92, < 24 hours old, and owned by
 * the same athlete. Unowned entries (pre-2026-09-01) are never served.
 */
export async function getCachedResponse(
  queryEmbedding: number[],
  userId: string,
): Promise<CachedResponse | null> {
  const cache = getCache();
  if (!cache) return null;

  try {
    // topK > 1 so another athlete's near-identical question doesn't shadow
    // this athlete's own cached answer.
    const results = await cache.query({
      vector: queryEmbedding,
      topK: 5,
      includeMetadata: true,
    });

    for (const result of results) {
      // Only consider very similar queries
      if (!result.score || result.score <= 0.92) continue;
      // Upstash types metadata as Dict | undefined; route through unknown.
      const metadata = result.metadata as unknown as CachedResponse;

      // A coaching answer is personal. No owner = pre-scoping entry (also
      // pre-pace-guard) — skip, never serve across athletes.
      if (metadata.user_id !== userId) continue;

      // Check if cache is less than 24 hours old
      const cacheAge = Date.now() - metadata.timestamp;
      const maxAge = 24 * 60 * 60 * 1000; // 24 hours

      if (cacheAge < maxAge) {
        console.log(`Cache hit! Similarity: ${result.score.toFixed(3)}`);
        return metadata;
      } else {
        console.log("Cache expired, fetching fresh response");
      }
    }

    return null;
  } catch (error) {
    console.error("Cache lookup failed:", error);
    return null;
  }
}

/**
 * Store a response in the semantic cache
 */
export async function cacheResponse(
  queryEmbedding: number[],
  query: string,
  response: string,
  model: string,
  userId: string,
): Promise<void> {
  const cache = getCache();
  if (!cache) return;

  try {
    await cache.upsert({
      id: crypto.randomUUID(),
      vector: queryEmbedding,
      metadata: {
        query,
        response,
        model,
        timestamp: Date.now(),
        user_id: userId,
        // Upstash's upsert wants its own Dict shape; CachedResponse is a
        // plain JSON record, so the conversion is safe.
      } as unknown as Record<string, unknown>,
    });
    console.log("Response cached successfully");
  } catch (error) {
    console.error("Cache write failed:", error);
  }
}

/**
 * Check if caching is available (Upstash configured)
 */
export function isCacheEnabled(): boolean {
  return !!Deno.env.get("UPSTASH_VECTOR_URL") && !!Deno.env.get("UPSTASH_VECTOR_TOKEN");
}
