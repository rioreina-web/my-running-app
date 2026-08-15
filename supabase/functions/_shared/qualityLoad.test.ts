import { assert, assertEquals } from "https://deno.land/std@0.208.0/assert/mod.ts";
import {
  aerobicLoadForBouts,
  longRunLoadFromMinutes,
  qualityLoadForBouts,
  qualityLoadForSession,
} from "./qualityLoad.ts";
import {
  buildZoneAnchors,
  paceToZone,
  paceWeight,
  ZONE_WEIGHTS,
  type Bout,
  type PaceZones,
} from "./workoutSegmentation.ts";
import { buildLoadContext, densityMultiplier, DENSITY_K } from "./loadTerms.ts";

/**
 * Minimal bout builder — only the fields the score reads.
 *
 * `paceSecPerMile` defaults to 0 and `weight` to the zone's table value. Both
 * matter now: the density term needs a real pace to look up a ceiling, and the
 * duration term reads `weight`. A 0 pace makes every shading term a no-op,
 * which is what the pre-existing base-formula tests below want.
 */
function bout(seconds: number, zone: string, isWork = true, paceSecPerMile = 0): Bout {
  return {
    zone: zone as Bout["zone"],
    seconds,
    distanceMeters: 0,
    paceSecPerMile,
    avgHr: null,
    isWork,
    isRest: !isWork,
    isRep: isWork,
    weight: ZONE_WEIGHTS[zone as Bout["zone"]] ?? 1,
  };
}

/** The test athlete's zones, matching workoutSegmentation.test.ts. */
const ZONES: PaceZones = {
  mile: 272, fiveK: 302, tenK: 314, hm: 328, mp: 343,
  steady: 362, moderate: 405, easy: 429,
};

Deno.test("scores one bout as seconds x weight / 60", () => {
  // 30 min at HMP → 1800 × 3.25 / 60
  assertEquals(qualityLoadForBouts([bout(1800, "hmp")]), 97.5);
  // 10 min at 5K → 600 × 5.5 / 60
  assertEquals(qualityLoadForBouts([bout(600, "5k")]), 55);
});

Deno.test("sums across bouts rather than averaging", () => {
  const bouts = [
    bout(180, "5k"), bout(180, "5k"), bout(180, "5k"),
    bout(180, "5k"), bout(180, "5k"),
    bout(1200, "mp"),
  ];
  // 900×5.5/60 = 82.5, plus 1200×2.5/60 = 50
  assertEquals(qualityLoadForBouts(bouts), 132.5);
});

Deno.test("excludes rest bouts entirely", () => {
  const bouts = [
    bout(600, "5k"),                 // counts: 55
    bout(600, "recovery", false),    // rest — excluded
    bout(600, "easy", false),        // rest — excluded
  ];
  assertEquals(qualityLoadForBouts(bouts), 55);
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
  // 137 × 8.0 / 60 = 18.266…
  assertEquals(qualityLoadForBouts([bout(137, "mile")]), 18.3);
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
  // Explicitly NOT work bouts — that is the scenario. `bout()` defaults
  // isWork to true, so the old fixture built a long run out of work bouts
  // and then asserted it had none; the stale first assertion was failing
  // ahead of it and hiding the contradiction.
  const bouts = [bout(4800, "easy", false), bout(600, "steady", false)];
  // 4800×1/60 = 80, plus 600×2.15/60 = 21.5 (steady reweighted 2026-08-11)
  assertEquals(aerobicLoadForBouts(bouts), 101.5);
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
  assertEquals(quality_load, Math.round((1200 * 5.5 / 60) * 10) / 10);
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

// ── Density / lactic / duration shading (2026-08-13) ─────────────────────
// These three terms are OPT-IN via a LoadContext. Every test above passes no
// context and asserts the unshaded base formula — that is the contract: with
// no usable zone table, the score is exactly what it always was.

Deno.test("shading is a no-op without a context", () => {
  const reps = [bout(194, "hmp", true, 328), bout(194, "hmp", true, 328)];
  assertEquals(qualityLoadForBouts(reps), qualityLoadForBouts(reps, null));
});

Deno.test("buildLoadContext: needs a real race anchor, never guesses", () => {
  assertEquals(buildLoadContext(null), null);
  assertEquals(buildLoadContext({}), null);
  assertEquals(buildLoadContext({ easy: 429 }), null); // no race anchor
  const ctx = buildLoadContext(ZONES);
  assert(ctx !== null);
  // Critical speed must land between the athlete's 10K and HM paces — that is
  // where the physiology puts it, and it falls out of the fit rather than
  // being asserted anywhere in the code.
  assert(ctx!.csPaceSecPerMile > 314, `CS ${ctx!.csPaceSecPerMile} should be slower than 10K`);
  assert(ctx!.csPaceSecPerMile < 343, `CS ${ctx!.csPaceSecPerMile} should be faster than MP`);
  assert(ctx!.dPrimeMeters > 0);
});

Deno.test("density: same volume + same pace, longer reps score higher", () => {
  const ctx = buildLoadContext(ZONES)!;
  // 6.21 km of work at HM pace, three ways. The base formula scores all three
  // IDENTICALLY — this is the whole reason the term exists.
  const asReps = (n: number) =>
    Array.from({ length: n }, () => bout(6214 / n * 328 / 1609.34, "hmp", true, 328));
  const tenKReps = asReps(10);
  const fiveTwoK = asReps(5);
  const continuous = asReps(1);

  assertEquals(qualityLoadForBouts(tenKReps), qualityLoadForBouts(continuous));

  const a = qualityLoadForBouts(tenKReps, ctx);
  const b = qualityLoadForBouts(fiveTwoK, ctx);
  const c = qualityLoadForBouts(continuous, ctx);
  assert(a < b, `10x1K ${a} should be < 5x2K ${b}`);
  assert(b < c, `5x2K ${b} should be < continuous ${c}`);
});

Deno.test("density: a race is capped at the ceiling, never beyond", () => {
  const ctx = buildLoadContext(ZONES)!;
  // A full half marathon at HM pace IS the ceiling — fraction 1.0, so the
  // multiplier is exactly 1 + DENSITY_K. Going beyond it must not keep climbing.
  // Tested on the term directly: routing through qualityLoadForBouts would also
  // pick up the SESSION-level duration term, which legitimately differs between
  // a 72-minute and a 143-minute effort and would mask what this is checking.
  const ceiling = ctx.ceilingSeconds(328)!;
  assert(ceiling > 0);
  const atCeiling = densityMultiplier(ceiling, ceiling);
  const beyond = densityMultiplier(ceiling * 2, ceiling);
  assertEquals(atCeiling, 1 + DENSITY_K);
  assertEquals(beyond, atCeiling);
  // And a short rep gets far less than a race.
  assert(densityMultiplier(194, ceiling) < atCeiling);
});

// Rest is NOT a quality_load axis — it belongs to effortModel's habit-relative
// density on effort_load. These two assert the boundary rather than the
// behaviour: quality_load must be INDIFFERENT to rest, or the two scores would
// be double-counting it.
Deno.test("quality_load is indifferent to rest — that axis belongs to effort_load", () => {
  const ctx = buildLoadContext(ZONES)!;
  const set = (restSeconds: number, pace: number, zone: string) => {
    const out: Bout[] = [];
    for (let i = 0; i < 8; i++) {
      out.push(bout(0.248548 * pace, zone, true, pace));
      if (i < 7) out.push(bout(restSeconds, "easy", false, 429));
    }
    return out;
  };
  // Identical work bouts, only the recovery differs — so the score must be
  // identical. If this ever starts differing, quality_load has grown a rest
  // term and is now double-counting against effort_load.
  assertEquals(
    qualityLoadForBouts(set(30, 272, "mile"), ctx),
    qualityLoadForBouts(set(180, 272, "mile"), ctx),
  );
  assertEquals(
    qualityLoadForBouts(set(30, 314, "10k"), ctx),
    qualityLoadForBouts(set(180, 314, "10k"), ctx),
  );
});

Deno.test("quality_load: rest makes no difference below critical speed either", () => {
  const ctx = buildLoadContext(ZONES)!;
  // MP is well below CS — rest length must make no difference at all.
  const set = (rest: number) => {
    const out: Bout[] = [];
    for (let i = 0; i < 6; i++) {
      out.push(bout(343, "mp", true, 343));
      if (i < 5) out.push(bout(rest, "easy", false, 429));
    }
    return out;
  };
  assertEquals(qualityLoadForBouts(set(60), ctx), qualityLoadForBouts(set(300), ctx));
});

Deno.test("duration: gated on real time, sized by intensity", () => {
  const ctx = buildLoadContext(ZONES)!;
  // A 45-minute interval session is under the ramp — duration adds nothing.
  const short = [bout(45 * 60, "hmp", true, 328)];
  const shortRamped = qualityLoadForBouts(short, ctx);
  const shortBase = qualityLoadForBouts(short, null);
  // Density still applies; isolate duration by checking a longer session gains
  // proportionally more than the density term alone could explain.
  const long = [bout(120 * 60, "hmp", true, 328)];
  const longGain = qualityLoadForBouts(long, ctx) / qualityLoadForBouts(long, null);
  const shortGain = shortRamped / shortBase;
  assert(longGain > shortGain, `2h session gain ${longGain} should exceed 45min ${shortGain}`);
});

Deno.test("duration: intensity ordering survives — moderate beats a longer easy run", () => {
  const ctx = buildLoadContext(ZONES)!;
  // The failure mode a pure time-on-feet term produces: the slower, longer run
  // wins purely for taking longer. Sizing by load is what prevents it.
  const moderate15mi = [bout(15 * 405, "moderate", false, 405)];
  const easy16mi = [bout(16 * 429, "easy", false, 429)];
  const m = aerobicLoadForBouts(moderate15mi, ctx);
  const e = aerobicLoadForBouts(easy16mi, ctx);
  assert(m > e, `15mi moderate ${m} must outscore 16mi easy ${e}`);
});

Deno.test("easy running is untouched by every term", () => {
  const ctx = buildLoadContext(ZONES)!;
  const easyRun = [bout(60 * 60, "easy", false, 429)];
  // No work bouts → quality branch scores 0 with or without context.
  assertEquals(qualityLoadForBouts(easyRun, ctx), 0);
  assertEquals(qualityLoadForBouts(easyRun, null), 0);
});

// ── The zone-boundary step (2026-08-14) ──────────────────────────────────

/**
 * A bout weighted the way PRODUCTION weights it — zone and weight both derived
 * from the actual pace, exactly as `segmentFromLaps` does it.
 *
 * The `bout()` helper at the top hard-codes the table weight, which is what
 * the base-formula tests above want. These tests need the curve, because the
 * curve is the thing under test.
 */
function curvedBout(seconds: number, paceSecPerMile: number, isWork = true): Bout {
  const anchors = buildZoneAnchors(ZONES);
  return {
    zone: paceToZone(paceSecPerMile, anchors),
    seconds,
    distanceMeters: (seconds / paceSecPerMile) * 1609.344,
    paceSecPerMile,
    avgHr: null,
    isWork,
    isRest: !isWork,
    isRep: isWork,
    weight: paceWeight(paceSecPerMile, anchors),
  };
}

Deno.test("one second per mile across a zone boundary is no longer a step", () => {
  // MP (343) and steady (362) bracket a boundary at their midpoint, 352.5 — so
  // 352 classifies `mp` and 353 classifies `steady`. Under the old
  // `ZONE_WEIGHTS[b.zone]` lookup that was 2.5 vs 2.15: a 14% drop in the
  // score for one second per mile, well inside GPS drift. On the curve the two
  // paces are neighbours and score like neighbours.
  const fast = curvedBout(36 * 60, 352);
  const slow = curvedBout(36 * 60, 353);
  // The fixture must actually straddle the boundary or it proves nothing.
  assertEquals(fast.zone, "mp");
  assertEquals(slow.zone, "steady");
  assert(
    Math.abs(ZONE_WEIGHTS.mp - ZONE_WEIGHTS.steady) / ZONE_WEIGHTS.mp > 0.1,
    "these zones no longer differ by a real step — re-pick the fixture paces",
  );

  const a = qualityLoadForBouts([fast]);
  const b = qualityLoadForBouts([slow]);
  const gapPct = (Math.abs(a - b) / a) * 100;
  assert(gapPct < 1, `one sec/mi moved the score ${gapPct.toFixed(1)}% (${a} vs ${b})`);
});

Deno.test("no zone boundary is a step — every second costs about what its neighbours cost", () => {
  // The property that matters is NOT a cap on how fast the score climbs. The
  // curve is legitimately steep between HM and MP (~2% per second per mile),
  // and that is the model working. What must never happen is a SPIKE: one
  // second per mile that moves the score far more than the seconds either side
  // of it. That spike is exactly the signature of a step table — zero change
  // within a zone, a cliff at the boundary — and it is what this asserts is
  // gone.
  const score = (pace: number) => qualityLoadForBouts([curvedBout(20 * 60, pace)]);
  const jump = (pace: number) => score(pace - 1) - score(pace);

  for (let pace = 428; pace >= 275; pace--) {
    const here = jump(pace);
    const neighbours = (jump(pace + 1) + jump(pace - 1)) / 2;
    assert(here >= 0, `score went backwards going faster at ${pace}s/mi`);
    assert(
      here <= neighbours * 1.5 + 0.01,
      `${pace}→${pace - 1}s/mi moved the score ${here.toFixed(3)} against `
        + `${neighbours.toFixed(3)} either side — that is a step, not a curve`,
    );
  }
});
