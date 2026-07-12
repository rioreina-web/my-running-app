/**
 * Tests for the voice-orphan matcher.
 *
 * Run: deno test _shared/voiceOrphanMatch.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { type OrphanCandidate, pickBestOrphan, type RunRef } from "./voiceOrphanMatch.ts";

// The real bug's shape: memo at 13:25 / 4.00 mi, Strava run 13:25 / 4.04 mi.
const RUN: RunRef = { workout_date: "2026-07-10T13:25:43Z", workout_distance_miles: 4.04 };

Deno.test("matches the same-run voice memo (minutes apart, 0.04 mi off)", () => {
  const cands: OrphanCandidate[] = [
    { id: "voice-1", workout_date: "2026-07-10T13:25:43Z", workout_distance_miles: 4.0 },
  ];
  assertEquals(pickBestOrphan(RUN, cands)?.id, "voice-1");
});

Deno.test("rejects a memo from a different run the same day (hours + miles off)", () => {
  const cands: OrphanCandidate[] = [
    { id: "morning-8mi", workout_date: "2026-07-10T06:00:00Z", workout_distance_miles: 8.0 },
  ];
  assertEquals(pickBestOrphan(RUN, cands), null);
});

Deno.test("rejects a same-time memo whose distance is well off", () => {
  const cands: OrphanCandidate[] = [
    { id: "wrong-dist", workout_date: "2026-07-10T13:25:00Z", workout_distance_miles: 10.0 },
  ];
  assertEquals(pickBestOrphan(RUN, cands), null);
});

Deno.test("8% tolerance admits an estimated distance", () => {
  // 4.04 * 1.08 = 4.36 — a memo logged as 4.3 should still match.
  const cands: OrphanCandidate[] = [
    { id: "est", workout_date: "2026-07-10T13:40:00Z", workout_distance_miles: 4.3 },
  ];
  assertEquals(pickBestOrphan(RUN, cands)?.id, "est");
});

Deno.test("picks the closest in time when several qualify", () => {
  const cands: OrphanCandidate[] = [
    { id: "far", workout_date: "2026-07-10T11:30:00Z", workout_distance_miles: 4.0 },
    { id: "near", workout_date: "2026-07-10T13:20:00Z", workout_distance_miles: 4.1 },
  ];
  assertEquals(pickBestOrphan(RUN, cands)?.id, "near");
});

Deno.test("null/malformed candidate fields are skipped, not thrown", () => {
  const cands: OrphanCandidate[] = [
    { id: "no-date", workout_date: null, workout_distance_miles: 4.0 },
    { id: "no-dist", workout_date: "2026-07-10T13:25:00Z", workout_distance_miles: null },
    { id: "bad-date", workout_date: "not-a-date", workout_distance_miles: 4.0 },
  ];
  assertEquals(pickBestOrphan(RUN, cands), null);
});

Deno.test("empty candidate set → null", () => {
  assert(pickBestOrphan(RUN, []) === null);
});
