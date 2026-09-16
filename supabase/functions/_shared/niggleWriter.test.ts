/**
 * Tests for the niggle writer's pure transform.
 *
 * Run: deno test --allow-net _shared/niggleWriter.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildNiggleResolutions, buildNiggleRows, writeNiggleMentions } from "./niggleWriter.ts";

const USER = "11111111-1111-1111-1111-111111111111";
const LOG = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const DATE = "2026-07-01T14:30:00Z";

Deno.test("step-2 done-when: 'right calf was tight' → one memo_llm row with side + verbatim", () => {
  const { rows } = buildNiggleRows(USER, LOG, DATE, {
    soreness: [{ location: "right calf", their_words: "right calf was tight after the tempo", severity_word: "tight" }],
  });
  assertEquals(rows.length, 1);
  assertEquals(rows[0].body_area, "calf");
  assertEquals(rows[0].side, "right");
  assertEquals(rows[0].severity_hint, "tight");
  assertEquals(rows[0].source, "memo_llm");
  assertEquals(rows[0].verbatim_quote, "right calf was tight after the tempo");
  assertEquals(rows[0].mentioned_at, "2026-07-01"); // date-only
  assertEquals(rows[0].user_id, USER);
  assertEquals(rows[0].training_log_id, LOG);
});

Deno.test("diagnosis word: location maps to anatomy, condition never becomes a body_area", () => {
  const { rows } = buildNiggleRows(USER, LOG, DATE, {
    soreness: [{ location: "IT band", their_words: "my ITBS is flaring up again", severity_word: "tightness" }],
  });
  assertEquals(rows.length, 1);
  assertEquals(rows[0].body_area, "it band");
  assertEquals(rows[0].severity_hint, "tight"); // "tightness" → tight
  assert(!/itbs/i.test(rows[0].body_area), "diagnosis acronym must not appear as body_area");
  // The athlete's words are preserved verbatim, ITBS and all.
  assertEquals(rows[0].verbatim_quote, "my ITBS is flaring up again");
});

Deno.test("unmappable location is dropped, not invented", () => {
  const { rows, dropped } = buildNiggleRows(USER, LOG, DATE, {
    soreness: [{ location: "spleen", their_words: "spleen felt weird", severity_word: "weird" }],
  });
  assertEquals(rows.length, 0);
  assertEquals(dropped, ["spleen"]);
});

Deno.test("severity falls back to 'sore' when the word carries no hint", () => {
  const { rows } = buildNiggleRows(USER, LOG, DATE, {
    soreness: [{ location: "knee", their_words: "knee felt weird", severity_word: "weird" }],
  });
  assertEquals(rows[0].severity_hint, "sore");
});

Deno.test("two mentions of the same area in one memo collapse to worst severity", () => {
  const { rows } = buildNiggleRows(USER, LOG, DATE, {
    soreness: [
      { location: "left knee", their_words: "knee a little tight early", severity_word: "tight" },
      { location: "left knee", their_words: "then real pain on the descent", severity_word: "pain" },
    ],
  });
  assertEquals(rows.length, 1); // one row per area (unique index constraint)
  assertEquals(rows[0].severity_hint, "pain"); // worst wins
});

Deno.test("distinct areas each get a row", () => {
  const { rows } = buildNiggleRows(USER, LOG, DATE, {
    soreness: [
      { location: "left knee", their_words: "left knee sore", severity_word: "sore" },
      { location: "right achilles", their_words: "right achilles tight", severity_word: "tight" },
    ],
  });
  assertEquals(rows.length, 2);
  const areas = rows.map((r) => `${r.side} ${r.body_area}`).sort();
  assertEquals(areas, ["left knee", "right achilles"]);
});

Deno.test("tolerates legacy bare-string soreness entries", () => {
  const { rows } = buildNiggleRows(USER, LOG, DATE, { soreness: ["left hamstring", "calves"] });
  assertEquals(rows.length, 2);
  const byArea = Object.fromEntries(rows.map((r) => [r.body_area, r]));
  assertEquals(byArea["hamstring"].side, "left");
  assertEquals(byArea["hamstring"].verbatim_quote, "left hamstring"); // string used as its own verbatim
  assertEquals(byArea["calf"].side, null);
});

Deno.test("no soreness / null extracted → no rows", () => {
  assertEquals(buildNiggleRows(USER, LOG, DATE, null).rows.length, 0);
  assertEquals(buildNiggleRows(USER, LOG, DATE, {}).rows.length, 0);
  assertEquals(buildNiggleRows(USER, LOG, DATE, { soreness: null }).rows.length, 0);
});

Deno.test("verbatim quote is capped at 400 chars", () => {
  const long = "x".repeat(600);
  const { rows } = buildNiggleRows(USER, LOG, DATE, {
    soreness: [{ location: "knee", their_words: long, severity_word: "sore" }],
  });
  assertEquals(rows[0].verbatim_quote.length, 400);
});

// ── I/O wrapper: upsert is called with the built rows and never throws ──

Deno.test("writeNiggleMentions upserts rows and returns the count", async () => {
  const captured: { table?: string; rows?: unknown; opts?: unknown } = {};
  const fakeClient = {
    from(table: string) {
      captured.table = table;
      return {
        upsert(rows: unknown, opts: unknown) {
          captured.rows = rows;
          captured.opts = opts;
          return Promise.resolve({ error: null });
        },
      };
    },
    // deno-lint-ignore no-explicit-any
  } as any;

  const n = await writeNiggleMentions(fakeClient, USER, LOG, DATE, {
    soreness: [{ location: "right calf", their_words: "right calf tight", severity_word: "tight" }],
  });
  assertEquals(n, 1);
  assertEquals(captured.table, "body_mentions");
  assertEquals((captured.opts as { onConflict: string }).onConflict, "user_id,training_log_id,body_area");
  assertEquals((captured.rows as Array<{ body_area: string }>)[0].body_area, "calf");
});

Deno.test("writeNiggleMentions swallows upsert errors (returns 0, no throw)", async () => {
  const fakeClient = {
    from() {
      return { upsert: () => Promise.resolve({ error: { message: "boom" } }) };
    },
    // deno-lint-ignore no-explicit-any
  } as any;
  const n = await writeNiggleMentions(fakeClient, USER, LOG, DATE, {
    soreness: [{ location: "knee", their_words: "sore knee", severity_word: "sore" }],
  });
  assertEquals(n, 0);
});

// ── Resolution builder (the "it's better now" watermark) ─────────────

Deno.test("buildNiggleResolutions maps an all-clear to a resolution row with side", () => {
  const { rows } = buildNiggleResolutions(USER, LOG, DATE, {
    resolved_niggles: [{ location: "left knee", their_words: "left knee feels totally fine now" }],
  });
  assertEquals(rows.length, 1);
  assertEquals(rows[0].body_area, "knee");
  assertEquals(rows[0].side, "left");
  assertEquals(rows[0].source, "memo_llm");
  assertEquals(rows[0].resolved_at, "2026-07-01");
  assertEquals(rows[0].verbatim_quote, "left knee feels totally fine now");
});

Deno.test("buildNiggleResolutions drops unmappable locations and tolerates bare strings", () => {
  const { rows, dropped } = buildNiggleResolutions(USER, LOG, DATE, {
    resolved_niggles: ["right achilles", "spleen"],
  });
  assertEquals(rows.length, 1);
  assertEquals(rows[0].body_area, "achilles");
  assertEquals(rows[0].side, "right");
  assertEquals(dropped, ["spleen"]);
});

Deno.test("buildNiggleResolutions returns nothing when there is no all-clear", () => {
  assertEquals(buildNiggleResolutions(USER, LOG, DATE, { soreness: [{ location: "knee" }] }).rows.length, 0);
  assertEquals(buildNiggleResolutions(USER, LOG, DATE, null).rows.length, 0);
  assertEquals(buildNiggleResolutions(USER, LOG, DATE, { resolved_niggles: null }).rows.length, 0);
});
