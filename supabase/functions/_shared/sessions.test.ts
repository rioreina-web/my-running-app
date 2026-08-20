import { assertEquals } from "jsr:@std/assert@1";
import {
  buildSessions, weeklyTotals, localDayKey, rankWorkout, normalizeWorkoutType, isQuality,
  assertPlausibleStartHours,
} from "./sessions.ts";

const TZ = "America/Chicago"; // the athlete's timezone, UTC-5 in August

function p(id: string, iso: string, miles: number, min: number, type?: string, extra: Record<string, unknown> = {}) {
  return { id, workoutDate: iso, miles, durationMinutes: min, workoutType: type ?? null, ...extra };
}

Deno.test("THE case: wu + tempo + cd is ONE session, not three runs", () => {
  const s = buildSessions([
    p("a", "2026-08-18T11:00:00Z", 2.1, 18, "easy"),      // 6:00am local
    p("b", "2026-08-18T11:25:00Z", 6.2, 38, "tempo"),     // 6:25am
    p("c", "2026-08-18T12:10:00Z", 2.0, 18, "easy"),      // 7:10am
  ], TZ);
  assertEquals(s.length, 1);
  assertEquals(s[0].pieces.length, 3);
  assertEquals(s[0].miles, 10.3);
  assertEquals(s[0].typeKey, "threshold");   // named for the tempo, not the warm-up
  assertEquals(s[0].isQuality, true);
  assertEquals(s[0].isSecond, false);
});

Deno.test("THE other case: a genuine double is TWO sessions", () => {
  const s = buildSessions([
    p("a", "2026-08-17T11:00:00Z", 6.0, 48, "easy"),   // 6:00am
    p("b", "2026-08-17T22:30:00Z", 4.0, 32, "easy"),   // 5:30pm
  ], TZ);
  assertEquals(s.length, 2);
  assertEquals(s[1].isSecond, true);
  assertEquals(weeklyTotals(s).miles, 10);
  assertEquals(weeklyTotals(s).daysRun, 1);
});

Deno.test("full day: morning workout + evening double = 2 sessions, 4 pieces", () => {
  const s = buildSessions([
    p("a", "2026-08-18T11:00:00Z", 2.1, 18, "easy"),
    p("b", "2026-08-18T11:25:00Z", 6.2, 38, "tempo"),
    p("c", "2026-08-18T12:10:00Z", 2.0, 18, "easy"),
    p("d", "2026-08-18T22:00:00Z", 5.0, 40, "easy"),   // 5pm double
  ], TZ);
  assertEquals(s.length, 2);
  assertEquals(s.map((x) => x.pieces.length), [3, 1]);
  assertEquals(s[0].miles, 10.3);
  assertEquals(s[1].miles, 5);
  assertEquals(s[1].isSecond, true);
  const w = weeklyTotals(s);
  assertEquals(w.sessions, 2);
  assertEquals(w.pieces, 4);
  assertEquals(w.doubles, 1);
  assertEquals(w.miles, 15.3);
});

Deno.test("a 65-minute gap stays ONE session", () => {
  // Gap measured from the previous piece's END. This was originally named
  // "the 65-minute gap from Jul 21" — that Jul 21 gap turned out to be an
  // artifact of local-as-UTC timestamps (see the REAL DATA tests below). The
  // behaviour is still correct; 65 min sits inside the observed 73-min
  // intra-session ceiling. Only the justification changed.
  const s = buildSessions([
    p("a", "2026-08-18T11:00:00Z", 2.0, 16, "easy"),
    p("b", "2026-08-18T12:21:00Z", 2.0, 16, "easy"), // 65 min after a's end
  ], TZ);
  assertEquals(s.length, 1);
});

Deno.test("a 2-hour gap splits — a shakeout is not the workout", () => {
  const s = buildSessions([
    p("a", "2026-08-18T11:00:00Z", 2.0, 16, "easy"),
    p("b", "2026-08-18T13:20:00Z", 8.0, 60, "tempo"),
  ], TZ);
  assertEquals(s.length, 2);
});

Deno.test("LOCAL day, not UTC: a 7:01pm run belongs to the day it was run", () => {
  // Aug 5 7:01pm Chicago == 2026-08-06T00:01Z
  assertEquals(localDayKey("2026-08-06T00:01:00Z", TZ), "2026-08-05");
  const s = buildSessions([p("a", "2026-08-06T00:01:00Z", 5, 40, "easy")], TZ);
  assertEquals(s[0].day, "2026-08-05");
});

Deno.test("UTC-boundary double does NOT merge across the local date line", () => {
  const s = buildSessions([
    p("a", "2026-08-15T01:30:00Z", 4.0, 32, "easy"), // Aug 14, 8:30pm local
    p("b", "2026-08-15T11:00:00Z", 4.0, 32, "easy"), // Aug 15, 6:00am local
  ], TZ);
  assertEquals(s.length, 2);
  assertEquals(s.map((x) => x.day), ["2026-08-14", "2026-08-15"]);
  assertEquals(s.every((x) => !x.isSecond), true); // different days, neither is a double
});

Deno.test("session is named for its hardest piece, whatever the order", () => {
  const s = buildSessions([
    p("a", "2026-08-18T11:00:00Z", 2, 16, "recovery"),
    p("b", "2026-08-18T11:20:00Z", 5, 30, "intervals"),
    p("c", "2026-08-18T12:00:00Z", 2, 16, "recovery"),
  ], TZ);
  assertEquals(s[0].typeKey, "intervals");
});

Deno.test("an UNKNOWN workout type never names the session", () => {
  const s = buildSessions([
    p("a", "2026-08-18T11:00:00Z", 2, 16, "brick"),    // not on the ladder → -1
    p("b", "2026-08-18T11:20:00Z", 5, 30, "threshold"),
  ], TZ);
  assertEquals(s[0].typeKey, "threshold");
  assertEquals(rankWorkout("brick"), -1);
});

Deno.test("mood comes from the named piece, not the cooldown that got a memo", () => {
  const s = buildSessions([
    p("a", "2026-08-18T11:00:00Z", 2, 16, "easy",      { mood: "ok" }),
    p("b", "2026-08-18T11:25:00Z", 6, 38, "threshold", { mood: "strong" }),
    p("c", "2026-08-18T12:10:00Z", 2, 16, "easy",      { mood: "wrecked" }),
  ], TZ);
  assertEquals(s[0].mood, "strong");
});

Deno.test("Strava junk titles are not treated as the athlete's words", () => {
  const s = buildSessions([
    p("a", "2026-08-18T11:00:00Z", 6, 45, "easy", { notes: "Morning Run" }),
  ], TZ);
  assertEquals(s[0].note, null);
});

Deno.test("normalization keeps tempo/interval/long in lockstep with the Swift", () => {
  assertEquals(normalizeWorkoutType("tempo"), "threshold");
  assertEquals(normalizeWorkoutType("interval"), "intervals");
  assertEquals(normalizeWorkoutType("Long"), "long_run");
  assertEquals(isQuality("tempo"), true);
  assertEquals(isQuality("easy"), false);
});

Deno.test("zero-distance rows are excluded, never counted as a session", () => {
  const s = buildSessions([
    p("a", "2026-08-18T11:00:00Z", 0, 30, "strength"),
    p("b", "2026-08-18T22:00:00Z", 5, 40, "easy"),
  ], TZ);
  assertEquals(s.length, 1);
  assertEquals(s[0].isSecond, false); // the strength row must not make this a double
});

Deno.test("REGRESSION: the week as uploads vs as sessions", () => {
  const rows = [
    p("1", "2026-08-17T11:00:00Z", 6.0, 48, "easy"),
    p("2", "2026-08-17T22:30:00Z", 4.0, 32, "easy"),
    p("3", "2026-08-18T11:00:00Z", 2.1, 18, "easy"),
    p("4", "2026-08-18T11:25:00Z", 6.2, 38, "tempo"),
    p("5", "2026-08-18T12:10:00Z", 2.0, 18, "easy"),
  ];
  const s = buildSessions(rows, TZ);
  const w = weeklyTotals(s);
  assertEquals(rows.length, 5);       // what every server aggregate counts today
  assertEquals(w.sessions, 3);        // what the athlete actually ran
  assertEquals(w.doubles, 1);
  assertEquals(w.qualitySessions, 1);
  assertEquals(w.miles, 20.3);        // miles are the SAME — only the count was wrong
});


// ---------------------------------------------------------------------------
// GARBAGE IN — locked against REAL rows, 2026-08-20.
//
// 108 of this athlete's 261 running rows are stored local-as-UTC: a 6:05am run
// written as `06:05Z` instead of `11:05Z`. (Detector: `source='strava' AND
// external_streams->'meta'->>'start_date' IS NULL`.) On the 71 days where EVERY
// row is shifted the grouping survives — the day is merely wrong. On the 9 days
// that MIX shifted and correct rows the grouping is destroyed, and the whole
// history reports 222 sessions / 41 doubles instead of the true 218 / 37.
//
// These tests exist so nobody re-derives the 90-minute constant, or a session
// count, from corrupted timestamps a second time.
// ---------------------------------------------------------------------------

/** Jul 21 2026, exactly as the four rows sit in `training_logs` today. */
const JUL21_AS_STORED = [
  p("wu", "2026-07-21T06:05:31Z", 2.01, 15.73, "easy"),      // really 6:05am, stored local-as-UTC
  p("cd", "2026-07-21T07:26:43Z", 1.02, 8.27, "recovery"),   // really 7:26am, stored local-as-UTC
  p("wo", "2026-07-21T11:28:05Z", 7.50, 43.17, "threshold"), // correct — 6:28am local
  p("pm", "2026-07-21T23:28:43Z", 3.90, 28.83, "easy"),      // correct — 6:28pm local
];

Deno.test("REAL DATA: mixed local-as-UTC rows invent a session on Jul 21", () => {
  const s = buildSessions(JUL21_AS_STORED, TZ);
  // The truth is 2 sessions: a 10.5mi threshold (wu+wo+cd) and a 3.9mi double.
  // As stored it is 3, and the threshold session has lost its warm-up and
  // cooldown to a phantom 1:05am "session".
  assertEquals(s.length, 3);
  assertEquals(s.map((x) => x.pieces.length), [2, 1, 1]);
  assertEquals(s[1].typeKey, "threshold");
  assertEquals(s[1].miles, 7.5);   // not the 10.5 actually run
});

Deno.test("REAL DATA: repairing the shifted rows restores the true Jul 21", () => {
  // +5h == CDT. This is what the deferred `workout_date` backfill would do.
  const repaired = JUL21_AS_STORED.map((r, i) =>
    i < 2 ? { ...r, workoutDate: new Date(new Date(r.workoutDate).getTime() + 5 * 3600_000).toISOString() } : r
  );
  const s = buildSessions(repaired, TZ);
  assertEquals(s.length, 2);
  assertEquals(s[0].typeKey, "threshold");
  assertEquals(s[0].pieces.length, 3);
  assertEquals(s[0].miles, 10.53);
  assertEquals(s[1].isSecond, true);
});

Deno.test("the guard flags the phantom pre-5am cluster, and only the mixed days", () => {
  const g = assertPlausibleStartHours(JUL21_AS_STORED, TZ);
  assertEquals(g.suspect.length, 2);
  assertEquals(g.mixedDays, ["2026-07-21"]);   // corrupt AND correct rows share a day
  assertEquals(g.suspectDays, []);             // none where the whole day is shifted

  // A day shifted in its entirety groups fine — flag it, but not as "mixed".
  const wholeDay = assertPlausibleStartHours([
    p("a", "2026-07-22T06:05:00Z", 2.0, 16, "easy"),
    p("b", "2026-07-22T06:30:00Z", 6.0, 40, "threshold"),
  ], TZ);
  assertEquals(wholeDay.suspectDays, ["2026-07-22"]);
  assertEquals(wholeDay.mixedDays, []);

  // Clean data must not trip it.
  assertEquals(assertPlausibleStartHours([p("a", "2026-07-22T11:05:00Z", 6, 45, "easy")], TZ).suspect.length, 0);
});

Deno.test("90 minutes sits in a genuinely EMPTY band, not on Jul 21's artifact", () => {
  // Measured over all 80 same-day end-to-start gaps in this athlete's repaired
  // history: the largest gap inside a session is 73 min and the smallest gap
  // between sessions is 148 min. Nothing lands between. Any constant in
  // (73, 148] reproduces the same grouping — 90 is not load-bearing to a minute.
  const rows = (gap: number) => [
    p("a", "2026-08-18T11:00:00Z", 2.0, 16, "easy"),
    p("b", new Date(Date.parse("2026-08-18T11:00:00Z") + (16 + gap) * 60_000).toISOString(), 6.0, 40, "threshold"),
  ];
  assertEquals(buildSessions(rows(73), TZ).length, 1);    // largest observed intra-session gap
  assertEquals(buildSessions(rows(148), TZ).length, 2);   // smallest observed inter-session gap
  // the whole empty band agrees with itself
  for (const g of [74, 90, 100, 120, 147]) {
    assertEquals(buildSessions(rows(g), TZ, 90).length, g <= 90 ? 1 : 2);
  }
});
