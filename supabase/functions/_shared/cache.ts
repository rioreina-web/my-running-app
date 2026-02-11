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
 * Returns cached response if similarity > 0.92 and < 24 hours old
 */
export async function getCachedResponse(
  queryEmbedding: number[]
): Promise<CachedResponse | null> {
  const cache = getCache();
  if (!cache) return null;

  try {
    const results = await cache.query({
      vector: queryEmbedding,
      topK: 1,
      includeMetadata: true,
    });

    // Only return if similarity > 0.92 (very similar queries)
    if (results[0]?.score && results[0].score > 0.92) {
      const metadata = results[0].metadata as CachedResponse;

      // Check if cache is less than 24 hours old
      const cacheAge = Date.now() - metadata.timestamp;
      const maxAge = 24 * 60 * 60 * 1000; // 24 hours

      if (cacheAge < maxAge) {
        console.log(`Cache hit! Similarity: ${results[0].score.toFixed(3)}`);
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
  model: string
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
      } as CachedResponse,
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
