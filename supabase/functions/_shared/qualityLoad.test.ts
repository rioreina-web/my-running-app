import { assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  aerobicLoadForBouts,
  longRunLoadFromMinutes,
  qualityLoadForBouts,
  qualityLoadForSession,
} from "./qualityLoad.ts";
import type { Bout } from "./workoutSegmentation.ts";

/** Minimal bout builder — only the fields the score reads. */
function bout(seconds: number, zone: string, isWork = true): Bout {
  return {
    zone: zone as Bout["zone"],
    seconds,
    distanceMeters: 0,
    paceSecPerMile: 0,
    avgHr: null,
    isWork,
    isRest: !isWork,
    isRep: isWork,
  };
}

Deno.test("scores one bout as seconds x weight / 60", () => {
  // 30 min at HMP → 1800 × 3.0 / 60
  assertEquals(qualityLoadForBouts([bout(1800, "hmp")]), 90);
  // 10 min at 5K → 600 × 4.0 / 60
  assertEquals(qualityLoadForBouts([bout(600, "5k")]), 40);
});

Deno.test("sums across bouts rather than averaging", () => {
  const bouts = [
    bout(180, "5k"), bout(180, "5k"), bout(180, "5k"),
    bout(180, "5k"), bout(180, "5k"),
    bout(1200, "mp"),
  ];
  // 900×4/60 = 60, plus 1200×2.5/60 = 50
  assertEquals(qualityLoadForBouts(bouts), 110);
});

Deno.test("excludes rest bouts entirely", () => {
  const bouts = [
    bout(600, "5k"),                 // counts: 40
    bout(600, "recovery", false),    // rest — excluded
    bout(600, "easy", false),        // rest — excluded
  ];
  assertEquals(qualityLoadForBouts(bouts), 40);
});

Deno.test("counts easy work bouts at weight 1.0, not zero", () => {
  // An `isWork` bout classified easy is unusual but must not be dropped
  // silently — it weighs 1.0 like the table says.
  assertEquals(qualityLoadForBouts([bout(600, "easy")]), 10);
});

Deno.test("an unknown zone weighs 1.0 rather than inflating the score", () => {
  assertEquals(qualityLoadForBouts([bout(600, "threshold")]), 10);
});

Deno.test("zero and negative seconds contribute nothing", () => {
  assertEquals(qualityLoadForBouts([bout(0, "mile"), bout(-60, "mile")]), 0);
});

Deno.test("no bouts is a real zero", () => {
  assertEquals(qualityLoadForBouts([]), 0);
});

Deno.test("rounds to one decimal", () => {
  // 137 × 5.0 / 60 = 11.4166…
  assertEquals(qualityLoadForBouts([bout(137, "mile")]), 11.4);
});

Deno.test("reproduces the calibration boundary from real sessions", () => {
  // Largest real stride set in prod: ~157s at mile pace → 13.1
  const strides = qualityLoadForBouts([bout(157, "mile")]);
  // Smallest real session: a 1K + 200/400s set, ~553s mostly at 5K → 42.1
  const session = qualityLoadForBouts([bout(553, "5k"), bout(80, "mile")]);
  assertEquals(strides < 25, true);
  assertEquals(session > 25, true);
});

// ── Long runs ────────────────────────────────────────────────────────────

Deno.test("aerobic load counts every bout, not just the work ones", () => {
  // A 90-minute long run: 80 min easy + 10 min drifting to steady.
  const bouts = [bout(4800, "easy"), bout(600, "steady")];
  // 4800×1/60 = 80, plus 600×2/60 = 20
  assertEquals(aerobicLoadForBouts(bouts), 100);
  // The quality-load view of the same run is zero — no work bouts at all.
  // That is precisely why long runs needed their own path.
  assertEquals(qualityLoadForBouts(bouts), 0);
});

Deno.test("a long run finished strong outscores the same time plodded", () => {
  const plod = aerobicLoadForBouts([bout(5400, "easy")]);
  const strong = aerobicLoadForBouts([bout(4200, "easy"), bout(1200, "mp")]);
  assertEquals(plod, 90);
  assertEquals(strong > plod, true);
});

Deno.test("aerobic load includes bouts flagged as rest", () => {
  // On a long run a slow stretch is still the long run, not a recovery jog
  // between reps — the whole run is the stimulus.
  assertEquals(aerobicLoadForBouts([bout(600, "easy", false)]), 10);
});

Deno.test("lap-less long run falls back to duration at the easy weight", () => {
  assertEquals(longRunLoadFromMinutes(93), 93);
  assertEquals(longRunLoadFromMinutes(0), 0);
  assertEquals(longRunLoadFromMinutes(null), 0);
  assertEquals(longRunLoadFromMinutes(undefined), 0);
});

Deno.test("a real long run clears the key-session floor", () => {
  // This athlete's average Saturday: 13.8 mi in 93 min.
  assertEquals(longRunLoadFromMinutes(93) > 25, true);
  // And the shortest one still does.
  assertEquals(longRunLoadFromMinutes(75) > 25, true);
});


// ─── THE EASY-RUN REGRESSION ────────────────────────────────────────────
//
// Named on purpose, not covered by accident. `aerobicLoadForBouts` counts
// EVERY bout, so if the long_run guard in `qualityLoadForSession` is ever
// widened to "any run with no work bouts", a routine easy run scores its own
// duration, clears the floor of 25, and every single day in the athlete's
// calendar gets a star. These tests are the tripwire.

const easyBout = (seconds: number) => bout(seconds, "easy", false);
const workBout = (seconds: number, zone: string) => bout(seconds, zone, true);

Deno.test("easy run scores NOTHING — the trap that would star every day", () => {
  // 60 minutes of easy running, no work bouts, not labelled a long run.
  const { quality_load, quality_kind } = qualityLoadForSession(
    "easy",
    [easyBout(3600)],
    60,
  );
  assertEquals(quality_kind, null);
  assertEquals(quality_load, null);
});

Deno.test("easy run stays unscored even when it is long in TIME but untyped", () => {
  // 93 minutes. If the guard leaked, this would score ~93 and sail over the
  // floor of 25 — the exact shape of the bug.
  const { quality_load, quality_kind } = qualityLoadForSession(
    null,
    [easyBout(5580)],
    93,
  );
  assertEquals(quality_kind, null);
  assertEquals(quality_load, null);
});

Deno.test("long run IS scored over every bout", () => {
  const { quality_load, quality_kind } = qualityLoadForSession(
    "long_run",
    [easyBout(5580)],
    93,
  );
  assertEquals(quality_kind, "long_run");
  // 5580s easy at weight 1.0 → 93 weighted minutes.
  assertEquals(quality_load, 93);
});

Deno.test("lapless long run falls back to duration", () => {
  const { quality_load, quality_kind } = qualityLoadForSession("long_run", [], 96);
  assertEquals(quality_kind, "long_run");
  assertEquals(quality_load, 96);
});

Deno.test("quality session scores its WORK bouts only, warmup excluded", () => {
  const { quality_load, quality_kind } = qualityLoadForSession(
    "intervals",
    [easyBout(900), workBout(1200, "5k"), easyBout(900)],
    50,
  );
  assertEquals(quality_kind, "quality");
  // Only the 1200s at 5k weight contributes; the 30 min of warmup/cooldown
  // must NOT appear. If this number grows, isWork filtering has regressed.
  assertEquals(quality_load, Math.round((1200 * 5 / 60) * 10) / 10);
});

Deno.test("a stride set scores real work but stays under the floor", () => {
  // 6 × 20s strides. Scores something — it IS work — but nowhere near 25.
  const { quality_load, quality_kind } = qualityLoadForSession(
    "easy",
    [easyBout(2400), workBout(120, "mile")],
    45,
  );
  assertEquals(quality_kind, "quality");
  if (quality_load === null || quality_load >= 25) {
    throw new Error(`stride set scored ${quality_load}, expected below the floor of 25`);
  }
});
