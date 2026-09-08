/**
 * Tests for the ladder.
 *
 * The load-bearing ones:
 *   - `direction:` percentages are of SPEED, so a lower percent is a SLOWER
 *     pace. Inverting this inverts the whole ladder and every reading built on
 *     it, and it is the single easiest thing to get backwards.
 *   - `heat:` a rung system cannot lose credited work out the fast edge, which
 *     a two-sided 95–105% band demonstrably did across July 2026.
 *   - `coarse:` the 2026-03-21 artifact must never become a best session.
 */

import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  effortEquivalentPace,
  paceForPctOfGoalSpeed,
  parsePaceToSeconds,
  rungForPace,
  sessionLadder,
  specificVolumeOverWindow,
  type SessionBlock,
} from "./specificVolume.ts";

/** Sub-2:20 marathon: 8400 / 26.2188 = 320.4 s/mi. */
const GOAL = 8400 / 26.2188;

const blk = (mi: number, pace: string, role = "work_rep"): SessionBlock => ({
  role,
  distanceMiles: mi,
  avgPacePerMile: pace,
});

Deno.test("direction: a lower percent of goal SPEED is a SLOWER pace", () => {
  // 80% of speed must be slower (a bigger seconds-per-mile) than 100%.
  assert(paceForPctOfGoalSpeed(GOAL, 80) > paceForPctOfGoalSpeed(GOAL, 100));
  assert(paceForPctOfGoalSpeed(GOAL, 110) < paceForPctOfGoalSpeed(GOAL, 100));
  // 5:20 goal → 80% is 6:40, 90% is 5:56.
  assertEquals(Math.round(paceForPctOfGoalSpeed(GOAL, 80)), 400);
  assertEquals(Math.round(paceForPctOfGoalSpeed(GOAL, 90)), 356);
});

Deno.test("rungs: the coach's own zones land where he described them", () => {
  // Base is 70–80% of marathon pace: 6:40 to 7:38.
  assertEquals(rungForPace(GOAL, 420), "base");        // 7:00
  // The steady long run's top end, ~90%: 5:56. (Exactly 356 sits a hair under
  // 90% for this goal pace and reads as base — the boundary is real, not a bug.)
  assertEquals(rungForPace(GOAL, 354), "support");
  assertEquals(rungForPace(GOAL, 357), "base");
  // Goal pace itself.
  assertEquals(rungForPace(GOAL, 320), "specific");
  // 95% (5:37) is the slow edge of specific, still specific.
  assertEquals(rungForPace(GOAL, 337), "specific");
  // Half-marathon pace for a 2:20 marathoner, ~104%.
  assertEquals(rungForPace(GOAL, 307), "specific");
  // Tempo/HMP support just above.
  assertEquals(rungForPace(GOAL, 300), "speed");
  // 5K pace, ~113%.
  assertEquals(rungForPace(GOAL, 282), "speed");
  // True aerobic power.
  assertEquals(rungForPace(GOAL, 270), "power");
  // Recovery jogging.
  assertEquals(rungForPace(GOAL, 465), "recovery");
});

Deno.test("kpi: cumulative session volume, not the longest rep", () => {
  // The coach's signature session: 4 x 3mi at MP with half-mile floats.
  const s = sessionLadder(
    [
      blk(3, "5:20"), blk(0.5, "7:10", "recovery"),
      blk(3, "5:22"), blk(0.5, "7:15", "recovery"),
      blk(3, "5:19"), blk(0.5, "7:05", "recovery"),
      blk(3, "5:21"),
    ],
    GOAL,
  );
  assertEquals(s.specificMiles, 12);
  assertEquals(s.longestSpecificBlockMiles, 3);
  // Floats are structural, not base mileage.
  assertEquals(s.miles.base, 0);
  assertEquals(s.miles.recovery, 0);
});

Deno.test("kpi: ten short reps and one long tempo both count their volume", () => {
  const reps = sessionLadder(Array.from({ length: 10 }, () => blk(0.62, "5:18")), GOAL);
  const tempo = sessionLadder([blk(6.2, "5:18")], GOAL);
  assertEquals(reps.specificMiles, 6.2);
  assertEquals(tempo.specificMiles, 6.2);
  // Volume is equal; extension is what separates them.
  assertEquals(reps.longestSpecificBlockMiles, 0.62);
  assertEquals(tempo.longestSpecificBlockMiles, 6.2);
});

Deno.test("heat: credited work moves up a rung instead of vanishing", () => {
  // 5:25 in Austin August, 4.92% credit → about 5:09, which is 103.6% of goal
  // speed. Under the old two-sided 95–105% band computed on RAW pace this
  // read as outside the band; here it is specific work, as it should be.
  const raw = sessionLadder([blk(6, "5:25")], GOAL, 0);
  const adj = sessionLadder([blk(6, "5:25")], GOAL, 0.0492);
  assertEquals(raw.specificMiles, 6);
  assertEquals(adj.specificMiles, 6);
  // And nothing is ever lost: every mile lands on some rung.
  const total = (l: typeof adj) => Object.values(l.miles).reduce((a, b) => a + b, 0);
  assertEquals(total(raw), 6);
  assertEquals(total(adj), 6);
});

Deno.test("heat: the credit only ever makes a pace faster", () => {
  assertEquals(effortEquivalentPace(340, 0), 340);
  assert(effortEquivalentPace(340, 0.05) < 340);
  // A negative adjustment must not penalise a cool day.
  assertEquals(effortEquivalentPace(340, -0.05), 340);
});

Deno.test("coarse: the 2026-03-21 artifact is flagged and cannot win", () => {
  // A 15-mile run parsed into three chunks, two of them 7 miles, read as
  // 14 miles of goal-pace work. It is not a session; it is a bad parse.
  const artifact = {
    id: "mar21",
    date: "2026-03-21",
    totalRunMiles: 15.03,
    blocks: [blk(7, "5:30"), blk(7, "5:32"), blk(1, "6:40")],
  };
  // A genuine continuous tempo IS a 6+ mile specific block — but it is the
  // whole run, not a chunk buried inside one, so it must NOT be flagged.
  const real = {
    id: "apr12",
    date: "2026-04-12",
    totalRunMiles: 6.26,
    blocks: [blk(6.25, "5:24")],
  };

  assert(sessionLadder(artifact.blocks, GOAL, 0, { totalRunMiles: 15.03 }).suspectCoarseParse);
  assert(!sessionLadder(real.blocks, GOAL, 0, { totalRunMiles: 6.26 }).suspectCoarseParse);

  const w = specificVolumeOverWindow([artifact, real], GOAL);
  assertEquals(w.bestSessionId, "apr12");
  assertEquals(w.bestSessionMiles, 6.25);
  assertEquals(w.suspectSessions, ["mar21"]);
});

Deno.test("window: the headline is the best single session, not the sum", () => {
  const w = specificVolumeOverWindow(
    [
      { id: "a", date: "2026-08-04", blocks: [blk(3, "5:20"), blk(3, "5:22")] },
      { id: "b", date: "2026-08-11", blocks: [blk(2, "5:18")] },
      { id: "c", date: "2026-08-18", blocks: [blk(1, "5:19")] },
    ],
    GOAL,
  );
  assertEquals(w.bestSessionMiles, 6);
  assertEquals(w.bestSessionDate, "2026-08-04");
  assertEquals(w.totalSpecificMiles, 9);
  assertEquals(w.sessionsWithSpecificWork, 3);
});

Deno.test("window: a long steady run reads as support, not as specific work", () => {
  // 18 miles at 85% of marathon speed — the coach's second kind of long run.
  const w = specificVolumeOverWindow(
    [{ id: "lr", date: "2026-08-23", blocks: [blk(18, "6:17", "long_run")] }],
    GOAL,
  );
  assertEquals(w.miles.support + w.miles.base, 18);
  assertEquals(w.bestSessionMiles, 0);
  // "The marathon's a distance before it's a pace" — this is not a lesser
  // session, it simply is not specific work, and the ladder says so plainly.
});

Deno.test("parse: only M:SS is accepted", () => {
  assertEquals(parsePaceToSeconds("5:37"), 337);
  assertEquals(parsePaceToSeconds("12:05"), 725);
  assertEquals(parsePaceToSeconds(""), null);
  assertEquals(parsePaceToSeconds("5:7"), null);
  assertEquals(parsePaceToSeconds("abc"), null);
  assertEquals(parsePaceToSeconds(null), null);
});

Deno.test("blocks without a usable pace or distance are skipped, not zeroed", () => {
  const s = sessionLadder(
    [blk(3, "5:20"), { role: "work_rep", distanceMiles: 2, avgPacePerMile: null }, blk(0, "5:20")],
    GOAL,
  );
  assertEquals(s.specificMiles, 3);
  assertEquals(s.blocksCounted, 1);
});
