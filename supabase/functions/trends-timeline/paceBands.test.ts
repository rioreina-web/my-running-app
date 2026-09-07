/**
 * Tests for paceBands.ts — the Pace Bands surface's band math.
 * Run: deno test supabase/functions/trends-timeline/paceBands.test.ts
 *
 * No LLM in this path, so no eval cassette is required (the eval gate fires
 * only on `_shared/prompts/` changes). These guard the decisions the spec
 * calls out as load-bearing: the weekly step anchor, the junk-snapshot
 * filter, heat-adjusted membership, time-weighted aggregates, the overlap
 * honesty number, the two-minute gate, and honest degradation.
 */
import {
  assert,
  assertAlmostEquals,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  anchorForWeek,
  buildPaceBands,
  buildWeeklyAnchors,
  weekStartISO,
  type FitnessSnapshotRow,
  type PaceBandLap,
  type PaceBandLog,
} from "./paceBands.ts";

const M_PER_MILE = 1609.344;

/** moving_time for `meters` at `paceSecPerMile`. */
const movSecs = (meters: number, pace: number) =>
  Math.round((meters / M_PER_MILE) * pace);

/** A lap: `meters` at raw `pace`, optionally heat-adjusted + HR. */
function lap(
  meters: number,
  pace: number,
  opts: Partial<PaceBandLap> = {},
): PaceBandLap {
  return {
    is_rest: false,
    distance_meters: meters,
    avg_pace_sec_per_mile: pace,
    moving_time_seconds: movSecs(meters, pace),
    ...opts,
  };
}

/** A snapshot with half/marathon predictions implied by sec/mile paces. */
function snap(
  createdAt: string,
  hmPace: number,
  mpPace: number,
  tier: string | null = "medium",
): FitnessSnapshotRow {
  return {
    created_at: createdAt,
    predicted_half_seconds: Math.round(hmPace * 13.1094),
    predicted_marathon_seconds: Math.round(mpPace * 26.2188),
    confidence_tier: tier,
  };
}

const log = (id: string, date: string, mi?: number): PaceBandLog => ({
  id,
  workout_date: date,
  workout_distance_miles: mi ?? null,
});

// Maya-ish: HM 5:23 (323 s/mi), MP 5:38 (338 s/mi).
const SNAPS = [
  snap("2026-03-24T12:00:00Z", 324, 339),
  snap("2026-04-14T12:00:00Z", 330, 345),
  snap("2026-05-12T12:00:00Z", 323, 338),
];

// ─── Week bucketing ────────────────────────────────────────────────────

Deno.test("weekStartISO snaps to the Monday of the UTC week", () => {
  assertEquals(weekStartISO("2026-08-02"), "2026-07-27"); // a Sunday
  assertEquals(weekStartISO("2026-07-27"), "2026-07-27"); // the Monday itself
  assertEquals(weekStartISO("2026-07-28T23:59:00Z"), "2026-07-27");
});

// ─── Anchors ───────────────────────────────────────────────────────────

Deno.test("weekly anchors take the median inside a week, not the latest", () => {
  const anchors = buildWeeklyAnchors([
    snap("2026-05-11T09:00:00Z", 320, 335),
    snap("2026-05-12T09:00:00Z", 324, 339),
    snap("2026-05-13T09:00:00Z", 328, 343),
  ]);
  assertEquals(anchors.length, 1);
  assertEquals(anchors[0].week, "2026-05-11");
  assertAlmostEquals(anchors[0].hm, 324, 0.5); // median, not the 328 latest
});

Deno.test("junk snapshots are dropped before the weekly median", () => {
  // Two glitched rows ~11% and ~19% slower than the real series. Without the
  // filter the 20 Jul anchor lands ~40 s/mi off and the chart lies.
  const anchors = buildWeeklyAnchors([
    snap("2026-06-01T09:00:00Z", 324, 339),
    snap("2026-06-08T09:00:00Z", 325, 340),
    snap("2026-06-15T09:00:00Z", 323, 338),
    snap("2026-06-22T09:00:00Z", 326, 341),
    snap("2026-07-20T09:00:00Z", 361, 377), // junk (6:01)
    snap("2026-07-21T09:00:00Z", 385, 402), // junk (6:25)
  ]);
  const weeks = anchors.map((a) => a.week);
  assert(!weeks.includes("2026-07-20"), "junk week should not produce an anchor");
  assertEquals(anchors.length, 4);
});

Deno.test("a real step change in fitness survives — the filter is local, not global", () => {
  // 20 weeks at 6:20 half pace, then 6 weeks at 5:30 after a block. That's a
  // 13% shift, so a filter measuring against ONE median for the whole window
  // would discard every recent week and leave her judged against months-old
  // fitness. Measured against local neighbours, the shift is not a spike.
  const rows: FitnessSnapshotRow[] = [];
  for (let w = 0; w < 20; w++) {
    rows.push(snap(`2026-01-${String(5 + w * 1).padStart(2, "0")}T09:00:00Z`, 380, 400));
  }
  for (let w = 0; w < 6; w++) {
    rows.push(snap(`2026-03-${String(2 + w * 1).padStart(2, "0")}T09:00:00Z`, 330, 345));
  }
  const anchors = buildWeeklyAnchors(rows);
  const latest = anchors[anchors.length - 1];
  assertAlmostEquals(latest.hm, 330, 1, "the newest anchor must be the new fitness");
});

Deno.test("a genuinely improving series is not mistaken for junk", () => {
  const anchors = buildWeeklyAnchors([
    snap("2026-03-02T09:00:00Z", 335, 350),
    snap("2026-04-06T09:00:00Z", 330, 345),
    snap("2026-05-04T09:00:00Z", 325, 340),
    snap("2026-06-01T09:00:00Z", 320, 335),
  ]);
  assertEquals(anchors.length, 4);
});

Deno.test("anchors carry forward, and carry back before the first snapshot", () => {
  const anchors = buildWeeklyAnchors(SNAPS);
  // A week between snapshots holds the earlier one — a step, not a curve.
  const mid = anchorForWeek(anchors, "2026-04-27")!;
  assertEquals(mid.week, "2026-04-13");
  // A week before any snapshot carries the earliest backward rather than
  // silently deleting every session that predates the first estimate.
  const early = anchorForWeek(anchors, "2026-02-02")!;
  assertEquals(early.week, "2026-03-23");
});

Deno.test("no usable snapshots means no surface, not a guessed band", () => {
  assertEquals(buildWeeklyAnchors([]), []);
  assertEquals(
    buildWeeklyAnchors([
      { created_at: "2026-05-12T12:00:00Z", predicted_half_seconds: null, predicted_marathon_seconds: null },
    ]),
    [],
  );
  const out = buildPaceBands(
    [log("a", "2026-05-12")],
    new Map([["a", [lap(3000, 323)]]]),
    [],
  );
  assertEquals(out, null);
});

// ─── Membership ────────────────────────────────────────────────────────

Deno.test("membership rides on heat-adjusted pace, not the watch pace", () => {
  // Raw 5:52 (352) sits outside the HM band (307–339). Heat-adjusted 5:22
  // (322) sits inside it. The lap belongs to the band on what the conditions
  // say the effort was worth.
  const out = buildPaceBands(
    [log("hot", "2026-05-12", 8)],
    new Map([[
      "hot",
      [lap(5000, 352, { heat_adjusted_pace_sec_per_mile: 322, avg_heart_rate: 168 })],
    ]]),
    SNAPS,
  )!;
  assert(out !== null);
  assertEquals(out.sessions.length, 1);
  const hm = out.sessions[0].hm!;
  assertEquals(hm.pace_adj_sec, 322);
  assertEquals(hm.pace_raw_sec, 352);
  assertEquals(hm.correction_sec, 30); // the stem the UI draws
  assertEquals(hm.hr_avg, 168);
});

Deno.test("no weather falls back to raw pace with a zero correction", () => {
  const out = buildPaceBands(
    [log("cool", "2026-05-12", 8)],
    new Map([["cool", [lap(5000, 325)]]]),
    SNAPS,
  )!;
  const hm = out.sessions[0].hm!;
  assertEquals(hm.pace_adj_sec, 325);
  assertEquals(hm.pace_raw_sec, 325);
  // Zero, not a fabricated correction — the UI suppresses the stem entirely.
  assertEquals(hm.correction_sec, 0);
});

Deno.test("rest laps and GPS fragments never enter a band", () => {
  const out = buildPaceBands(
    [log("s", "2026-05-12", 6)],
    new Map([[
      "s",
      [
        lap(3000, 325), // real work, in band
        lap(1000, 325, { is_rest: true }), // flagged rest at band pace
        lap(120, 325), // 120 m fragment at band pace
      ],
    ]]),
    SNAPS,
  )!;
  const hm = out.sessions[0].hm!;
  // Only the 3000 m lap counted.
  assertAlmostEquals(hm.miles, 3000 / M_PER_MILE, 0.01);
});

Deno.test("the band steps weekly — the same pace can fall in or out", () => {
  // The identical 5:44 (344) block, run five weeks apart. Under the 13 Apr
  // anchor (HM 330 → band 313.5–346.5) it is HM work. Under the 11 May anchor
  // (HM 323 → band 306.9–339.2) the same pace is no longer HM work: her
  // fitness moved, so the band moved under her.
  const laps = new Map([
    ["apr", [lap(6000, 344)]],
    ["may", [lap(6000, 344)]],
  ]);
  const out = buildPaceBands(
    [log("apr", "2026-04-20", 8), log("may", "2026-05-18", 8)],
    laps,
    SNAPS,
  )!;
  const apr = out.sessions.find((s) => s.log_id === "apr")!;
  const may = out.sessions.find((s) => s.log_id === "may")!;
  assert(apr.hm !== null, "April: 5:44 is inside the 5:14–5:47 HM band");
  assertEquals(may.hm, null, "May: the same 5:44 is outside the 5:07–5:39 HM band");
  assertEquals(apr.hm_anchor_sec, 330);
  assertEquals(may.hm_anchor_sec, 323);
});

// ─── Aggregation ───────────────────────────────────────────────────────

Deno.test("aggregates are time-weighted, not lap-count-weighted", () => {
  // A long 5:35 (335) block and a short 5:10 (310) rep, both inside the HM
  // band (307–339) at the 11 May anchor. Lap-count weighting would say 322.5;
  // time weighting must lean hard toward the long block.
  const longMeters = 8000, shortMeters = 400;
  const out = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([["s", [lap(longMeters, 335), lap(shortMeters, 310)]]]),
    SNAPS,
  )!;
  const hm = out.sessions[0].hm!;
  const tLong = movSecs(longMeters, 335), tShort = movSecs(shortMeters, 310);
  const expected = Math.round((335 * tLong + 310 * tShort) / (tLong + tShort));
  assertEquals(hm.pace_adj_sec, expected);
  assert(hm.pace_adj_sec > 330, "must not be the 322 lap-count mean");
});

Deno.test("HR averages only over laps that carry one", () => {
  const out = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([[
      "s",
      [lap(3000, 325, { avg_heart_rate: 170 }), lap(3000, 325)],
    ]]),
    SNAPS,
  )!;
  // The HR-less lap must not pull the average toward zero.
  assertEquals(out.sessions[0].hm!.hr_avg, 170);
});

Deno.test("a session under two minutes in band is not a session in that band", () => {
  // 400 m at 325 s/mi ≈ 81 s — real running, but not band work.
  const out = buildPaceBands(
    [log("brush", "2026-05-12", 8)],
    new Map([["brush", [lap(400, 325), lap(6000, 480)]]]),
    SNAPS,
  );
  assertEquals(out, null, "nothing cleared the gate, so there is no surface");
});

Deno.test("session_mi reports the whole run, not just the in-band part", () => {
  const out = buildPaceBands(
    [log("lr", "2026-05-12", 16.5)],
    new Map([["lr", [lap(6000, 325), lap(20000, 520)]]]),
    SNAPS,
  )!;
  assertEquals(out.sessions[0].session_mi, 16.5);
  assert(out.sessions[0].hm!.miles < 4, "in-band miles are the small dark bar");
});

// ─── Overlap — the honesty number ──────────────────────────────────────

Deno.test("minutes qualifying for both bands are counted and reported", () => {
  // 11 May anchors: HM 323 (307–339), MP 338 (321–355). They share 321–339.
  // A 5:30 (330) block sits in both.
  const out = buildPaceBands(
    [log("s", "2026-05-12", 10)],
    new Map([["s", [lap(9000, 330)]]]),
    SNAPS,
  )!;
  const s = out.sessions[0];
  assert(s.hm !== null && s.mp !== null, "the block belongs to both bands");
  assertAlmostEquals(s.overlap_min, movSecs(9000, 330) / 60, 0.2);
  assert(out.overlap !== null);
  assertEquals(out.overlap!.gap_sec, 15); // 338 − 323
  assertEquals(out.overlap!.width_sec, 18); // 339 − 321
  assertEquals(out.overlap!.weeks_overlapping, out.overlap!.weeks_total);
});

Deno.test("overlap is measured symmetrically when MP comes out faster than HM", () => {
  // A stale half prediction can invert the usual order: HM 6:40, MP 5:20.
  // Bands 380–420 and 304–336 share nothing. Assuming HM is always the faster
  // anchor would report a 116 s/mi overlap between two disjoint bands, and
  // drive the persistent "your bands overlap" note off a fiction.
  const inverted = [snap("2026-05-12T12:00:00Z", 400, 320)];
  const out = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([["s", [lap(6000, 320)]]]),
    inverted,
  )!;
  assertEquals(out.overlap, null);
});

Deno.test("overlap width is the shared pace, not the distance between edges", () => {
  // HM 5:40 (340 → 323–357), MP 5:20 (320 → 304–336). They do overlap, but
  // only across 323–336: 13 s/mi, not the 53 an order-assuming subtraction
  // would report.
  const out = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([["s", [lap(6000, 330)]]]),
    [snap("2026-05-12T12:00:00Z", 340, 320)],
  )!;
  assertEquals(out.overlap!.width_sec, 13);
});

Deno.test("bands that never touch report no overlap", () => {
  // HM 5:23 vs MP 7:00 — far enough apart that ±5% never meets.
  const wide = [snap("2026-05-12T12:00:00Z", 323, 420)];
  const out = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([["s", [lap(6000, 325)]]]),
    wide,
  )!;
  assertEquals(out.overlap, null);
  assertEquals(out.sessions[0].mp, null);
});

// ─── Window shape ──────────────────────────────────────────────────────

Deno.test("sessions come back oldest → newest with per-band summaries", () => {
  // At the 11 May anchors the HM band is 307–339 and the MP band 321–355, so
  // 325 is in both and 345 is MP-only. Two HM sessions, three MP.
  const laps = new Map([
    ["c", [lap(6000, 325)]],
    ["a", [lap(6000, 325)]],
    ["b", [lap(6000, 345)]],
  ]);
  const out = buildPaceBands(
    [log("c", "2026-05-26", 8), log("a", "2026-05-12", 8), log("b", "2026-05-19", 8)],
    laps,
    SNAPS,
  )!;
  assertEquals(out.sessions.map((s) => s.log_id), ["a", "b", "c"]);
  assertEquals(out.window_start, "2026-05-12");
  assertEquals(out.window_end, "2026-05-26");
  assertEquals(out.hm.sessions, 2);
  assertEquals(out.mp.sessions, 3);
  assertEquals(out.sessions[1].hm, null, "the 5:45 session is MP work only");
  assertEquals(out.hm.anchor_sec, 323);
  assertEquals(out.hm.fast_sec, 307);
  assertEquals(out.hm.slow_sec, 339);
  assertEquals(out.confidence_tier, "medium");
});

Deno.test("dew point rides along for the readout without touching membership", () => {
  const out = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([["s", [lap(6000, 325)]]]),
    SNAPS,
    new Map([["s", 70.4]]),
  )!;
  assertEquals(out.sessions[0].dew_point_f, 70);
});

Deno.test("confidence comes from a snapshot that survived the filter", () => {
  // The junk row is also the newest AND the only 'low' one. Reading tiers off
  // the raw rows would mark the band LOW CONFIDENCE on data that contributed
  // nothing to the anchor.
  const rows = [
    snap("2026-05-01T09:00:00Z", 323, 338, "high"),
    snap("2026-05-08T09:00:00Z", 324, 339, "high"),
    snap("2026-05-15T09:00:00Z", 322, 337, "high"),
    snap("2026-05-18T09:00:00Z", 325, 340, "high"),
    snap("2026-05-19T09:00:00Z", 420, 440, "low"), // junk
  ];
  const out = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([["s", [lap(6000, 325)]]]),
    rows,
  )!;
  assertEquals(out.confidence_tier, "high");
});

Deno.test("a malformed timestamp drops out instead of taking the surface down", () => {
  // `weekStartISO` used to throw here, and one bad row killed everything.
  assertEquals(weekStartISO("not-a-date"), "not-a-date");
  assertEquals(weekStartISO(""), "");
  const anchors = buildWeeklyAnchors([
    { created_at: "", predicted_half_seconds: 4234, predicted_marathon_seconds: 8863 },
    snap("2026-05-12T12:00:00Z", 323, 338),
  ]);
  assert(anchors.length >= 1);
});

Deno.test("a lap with distance but no clock still counts toward session miles", () => {
  // It can't be time-weighted into a band, but it IS ground she covered — the
  // pale session-total bar must not shrink because a watch dropped a duration.
  const out = buildPaceBands(
    [log("s", "2026-05-12")], // no workout_distance_miles → laps are the fallback
    new Map([[
      "s",
      [lap(6000, 325), { ...lap(5000, 325), moving_time_seconds: null }],
    ]]),
    SNAPS,
  )!;
  assertAlmostEquals(out.sessions[0].session_mi, 11000 / M_PER_MILE, 0.02);
  // ...but only the timed lap is in the band.
  assertAlmostEquals(out.sessions[0].hm!.miles, 6000 / M_PER_MILE, 0.02);
});

Deno.test("non-numeric lap values are rejected, not concatenated", () => {
  const bad = {
    is_rest: false,
    distance_meters: "6000",
    avg_pace_sec_per_mile: 325,
    moving_time_seconds: "1212",
  } as unknown as PaceBandLap;
  const out = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([["s", [bad, lap(6000, 325)]]]),
    SNAPS,
  )!;
  // Only the well-typed lap survived — no 12121212-second accumulator.
  assertAlmostEquals(out.sessions[0].hm!.minutes, movSecs(6000, 325) / 60, 0.1);
});

Deno.test("band edges are inclusive, matching the spec's BETWEEN", () => {
  // 11 May HM anchor 323 → slow edge 339.15. A lap exactly on the edge is in.
  const edge = 339;
  const out = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([["s", [lap(6000, edge)]]]),
    SNAPS,
  )!;
  assert(out.sessions[0].hm !== null, "a lap on the slow edge is in band")
  const past = buildPaceBands(
    [log("s", "2026-05-12", 8)],
    new Map([["s", [lap(6000, 341)]]]),
    SNAPS,
  )!;
  assertEquals(past.sessions[0].hm, null, "a lap past the edge is not")
});

Deno.test("a workout with no laps is absent, never a faked zero", () => {
  const out = buildPaceBands(
    [log("has", "2026-05-12", 8), log("none", "2026-05-14", 8)],
    new Map([["has", [lap(6000, 325)]]]),
    SNAPS,
  )!;
  assertEquals(out.sessions.length, 1);
  assertEquals(out.sessions[0].log_id, "has");
});
