/**
 * Unit tests for the pace readback guard.
 *
 * The test that matters most is the first one: it replays the 2026-09-01
 * production failure — a rep pace presented as a session pace, plus a
 * model-invented heat-adjusted pace — and both must be caught.
 *
 * Run: deno test --allow-all _shared/pace-guard.test.ts
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  findUnlicensedPaces,
  licensedTimeTokens,
  paceCorrectionNote,
} from "./pace-guard.ts";

// A context shaped like buildTrainingPeriodDocument output for the Sep 1 runs.
const CONTEXT = `
Tue Sep 1: INTERVALS 7.5mi @ 5:48/mi (session avg) [struggling] | conditions: 78°F, dew 74°F, very hot — effort-equivalent ≈5:30/mi in cool conditions
  Within-run parts (segment paces of THIS one run — not the run's pace): rep 1 0.62mi @ 5:25/mi, recovery 0.62mi @ 5:56/mi, rep 4 0.62mi @ 5:36/mi
Tue Sep 1: RECOVERY 1.6mi @ 8:27/mi (session avg)
  Within-run parts (segment paces of THIS one run — not the run's pace): warmup 0.22mi @ 8:46/mi, rep 1 0.08mi @ 5:39/mi, rep 2 0.08mi @ 5:34/mi
`;

Deno.test("catches the shipped failure: invented heat-adjusted pace", () => {
  const licensed = licensedTimeTokens(CONTEXT);
  // "5:36/mi" IS in context (a rep pace) so the guard cannot catch that
  // misattribution — that's the context labeling's job. But "5:19/mi", the
  // model's own heat arithmetic off the wrong base, is nowhere in context.
  const reply =
    "Your 5:36/mi pace was actually closer to a 5:19/mi effort when you factor in the conditions.";
  assertEquals(findUnlicensedPaces(reply, licensed), ["5:19"]);
});

Deno.test("licenses paces that appear in context, in any claim phrasing", () => {
  const licensed = licensedTimeTokens(CONTEXT);
  const reply =
    "You averaged 5:48/mi for the session — effort-equivalent about 5:30 per mile, with reps at 5:25/mi. That 8:27 pace on the recovery jog was right.";
  assertEquals(findUnlicensedPaces(reply, licensed), []);
});

Deno.test("ignores non-pace times: durations, race predictions, clock times", () => {
  const licensed = licensedTimeTokens("Total 43:20 for 7.5mi.");
  const reply =
    "You ran 43:20 total. That fitness points toward a 2:37 marathon. Start around 6:30 AM.";
  assertEquals(findUnlicensedPaces(reply, licensed), []);
});

Deno.test("flags a bare invented pace claim and dedupes repeats", () => {
  const licensed = licensedTimeTokens("Nothing here but 9:00/mi easy.");
  const reply =
    "Hold 7:15 pace on the tempo, settling into 7:15 per mile by halfway, then 6:50/mi to close.";
  assertEquals(findUnlicensedPaces(reply, licensed), ["7:15", "6:50"]);
});

Deno.test("leading-zero minutes normalize to the same token", () => {
  const licensed = licensedTimeTokens("Splits at 5:48/mi.");
  assertEquals(findUnlicensedPaces("You held 05:48/mi throughout.", licensed), []);
});

Deno.test("correction note names every offender", () => {
  const note = paceCorrectionNote(["5:19", "7:15"]);
  assert(note.includes("5:19, 7:15"));
  assert(note.includes("session avg"));
});
