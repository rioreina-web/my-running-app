/**
 * Tests for the memory-consolidation planner.
 *
 * Run: deno test --allow-net _shared/memoryConsolidation.test.ts
 *
 * The load-bearing property (plan Step 4 done-when): running consolidation
 * twice in a row is a no-op the second time (idempotent).
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  CATEGORY_CAP,
  ConsolidatableMemory,
  consolidateMemories,
  planConsolidation,
} from "./memoryConsolidation.ts";

const NOW = "2026-07-02T12:00:00.000Z";
const daysAgo = (d: number) => new Date(new Date(NOW).getTime() - d * 86400000).toISOString();

function mem(p: Partial<ConsolidatableMemory> & { id: string; category: string; content: string }): ConsolidatableMemory {
  return {
    importance: 5,
    mention_count: 1,
    created_at: daysAgo(10),
    last_confirmed_at: daysAgo(10),
    expires_at: null,
    status: "active",
    ...p,
  };
}

/** Apply a plan to an in-memory list, returning the post-consolidation active set. */
function applyPlan(memories: ConsolidatableMemory[], plan: ReturnType<typeof planConsolidation>): ConsolidatableMemory[] {
  const archived = new Set(plan.archiveIds);
  const survivorPatch = new Map(plan.merges.map((m) => [m.keepId, m]));
  return memories
    .filter((m) => !archived.has(m.id))
    .map((m) => {
      const patch = survivorPatch.get(m.id);
      return patch
        ? { ...m, mention_count: patch.mention_count, importance: patch.importance, last_confirmed_at: patch.last_confirmed_at }
        : m;
    });
}

// ── Merge ────────────────────────────────────────────────────────────────

Deno.test("merge: near-dup rows in a category collapse to the oldest, summing mentions + max importance", () => {
  const memories = [
    mem({ id: "b", category: "preference", content: "Hates treadmills", importance: 5, mention_count: 2, created_at: daysAgo(5) }),
    mem({ id: "a", category: "preference", content: "Hates treadmills", importance: 7, mention_count: 1, created_at: daysAgo(20) }),
  ];
  const plan = planConsolidation(memories, NOW);
  assertEquals(plan.merges.length, 1);
  assertEquals(plan.merges[0].keepId, "a"); // oldest created_at
  assertEquals(plan.merges[0].dropIds, ["b"]);
  assertEquals(plan.merges[0].mention_count, 3); // 1 + 2
  assertEquals(plan.merges[0].importance, 7);    // max
  assertEquals(plan.archiveIds, ["b"]);
  assertEquals(plan.reasons["b"], "merged into a");
});

Deno.test("merge: distinct memories in the same category are left alone", () => {
  const memories = [
    mem({ id: "a", category: "preference", content: "Hates treadmills" }),
    mem({ id: "b", category: "preference", content: "Does long runs on Saturday" }),
  ];
  const plan = planConsolidation(memories, NOW);
  assertEquals(plan.merges.length, 0);
  assertEquals(plan.archiveIds.length, 0);
});

// ── Archive: expired transients + stale low-importance ────────────────────

Deno.test("archive: an expired transient is archived (not deleted)", () => {
  const memories = [
    mem({ id: "t", category: "life", content: "Traveling this week", expires_at: daysAgo(1) }),
  ];
  const plan = planConsolidation(memories, NOW);
  assertEquals(plan.archiveIds, ["t"]);
  assertEquals(plan.reasons["t"], "expired transient");
});

Deno.test("archive: year-stale low-importance row is forgotten; high-importance is kept", () => {
  const memories = [
    mem({ id: "old-low", category: "preference", content: "Likes morning runs", importance: 3, last_confirmed_at: daysAgo(400) }),
    mem({ id: "old-high", category: "constraint", content: "Works night shifts", importance: 8, last_confirmed_at: daysAgo(400) }),
  ];
  const plan = planConsolidation(memories, NOW);
  assertEquals(plan.archiveIds, ["old-low"]);
  assert(!plan.archiveIds.includes("old-high"), "importance > 4 must survive staleness");
});

// ── Cap ───────────────────────────────────────────────────────────────────

Deno.test("cap: a category over the cap archives the lowest-importance rows first", () => {
  // Genuinely distinct phrases (no shared filler tokens — otherwise they'd
  // merge before the cap stage and defeat the test).
  const words = [
    "treadmills", "hills", "trails", "mornings", "podcasts", "negatives",
    "doubles", "fasted", "heat", "cold", "track", "solo", "groups",
  ];
  const memories: ConsolidatableMemory[] = [];
  for (let i = 0; i < CATEGORY_CAP + 3; i++) {
    memories.push(mem({
      id: `p${i}`,
      category: "preference",
      content: words[i], // distinct single-token content
      importance: i + 1, // p0 lowest .. highest last; all recent so not stale
      last_confirmed_at: daysAgo(1),
    }));
  }
  const plan = planConsolidation(memories, NOW);
  assertEquals(plan.archiveIds.sort(), ["p0", "p1", "p2"].sort()); // 3 lowest importance
  for (const id of plan.archiveIds) assertEquals(plan.reasons[id], `over category cap (${CATEGORY_CAP})`);
});

// ── Idempotency (the load-bearing property) ───────────────────────────────

Deno.test("idempotent: a second consolidation over the applied result is a no-op", () => {
  const memories: ConsolidatableMemory[] = [
    mem({ id: "a", category: "preference", content: "Hates treadmills", importance: 7, created_at: daysAgo(20) }),
    mem({ id: "b", category: "preference", content: "Hates treadmills", importance: 5, created_at: daysAgo(5) }),
    mem({ id: "t", category: "life", content: "Fighting a cold", expires_at: daysAgo(2) }),
    mem({ id: "s", category: "gear", content: "Old shoe note", importance: 2, last_confirmed_at: daysAgo(500) }),
  ];
  // Add an over-cap category too.
  for (let i = 0; i < CATEGORY_CAP + 2; i++) {
    memories.push(mem({ id: `r${i}`, category: "race", content: `Ran race event ${i} in a prior season`, importance: (i % 9) + 1, last_confirmed_at: daysAgo(3) }));
  }

  const first = planConsolidation(memories, NOW);
  assert(first.merges.length + first.archiveIds.length > 0, "first pass should do work");

  const afterFirst = applyPlan(memories, first);
  const second = planConsolidation(afterFirst, NOW);
  assertEquals(second.merges.length, 0, "no merges left");
  assertEquals(second.archiveIds.length, 0, "nothing left to archive");
});

// ── I/O wrapper ────────────────────────────────────────────────────────────

Deno.test("consolidateMemories: applies survivor update + archive, returns counts", async () => {
  const rows = [
    mem({ id: "a", category: "preference", content: "Hates treadmills", importance: 7, created_at: daysAgo(20) }),
    mem({ id: "b", category: "preference", content: "Hates treadmills", importance: 5, created_at: daysAgo(5) }),
  ];
  const captured = { updates: [] as unknown[], archived: null as unknown };
  const readChain = { limit: () => Promise.resolve({ data: rows, error: null }) };
  const fake = {
    from() {
      return {
        select: () => ({ eq: () => ({ eq: () => readChain }) }),
        update(patch: Record<string, unknown>) {
          if (patch.status === "archived") {
            // .update({status}).in(ids).eq(user_id)
            return { in: (_col: unknown, ids: unknown) => ({ eq: () => { captured.archived = ids; return Promise.resolve({ error: null }); } }) };
          }
          // .update(patch).eq(id).eq(user_id)
          return { eq: () => ({ eq: () => { captured.updates.push(patch); return Promise.resolve({ error: null }); } }) };
        },
      };
    },
  } as any;

  const res = await consolidateMemories(fake, "user-1", NOW);
  assertEquals(res, { merged: 1, archived: 1 });
  assertEquals((captured.updates[0] as { mention_count: number }).mention_count, 2);
  assertEquals(captured.archived, ["b"]);
});

Deno.test("consolidateMemories: read error → zero counts, no throw", async () => {
  const errChain = { limit: () => Promise.resolve({ data: null, error: { message: "boom" } }) };
  const fake = {
    from: () => ({ select: () => ({ eq: () => ({ eq: () => errChain }) }) }),
  } as any;
  const res = await consolidateMemories(fake, "user-1", NOW);
  assertEquals(res, { merged: 0, archived: 0 });
});
