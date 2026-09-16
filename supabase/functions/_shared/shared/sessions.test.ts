import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { groupIntoSessions } from "./sessions.ts";

Deno.test("sessions: empty input → empty array", () => {
  assertEquals(groupIntoSessions([]), []);
});

Deno.test("sessions: two uploads <3h apart on the same day are one session", () => {
  const rows = [
    { workout_date: "2026-06-10T08:00:00Z", workout_duration_minutes: 20 },
    { workout_date: "2026-06-10T10:00:00Z", workout_duration_minutes: 40 },
  ];
  const sessions = groupIntoSessions(rows);
  assertEquals(sessions.length, 1);
  assertEquals(sessions[0].length, 2);
});

Deno.test("sessions: same-day uploads >3h apart (and not bridged by duration) split", () => {
  const rows = [
    { workout_date: "2026-06-10T06:00:00Z", workout_duration_minutes: 30 },
    { workout_date: "2026-06-10T18:00:00Z", workout_duration_minutes: 30 },
  ];
  assertEquals(groupIntoSessions(rows).length, 2);
});

Deno.test("sessions: long prior run bridges a >3h start gap via end-to-start ≤1.5h", () => {
  // Run A starts 12:00, lasts 150min (ends ~14:30). Run B starts 15:30 →
  // start-gap 3.5h (>3) BUT end-to-start gap is 1.0h (≤1.5) → same session.
  const rows = [
    { workout_date: "2026-06-10T12:00:00Z", workout_duration_minutes: 150 },
    { workout_date: "2026-06-10T15:30:00Z", workout_duration_minutes: 20 },
  ];
  const sessions = groupIntoSessions(rows);
  assertEquals(sessions.length, 1);
  assertEquals(sessions[0].length, 2);
});

Deno.test("sessions: different days are always distinct sessions", () => {
  const rows = [
    { workout_date: "2026-06-10T08:00:00Z", workout_duration_minutes: 40 },
    { workout_date: "2026-06-11T08:00:00Z", workout_duration_minutes: 40 },
  ];
  assertEquals(groupIntoSessions(rows).length, 2);
});

Deno.test("sessions: unsorted input is grouped correctly (sorts ascending first)", () => {
  const rows = [
    { workout_date: "2026-06-11T08:00:00Z", workout_duration_minutes: 40 },
    { workout_date: "2026-06-10T10:00:00Z", workout_duration_minutes: 40 },
    { workout_date: "2026-06-10T08:00:00Z", workout_duration_minutes: 20 },
  ];
  const sessions = groupIntoSessions(rows);
  assertEquals(sessions.length, 2);
  // First (earlier) session holds the two 06-10 runs.
  assertEquals(sessions[0].length, 2);
  assertEquals(sessions[1].length, 1);
});
