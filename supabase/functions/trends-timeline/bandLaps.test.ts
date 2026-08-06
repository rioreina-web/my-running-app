/**
 * Tests for bandLaps.ts — the substrate an adjustable pace band reads.
 * Run: deno test supabase/functions/trends-timeline/bandLaps.test.ts
 *
 * No LLM in this path, so no eval cassette is required.
 *
 * These guard the decisions that make the client-side controls possible at
 * all: that the ladder matches the canonical pace table, that MP and HMP stay
 * bit-identical to the Pace Bands surface's anchors, that lap ORDER and the
 * breaks in it survive the wire (a longest-block minimum is meaningless if
 * rest laps are filtered out on the way), and that the payload degrades to
 * null rather than to a guess.
 */
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { buildBandLaps, ladderFor } from "./bandLaps.ts";
import {
  buildPaceBands,
  buildWeeklyAnchors,
  type FitnessSnapshotRow,
  type PaceBandLap,
  type PaceBandLog,
} from "./paceBands.ts";
import { derivePaceTableFromGoal } from "../_shared/paces.ts";
import { analyticsRunLogs, type TimelineLog } from "./timeline.ts";

const M_PER_MILE = 1609.344;

/** moving_time for `meters` at `paceSecPerMile`. */
const movSecs = (meters: number, pace: number) =>
  Math.round((meters / M_PER_MILE) * pace);

/** A lap: `meters` at raw `pace`, optionally heat-adjusted / HR / rest. */
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

const MILE = 1609;

// ─── The ladder ────────────────────────────────────────────────────────

Deno.test("ladder derives LT/10K/5K/3K/mile from the canonical pace table", () => {
  const anchor = { week: "2026-05-11", hm: 323, mp: 338 };
  const table = derivePaceTableFromGoal(323, "half_marathon");
  const ladder = ladderFor(anchor);

  assertEquals(ladder.lt, Math.round(table.threshold));
  assertEquals(ladder.k10, Math.round(table.tenK));
  assertEquals(ladder.k5, Math.round(table.fiveK));
  assertEquals(ladder.k3, Math.round(table.threeK));
  assertEquals(ladder.mile, Math.round(table.mile));
});

Deno.test("ladder is ordered fastest → slowest across the race zones", () => {
  const l = ladderFor({ week: "2026-05-11", hm: 323, mp: 338 });
  // Smaller sec/mile = faster. Mile is the fastest anchor, MP the slowest.
  assert(l.mile < l.k3, "mile faster than 3K");
  assert(l.k3 < l.k5, "3K faster than 5K");
  assert(l.k5 < l.k10, "5K faster than 10K");
  assert(l.k10 < l.lt, "10K faster than LT");
  assert(l.lt < l.hmp, "LT faster than HMP");
  assert(l.hmp < l.mp, "HMP faster than MP");
});

Deno.test("MP and HMP anchors are the SAME numbers the Pace Bands surface draws", () => {
  // The two surfaces sit one scroll apart. If MP means 5:38 on one and 5:39 on
  // the other, both are wrong to the athlete.
  const anchors = buildWeeklyAnchors(SNAPS);
  const latest = anchors[anchors.length - 1];
  const ladder = ladderFor(latest);

  const logs = [log("a", "2026-05-14", 8)];
  const laps = new Map<string, PaceBandLap[]>([["a", [lap(MILE * 4, 323)]]]);
  const bands = buildPaceBands(logs, laps, SNAPS)!;

  assertEquals(ladder.hmp, bands.hm.anchor_sec);
  assertEquals(ladder.mp, bands.mp.anchor_sec);
});

// ─── Order and breaks ──────────────────────────────────────────────────

Deno.test("rest laps SHIP, flagged — they are the breaks between blocks", () => {
  // Four in-band miles broken by three recovery jogs. A client measuring the
  // longest unbroken stretch must see seven laps, not four: filtering the
  // recoveries out makes 4×1mi look like one continuous 4-mile block.
  const laps: PaceBandLap[] = [
    lap(MILE, 320),
    lap(600, 480, { is_rest: true }),
    lap(MILE, 322),
    lap(600, 480, { is_rest: true }),
    lap(MILE, 319),
    lap(600, 480, { is_rest: true }),
    lap(MILE, 321),
  ];
  const out = buildBandLaps(
    [log("a", "2026-05-14", 8)],
    new Map([["a", laps]]),
    SNAPS,
  )!;

  const session = out.sessions[0];
  assertEquals(session.laps.length, 7);
  assertEquals(session.laps.map((l) => l.skip), [
    false,
    true,
    false,
    true,
    false,
    true,
    false,
  ]);
});

Deno.test("GPS fragments ship flagged rather than dropped", () => {
  const laps: PaceBandLap[] = [
    lap(MILE, 320),
    lap(200, 400), // under MIN_LAP_METERS
    lap(MILE, 321),
  ];
  const out = buildBandLaps([log("a", "2026-05-14")], new Map([["a", laps]]), SNAPS)!;
  assertEquals(out.sessions[0].laps.map((l) => l.skip), [false, true, false]);
});

Deno.test("laps keep their input order", () => {
  const laps = [lap(MILE, 400), lap(MILE, 320), lap(MILE, 360)];
  const out = buildBandLaps([log("a", "2026-05-14")], new Map([["a", laps]]), SNAPS)!;
  assertEquals(out.sessions[0].laps.map((l) => l.raw), [400, 320, 360]);
});

Deno.test("a lap with no pace or no clock is dropped, not flagged", () => {
  // It cannot be in a band AND it is not evidence of a break — it is simply
  // unrecorded. Shipping it as a break would invent a gap that never happened.
  const laps: PaceBandLap[] = [
    lap(MILE, 320),
    { is_rest: false, distance_meters: MILE, avg_pace_sec_per_mile: null, moving_time_seconds: 300 },
    { is_rest: false, distance_meters: MILE, avg_pace_sec_per_mile: 320, moving_time_seconds: null },
    lap(MILE, 321),
  ];
  const out = buildBandLaps([log("a", "2026-05-14")], new Map([["a", laps]]), SNAPS)!;
  assertEquals(out.sessions[0].laps.length, 2);
  assertEquals(out.sessions[0].laps.every((l) => !l.skip), true);
});

// ─── Membership pace ───────────────────────────────────────────────────

Deno.test("adj carries the heat-adjusted pace, raw carries the watch", () => {
  const laps = [lap(MILE, 334, { heat_adjusted_pace_sec_per_mile: 320 })];
  const out = buildBandLaps([log("a", "2026-05-14")], new Map([["a", laps]]), SNAPS)!;
  assertEquals(out.sessions[0].laps[0].raw, 334);
  assertEquals(out.sessions[0].laps[0].adj, 320);
});

Deno.test("no weather on file → adj equals raw, never a fabricated correction", () => {
  const laps = [lap(MILE, 334)];
  const out = buildBandLaps([log("a", "2026-05-14")], new Map([["a", laps]]), SNAPS)!;
  assertEquals(out.sessions[0].laps[0].adj, 334);
  assertEquals(out.sessions[0].laps[0].raw, 334);
});

// ─── Sessions and the window ───────────────────────────────────────────

Deno.test("the ladder steps weekly — a run is judged against its own week", () => {
  const out = buildBandLaps(
    [log("early", "2026-04-20"), log("late", "2026-05-14")],
    new Map([
      ["early", [lap(MILE, 330)]],
      ["late", [lap(MILE, 323)]],
    ]),
    SNAPS,
  )!;

  // 20 Apr sits under the 14 Apr snapshot (HM 330); 14 May under 12 May (323).
  assertEquals(out.sessions[0].anchors.hmp, 330);
  assertEquals(out.sessions[1].anchors.hmp, 323);
});

Deno.test("sessions are date-sorted regardless of input order", () => {
  const out = buildBandLaps(
    [log("c", "2026-06-01"), log("a", "2026-05-01"), log("b", "2026-05-20")],
    new Map([
      ["a", [lap(MILE, 320)]],
      ["b", [lap(MILE, 321)]],
      ["c", [lap(MILE, 322)]],
    ]),
    SNAPS,
  )!;
  assertEquals(out.sessions.map((s) => s.log_id), ["a", "b", "c"]);
  assertEquals(out.window_start, "2026-05-01");
  assertEquals(out.window_end, "2026-06-01");
});

Deno.test("session_mi prefers the log's own distance over summed laps", () => {
  // A double: the laps only cover the second run, the log knows the whole day.
  const out = buildBandLaps(
    [log("a", "2026-05-14", 14.2)],
    new Map([["a", [lap(MILE, 320)]]]),
    SNAPS,
  )!;
  assertEquals(out.sessions[0].session_mi, 14.2);
});

Deno.test("an all-rest session is left out — nothing there can ever be in band", () => {
  const out = buildBandLaps(
    [log("a", "2026-05-14"), log("b", "2026-05-16")],
    new Map([
      ["a", [lap(600, 480, { is_rest: true }), lap(200, 500)]],
      ["b", [lap(MILE, 320)]],
    ]),
    SNAPS,
  );
  assertEquals(out!.sessions.map((s) => s.log_id), ["b"]);
});

Deno.test("EVERY session with a usable lap ships — the band gate is the client's call", () => {
  // This is the whole point of the sibling payload. `paceBands` drops a session
  // that held under two minutes in HM/MP; here a 90-second touch must survive,
  // because at ±8% around LT it may be half a workout.
  const laps = [lap(400, 300)]; // ~75 s, nowhere near the 2-minute band gate
  const logs = [log("a", "2026-05-14")];
  const lapMap = new Map([["a", laps]]);

  assertEquals(buildPaceBands(logs, lapMap, SNAPS), null);
  assertEquals(buildBandLaps(logs, lapMap, SNAPS)!.sessions.length, 1);
});

// ─── Dedup (the caller's half of the contract) ─────────────────────────

Deno.test("a run logged by BOTH Strava and voice is one session, not two", () => {
  // The exact shape found in prod 2026-08-05: same timestamp, same distance,
  // same duration, same laps, neither trimmed. Before `analyticsRunLogs` was
  // applied at the band call site, every in-band minute of these counted
  // twice — and on the live athlete that was the two biggest threshold
  // sessions of the block.
  const rows: TimelineLog[] = [
    {
      id: "strava-1", workout_date: "2026-07-21T11:28:05Z",
      workout_distance_miles: 7.5, workout_duration_minutes: 43.17,
      workout_type: "run", workout_pace_per_mile: null, mood: null,
      source: "strava", stats_excluded: null,
    },
    {
      id: "voice-1", workout_date: "2026-07-21T11:28:05Z",
      workout_distance_miles: 7.5, workout_duration_minutes: 43.17,
      workout_type: "run", workout_pace_per_mile: null, mood: null,
      source: "voice_log", stats_excluded: false,
    },
  ];

  const kept = analyticsRunLogs(rows);
  assertEquals(kept.length, 1);
  // Strava outranks voice_log: the GPS row is the one with real lap data.
  assertEquals(kept[0].id, "strava-1");

  const laps = new Map<string, PaceBandLap[]>([
    ["strava-1", [lap(MILE * 6, 320)]],
    ["voice-1", [lap(MILE * 6, 320)]],
  ]);

  const deduped = buildBandLaps(kept, laps, SNAPS)!;
  const naive = buildBandLaps(rows, laps, SNAPS)!;
  assertEquals(deduped.sessions.length, 1);
  assertEquals(naive.sessions.length, 2); // what the bug looked like
});

Deno.test("a genuine double stays two sessions", () => {
  // Same day, same source, different distances — a real morning/evening
  // double must not be collapsed by the dedup that catches cross-source
  // duplicates.
  const rows: TimelineLog[] = [
    {
      id: "am", workout_date: "2026-07-21T06:05:00Z",
      workout_distance_miles: 2.0, workout_duration_minutes: 15.7,
      workout_type: "run", workout_pace_per_mile: null, mood: null,
      source: "strava", stats_excluded: null,
    },
    {
      id: "pm", workout_date: "2026-07-21T23:28:00Z",
      workout_distance_miles: 3.9, workout_duration_minutes: 28.8,
      workout_type: "run", workout_pace_per_mile: null, mood: null,
      source: "strava", stats_excluded: null,
    },
  ];
  assertEquals(analyticsRunLogs(rows).length, 2);
});

Deno.test("a trimmed run is out — the athlete's decision still wins", () => {
  const rows: TimelineLog[] = [
    {
      id: "trimmed", workout_date: "2026-07-21T06:05:00Z",
      workout_distance_miles: 6.0, workout_duration_minutes: 40,
      workout_type: "run", workout_pace_per_mile: null, mood: null,
      source: "strava", stats_excluded: true,
    },
  ];
  assertEquals(analyticsRunLogs(rows).length, 0);
});

// ─── Honest degradation ────────────────────────────────────────────────

Deno.test("no usable snapshot → null, never a guessed ladder", () => {
  const logs = [log("a", "2026-05-14")];
  const laps = new Map([["a", [lap(MILE, 320)]]]);
  assertEquals(buildBandLaps(logs, laps, []), null);
  assertEquals(
    buildBandLaps(logs, laps, [
      { created_at: "2026-05-01", predicted_half_seconds: null, predicted_marathon_seconds: null },
    ]),
    null,
  );
});

Deno.test("no laps at all → null", () => {
  assertEquals(buildBandLaps([log("a", "2026-05-14")], new Map(), SNAPS), null);
});

Deno.test("confidence tier comes from the latest surviving snapshot", () => {
  const out = buildBandLaps(
    [log("a", "2026-05-14")],
    new Map([["a", [lap(MILE, 320)]]]),
    [...SNAPS, snap("2026-05-19T12:00:00Z", 322, 337, "low")],
  )!;
  assertEquals(out.confidence_tier, "low");
});

Deno.test("dew point is carried for the readout and never touches membership", () => {
  const out = buildBandLaps(
    [log("a", "2026-05-14"), log("b", "2026-05-16")],
    new Map([
      ["a", [lap(MILE, 320)]],
      ["b", [lap(MILE, 320)]],
    ]),
    SNAPS,
    new Map([["a", 71.4]]),
  )!;
  assertEquals(out.sessions[0].dew_point_f, 71);
  assertEquals(out.sessions[1].dew_point_f, null);
  // Same lap, same adj, with and without weather on file.
  assertEquals(out.sessions[0].laps[0].adj, out.sessions[1].laps[0].adj);
});
