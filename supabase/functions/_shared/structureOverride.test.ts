/**
 * Tests for the athlete-facing structure correction (override).
 *
 * Run: deno test _shared/structureOverride.test.ts
 */
import { assert, assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { isUserEdited, normalizeOverride } from "./structureOverride.ts";

// The bug this feature fixes: a 3k tempo + 3×(1k,600) that auto-parsed as
// 5500m·1K·600m·1800m. The athlete corrects it to the real structure.
const CORRECTED = {
  intent_pattern: "3k tempo + 3 × (1k @ 10K, 600m @ 5K)",
  blocks: [
    { role: "warmup", distance_miles: 0.93, duration_s: 420, avg_pace_per_mile: "7:30", avg_hr: 140 },
    { role: "work_rep", distance_miles: 1.86, duration_s: 740, avg_pace_per_mile: "6:38", avg_hr: 162 }, // 3k tempo
    { role: "recovery", distance_miles: 0.2, duration_s: 180, avg_pace_per_mile: null, avg_hr: 150 },
    { role: "work_rep", distance_miles: 0.62, duration_s: 188, avg_pace_per_mile: "5:03", avg_hr: 168 }, // 1k
    { role: "recovery", distance_miles: 0.1, duration_s: 113, avg_pace_per_mile: null, avg_hr: 150 },
    { role: "work_rep", distance_miles: 0.37, duration_s: 111, avg_pace_per_mile: "4:58", avg_hr: 170 }, // 600
    { role: "recovery", distance_miles: 0.18, duration_s: 192, avg_pace_per_mile: null, avg_hr: 148 },
    { role: "work_rep", distance_miles: 0.62, duration_s: 189, avg_pace_per_mile: "5:04", avg_hr: 169 }, // 1k
    { role: "work_rep", distance_miles: 0.37, duration_s: 112, avg_pace_per_mile: "5:00", avg_hr: 171 }, // 600
    { role: "work_rep", distance_miles: 0.62, duration_s: 190, avg_pace_per_mile: "5:05", avg_hr: 170 }, // 1k
    { role: "work_rep", distance_miles: 0.37, duration_s: 113, avg_pace_per_mile: "5:02", avg_hr: 172 }, // 600
    { role: "cooldown", distance_miles: 0.8, duration_s: 400, avg_pace_per_mile: "8:20", avg_hr: 135 },
  ],
};

Deno.test("normalizeOverride: counts work reps and renumbers", () => {
  const out = normalizeOverride(CORRECTED, { type: "intervals", pattern: "old" });
  assertEquals(out.work?.reps, 7); // tempo + 1k,600,1k,600,1k,600
  // rep_num is assigned only to work_rep blocks, in order.
  const repNums = out.blocks.filter((b) => b.role === "work_rep").map((b) => b.rep_num);
  assertEquals(repNums, [1, 2, 3, 4, 5, 6, 7]);
  // recovery/warmup/cooldown carry no rep number.
  assert(out.blocks.every((b) => b.role === "work_rep" || b.rep_num === null));
});

Deno.test("normalizeOverride: stamps edit markers + carries type forward", () => {
  const out = normalizeOverride(CORRECTED, { type: "intervals" });
  assertEquals(out.edited_by_user, true);
  assert(typeof out.edited_at === "string" && out.edited_at.length > 0);
  assertEquals(out.type, "intervals"); // carried from existing auto-parse
  assertEquals(out.intent_pattern, "3k tempo + 3 × (1k @ 10K, 600m @ 5K)");
});

Deno.test("normalizeOverride: re-derives pace when missing after a split", () => {
  const split = {
    blocks: [
      // 1.24mi in 372s with no pace supplied → 5:00/mi.
      { role: "work_rep", distance_miles: 1.24, duration_s: 372 },
      { role: "recovery", distance_miles: 0.1, duration_s: 90 },
    ],
  };
  const out = normalizeOverride(split);
  assertEquals(out.blocks[0].avg_pace_per_mile, "5:00");
});

Deno.test("normalizeOverride: rejects structurally invalid input", () => {
  assertThrows(() => normalizeOverride(null), Error, "object");
  assertThrows(() => normalizeOverride({}), Error, "blocks");
  assertThrows(() => normalizeOverride({ blocks: [] }), Error, "empty");
  assertThrows(
    () => normalizeOverride({ blocks: [{ role: "sprint", distance_miles: 1, duration_s: 100 }] }),
    Error,
    "invalid role",
  );
  // No work_rep at all → meaningless as a "structure."
  assertThrows(
    () => normalizeOverride({ blocks: [{ role: "recovery", distance_miles: 0.1, duration_s: 60 }] }),
    Error,
    "at least one work_rep",
  );
});

Deno.test("isUserEdited: only true for the explicit marker", () => {
  assert(isUserEdited({ edited_by_user: true, blocks: [] }));
  assert(!isUserEdited({ edited_by_user: false, blocks: [] }));
  assert(!isUserEdited({ blocks: [] }));
  assert(!isUserEdited(null));
  assert(!isUserEdited("nope"));
});
