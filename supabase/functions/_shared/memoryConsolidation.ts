/**
 * Memory consolidation — the weekly "sleep" job (plan Step 4).
 *
 * A coach remembers ~30 things about an athlete, not 3,000. This keeps the
 * store small and honest:
 *   1. MERGE remaining near-duplicates within a category (keep the oldest row,
 *      sum mention_count, take max importance). The write-path dedup only
 *      catches near-identical strings (≥0.7 at write time); looser paraphrases
 *      accumulate and get merged here.
 *   2. ARCHIVE (never delete) expired transients and memories not re-confirmed
 *      in 12 months with importance ≤ 4. Forgetting a low-signal, year-stale
 *      preference is honest — preferences change.
 *   3. CAP each category at 10 active rows, archiving lowest-importance first.
 *
 * Archiving (status → 'archived') is reversible and auditable; DELETE stays an
 * athlete-only action (Model of You). The planner is PURE and idempotent:
 * feeding it an already-consolidated set yields zero operations — the property
 * the cron relies on (running twice in a row is a no-op the second time).
 *
 * Reuses the tokenizer/overlap from memoryWriter.ts so "duplicate" means the
 * same thing on the write path and the consolidation path.
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { tokenize, tokenOverlap } from "./memoryWriter.ts";

export const CATEGORY_CAP = 10;
export const STALE_MONTHS = 12;
export const STALE_IMPORTANCE_MAX = 4;
const MERGE_THRESHOLD = 0.7;

/** Active memory row shape consumed by the planner. */
export interface ConsolidatableMemory {
  id: string;
  category: string;
  content: string;
  importance: number | null;
  mention_count: number | null;
  created_at: string;
  last_confirmed_at: string | null;
  expires_at: string | null;
  status?: string;
}

/** Update the surviving row of a merge cluster. */
export interface MergeOp {
  keepId: string;
  dropIds: string[];
  mention_count: number;
  importance: number;
  last_confirmed_at: string;
}

export interface ConsolidationPlan {
  /** Rows to update as merge survivors. */
  merges: MergeOp[];
  /** Ids to archive (expired transient, stale low-importance, or over-cap).
   *  Includes the dropIds from merges — the single source of truth for what
   *  moves to status='archived'. */
  archiveIds: string[];
  /** Human-readable reason per archived id (audit log). */
  reasons: Record<string, string>;
}

function importanceOf(m: ConsolidatableMemory): number {
  return m.importance ?? 5;
}
function confirmedAt(m: ConsolidatableMemory): number {
  return new Date(m.last_confirmed_at ?? m.created_at).getTime();
}

/**
 * PURE: decide the merge/archive operations for one athlete's active memories.
 * Deterministic and idempotent — order-independent, and a no-op on an already
 * consolidated set.
 */
export function planConsolidation(
  memories: ConsolidatableMemory[],
  nowIso: string = new Date().toISOString(),
): ConsolidationPlan {
  const nowMs = new Date(nowIso).getTime();
  const staleCutoff = nowMs - STALE_MONTHS * 30 * 86400000;

  // Only active rows participate.
  const active = memories.filter((m) => (m.status ?? "active") === "active");

  const merges: MergeOp[] = [];
  const archiveIds: string[] = [];
  const reasons: Record<string, string> = {};
  const consumed = new Set<string>(); // ids already resolved (merged away or survivors)

  // ── 1. Merge near-duplicates within each category (union-find clusters) ──
  const byCat = new Map<string, ConsolidatableMemory[]>();
  for (const m of active) {
    if (!byCat.has(m.category)) byCat.set(m.category, []);
    byCat.get(m.category)!.push(m);
  }

  // The set that survives merging (used by later stages).
  const survivors: ConsolidatableMemory[] = [];

  for (const rows of byCat.values()) {
    const toks = rows.map((r) => tokenize(r.content));
    const n = rows.length;
    const parent = rows.map((_, i) => i);
    const find = (i: number): number => (parent[i] === i ? i : (parent[i] = find(parent[i])));
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        if (tokenOverlap(toks[i], toks[j]) >= MERGE_THRESHOLD) {
          parent[find(i)] = find(j);
        }
      }
    }
    // Group by cluster root.
    const clusters = new Map<number, ConsolidatableMemory[]>();
    for (let i = 0; i < n; i++) {
      const r = find(i);
      if (!clusters.has(r)) clusters.set(r, []);
      clusters.get(r)!.push(rows[i]);
    }
    for (const cluster of clusters.values()) {
      if (cluster.length === 1) {
        survivors.push(cluster[0]);
        continue;
      }
      // Keep the OLDEST (created_at asc; tie → smallest id for determinism).
      const sorted = [...cluster].sort((a, b) => {
        const t = new Date(a.created_at).getTime() - new Date(b.created_at).getTime();
        return t !== 0 ? t : a.id.localeCompare(b.id);
      });
      const keep = sorted[0];
      const drops = sorted.slice(1);
      const mergedCount = cluster.reduce((s, m) => s + (m.mention_count ?? 1), 0);
      const mergedImportance = Math.min(10, Math.max(...cluster.map(importanceOf)));
      const mergedConfirmed = new Date(Math.max(...cluster.map(confirmedAt))).toISOString();
      merges.push({
        keepId: keep.id,
        dropIds: drops.map((d) => d.id),
        mention_count: mergedCount,
        importance: mergedImportance,
        last_confirmed_at: mergedConfirmed,
      });
      for (const d of drops) {
        archiveIds.push(d.id);
        reasons[d.id] = `merged into ${keep.id}`;
        consumed.add(d.id);
      }
      // The survivor carries the merged aggregates forward for later stages.
      survivors.push({
        ...keep,
        mention_count: mergedCount,
        importance: mergedImportance,
        last_confirmed_at: mergedConfirmed,
      });
    }
  }

  // ── 2. Archive expired transients + stale low-importance survivors ──
  const kept: ConsolidatableMemory[] = [];
  for (const m of survivors) {
    if (consumed.has(m.id)) continue;
    if (m.expires_at && new Date(m.expires_at).getTime() < nowMs) {
      archiveIds.push(m.id);
      reasons[m.id] = "expired transient";
      consumed.add(m.id);
      continue;
    }
    if (confirmedAt(m) < staleCutoff && importanceOf(m) <= STALE_IMPORTANCE_MAX) {
      archiveIds.push(m.id);
      reasons[m.id] = `stale >${STALE_MONTHS}mo, importance ≤ ${STALE_IMPORTANCE_MAX}`;
      consumed.add(m.id);
      continue;
    }
    kept.push(m);
  }

  // ── 3. Cap each category (archive lowest importance, then oldest confirm) ──
  const keptByCat = new Map<string, ConsolidatableMemory[]>();
  for (const m of kept) {
    if (!keptByCat.has(m.category)) keptByCat.set(m.category, []);
    keptByCat.get(m.category)!.push(m);
  }
  for (const rows of keptByCat.values()) {
    if (rows.length <= CATEGORY_CAP) continue;
    // Rank keepers: importance desc, then most-recently-confirmed desc.
    const ranked = [...rows].sort((a, b) => {
      const imp = importanceOf(b) - importanceOf(a);
      return imp !== 0 ? imp : confirmedAt(b) - confirmedAt(a);
    });
    for (const m of ranked.slice(CATEGORY_CAP)) {
      archiveIds.push(m.id);
      reasons[m.id] = `over category cap (${CATEGORY_CAP})`;
    }
  }

  return { merges, archiveIds, reasons };
}

/**
 * I/O wrapper: read one athlete's active memories, plan, apply. Service-role.
 * NEVER throws. Returns counts. Idempotent by construction — a second run over
 * an already-consolidated store finds nothing to do.
 */
export async function consolidateMemories(
  supabaseClient: SupabaseClient,
  userId: string,
  nowIso: string = new Date().toISOString(),
): Promise<{ merged: number; archived: number }> {
  try {
    const { data, error } = await supabaseClient
      .from("user_memories")
      .select("id, category, content, importance, mention_count, created_at, last_confirmed_at, expires_at, status")
      .eq("user_id", userId)
      .eq("status", "active")
      .limit(2000);
    if (error) {
      console.warn(`[memoryConsolidation] read failed for ${userId}: ${error.message}`);
      return { merged: 0, archived: 0 };
    }

    const plan = planConsolidation((data ?? []) as ConsolidatableMemory[], nowIso);

    // Update merge survivors first (so aggregates land before the drops archive).
    for (const mrg of plan.merges) {
      const { error: updErr } = await supabaseClient
        .from("user_memories")
        .update({
          mention_count: mrg.mention_count,
          importance: mrg.importance,
          last_confirmed_at: mrg.last_confirmed_at,
          updated_at: nowIso,
        })
        .eq("id", mrg.keepId)
        .eq("user_id", userId);
      if (updErr) console.warn(`[memoryConsolidation] survivor ${mrg.keepId} update failed: ${updErr.message}`);
      else console.log(`[memoryConsolidation] merged ${mrg.dropIds.length} into ${mrg.keepId} (mentions=${mrg.mention_count}, imp=${mrg.importance})`);
    }

    let archived = 0;
    if (plan.archiveIds.length > 0) {
      const { error: arcErr } = await supabaseClient
        .from("user_memories")
        .update({ status: "archived", updated_at: nowIso })
        .in("id", plan.archiveIds)
        .eq("user_id", userId);
      if (arcErr) {
        console.warn(`[memoryConsolidation] archive failed for ${userId}: ${arcErr.message}`);
      } else {
        archived = plan.archiveIds.length;
        for (const id of plan.archiveIds) {
          console.log(`[memoryConsolidation] archived ${id}: ${plan.reasons[id] ?? "?"}`);
        }
      }
    }

    return { merged: plan.merges.length, archived };
  } catch (e) {
    console.warn(`[memoryConsolidation] error for ${userId}: ${e instanceof Error ? e.message : String(e)}`);
    return { merged: 0, archived: 0 };
  }
}
