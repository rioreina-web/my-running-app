/**
 * Group B detector + stream-helper tests — pure, no server. Run:
 *   deno test supabase/functions/trends-insights/detectorsB.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { detectB1, detectB2, detectB5 } from "./detectorsB.ts";
import {
  band30,
  decouplingPct,
  hrr60,
  modalBand,
  paceSecFromVel,
  pickStream,
  type StreamRun,
} from "./streams.ts";
import type { DetectCtx } from "./contract.ts";

const FILL = (v: number, n: number) => new Array(n).fill(v);

function run(o: Partial<StreamRun> & { logId: string }): StreamRun {
  return {
    date: "2026-06-01",
    type: null,
    weekIndex: 0,
    weekLabel: "Jun 1",
    time: [],
    hr: [],
    vel: [],
    cadence: [],
    repEndIdx: [],
    ...o,
  };
}

/** DetectCtx carrying only stream runs (A/C not exercised here). */
function bctx(streamRuns: StreamRun[]): DetectCtx {
  return { weeks: [], mentions: [], streamRuns };
}

// ─── helpers ───────────────────────────────────────────────────────────

Deno.test("pace + band helpers", () => {
  assertEquals(Math.round(paceSecFromVel(3.0)), 536); // 3 m/s ≈ 8:56/mi
  assertEquals(band30(536), 510);
  assertEquals(paceSecFromVel(0), Infinity);
});

Deno.test("pickStream reads top-level and nested shapes", () => {
  assertEquals(pickStream({ heartrate: [1, 2, 3] }, "heartrate"), [1, 2, 3]);
  assertEquals(pickStream({ streams: { heartrate: [4, 5] } }, "heartrate"), [4, 5]);
  assertEquals(pickStream({}, "heartrate"), []);
});

Deno.test("modalBand finds the most-run pace band", () => {
  const r = run({ logId: "a", vel: [...FILL(3.0, 500), ...FILL(2.5, 100)] });
  const m = modalBand([r]);
  assert(m);
  assertEquals(m!.band, band30(paceSecFromVel(3.0)));
});

Deno.test("decouplingPct is positive when back-half HR drifts up", () => {
  const first = FILL(150, 400);
  const second = FILL(162, 400); // +8%
  const r = run({ logId: "d", hr: [...first, ...second], vel: FILL(3.0, 800) });
  const pct = decouplingPct(r);
  assert(pct != null && pct > 6 && pct < 10);
});

Deno.test("hrr60 averages post-rep drop", () => {
  const hr = FILL(170, 400);
  for (let i = 260; i < 400; i++) hr[i] = 140; // recovery after rep end at 200
  const r = run({ logId: "h", hr, repEndIdx: [200] });
  assertEquals(hrr60(r), 30); // 170 → 140
});

// ─── B1 ────────────────────────────────────────────────────────────────

Deno.test("B1 hidden with no stream data", () => {
  assertEquals(detectB1(bctx([])).status, "hidden");
});

Deno.test("B1 fires when HR at a fixed pace falls across weeks", () => {
  // Same pace (3 m/s) every week; HR 152 → 144 over 5 weeks.
  const hrs = [152, 150, 148, 146, 144];
  const runs = hrs.map((hr, w) =>
    run({ logId: `w${w}`, weekIndex: w, weekLabel: `Wk${w}`, vel: FILL(3.0, 600), hr: FILL(hr, 600) })
  );
  const card = detectB1(bctx(runs));
  assertEquals(card.status, "active");
  assert(card.body.includes("144"));
  assertEquals(card.evidence.length, 2);
});

Deno.test("B1 quiet when HR at pace is flat", () => {
  const runs = [0, 1, 2, 3].map((w) =>
    run({ logId: `w${w}`, weekIndex: w, weekLabel: `Wk${w}`, vel: FILL(3.0, 600), hr: FILL(150, 600) })
  );
  assertEquals(detectB1(bctx(runs)).status, "quiet");
});

// ─── B2 ────────────────────────────────────────────────────────────────

Deno.test("B2 fires when long-run decoupling trends down", () => {
  // Four long runs, decoupling 8% → 2%.
  const drifts = [0.08, 0.06, 0.04, 0.02];
  const runs = drifts.map((x, i) =>
    run({
      logId: `l${i}`,
      type: "long",
      date: `2026-0${i + 3}-01`,
      weekLabel: `M${i}`,
      vel: FILL(3.0, 800),
      hr: [...FILL(150, 400), ...FILL(Math.round(150 * (1 + x)), 400)],
    })
  );
  const card = detectB2(bctx(runs));
  assertEquals(card.status, "active");
});

Deno.test("B2 hidden with < 4 long runs", () => {
  const runs = [0, 1].map((i) =>
    run({ logId: `l${i}`, type: "long", vel: FILL(3.0, 800), hr: [...FILL(150, 400), ...FILL(160, 400)] })
  );
  assertEquals(detectB2(bctx(runs)).status, "hidden");
});

// ─── B5 ────────────────────────────────────────────────────────────────

Deno.test("B5 fires when between-rep recovery improves", () => {
  const drops = [20, 24, 28]; // bpm/60s over three sessions
  const runs = drops.map((d, i) => {
    const hr = FILL(170, 400);
    for (let k = 260; k < 400; k++) hr[k] = 170 - d;
    return run({ logId: `r${i}`, date: `2026-0${i + 3}-01`, weekLabel: `S${i}`, hr, repEndIdx: [200] });
  });
  const card = detectB5(bctx(runs));
  assertEquals(card.status, "active");
  assert(card.body.includes("28"));
});
