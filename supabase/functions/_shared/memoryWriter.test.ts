/**
 * Tests for the memory writer's pure planner + I/O wrapper.
 *
 * Run: deno test --allow-net _shared/memoryWriter.test.ts
 *
 * Covers plan Step 3 "done-when": fresh insert, reinforcement path (no dup
 * row, importance bumped), transient expiry set, and PR-category dedup against
 * the legacy chat_regex rows.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  coerceMemoryCandidates,
  ExistingMemory,
  planMemoryWrites,
  tokenize,
  tokenOverlap,
  writeMemoryCandidates,
} from "./memoryWriter.ts";

const USER = "11111111-1111-1111-1111-111111111111";
const LOG = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const NOW = "2026-07-02T15:00:00.000Z";
const MEMO_DATE = "2026-07-02T09:00:00Z";

// ── coerce: closed vocabulary + clamping ─────────────────────────────────

Deno.test("coerce: keeps valid categories, drops injury/unknown, clamps importance", () => {
  const got = coerceMemoryCandidates([
    { category: "constraint", content: "Works night shifts", durable: true, importance: 8 },
    { category: "injury", content: "sore knee", durable: true, importance: 9 }, // dropped (niggles live in body_mentions)
    { category: "vibes", content: "good energy", durable: true, importance: 5 }, // dropped (not in vocab)
    { category: "preference", content: "  ", durable: true, importance: 5 },     // dropped (empty content)
    { category: "life", content: "New job", durable: true, importance: 99 },      // importance clamped to 10
  ]);
  assertEquals(got.length, 2); // injury, unknown category, and empty-content all dropped
  assertEquals(got.map((c) => c.category).sort(), ["constraint", "life"]);
  const life = got.find((c) => c.category === "life")!;
  assertEquals(life.importance, 10);
});

Deno.test("coerce: durable defaults to true, only explicit false flips it", () => {
  const got = coerceMemoryCandidates([
    { category: "life", content: "Traveling this week", durable: false, importance: 4 },
    { category: "preference", content: "Runs before work" }, // no durable → true
  ]);
  assertEquals(got.find((c) => c.content === "Traveling this week")!.durable, false);
  assertEquals(got.find((c) => c.content === "Runs before work")!.durable, true);
});

Deno.test("coerce: non-array input → []", () => {
  assertEquals(coerceMemoryCandidates(null).length, 0);
  assertEquals(coerceMemoryCandidates(undefined).length, 0);
  assertEquals(coerceMemoryCandidates("nope").length, 0);
  assertEquals(coerceMemoryCandidates({}).length, 0);
});

// ── token overlap ────────────────────────────────────────────────────────

Deno.test("tokenOverlap: PR phrasing vs legacy regex row crosses 0.7", () => {
  // Legacy chat_regex content: "marathon PR: 3:28:00"; new candidate framing.
  const ov = tokenOverlap(tokenize("my marathon PR is 3:28"), tokenize("marathon PR: 3:28:00"));
  assert(ov >= 0.7, `expected ≥0.7, got ${ov}`);
});

Deno.test("tokenOverlap: distinct preferences stay well below threshold", () => {
  const ov = tokenOverlap(tokenize("Does long runs on Saturdays"), tokenize("Hates treadmills"));
  assert(ov < 0.7, `expected <0.7, got ${ov}`);
});

// ── plan: fresh insert ───────────────────────────────────────────────────

Deno.test("plan: fresh candidate with no existing → one insert, source memo_llm", () => {
  const { inserts, reinforcements } = planMemoryWrites(
    USER, LOG, MEMO_DATE, "squeezed in 6 easy before my shift",
    coerceMemoryCandidates([{ category: "constraint", content: "Works night shifts", durable: true, importance: 8 }]),
    [], NOW,
  );
  assertEquals(reinforcements.length, 0);
  assertEquals(inserts.length, 1);
  const r = inserts[0];
  assertEquals(r.category, "constraint");
  assertEquals(r.source, "memo_llm");
  assertEquals(r.status, "active");
  assertEquals(r.mention_count, 1);
  assertEquals(r.importance, 8);
  assertEquals(r.expires_at, null);            // durable → no expiry
  assertEquals(r.memory_date, null);           // not an episode
  assertEquals(r.last_confirmed_at, NOW);
  assertEquals(r.extracted_from, "squeezed in 6 easy before my shift");
});

// ── plan: reinforcement (no dup row, importance +1, mention_count++) ──────

Deno.test("plan: near-dup of existing same-category row reinforces, does NOT insert", () => {
  // The memo LLM re-emits similar framing on re-mention (same prompt), so a
  // realistic re-mention lands ≥0.7 against the stored string. (Looser
  // paraphrases are left to the weekly consolidation job, Step 4 — the write
  // path deliberately only catches near-identical.)
  const existing: ExistingMemory[] = [
    { id: "m1", category: "constraint", content: "Works night shifts at the hospital", importance: 6, mention_count: 1 },
  ];
  const { inserts, reinforcements } = planMemoryWrites(
    USER, LOG, MEMO_DATE, "on nights again this week",
    coerceMemoryCandidates([{ category: "constraint", content: "Works night shifts", durable: true, importance: 7 }]),
    existing, NOW,
  );
  assertEquals(inserts.length, 0);
  assertEquals(reinforcements.length, 1);
  assertEquals(reinforcements[0].id, "m1");
  assertEquals(reinforcements[0].mention_count, 2);      // ++
  assertEquals(reinforcements[0].importance, 7);         // 6 + 1
  assertEquals(reinforcements[0].last_confirmed_at, NOW);
});

Deno.test("plan: reinforcement importance caps at 10", () => {
  const existing: ExistingMemory[] = [
    { id: "m1", category: "constraint", content: "Works night shifts at the hospital", importance: 10, mention_count: 4 },
  ];
  const { reinforcements } = planMemoryWrites(
    USER, LOG, MEMO_DATE, "on nights again",
    coerceMemoryCandidates([{ category: "constraint", content: "Works night shifts", durable: true, importance: 8 }]),
    existing, NOW,
  );
  assertEquals(reinforcements[0].importance, 10); // capped
});

// ── plan: PR-category dedup against the legacy chat_regex rows ────────────

Deno.test("plan: PR candidate near-dups the legacy regex PR row → reinforce, no second PR row", () => {
  const existing: ExistingMemory[] = [
    { id: "pr-legacy", category: "pr", content: "marathon PR: 3:28:00", importance: 8, mention_count: 1 },
  ];
  const { inserts, reinforcements } = planMemoryWrites(
    USER, LOG, MEMO_DATE, "reminder my marathon pr is 3:28",
    coerceMemoryCandidates([{ category: "pr", content: "My marathon PR is 3:28", durable: true, importance: 8 }]),
    existing, NOW,
  );
  assertEquals(inserts.length, 0, "must not create a duplicate PR row");
  assertEquals(reinforcements.length, 1);
  assertEquals(reinforcements[0].id, "pr-legacy");
});

// ── plan: transient expiry ───────────────────────────────────────────────

Deno.test("plan: durable:false candidate gets expires_at ~60d out", () => {
  const { inserts } = planMemoryWrites(
    USER, LOG, MEMO_DATE, "traveling for work all week",
    coerceMemoryCandidates([{ category: "life", content: "Traveling for work this week", durable: false, importance: 4 }]),
    [], NOW,
  );
  assertEquals(inserts.length, 1);
  assert(inserts[0].expires_at !== null, "transient must have expiry");
  const days = (new Date(inserts[0].expires_at!).getTime() - new Date(NOW).getTime()) / 86400000;
  assertEquals(Math.round(days), 60);
});

// ── plan: episode carries memory_date + verbatim ─────────────────────────

Deno.test("plan: episode insert carries memory_date (memo date) and their_words", () => {
  const { inserts } = planMemoryWrites(
    USER, LOG, MEMO_DATE, "the day it clicked",
    coerceMemoryCandidates([{
      category: "episode",
      content: "Called the trail 20-miler the day it clicked",
      their_words: "the day it clicked",
      durable: true,
      importance: 8,
    }]),
    [], NOW,
  );
  assertEquals(inserts.length, 1);
  assertEquals(inserts[0].memory_date, "2026-07-02"); // date-only from memoDate
  assertEquals(inserts[0].their_words, "the day it clicked");
});

// ── plan: within-batch collapse (memo says the same thing twice) ─────────

Deno.test("plan: two near-dup candidates in one memo collapse to a single insert", () => {
  const { inserts } = planMemoryWrites(
    USER, LOG, MEMO_DATE, "hate treadmills, treadmills are the worst",
    coerceMemoryCandidates([
      { category: "preference", content: "Hates treadmills", durable: true, importance: 5 },
      { category: "preference", content: "Hates treadmills", durable: true, importance: 5 },
    ]),
    [], NOW,
  );
  assertEquals(inserts.length, 1);
});

Deno.test("plan: one existing row is reinforced at most once per batch", () => {
  const existing: ExistingMemory[] = [
    { id: "m1", category: "preference", content: "Hates treadmills", importance: 5, mention_count: 1 },
  ];
  const { inserts, reinforcements } = planMemoryWrites(
    USER, LOG, MEMO_DATE, "excerpt",
    coerceMemoryCandidates([
      { category: "preference", content: "Hates treadmills", durable: true, importance: 5 },
      { category: "preference", content: "Really hates treadmills", durable: true, importance: 5 },
    ]),
    existing, NOW,
  );
  // First collapses onto m1 (reinforce); second finds m1 already reinforced,
  // so it inserts as a fresh row rather than double-bumping.
  assertEquals(reinforcements.length, 1);
  assertEquals(reinforcements[0].mention_count, 2);
  assertEquals(inserts.length, 1);
});

// ── I/O wrapper ──────────────────────────────────────────────────────────

Deno.test("writeMemoryCandidates: [] candidates → no reads/writes, zero counts", async () => {
  let called = false;
  const fake = { from() { called = true; return {}; } } as any;
  const res = await writeMemoryCandidates(fake, USER, LOG, MEMO_DATE, "x", []);
  assertEquals(res, { inserted: 0, reinforced: 0 });
  assertEquals(called, false);
});

Deno.test("writeMemoryCandidates: inserts fresh rows and reinforces existing", async () => {
  const captured: { inserted?: unknown; updates: unknown[] } = { updates: [] };
  const fake = {
    from(_table: string) {
      return {
        // read chain: select().eq().eq().in()
        select() {
          return {
            eq() {
              return {
                eq() {
                  return {
                    in() {
                      return Promise.resolve({
                        data: [{ id: "m1", category: "preference", content: "Does long runs on Saturday", importance: 6, mention_count: 1 }],
                        error: null,
                      });
                    },
                  };
                },
              };
            },
          };
        },
        insert(rows: unknown) {
          captured.inserted = rows;
          return Promise.resolve({ error: null });
        },
        update(patch: unknown) {
          return {
            eq() {
              return {
                eq() {
                  captured.updates.push(patch);
                  return Promise.resolve({ error: null });
                },
              };
            },
          };
        },
      };
    },
  } as any;

  const res = await writeMemoryCandidates(fake, USER, LOG, MEMO_DATE, "excerpt", [
    { category: "preference", content: "Does long runs on Saturday", durable: true, importance: 7 }, // dups m1 → reinforce
    { category: "constraint", content: "Works night shifts", durable: true, importance: 8 },          // fresh insert
  ]);

  assertEquals(res.inserted, 1);
  assertEquals(res.reinforced, 1);
  assertEquals((captured.inserted as Array<{ category: string }>)[0].category, "constraint");
  assertEquals((captured.updates[0] as { mention_count: number }).mention_count, 2);
});

Deno.test("writeMemoryCandidates: never throws on client error, returns zeros", async () => {
  const fake = {
    from() {
      return {
        select() { return { eq() { return { eq() { return { in() { throw new Error("boom"); } } } } } }; },
      };
    },
  } as any;
  const res = await writeMemoryCandidates(fake, USER, LOG, MEMO_DATE, "x", [
    { category: "life", content: "New job", durable: true, importance: 5 },
  ]);
  assertEquals(res, { inserted: 0, reinforced: 0 });
});
