/**
 * Memory writer — the memo pipeline's long-term-memory extractor
 * (roadmap milestone 4.1, "it knows you", 2026-07-02).
 *
 * Same shape as `niggleWriter.ts`: a PURE planner (`planMemoryWrites`) that
 * carries every decision worth testing, plus a thin, never-throws I/O wrapper
 * (`writeMemoryCandidates`) that does the reads/writes. The planner lives in
 * `_shared/` so tests import it without booting the edge function.
 *
 * The write policy is DEDUP-OR-REINFORCE (plan Step 3):
 *   - A candidate that near-duplicates an existing active memory in the same
 *     category (token overlap ≥ 0.7) does NOT insert a second row. Instead it
 *     REINFORCES the existing one: mention_count++, last_confirmed_at = now,
 *     importance += 1 (capped at 10). Re-mentioning IS the signal that
 *     something matters — that's how a preference earns its keep.
 *   - Otherwise it inserts a fresh row (source 'memo_llm').
 *   - Transient life context (durable: false) gets expires_at = now + 60d so
 *     the coach doesn't remember a head cold forever.
 *   - Episodes carry memory_date (when the moment happened) + the athlete's
 *     verbatim phrase.
 *
 * Injuries/niggles are deliberately NOT written here — they live in
 * `body_mentions` (hard rule #2, no double-surfacing). The prompt is instructed
 * to return [] for body complaints; this module also drops the 'injury'
 * category defensively.
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/** Closed category vocabulary for long-term memory (mirrors prompt v3). */
export const MEMORY_CATEGORIES = [
  "pr",
  "race",
  "preference",
  "constraint",
  "life",
  "gear",
  "episode",
] as const;
export type MemoryCategory = (typeof MEMORY_CATEGORIES)[number];

const TRANSIENT_TTL_DAYS = 60;

/** One candidate as emitted by the memo LLM (loose — validated in coerce). */
export interface MemoryCandidate {
  category: MemoryCategory;
  content: string;
  their_words?: string;
  durable: boolean;
  importance: number;
}

/** An existing active row we dedup against (subset of user_memories columns). */
export interface ExistingMemory {
  id: string;
  category: string;
  content: string;
  importance: number | null;
  mention_count: number | null;
}

/** A row shaped for INSERT into user_memories. */
export interface MemoryInsertRow {
  user_id: string;
  category: string;
  content: string;
  their_words: string | null;
  source: "memo_llm";
  status: "active";
  extracted_from: string | null;
  importance: number;
  mention_count: number;
  memory_date: string | null;
  expires_at: string | null;
  last_confirmed_at: string;
}

/** A reinforcement of an existing row (dedup path — no new row). */
export interface MemoryReinforcement {
  id: string;
  mention_count: number;
  importance: number;
  last_confirmed_at: string;
}

export interface MemoryWritePlan {
  inserts: MemoryInsertRow[];
  reinforcements: MemoryReinforcement[];
}

const DEDUP_THRESHOLD = 0.7;

// Tiny stopword set so "my marathon PR is 3:28" and "marathon PR: 3:28:00"
// collapse. Kept deliberately small — over-stemming makes distinct memories
// look alike.
const STOPWORDS = new Set([
  "a", "an", "the", "my", "i", "is", "are", "was", "were", "be", "been",
  "of", "to", "in", "on", "at", "for", "and", "or", "with", "that", "this",
  "have", "has", "had", "im", "ive",
]);

/**
 * PURE: normalize a memory string to a token set for overlap comparison.
 * Lowercases, splits on any non-alphanumeric (so "3:28" → "3","28"), drops
 * stopwords and empties.
 */
export function tokenize(s: string): Set<string> {
  return new Set(
    (s || "")
      .toLowerCase()
      .split(/[^a-z0-9]+/)
      .filter((t) => t.length > 0 && !STOPWORDS.has(t)),
  );
}

/** PURE: Jaccard overlap of two token sets (intersection / union), 0..1. */
export function tokenOverlap(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 && b.size === 0) return 1;
  if (a.size === 0 || b.size === 0) return 0;
  let inter = 0;
  for (const t of a) if (b.has(t)) inter++;
  const union = a.size + b.size - inter;
  return union === 0 ? 0 : inter / union;
}

function clampImportance(n: unknown, fallback = 5): number {
  const v = Math.round(Number(n));
  if (!Number.isFinite(v)) return fallback;
  return Math.max(1, Math.min(10, v));
}

/**
 * PURE: coerce the LLM's `memory_candidates` (array of loose objects) into
 * validated candidates. Drops anything without a valid closed-vocab category
 * or non-empty content. Defensively drops 'injury' (niggles live in
 * body_mentions). Episodes without their_words are kept but their_words is
 * required to be meaningful at render time; we keep the phrase when present.
 */
export function coerceMemoryCandidates(raw: unknown): MemoryCandidate[] {
  if (!Array.isArray(raw)) return [];
  const out: MemoryCandidate[] = [];
  for (const e of raw) {
    if (!e || typeof e !== "object") continue;
    const o = e as Record<string, unknown>;
    const category = typeof o.category === "string" ? o.category.trim().toLowerCase() : "";
    if (!MEMORY_CATEGORIES.includes(category as MemoryCategory)) continue; // drops 'injury', typos, etc.
    const content = typeof o.content === "string" ? o.content.trim() : "";
    if (content.length === 0) continue;
    const their_words = typeof o.their_words === "string" ? o.their_words.trim() : "";
    // durable defaults to true unless explicitly false.
    const durable = o.durable === false ? false : true;
    out.push({
      category: category as MemoryCategory,
      content: content.slice(0, 300),
      their_words: their_words.length > 0 ? their_words.slice(0, 300) : undefined,
      durable,
      importance: clampImportance(o.importance),
    });
  }
  return out;
}

/**
 * PURE: given validated candidates and the athlete's existing active memories,
 * decide inserts vs. reinforcements. Guards three ways:
 *   1. Near-dup of an existing row (same category, overlap ≥ 0.7) → reinforce
 *      that row (once); never a second DB row.
 *   2. Near-dup of a candidate ALREADY planned as an insert this batch →
 *      collapse (a memo that says the same thing twice writes one row).
 *   3. An existing row is reinforced at most once per batch.
 */
export function planMemoryWrites(
  userId: string,
  trainingLogId: string,
  memoDateIso: string,
  excerpt: string,
  candidates: MemoryCandidate[],
  existing: ExistingMemory[],
  nowIso: string = new Date().toISOString(),
): MemoryWritePlan {
  const inserts: MemoryInsertRow[] = [];
  const reinforcements: MemoryReinforcement[] = [];
  const reinforcedIds = new Set<string>();

  // Pre-tokenize existing rows once, grouped by category.
  const existingByCat = new Map<string, Array<{ row: ExistingMemory; tokens: Set<string> }>>();
  for (const m of existing) {
    const cat = String(m.category);
    if (!existingByCat.has(cat)) existingByCat.set(cat, []);
    existingByCat.get(cat)!.push({ row: m, tokens: tokenize(m.content) });
  }

  // Track tokens of inserts planned this batch, by category (guard #2).
  const plannedInsertTokens = new Map<string, Set<string>[]>();

  const memoDate = memoDateIso.slice(0, 10);
  const trimmedExcerpt = excerpt ? excerpt.slice(0, 200) : null;

  for (const c of candidates) {
    const candTokens = tokenize(c.content);

    // (1) Match an existing active row not yet reinforced this batch.
    let matched: { row: ExistingMemory; tokens: Set<string> } | null = null;
    let bestOverlap = 0;
    for (const cand of existingByCat.get(c.category) ?? []) {
      if (reinforcedIds.has(cand.row.id)) continue;
      const ov = tokenOverlap(candTokens, cand.tokens);
      if (ov >= DEDUP_THRESHOLD && ov > bestOverlap) {
        bestOverlap = ov;
        matched = cand;
      }
    }
    if (matched) {
      const existingImportance = matched.row.importance ?? 5;
      const existingCount = matched.row.mention_count ?? 1;
      reinforcements.push({
        id: matched.row.id,
        mention_count: existingCount + 1,
        importance: Math.min(10, existingImportance + 1),
        last_confirmed_at: nowIso,
      });
      reinforcedIds.add(matched.row.id);
      continue;
    }

    // (2) Collapse against a candidate already planned as an insert this batch.
    const planned = plannedInsertTokens.get(c.category) ?? [];
    if (planned.some((t) => tokenOverlap(candTokens, t) >= DEDUP_THRESHOLD)) {
      continue;
    }

    // (3) Fresh insert.
    const expires_at = c.durable
      ? null
      : new Date(new Date(nowIso).getTime() + TRANSIENT_TTL_DAYS * 86400000).toISOString();
    inserts.push({
      user_id: userId,
      category: c.category,
      content: c.content,
      their_words: c.their_words ?? null,
      source: "memo_llm",
      status: "active",
      extracted_from: trimmedExcerpt,
      importance: c.importance,
      mention_count: 1,
      memory_date: c.category === "episode" ? memoDate : null,
      expires_at,
      last_confirmed_at: nowIso,
    });
    plannedInsertTokens.set(c.category, [...planned, candTokens]);
  }

  return { inserts, reinforcements };
}

/**
 * I/O wrapper: coerce candidates, fetch the athlete's active same-category
 * memories, plan writes, then insert + reinforce. Runs service-role. NEVER
 * throws — a memory-write failure must not fail memo processing. Returns the
 * number inserted and reinforced.
 *
 * `excerpt` is the memo text the candidates were drawn from (stored, truncated,
 * as extracted_from provenance). `memoDateIso` is the workout/memo date used as
 * the episode memory_date.
 */
export async function writeMemoryCandidates(
  supabaseClient: SupabaseClient,
  userId: string,
  trainingLogId: string,
  memoDateIso: string,
  excerpt: string,
  rawCandidates: unknown,
): Promise<{ inserted: number; reinforced: number }> {
  try {
    const candidates = coerceMemoryCandidates(rawCandidates);
    if (candidates.length === 0) return { inserted: 0, reinforced: 0 };

    const categories = [...new Set(candidates.map((c) => c.category))];
    const { data: existingRaw, error: readErr } = await supabaseClient
      .from("user_memories")
      .select("id, category, content, importance, mention_count")
      .eq("user_id", userId)
      .eq("status", "active")
      .in("category", categories);

    if (readErr) {
      console.warn(`[memoryWriter] existing-memory read failed: ${readErr.message}`);
      // Proceed with no existing → everything inserts. Consolidation will
      // merge any dups later; better to remember than to silently drop.
    }
    const existing = (existingRaw ?? []) as ExistingMemory[];

    const { inserts, reinforcements } = planMemoryWrites(
      userId,
      trainingLogId,
      memoDateIso,
      excerpt,
      candidates,
      existing,
    );

    if (inserts.length > 0) {
      const { error: insErr } = await supabaseClient.from("user_memories").insert(inserts);
      if (insErr) {
        console.warn(`[memoryWriter] insert failed: ${insErr.message}`);
        return { inserted: 0, reinforced: 0 };
      }
      for (const r of inserts) {
        console.log(`[memoryWriter] +memory ${r.category}[imp${r.importance}${r.expires_at ? ",transient" : ""}]: ${r.content}`);
      }
    }

    let reinforced = 0;
    for (const r of reinforcements) {
      const { error: updErr } = await supabaseClient
        .from("user_memories")
        .update({
          mention_count: r.mention_count,
          importance: r.importance,
          last_confirmed_at: r.last_confirmed_at,
          updated_at: r.last_confirmed_at,
        })
        .eq("id", r.id)
        .eq("user_id", userId); // defense-in-depth: never touch another athlete's row
      if (updErr) {
        console.warn(`[memoryWriter] reinforce ${r.id} failed: ${updErr.message}`);
        continue;
      }
      reinforced++;
      console.log(`[memoryWriter] ↑memory ${r.id} → mentions=${r.mention_count}, imp=${r.importance}`);
    }

    return { inserted: inserts.length, reinforced };
  } catch (e) {
    console.warn(`[memoryWriter] error: ${e instanceof Error ? e.message : String(e)}`);
    return { inserted: 0, reinforced: 0 };
  }
}
