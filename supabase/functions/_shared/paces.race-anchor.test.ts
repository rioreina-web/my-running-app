/**
 * Phase 2 race anchoring — sub-task C unit tests.
 *
 * Pins the decision from outputs/maya-product-roadmap-2026-05-28.md (Q20)
 * and outputs/phase-2-race-anchoring-plan-2026-06-04.md: a confirmed race
 * in athlete_state.confirmed_races anchors the pace table, outranking the
 * athlete_pace_profiles row (which can be goal-derived, i.e. aspirational).
 *
 * Maya's numbers: Houston Marathon 3:28:00 (Jan 2026) = 12,480s over
 * 26.2188 mi = 476 sec/mi MP. Her 3:16 BQ goal would be 448 sec/mi.
 * After sub-task C her zones anchor on 476, not 448.
 *
 * Run: deno test --allow-all _shared/paces.race-anchor.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  paceTableFromProfile,
  pickAnchorRace,
  type ConfirmedRace,
} from "./paces.ts";

const HOUSTON: ConfirmedRace = {
  date: "2026-01-18",
  distance: "marathon",
  finish_time_seconds: 3 * 3600 + 28 * 60, // 3:28:00 = 12480
  official: true,
  event_name: "Houston Marathon",
};

// A goal-derived profile anchored on Maya's 3:16 aspiration (448 sec/mi MP).
const ASPIRATIONAL_PROFILE = {
  goal_race_distance: "marathon",
  marathon_pace_seconds: 448,
  half_pace_seconds: null,
  ten_k_pace_seconds: null,
  five_k_pace_seconds: null,
  mile_pace_seconds: null,
};

Deno.test("pickAnchorRace: most recent qualifying race wins", () => {
  const older: ConfirmedRace = {
    date: "2024-10-06",
    distance: "half",
    finish_time_seconds: 92 * 60,
  };
  const anchor = pickAnchorRace([older, HOUSTON]);
  assert(anchor);
  assertEquals(anchor.distanceKey, "marathon");
  assertEquals(anchor.finishTimeSeconds, 12480);
  assertEquals(anchor.date, "2026-01-18");
});

Deno.test("pickAnchorRace: 'other'/unknown distances and malformed rows are skipped", () => {
  const junk = [
    { date: "2026-03-01", distance: "other", finish_time_seconds: 3600 },
    { date: "2026-04-01", distance: "marathon", finish_time_seconds: 0 },
    null as unknown as ConfirmedRace,
  ];
  assertEquals(pickAnchorRace(junk as ConfirmedRace[]), null);
  assertEquals(pickAnchorRace([]), null);
  assertEquals(pickAnchorRace(null), null);
});

Deno.test("paceTableFromProfile: confirmed race outranks the (aspirational) profile", () => {
  const table = paceTableFromProfile(ASPIRATIONAL_PROFILE, [HOUSTON]);
  assert(table);
  // MP anchors on Houston (12480 / 26.2188 ≈ 476), not the 448 goal pace.
  assert(Math.abs(table.mp - 476) <= 1, `mp should be ~476 (race), got ${table.mp}`);
  assert(table.mp > 470, "mp must not be the 448 aspirational anchor");
});

Deno.test("paceTableFromProfile: race anchor works with a null profile", () => {
  const table = paceTableFromProfile(null, [HOUSTON]);
  assert(table);
  assert(Math.abs(table.mp - 476) <= 1);
  // The ladder fills the rest of the zones from the race anchor.
  assert(table.easy > table.mp, "easy must be slower than MP");
  assert(table.fiveK < table.mp, "5K must be faster than MP");
});

Deno.test("paceTableFromProfile: falls back to profile when no qualifying race", () => {
  const table = paceTableFromProfile(ASPIRATIONAL_PROFILE, null);
  assert(table);
  // Float tolerance — the ladder round-trips through race-equivalence ratios.
  assert(Math.abs(table.mp - 448) < 0.001, `mp should be 448, got ${table.mp}`);
});
