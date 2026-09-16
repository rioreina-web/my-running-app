import { assert, assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  buildEffortProfile,
  densityBaselineFromSamples,
  densityFromBouts,
  describeDensity,
  gradeFactor,
  neutralEquivalentLaps,
  repRestSplit,
  restSampleFrom,
  ZONE_REST_RATIO_FALLBACK,
  type EffortLap,
} from "./effortModel.ts";
import { segmentFromLaps, type PaceZones } from "./workoutSegmentation.ts";
import { adjustPace } from "./pace-heat-adjustment.ts";

// An athlete whose 5K pace is 5:14/mi — so a 1K in 3:15 lands squarely in the
// 5K zone. Ratios follow the canonical race-equivalence ladder.
const ZONES: PaceZones = {
  mile: 290,
  threeK: 302,
  fiveK: 314,
  tenK: 330,
  hm: 348,
  mp: 365,
  steady: 395,
  moderate: 435,
  easy: 477,
};

const EASY_PACE = 477;

function easyLap(seconds: number, isRest = false): EffortLap {
  return {
    is_rest: isRest,
    distance_meters: Math.round((seconds / EASY_PACE) * 1609.344),
    avg_pace_sec_per_mile: EASY_PACE,
    moving_time_seconds: seconds,
  };
}

function repLap(extra: Partial<EffortLap> = {}): EffortLap {
  return {
    is_rest: false,
    distance_meters: 1000,
    avg_pace_sec_per_mile: 314, // 3:15/km
    moving_time_seconds: 195,
    ...extra,
  };
}

/** 10×1K @ 3:15 with `restSeconds` recovery, 10 min warmup + 10 min cooldown. */
function tenByK(restSeconds: number, extra: Partial<EffortLap> = {}): EffortLap[] {
  const laps: EffortLap[] = [easyLap(600)];
  for (let i = 0; i < 10; i++) {
    laps.push(repLap(extra));
    if (i < 9) laps.push(easyLap(restSeconds, true));
  }
  laps.push(easyLap(600));
  return laps;
}

// ── The headline case ──────────────────────────────────────────────────────

Deno.test("10×1K off 60s vs off 90s: the old load model preferred the easier one", () => {
  // Documents the bug this module exists to fix. `stress_load` is
  // intensity_score × duration, and duration shrinks when the rest shrinks.
  const a = segmentFromLaps(tenByK(90), ZONES);
  const b = segmentFromLaps(tenByK(60), ZONES);

  const loadA = (a.intensityScore * a.totalSeconds) / 60;
  const loadB = (b.intensityScore * b.totalSeconds) / 60;

  assert(
    loadB < loadA,
    `the inversion should reproduce: 60s rest ${loadB.toFixed(1)} vs 90s rest ${loadA.toFixed(1)}`,
  );
});

Deno.test("10×1K off 60s carries more effort load than off 90s", () => {
  // Same athlete, same reps, same paces — only the recovery differs. The
  // athlete habitually takes 90s in this zone, so that session sits at their
  // baseline and the 60s session reads as denser than their habit.
  const baseline = densityBaselineFromSamples([
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.47 },
  ]);

  const a = buildEffortProfile(tenByK(90), ZONES, { baseline });
  const b = buildEffortProfile(tenByK(60), ZONES, { baseline });

  assert(
    b.effortLoad > a.effortLoad,
    `60s rest should carry more: ${b.effortLoad} vs ${a.effortLoad}`,
  );
  // Same work at the same paces — the base (density-blind) load still favours
  // the longer-rest session, exactly as before. The density term is the fix.
  assert(b.baseLoad < a.baseLoad);
  assert(b.densityDelta > a.densityDelta);
});

Deno.test("10×1K density figures are the ones a coach would quote", () => {
  const a = buildEffortProfile(tenByK(90), ZONES).density;
  const b = buildEffortProfile(tenByK(60), ZONES).density;

  assertEquals(a.repCount, 10);
  assertEquals(a.medianRepSeconds, 195);
  assertEquals(a.medianRestSeconds, 90);
  assertEquals(a.restRatio, 0.46);
  assertEquals(a.densityPct, 70.7); // 1950s work / 2760s block (9 recoveries)
  assertEquals(a.zone, "5k");

  assertEquals(b.medianRestSeconds, 60);
  assertEquals(b.restRatio, 0.31);
  assertEquals(b.densityPct, 78.3);
});

// ── Density mechanics ──────────────────────────────────────────────────────

Deno.test("running your habitual rest earns no density adjustment", () => {
  const baseline = densityBaselineFromSamples([
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.46 },
  ]);
  const d = buildEffortProfile(tenByK(90), ZONES, { baseline }).density;
  assertEquals(d.baselineSource, "athlete");
  assertEquals(d.multiplier, 1);
});

Deno.test("more rest than habit damps the load, less rest lifts it", () => {
  const baseline = densityBaselineFromSamples([
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.46 },
  ]);
  const lots = buildEffortProfile(tenByK(150), ZONES, { baseline }).density;
  const few = buildEffortProfile(tenByK(45), ZONES, { baseline }).density;

  assert(lots.multiplier < 1, `expected <1, got ${lots.multiplier}`);
  assert(few.multiplier > 1, `expected >1, got ${few.multiplier}`);
  // Asymmetric: padding recovery saves less than cutting it costs.
  assert(1 - lots.multiplier < few.multiplier - 1);
});

Deno.test("no rep history falls back to cold start and says so", () => {
  const d = buildEffortProfile(tenByK(90), ZONES).density;
  assertEquals(d.baselineSource, "cold_start");
  assertEquals(d.baselineRestRatio, ZONE_REST_RATIO_FALLBACK["5k"]);
});

Deno.test("baseline needs 3 samples in a zone before it outranks cold start", () => {
  const thin = densityBaselineFromSamples([
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.46 },
  ]);
  assertEquals(thin.byZone["5k"], undefined);
  assertEquals(thin.countByZone["5k"], 2);

  const d = buildEffortProfile(tenByK(90), ZONES, { baseline: thin }).density;
  assertEquals(d.baselineSource, "cold_start");
});

Deno.test("baseline uses the median, so one set-break session can't move it", () => {
  const baseline = densityBaselineFromSamples([
    { zone: "5k", restRatio: 0.45 },
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.47 },
    { zone: "5k", restRatio: 4.0 }, // paused watch / long set break
  ]);
  assertEquals(baseline.byZone["5k"], 0.465);
});

Deno.test("a steady run has no density and is neither credited nor penalised", () => {
  const laps = [easyLap(600), easyLap(1800), easyLap(600)];
  const p = buildEffortProfile(laps, ZONES);
  assertEquals(p.density.repCount, 0);
  assertEquals(p.density.restRatio, null);
  assertEquals(p.density.multiplier, 1);
  assertEquals(p.effortLoad, p.baseLoad);
});

Deno.test("warmup and cooldown are excluded from the rep block", () => {
  // 3 reps → 2 inter-rep recoveries. The 10-min bookends must not count.
  const laps = [
    easyLap(600),
    repLap(),
    easyLap(90, true),
    repLap(),
    easyLap(90, true),
    repLap(),
    easyLap(600),
  ];
  const { reps, rests } = repRestSplit(segmentFromLaps(laps, ZONES).bouts);
  assertEquals(reps.length, 3);
  assertEquals(rests, [90, 90]);
});

Deno.test("restSampleFrom feeds the next session's baseline", () => {
  const d = buildEffortProfile(tenByK(90), ZONES).density;
  assertEquals(restSampleFrom(d), { zone: "5k", restRatio: 0.46 });
});

// ── Conditions ─────────────────────────────────────────────────────────────

Deno.test("heat enters through the pace, lifting the bout up the intensity curve", () => {
  // 78°F / 75°F dew — composite ~163, "very hot". A 1K rep is 0.62 mi, so it
  // takes the short-rep half-scaling.
  const cool = buildEffortProfile(tenByK(90), ZONES);
  const hot = buildEffortProfile(tenByK(90), ZONES, {
    conditions: { temp_f: 78, dew_point_f: 75 },
  });

  assert(hot.heatApplied);
  assert(!cool.heatApplied);
  assert(
    hot.effortLoad > cool.effortLoad,
    `heat should raise the load: ${hot.effortLoad} vs ${cool.effortLoad}`,
  );
  // The raw segmentation is untouched — the watch's paces are preserved.
  assertEquals(
    hot.rawSegmentation.intensityScore,
    cool.rawSegmentation.intensityScore,
  );
});

// ── Threshold in the heat: the continuous-effort scaling ───────────────────

const LT_PACE = 340; // ~1-hour race pace for this athlete → hmp band

/** A continuous N-mile threshold run, auto-lapped by the watch into 1-mile
 *  splits, with a 2mi warmup and cooldown. No recoveries anywhere. */
function continuousThreshold(miles: number): EffortLap[] {
  const laps: EffortLap[] = [easyLap(954)];
  for (let i = 0; i < miles; i++) {
    laps.push({
      is_rest: false,
      distance_meters: 1609,
      avg_pace_sec_per_mile: LT_PACE,
      moving_time_seconds: LT_PACE,
    });
  }
  laps.push(easyLap(954));
  return laps;
}

/** The same threshold volume broken into 1-mile reps off 90s jog. */
function thresholdReps(count: number): EffortLap[] {
  const laps: EffortLap[] = [easyLap(954)];
  for (let i = 0; i < count; i++) {
    laps.push({
      is_rest: false,
      distance_meters: 1609,
      avg_pace_sec_per_mile: LT_PACE,
      moving_time_seconds: LT_PACE,
    });
    if (i < count - 1) laps.push(easyLap(90, true));
  }
  laps.push(easyLap(954));
  return laps;
}

Deno.test("a continuous tempo takes the FULL heat penalty despite 1-mile auto-splits", () => {
  // Regression: the scaling used to key on lap distance, so a watch auto-lapping
  // a 6-mile tempo into 1-mile splits bought repLengthFactor 0.667 and threw
  // away a third of the correction — on exactly the session type that earns the
  // whole thing. It must now key on the 6-mile continuous block.
  const laps = continuousThreshold(6);
  const { laps: adj } = neutralEquivalentLaps(laps, ZONES, {
    temp_f: 82,
    dew_point_f: 72,
  });
  const full = adjustPace(LT_PACE, 82, 72, null); // continuous basis
  const tempoLap = adj.find((l) => l.moving_time_seconds === LT_PACE)!;
  assertEquals(
    Math.round(tempoLap.avg_pace_sec_per_mile!),
    Math.round(full.neutralEquivalentPaceSeconds),
  );
});

Deno.test("mile reps off a jog keep the short-rep scaling — the body does cool", () => {
  // The counterpart: real recoveries mean the reduced factor is correct here.
  // Same volume, same pace, same weather — only the recovery structure differs.
  const cont = buildEffortProfile(continuousThreshold(6), ZONES, {
    conditions: { temp_f: 82, dew_point_f: 72 },
  });
  const reps = buildEffortProfile(thresholdReps(6), ZONES, {
    conditions: { temp_f: 82, dew_point_f: 72 },
  });

  const contMile = cont.segmentation.bouts.find((b) => b.isRep)!;
  const repMile = reps.segmentation.bouts.find((b) => b.isRep)!;
  // Continuous gets the bigger correction → a faster neutral-equivalent pace.
  assert(
    contMile.paceSecPerMile < repMile.paceSecPerMile,
    `continuous ${contMile.paceSecPerMile} should credit more than reps ${repMile.paceSecPerMile}`,
  );
});

Deno.test("the same threshold session reads harder in heat than in cool air", () => {
  const cool = buildEffortProfile(continuousThreshold(6), ZONES, {
    conditions: { temp_f: 52, dew_point_f: 44 },
  });
  const hot = buildEffortProfile(continuousThreshold(6), ZONES, {
    conditions: { temp_f: 82, dew_point_f: 72 },
  });

  assertEquals(cool.heatApplied, false); // dew 44F — nothing to correct
  assertEquals(hot.heatApplied, true);
  assert(
    hot.effortLoad > cool.effortLoad,
    `hot ${hot.effortLoad} should exceed cool ${cool.effortLoad}`,
  );
});

Deno.test("flat and cool leaves the paces completely alone", () => {
  const laps = tenByK(90);
  const { laps: out, heatApplied, gradeApplied } = neutralEquivalentLaps(laps, ZONES, {
    temp_f: 50,
    dew_point_f: 42,
  });
  assertEquals(heatApplied, false);
  assertEquals(gradeApplied, false);
  assertEquals(out, laps);
});

Deno.test("grade is capped and asymmetric", () => {
  assertEquals(gradeFactor(0), 1);
  assert(gradeFactor(4) < 1); // uphill → faster-equivalent
  assert(gradeFactor(-4) > 1); // downhill → slower-equivalent
  // Beyond the cap nothing more accrues.
  assertEquals(gradeFactor(20), gradeFactor(8));
  // Uphill credit outweighs the downhill discount at equal grade.
  assert(1 - gradeFactor(4) > gradeFactor(-4) - 1);
});

Deno.test("hilly reps read as more effort than the same clock on the flat", () => {
  const flat = buildEffortProfile(tenByK(90), ZONES);
  const hilly = buildEffortProfile(
    tenByK(90, { total_elevation_gain: 20 }), // 20m over 1000m ≈ 2% grade
    ZONES,
  );
  assert(hilly.gradeApplied);
  assert(hilly.effortLoad > flat.effortLoad);
  assertEquals(hilly.totalElevationGainM, 200);
});

// ── HR ─────────────────────────────────────────────────────────────────────

Deno.test("HR splits into whole-run, work-only, and recovery drop", () => {
  const laps: EffortLap[] = [
    easyLap(600),
    repLap({ avg_heart_rate: 178 }),
    { ...easyLap(90, true), avg_heart_rate: 148 },
    repLap({ avg_heart_rate: 182 }),
    { ...easyLap(90, true), avg_heart_rate: 150 },
    repLap({ avg_heart_rate: 184 }),
    easyLap(600),
  ];
  const p = buildEffortProfile(laps, ZONES);
  assert(p.hasHr);
  assertEquals(p.avgWorkHr, 181);
  assertEquals(p.recoveryHrDropBpm, 31); // (178−148 + 182−150) / 2
  // Work HR sits above the whole-run average, which includes the easy bookends.
  assert(p.avgRunHr! < p.avgWorkHr!);
});

// ── Narration ──────────────────────────────────────────────────────────────

Deno.test("density narration states facts and never ranks", () => {
  const baseline = densityBaselineFromSamples([
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.46 },
    { zone: "5k", restRatio: 0.46 },
  ]);
  const lines = describeDensity(
    buildEffortProfile(tenByK(60), ZONES, { baseline }).density,
  ).join(" ");

  assert(lines.includes("78.3%"));
  assert(lines.includes("0.31"));
  for (const banned of ["harder", "better", "should", "easier", "worse", "improve"]) {
    assert(!lines.toLowerCase().includes(banned), `narration must not say "${banned}"`);
  }
});

Deno.test("density narration is empty when there is no density to describe", () => {
  const p = buildEffortProfile([easyLap(1800)], ZONES);
  assertEquals(describeDensity(p.density), []);
});

// ── Guards ─────────────────────────────────────────────────────────────────

Deno.test("degenerate input never throws or invents a multiplier", () => {
  for (const laps of [[], [easyLap(0)], [repLap({ moving_time_seconds: 0 })]]) {
    const p = buildEffortProfile(laps as EffortLap[], ZONES);
    assertEquals(p.density.multiplier, 1);
    assertEquals(p.effortLoad, p.baseLoad);
  }
});

Deno.test("a single rep has no measurable density", () => {
  const p = buildEffortProfile([easyLap(600), repLap(), easyLap(600)], ZONES);
  assertEquals(p.density.repCount, 0);
  assertEquals(p.density.multiplier, 1);
});
