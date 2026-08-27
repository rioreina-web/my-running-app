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

// ── created_at fallback (2026-08-24 regression) ─────────────────────
// A memo recorded with no run selected lands NULL-dated. It must still
// reconcile, off its write time.

Deno.test("NULL-dated memo matches on created_at", () => {
  const cands: OrphanCandidate[] = [
    {
      id: "null-dated",
      workout_date: null,
      workout_distance_miles: 4.0,
      created_at: "2026-07-10T15:10:00Z", // ~1h45m after the run
    },
  ];
  assertEquals(pickBestOrphan(RUN, cands)?.id, "null-dated");
});

Deno.test("the real 2026-08-24 shape: memo written 6h29m after the run", () => {
  // The regression this window exists for. A symmetric ±4h fallback rejects it.
  const run: RunRef = { workout_date: "2026-08-24T12:23:57Z", workout_distance_miles: 10.01 };
  const cands: OrphanCandidate[] = [
    { id: "evening-memo", workout_date: null, workout_distance_miles: 10, created_at: "2026-08-24T18:53:34Z" },
  ];
  assertEquals(pickBestOrphan(run, cands)?.id, "evening-memo");
});

Deno.test("created_at fallback stops at 18h back", () => {
  const cands: OrphanCandidate[] = [
    { id: "next-day", workout_date: null, workout_distance_miles: 4.0, created_at: "2026-07-11T13:25:00Z" },
  ];
  assertEquals(pickBestOrphan(RUN, cands), null);
});

Deno.test("a memo written well BEFORE the run is not a match for it", () => {
  // Asymmetry check: 6h before the run start is inside the 18h span in
  // magnitude, but on the wrong side — a memo cannot describe a future run.
  const cands: OrphanCandidate[] = [
    { id: "premonition", workout_date: null, workout_distance_miles: 4.0, created_at: "2026-07-10T07:25:00Z" },
  ];
  assertEquals(pickBestOrphan(RUN, cands), null);
});

Deno.test("a stated-date match outranks a closer-in-time fallback match", () => {
  const cands: OrphanCandidate[] = [
    { id: "fallback-closer", workout_date: null, workout_distance_miles: 4.0, created_at: "2026-07-10T13:30:00Z" },
    { id: "stated-further", workout_date: "2026-07-10T15:00:00Z", workout_distance_miles: 4.0 },
  ];
  assertEquals(pickBestOrphan(RUN, cands)?.id, "stated-further");
});

Deno.test("created_at fallback still honours the distance tolerance", () => {
  const cands: OrphanCandidate[] = [
    { id: "wrong-dist", workout_date: null, workout_distance_miles: 10.0, created_at: "2026-07-10T14:00:00Z" },
  ];
  assertEquals(pickBestOrphan(RUN, cands), null);
});

Deno.test("a stated workout_date always wins over created_at", () => {
  // Written days later (a backfill), but it states the run's own time.
  const cands: OrphanCandidate[] = [
    {
      id: "stated",
      workout_date: "2026-07-10T13:25:00Z",
      workout_distance_miles: 4.0,
      created_at: "2026-07-20T09:00:00Z",
    },
  ];
  assertEquals(pickBestOrphan(RUN, cands)?.id, "stated");
});

Deno.test("a distance-less memo is still rejected even with created_at", () => {
  const cands: OrphanCandidate[] = [
    { id: "no-dist", workout_date: null, workout_distance_miles: null, created_at: "2026-07-10T14:00:00Z" },
  ];
  assertEquals(pickBestOrphan(RUN, cands), null);
});

Deno.test("empty candidate set → null", () => {
  assert(pickBestOrphan(RUN, []) === null);
});
