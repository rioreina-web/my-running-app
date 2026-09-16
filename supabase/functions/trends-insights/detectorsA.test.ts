/**
 * Group A detector tests — pure, no server. Run:
 *   deno test supabase/functions/trends-insights/detectorsA.test.ts
 *
 * Covers each detector's active / quiet / hidden branches, plus the
 * detection-not-diagnosis lint over every card any scenario can produce.
 */

import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { detectA1, detectA2, detectA3, detectA4 } from "./detectorsA.ts";
import { runDetectors } from "./detect.ts";
import { BANNED_TERMS, type DetectCtx } from "./contract.ts";
import type { TrendsWeekOut, TrendsDayOut, TimelineMention } from "../trends-timeline/timeline.ts";

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Build a TrendsWeekOut for the i-th Monday after 2026-01-05 (a Monday). */
function wk(
  i: number,
  o: Partial<Pick<TrendsWeekOut, "miles" | "quality_miles" | "key_pace_sec" | "mood" | "niggles" | "voice_quote">> = {},
): TrendsWeekOut {
  const base = Date.UTC(2026, 0, 5); // Mon Jan 5 2026
  const d = new Date(base + i * 7 * 24 * 60 * 60 * 1000);
  const iso = d.toISOString().split("T")[0];
  return {
    week_start: iso,
    month: MONTHS[d.getUTCMonth()],
    date_label: `${MONTHS[d.getUTCMonth()]} ${d.getUTCDate()}`,
    miles: o.miles ?? 0,
    quality_miles: o.quality_miles ?? 0,
    key_pace_sec: o.key_pace_sec ?? null,
    mood: o.mood ?? null,
    niggles: o.niggles ?? [],
    voice_quote: o.voice_quote ?? null,
  };
}

/** A body mention dated inside week i (the Wednesday of that week). */
function mention(i: number, body_area: string, side: string | null = null): TimelineMention {
  const base = Date.UTC(2026, 0, 5);
  const d = new Date(base + (i * 7 + 2) * 24 * 60 * 60 * 1000);
  return {
    body_area,
    side,
    verbatim_quote: `${body_area} grumbled today`,
    severity_hint: "tight",
    mentioned_at: d.toISOString().split("T")[0],
  };
}

/** DetectCtx with no stream data (Group A tests don't exercise B). */
function dctx(
  weeks: TrendsWeekOut[],
  mentions: TimelineMention[] = [],
  days: TrendsDayOut[] = [],
): DetectCtx {
  return { weeks, mentions, streamRuns: [], days };
}

const A4_BASE = Date.UTC(2026, 0, 5); // Mon Jan 5 2026

/** A body mention on the day `dayOffset` days after A4_BASE. */
function mentionOn(dayOffset: number, body_area: string, side: string | null = null): TimelineMention {
  const d = new Date(A4_BASE + dayOffset * 24 * 60 * 60 * 1000);
  return {
    body_area,
    side,
    verbatim_quote: `${body_area} grumbled today`,
    severity_hint: "tight",
    mentioned_at: d.toISOString().split("T")[0],
  };
}

/** A dense easy-day window of `n` days from A4_BASE, with `type` overrides by offset. */
function denseDays(n: number, overrides: Record<number, TrendsDayOut["type"]> = {}): TrendsDayOut[] {
  const out: TrendsDayOut[] = [];
  for (let i = 0; i < n; i++) {
    const d = new Date(A4_BASE + i * 24 * 60 * 60 * 1000);
    const type = overrides[i] ?? "easy";
    out.push({
      date: d.toISOString().split("T")[0],
      miles: type === "rest" ? 0 : 8,
      type,
      mood: null,
      niggles: [],
    });
  }
  return out;
}

// ─── A1 ────────────────────────────────────────────────────────────────

Deno.test("A1 hidden below the gate (< 6 logged weeks)", () => {
  const weeks = [wk(0, { miles: 30 }), wk(1, { miles: 32 })];
  const card = detectA1(dctx(weeks, [mention(0, "achilles"), mention(1, "achilles")]));
  assertEquals(card.status, "hidden");
});

Deno.test("A1 fires when same body_area clusters in the biggest weeks", () => {
  // Six low weeks + three big weeks; achilles only ever mentioned in the big ones.
  const weeks = [
    wk(0, { miles: 30 }),
    wk(1, { miles: 31 }),
    wk(2, { miles: 30 }),
    wk(3, { miles: 32 }),
    wk(4, { miles: 31 }),
    wk(5, { miles: 30 }),
    wk(6, { miles: 49, niggles: ["R achilles"] }),
    wk(7, { miles: 53, niggles: ["R achilles"] }),
    wk(8, { miles: 53, niggles: ["R achilles"] }),
  ];
  const mentions = [mention(6, "achilles", "R"), mention(7, "achilles", "R"), mention(8, "achilles", "R")];
  const card = detectA1(dctx(weeks, mentions));
  assertEquals(card.status, "active");
  assertEquals(card.confidence, "high");
  assert(card.body.includes("achilles"));
  assertEquals(card.evidence.length, 3);
});

Deno.test("A1 quiet when mentions scatter across low and high weeks", () => {
  const weeks = [
    wk(0, { miles: 30, niggles: ["L calf"] }),
    wk(1, { miles: 31 }),
    wk(2, { miles: 30 }),
    wk(3, { miles: 32 }),
    wk(4, { miles: 31 }),
    wk(5, { miles: 30 }),
    wk(6, { miles: 53, niggles: ["L calf"] }),
  ];
  const mentions = [mention(0, "calf", "L"), mention(6, "calf", "L")];
  const card = detectA1(dctx(weeks, mentions));
  assertEquals(card.status, "quiet");
});

// ─── A2 ────────────────────────────────────────────────────────────────

Deno.test("A2 hidden below the gate (< 3 weeks with mood)", () => {
  const weeks = [wk(0, { miles: 30, mood: "tired" }), wk(1, { miles: 28, mood: "tired" })];
  assertEquals(detectA2(dctx(weeks)).status, "hidden");
});

Deno.test("A2 fires on consecutive modest-load + tired weeks", () => {
  const weeks = [
    wk(0, { miles: 40, mood: "positive" }),
    wk(1, { miles: 42, mood: "energized" }),
    wk(2, { miles: 44, mood: "positive" }),
    wk(3, { miles: 30, mood: "tired" }),
    wk(4, { miles: 31, mood: "struggling" }),
    wk(5, { miles: 29, mood: "tired" }),
  ];
  const card = detectA2(dctx(weeks));
  assertEquals(card.status, "active");
  assert(card.evidence.length >= 2);
});

// ─── A3 ────────────────────────────────────────────────────────────────

Deno.test("A3 hidden below the gate (< 4 key-pace weeks)", () => {
  const weeks = [wk(0, { miles: 40, key_pace_sec: 420 }), wk(1, { miles: 42, key_pace_sec: 418 })];
  assertEquals(detectA3(dctx(weeks)).status, "hidden");
});

Deno.test("A3 fires 'absorbing' when pace falls, volume holds, mood warm", () => {
  const weeks = [
    wk(0, { miles: 38, key_pace_sec: 418, mood: "positive" }),
    wk(1, { miles: 43, key_pace_sec: 414, mood: "energized" }),
    wk(2, { miles: 48, key_pace_sec: 410, mood: "positive" }),
    wk(3, { miles: 53, key_pace_sec: 405, mood: "energized" }),
  ];
  const card = detectA3(dctx(weeks));
  assertEquals(card.status, "active");
  assert(card.headline.toLowerCase().includes("engine"));
});

Deno.test("A3 fires 'paying' when pace falls but mood reads tired", () => {
  const weeks = [
    wk(0, { miles: 44, key_pace_sec: 418, mood: "tired" }),
    wk(1, { miles: 48, key_pace_sec: 413, mood: "tired" }),
    wk(2, { miles: 50, key_pace_sec: 409, mood: "struggling" }),
    wk(3, { miles: 53, key_pace_sec: 404, mood: "tired" }),
  ];
  const card = detectA3(dctx(weeks));
  assertEquals(card.status, "active");
  assert(card.body.toLowerCase().includes("paid") || card.body.toLowerCase().includes("costing") || card.headline.toLowerCase().includes("costing"));
});

// ─── Detection-not-diagnosis lint ──────────────────────────────────────

Deno.test("no card ever emits a banned (prescriptive/causal) term", () => {
  const scenarios: DetectCtx[] = [
    // A1 active + A3 absorbing
    {
      weeks: [
        wk(0, { miles: 30 }), wk(1, { miles: 31 }), wk(2, { miles: 30 }),
        wk(3, { miles: 38, key_pace_sec: 418, mood: "positive" }),
        wk(4, { miles: 43, key_pace_sec: 414, mood: "energized" }),
        wk(5, { miles: 48, key_pace_sec: 410, mood: "positive" }),
        wk(6, { miles: 53, key_pace_sec: 405, mood: "energized", niggles: ["R achilles"] }),
        wk(7, { miles: 53, key_pace_sec: 404, mood: "positive", niggles: ["R achilles"] }),
      ],
      mentions: [mention(6, "achilles", "R"), mention(7, "achilles", "R")],
      streamRuns: [],
    },
    // A2 active + A1 quiet
    {
      weeks: [
        wk(0, { miles: 40, mood: "positive", niggles: ["L calf"] }),
        wk(1, { miles: 42, mood: "energized" }),
        wk(2, { miles: 44, mood: "positive" }),
        wk(3, { miles: 30, mood: "tired" }),
        wk(4, { miles: 31, mood: "struggling" }),
        wk(5, { miles: 29, mood: "tired", niggles: ["L calf"] }),
      ],
      mentions: [mention(0, "calf", "L"), mention(5, "calf", "L")],
      streamRuns: [],
    },
    // A4 active (weekday rhythm + key-linked) — exercises the "morning after"
    // and "the others don't" copy against the prescriptive/causal lint.
    {
      weeks: [wk(0, { miles: 40 }), wk(1, { miles: 42 })],
      mentions: [mentionOn(7, "achilles"), mentionOn(13, "calf")],
      streamRuns: [],
      days: denseDays(21, { 6: "long", 13: "long" }),
    },
  ];

  for (const ctx of scenarios) {
    for (const card of runDetectors(ctx)) {
      const text = `${card.headline} ${card.body}`.toLowerCase();
      for (const term of BANNED_TERMS) {
        const re = new RegExp(`\\b${term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`, "i");
        assert(!re.test(text), `card ${card.id} contains banned term "${term}": "${text}"`);
      }
    }
  }
});

// ─── A4 · weekday rhythm (only the daily substrate earns it) ───────────

Deno.test("A4 hidden with no daily substrate", () => {
  const card = detectA4(dctx([], [mentionOn(9, "achilles"), mentionOn(23, "achilles")], []));
  assertEquals(card.status, "hidden");
});

Deno.test("A4 hidden below the gate (< 2 mentions)", () => {
  const card = detectA4(dctx([], [mentionOn(9, "achilles")], denseDays(28)));
  assertEquals(card.status, "hidden");
});

Deno.test("A4 fires when every mention lands on the same weekday", () => {
  // Offsets 9 and 23 are both Wednesdays (base is a Monday).
  const card = detectA4(dctx([], [mentionOn(9, "achilles"), mentionOn(23, "achilles")], denseDays(28)));
  assertEquals(card.status, "active");
  assert(card.body.includes("Wednesday"));
  assert(card.body.includes("2 mentions"));
});

Deno.test("A4 fires when mentions trail hard sessions (different weekdays)", () => {
  // Long run on offset 6 (Sun) → mention offset 7 (Mon, morning after);
  // long run on offset 13 (Sun) → mention offset 13 (on the day). Diff weekdays.
  const days = denseDays(21, { 6: "long", 13: "long" });
  const card = detectA4(dctx([], [mentionOn(7, "achilles"), mentionOn(13, "calf")], days));
  assertEquals(card.status, "active");
  assert(card.body.includes("key session or the morning after"));
});

Deno.test("A4 quiet when mentions scatter with no rhythm", () => {
  // Offset 9 (Wed) and offset 15 (Tue), no hard days near either.
  const card = detectA4(dctx([], [mentionOn(9, "achilles"), mentionOn(15, "calf")], denseDays(28)));
  assertEquals(card.status, "quiet");
  assert(card.headline.toLowerCase().includes("no weekday rhythm"));
});

Deno.test("runDetectors drops hidden cards and sorts group A first", () => {
  const ctx: DetectCtx = {
    weeks: [
      wk(0, { miles: 38, key_pace_sec: 418, mood: "positive" }),
      wk(1, { miles: 43, key_pace_sec: 414, mood: "energized" }),
      wk(2, { miles: 48, key_pace_sec: 410, mood: "positive" }),
      wk(3, { miles: 53, key_pace_sec: 405, mood: "energized" }),
    ],
    mentions: [],
    streamRuns: [],
  };
  const cards = runDetectors(ctx);
  assert(cards.length > 0);
  assert(cards.every((c) => c.status !== "hidden"));
  assert(cards.every((c) => c.group === "A")); // B/C are scaffolds → hidden → dropped
});
