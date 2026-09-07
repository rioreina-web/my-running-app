/**
 * session-story/story.test.ts — pure-builder tests.
 * Run: deno test supabase/functions/session-story/story.test.ts
 */
import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildStory,
  lastMilesPace,
  readMemo,
  splitHalvesByTime,
  sustainedDrift,
  thirdsFade,
  type StoryLapRow,
  type StoryLogRow,
} from "./story.ts";
import type { ZoneTable } from "../_shared/quality-volume.ts";

// Zones matching a ~5:10-mile / 5:55-MP athlete — reps at ~5:15 classify 5K-ish.
const ZONES: ZoneTable = {
  mile: 300,
  threeK: 312,
  fiveK: 320,
  tenK: 335,
  hm: 350,
  mp: 365,
  steady: 395,
  moderate: 420,
  easy: 450,
};

const METERS_PER_MILE = 1609.344;

function log(overrides: Partial<StoryLogRow> = {}): StoryLogRow {
  return {
    id: "log-1",
    workout_date: "2026-07-21",
    workout_distance_miles: 12.0,
    workout_duration_minutes: 90,
    notes: null,
    cleaned_notes: null,
    mood: null,
    weather_actual: { temp_f: 78, dew_point_f: 72 },
    ...overrides,
  };
}

/** A rep lap at `paceSec`/mi for `miles`, plus HR. */
function repLap(paceSec: number, miles: number, hr: number | null): StoryLapRow {
  return {
    is_rest: false,
    distance_meters: miles * METERS_PER_MILE,
    moving_time_seconds: paceSec * miles,
    avg_pace_sec_per_mile: paceSec,
    avg_heart_rate: hr,
    max_heart_rate: hr != null ? hr + 8 : null,
    total_elevation_gain: 2,
  };
}

function restLap(seconds: number): StoryLapRow {
  return {
    is_rest: true,
    distance_meters: 200,
    moving_time_seconds: seconds,
    avg_pace_sec_per_mile: 700,
    avg_heart_rate: 130,
  };
}

/** 6×1mi @ ~5:28 with rests, warmup/cooldown at easy pace. */
function intervalLaps(): StoryLapRow[] {
  const paces = [328, 325, 333, 334, 316, 331];
  const hrs = [160, 165, 166, 167, 170, 169];
  const out: StoryLapRow[] = [repLap(560, 1.5, 140)];
  paces.forEach((p, i) => {
    out.push(repLap(p, 1.0, hrs[i]));
    if (i < paces.length - 1) out.push(restLap(100));
  });
  out.push(repLap(570, 1.0, 138));
  return out;
}

/** A 13-mi long run: first half ~6:50, second half ~6:57. */
function longRunLaps(): StoryLapRow[] {
  const out: StoryLapRow[] = [];
  for (let i = 0; i < 13; i++) {
    const pace = i < 7 ? 410 : 417;
    const hr = i < 7 ? 151 : 156;
    out.push(repLap(pace, 1.0, hr));
  }
  return out;
}

Deno.test("interval session takes the reps path with per-rep segments + HR", () => {
  const story = buildStory({ log: log(), laps: intervalLaps(), mentions: [] }, ZONES);
  assertEquals(story.kind, "reps");
  assertEquals(story.segments.length, 6);
  assertEquals(story.segments[0].label, "R1");
  assertEquals(story.segments[0].pace_sec, 328);
  assertEquals(story.segments[0].hr, 160);
  assert(story.avg_pace_sec != null && story.avg_pace_sec > 300 && story.avg_pace_sec < 340);
  // Heat present → neutral pace is faster than raw.
  assert(story.neutral_pace_sec != null && story.neutral_pace_sec < story.avg_pace_sec!);
  assert(story.heat != null && story.heat.cost_sec_per_mi > 0);
});

Deno.test("long run takes the sustained path with halves + last-2mi", () => {
  const story = buildStory({ log: log(), laps: longRunLaps(), mentions: [] }, ZONES);
  assertEquals(story.kind, "sustained");
  const labels = story.segments.map((s) => s.label);
  assert(labels.includes("1st half") && labels.includes("2nd half"));
  assert(labels.some((l) => l.startsWith("Last")));
  // Positive fade: the run slowed in the back half.
  assert(story.fade_sec_per_mi != null && story.fade_sec_per_mi > 0);
  // Decoupling read exists and is meaningful for a 89-min run with full HR.
  assert(story.drift != null && story.drift.kind === "decoupling" && story.drift.meaningful);
});

Deno.test("no laps degrades to memo + niggles only, never throws", () => {
  const story = buildStory({
    log: log({ cleaned_notes: "Legs felt heavy but the effort was honest today." }),
    laps: [],
    mentions: [{ body_area: "knee", side: "left", severity_hint: "sore", verbatim_quote: "sore left knee" }],
  }, ZONES);
  assertEquals(story.segments.length, 0);
  assertEquals(story.avg_pace_sec, null);
  assert(story.memo != null && story.memo.text.includes("honest"));
  assertEquals(story.niggles.length, 1);
  assertEquals(story.niggles[0].body_area, "knee");
});

Deno.test("thirdsFade: last third vs first third, positive = slowing", () => {
  assertEquals(thirdsFade([300, 300, 310, 310]), 10);
  assertEquals(thirdsFade([300, 310]), null); // < 3 reps → no fade read
  const negative = thirdsFade([330, 320, 310, 300, 290, 280]);
  assert(negative != null && negative < 0);
});

Deno.test("splitHalvesByTime splits by moving time, not lap count", () => {
  // One long slow lap then many short fast laps: the time midpoint lands
  // inside the fast tail, so the halves are NOT 1-vs-rest by count.
  const laps: StoryLapRow[] = [
    repLap(600, 3.0, 140), // 30 min
    ...Array.from({ length: 6 }, () => repLap(360, 1.0, 165)), // 6 min each
  ];
  const halves = splitHalvesByTime(laps);
  assert(halves != null);
  assert(halves.pace1 > halves.pace2); // front half slower (the 600 lap dominates)
});

Deno.test("lastMilesPace reads the tail and refuses a too-short tail", () => {
  const tail = lastMilesPace(longRunLaps(), 2);
  assert(tail != null && Math.round(tail.pace) === 417);
  assertEquals(lastMilesPace([repLap(400, 0.5, 150)], 2), null);
});

Deno.test("sustainedDrift gates on duration and HR coverage", () => {
  const laps = longRunLaps();
  const halves = splitHalvesByTime(laps);
  const total = laps.reduce((a, l) => a + Number(l.moving_time_seconds ?? 0), 0);
  const ok = sustainedDrift(laps, halves, total);
  assert(ok != null && ok.meaningful);
  // Same shape but only 15 minutes of running → explicitly not meaningful.
  const short = sustainedDrift(laps, halves, 15 * 60);
  assert(short != null && !short.meaningful && short.note.length > 0);
});

Deno.test("readMemo gates auto-titles and short strings, keeps real words", () => {
  assertEquals(readMemo(log({ notes: "Morning Run" })), null);
  assertEquals(readMemo(log({ notes: "Evening Run" })), null);
  assertEquals(readMemo(log({ notes: "ok" })), null);
  const real = readMemo(log({ cleaned_notes: "Forgot to turn it off Ks again", mood: "tired" }));
  assert(real != null && real.mood === "tired");
});

Deno.test("short-rep session marks drift not meaningful instead of faking one", () => {
  // 8×200m @ ~32s reps with HR — the analyzer nulls hrDrift for short reps.
  const laps: StoryLapRow[] = [];
  for (let i = 0; i < 8; i++) {
    laps.push({
      is_rest: false,
      distance_meters: 200,
      moving_time_seconds: 32,
      avg_pace_sec_per_mile: 255,
      avg_heart_rate: 130 + i * 3,
      max_heart_rate: 150 + i * 3,
      total_elevation_gain: 0,
    });
    laps.push(restLap(60));
  }
  const story = buildStory({ log: log(), laps, mentions: [] }, ZONES);
  assertEquals(story.kind, "reps");
  if (story.drift != null) {
    assert(!story.drift.meaningful);
    assert(story.drift.note.length > 0);
  }
});
