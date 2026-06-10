// deterministic-builder.ts
// Server-side deterministic training plan builder based on PRD periodization.
// 18-week countdown: Phase 0 (Intro), Phase 1 (Fundamental), Phase 2 (Specific), Phase 3 (Peak/Taper/Race)

// ── Types ──────────────────────────────────────────────────────────

export interface DeterministicPlanInputs {
  startDate: string;
  raceDate: string;
  raceDistance: string;
  goalTimeSeconds: number | null;
  currentWeeklyMileage: number;
  maxWeeklyMileage: number | null;
  preferredLongRunDay: number;
  workout1Day: number; // 1=Mon..7=Sun — speed/tempo slot
  workout2Day: number; // 1=Mon..7=Sun — medium long / second quality slot
  runsPerWeek: number;
  canRunDoubles: boolean;
  planName: string;
}

interface PlanOutput {
  plan: {
    name: string;
    startDate: string;
    endDate: string;
    targetRaceDistance: string;
    targetTimeSeconds: number | null;
  };
  weeks: Array<{
    weekNumber: number;
    weeklyMileage: number;
    workouts: Array<{
      dayOfWeek: number;
      workoutCode: string;
      totalDistanceMiles: number;
      session?: number;
    }>;
  }>;
}

const RACE_MILES: Record<string, number> = {
  "5k": 3.107, "10k": 6.214, "half_marathon": 13.109, "marathon": 26.219,
};

// ── Workout Distance Lookups ────────────────────────────────────────
// Each workout has an inherent distance. For endurance runs it's explicit.
// For intervals it's warmup + reps*dist + recovery + cooldown.

const WORKOUT_DISTANCES: Record<string, number> = {
  // 0.80 Basic Endurance
  BE_1: 10, BE_2: 12, BE_3: 15, BE_4: 18, BE_5: 20, BE_6: 22, BE_7: 24, BE_8: 16,
  // 0.85 General Endurance
  GE_1: 10, GE_2: 12, GE_3: 15, GE_4: 18, GE_5: 20, GE_6: 22, GE_7: 8, GE_8: 11, GE_9: 16,
  // 0.90 Race-Supportive Endurance
  RSE_1: 8, RSE_2: 10, RSE_3: 12, RSE_4: 15, RSE_5: 18, RSE_6: 20, RSE_7: 16, RSE_8: 16,
  // 0.95 Race-Specific Endurance
  RCE_1: 10, RCE_2: 12, RCE_3: 15, RCE_4: 18, RCE_5: 16, RCE_6: 20, RCE_7: 19, RCE_8: 19,
  // 1.00 Race Pace (continuous + warmup/cooldown for alternations)
  RP_1: 10, RP_2: 12,
  RP_3: 14,   // 10x1mi + .5mi float ≈ 10+4.5+2WU+2CD but capped by session
  RP_4: 14,   // 5x2mi + .5mi float = 10+2+4= 16 → ~14 w/ WU/CD embedded
  RP_5: 17,   // 6x2mi + 1mi float = 12+5 = 17
  RP_6: 16,   // 4x3mi + 1mi float = 12+3 = 15 + 1CD
  RP_7: 17,   // 5x3mi + .5mi float = 15+2 = 17
  RP_8: 12,   // 2x5mi + 1mi float = 10+1 = 11 + 1WU
  RP_9: 18,   // 3x5mi + 1mi float = 15+2 = 17 + 1WU
  RP_10: 14,  // 2x6mi + 1mi float = 12+1 = 13 + 1WU
  RP_11: 16,  // 10x1km + 1km float ≈ 6.2+6.2 = 12.4 + 4WU/CD
  RP_12: 18,  // 8x2km + 1km float ≈ 10+4.3 + 4
  RP_13: 21,  // 10x2km + 1km float ≈ 12.4+5.6 + 3
  RP_14: 16,  // 6x3km + 1km float ≈ 11.2+3.1 + 2
  RP_15: 13,  // 4x4km + 1km float ≈ 10+1.9 + 1
  RP_16: 17,  // 5x4km + 1km float ≈ 12.4+2.5
  RP_17: 16,  // 4x5km + 1km float ≈ 12.4+1.9
  RP_18: 20,  // 5x5km + 1km float ≈ 15.5+2.5
  RP_19: 21,  // descending ladder 7+6+5+4+3+2km + 5x1km float ≈ 17+3
  // 1.05 Race-Specific Speed (total session = WU + intervals + recovery + CD)
  RSS_1: 12,  // 10mi steady state + 2mi WU
  RSS_2: 10,  // 6x6' steady + 3' easy ≈ fartlek ~10mi
  RSS_3: 10,  // 12x2' fast + 2' easy ≈ fartlek ~10mi
  RSS_4: 10,  // 10x3' steady + 2' moderate ≈ fartlek ~10mi
  RSS_5: 10,  // 10x800m + rest ≈ 5mi fast + 2WU + 2CD + 1jog = 10
  RSS_6: 12,  // 10x1km + rest ≈ 6.2mi fast + 4WU/CD + 2jog = 12
  RSS_7: 12,  // 6xmile + rest ≈ 6mi fast + 4WU/CD + 2jog = 12
  RSS_8: 10,  // 3x2mi + .5mi float = 6+1 + 3WU/CD = 10
  RSS_9: 13,  // 12x1km + rest ≈ 7.5mi fast + 4WU/CD + 1.5jog
  RSS_10: 14, // 8xmile + rest ≈ 8mi fast + 4WU/CD + 2jog
  RSS_11: 10, // 3mi/2mi/1mi cutdown + floats = 6+1.5 + 2.5 = 10
  RSS_12: 9,  // 2x3mi + .5mi float = 6+.5 + 2.5 = 9
  RSS_13: 11, // 7mi progression + 4WU/CD = 11
  RSS_14: 10, // 3x2mi + .5mi float = 6+1 + 3WU/CD = 10
  RSS_15: 13, // 2x4mi + .5mi float = 8+.5 + 4WU/CD = 13
  RSS_16: 12, // 6xmile + 1' float = 6+1 + 4WU/CD + 1 = 12
  RSS_17: 8,  // 4xmile + 2' rest = 4 + 4WU/CD = 8
  RSS_18: 10, // 2x3mi + .5mi float = 6+.5 + 3.5WU/CD = 10
  RSS_19: 11, // 7mi progression 97>103% + 4WU/CD = 11
  RSS_4b: 12, // 10x3'/3' alternation ≈ fartlek ~12mi
  // 1.10 Race-Supportive Speed
  RSPS_8: 10, // 3x4x800m at 108% + rest
  RSPS_1: 7,  // 12x400m + rest ≈ 3mi fast + 4WU/CD = 7
  RSPS_2: 9,  // 8x800m + rest ≈ 4mi fast + 4WU/CD + 1jog = 9
  RSPS_3: 10, // 3x4x800m + rest ≈ 6mi fast + 4WU/CD = 10
  RSPS_4: 9,  // 12x600m + 200m float ≈ 4.5mi + 1.5mi + 3WU/CD = 9
  RSPS_5: 10, // 8x1000m + rest ≈ 5mi fast + 4WU/CD + 1jog = 10
  RSPS_6: 11, // 5xmile + rest ≈ 5mi fast + 4WU/CD + 2jog = 11
  RSPS_7: 14, // 8xmile + rest ≈ 8mi fast + 4WU/CD + 2jog = 14
  // 1.15 Mechanical Speed
  GS_1: 7,    // 12x200m + 200m jog ≈ 1.5+1.5 + 4WU/CD = 7
  GS_2: 7,    // 12x300m + 200m float ≈ 2.2+1.5 + 3.3 = 7
  GS_3: 6,    // 10x400m + 200m jog ≈ 2.5+1.2 + 2.3 = 6
  GS_4: 8,    // 12x400m + 400m jog ≈ 3+3 + 2 = 8
  GS_5: 6,    // hill sprints + full recovery
  GS_6: 5,    // 8x100m strides
  GS_7: 6,    // hill sprints + full recovery
  GS_8: 6,    // 8x15s hill sprints + full recovery
  // Special
  FARTLEK: 8,
  EASY: 8,
  STRIDES: 8,
  REST: 0,
};

// ── Phase Logic ─────────────────────────────────────────────────────

type PRDPhase = 0 | 1 | 2 | 3;

function getPhase(weeksOut: number, totalWeeks: number): PRDPhase {
  // Scale phase boundaries proportionally for plans shorter/longer than 18 weeks
  const pct = weeksOut / totalWeeks;
  if (pct > 0.89) return 0;   // Top ~11% = Introductory (2 of 18)
  if (pct > 0.56) return 1;   // Next ~33% = Fundamental (6 of 18)
  if (pct > 0.11) return 2;   // Next ~45% = Specific (8 of 18)
  return 3;                    // Final ~11% = Taper/Race (2 of 18)
}

// ── Volume Calculation ──────────────────────────────────────────────

function computeTargetMileage(
  weeksOut: number,
  totalWeeks: number,
  currentMileage: number,
  maxMileage: number,
): number {
  const pct = weeksOut / totalWeeks;

  // Phase 0 + early Phase 1: ramp from current to 85% of max
  if (pct > 0.56) {
    const rangeStart = 0.56;
    const rangeEnd = 1.0;
    const t = (pct - rangeStart) / (rangeEnd - rangeStart); // 1.0 at start, 0.0 at boundary
    const target85 = maxMileage * 0.85;
    return Math.round(currentMileage + (target85 - currentMileage) * (1 - t));
  }
  // Phase 2: ramp from 85% to 100% of max (longer phase now)
  if (pct > 0.11) {
    const rangeStart = 0.11;
    const rangeEnd = 0.56;
    const t = (pct - rangeStart) / (rangeEnd - rangeStart);
    const from = maxMileage * 0.85;
    return Math.round(from + (maxMileage - from) * (1 - t));
  }
  // Phase 3: Taper + Race (2 weeks)
  if (weeksOut === 2) return Math.round(maxMileage * 0.60); // Taper
  return Math.round(maxMileage * 0.35); // Race week (includes race distance)
}

function computeMaxMileage(current: number, raceDistance: string): number {
  // Marathon mid-late weeks should target 75-100mpw
  if (raceDistance === "marathon") return Math.min(Math.max(Math.round(current * 1.7), 75), 100);
  if (raceDistance === "half_marathon") return Math.min(Math.max(Math.round(current * 1.5), 55), 85);
  if (raceDistance === "10k") return Math.min(Math.round(current * 1.3), 70);
  return Math.min(Math.round(current * 1.2), 60);
}

// ── Distance-Aware Workout Selection ────────────────────────────────

// Select the endurance workout (from a pace group) whose distance best matches the target
function selectByDistance(codes: string[], targetMiles: number): string {
  let bestCode = codes[0];
  let bestDiff = Infinity;
  for (const code of codes) {
    const dist = WORKOUT_DISTANCES[code] || 10;
    const diff = Math.abs(dist - targetMiles);
    if (diff < bestDiff) {
      bestDiff = diff;
      bestCode = code;
    }
  }
  return bestCode;
}

// Select an interval workout that fits within the target session miles
function selectIntervalByFit(codes: string[], targetMiles: number, progressionIdx: number, totalPhaseWeeks: number): string {
  // Filter to workouts that fit within ±3mi of target
  const fitting = codes.filter(c => {
    const dist = WORKOUT_DISTANCES[c] || 10;
    return dist <= targetMiles + 2 && dist >= targetMiles - 3;
  });

  const pool = fitting.length > 0 ? fitting : codes;
  // Progress through the pool based on phase progression
  const idx = Math.min(
    Math.floor((progressionIdx / Math.max(totalPhaseWeeks, 1)) * pool.length),
    pool.length - 1
  );
  return pool[idx];
}

// ── Workout Code Groups ─────────────────────────────────────────────

// Long run codes by pace
const BE_CODES = ["BE_1", "BE_2", "BE_3", "BE_4", "BE_5", "BE_6", "BE_7"];
const GE_CODES = ["GE_1", "GE_2", "GE_3", "GE_4", "GE_5", "GE_6"];
const GE_PROG_CODES = ["GE_7", "GE_8", "GE_9"]; // Progressions (time-based)
const RSE_ENDURANCE_CODES = ["RSE_1", "RSE_2", "RSE_3", "RSE_4", "RSE_5", "RSE_6"];
const RSE_ALTERNATION_CODES = ["RSE_7", "RSE_8"];
const RCE_CONTINUOUS_CODES = ["RCE_1", "RCE_2", "RCE_3", "RCE_4"];
const RCE_ALTERNATION_CODES = ["RCE_5", "RCE_6", "RCE_7", "RCE_8"];

// Speed codes by pace
const GS_CODES = ["GS_1", "GS_2", "GS_3", "GS_4", "GS_5", "GS_6", "GS_7"];
const RSPS_JOG_CODES = ["RSPS_1", "RSPS_2", "RSPS_3", "RSPS_5", "RSPS_6", "RSPS_7"]; // Jog recovery
const RSPS_FLOAT_CODES = ["RSPS_4"]; // Float recovery
const RSS_FARTLEK_CODES = ["RSS_1", "RSS_2", "RSS_3", "RSS_4"];
const RSS_INTERVAL_FLOAT_CODES = ["RSS_8", "RSS_12", "RSS_13"]; // Float recovery
const RSS_INTERVAL_JOG_CODES = ["RSS_5", "RSS_6", "RSS_7", "RSS_9", "RSS_10"]; // Jog recovery
const RP_CONTINUOUS_CODES = ["RP_1", "RP_2"];
const RP_ALTERNATION_CODES = ["RP_3", "RP_4", "RP_5", "RP_6", "RP_7", "RP_8", "RP_9", "RP_10",
  "RP_11", "RP_12", "RP_13", "RP_14", "RP_15", "RP_16", "RP_17", "RP_18", "RP_19"];

// ── Main Builder ────────────────────────────────────────────────────

export function buildDeterministicPlan(inputs: DeterministicPlanInputs): PlanOutput {
  const start = new Date(inputs.startDate + "T00:00:00Z");
  const end = new Date(inputs.raceDate + "T00:00:00Z");
  const totalWeeks = Math.max(4, Math.min(24,
    Math.ceil((end.getTime() - start.getTime()) / (7 * 86400000)),
  ));

  const maxMileage = inputs.maxWeeklyMileage || computeMaxMileage(inputs.currentWeeklyMileage, inputs.raceDistance);
  const longRunDay = inputs.preferredLongRunDay;
  const workout1Day = inputs.workout1Day || 2;
  const workout2Day = inputs.workout2Day || 4;

  // Count weeks per phase
  const phaseProgress: Record<PRDPhase, number> = { 0: 0, 1: 0, 2: 0, 3: 0 };
  const phaseWeekCounts: Record<PRDPhase, number> = { 0: 0, 1: 0, 2: 0, 3: 0 };
  for (let w = 0; w < totalWeeks; w++) {
    phaseWeekCounts[getPhase(totalWeeks - w, totalWeeks)]++;
  }

  let prevSatMPVolume = 0;
  let prevTueCode = "";
  let prevSatCode = "";
  const weeks: PlanOutput["weeks"] = [];

  // Tuesday workout categories — cycle through types for variety
  const TUE_CATEGORIES = {
    progression: ["GE_7", "GE_8", "GE_9", "RSS_13", "RSS_19"],
    fartlek: ["RSS_1", "RSS_2", "RSS_3", "RSS_4", "RSS_4b", "FARTLEK"],
    trackShort: ["RSPS_1", "RSPS_2", "RSPS_5", "RSPS_7", "RSPS_8", "GS_3", "GS_4"],
    trackLong: ["RSS_5", "RSS_6", "RSS_7", "RSS_9", "RSS_10"],
    tempo: ["RSS_8", "RSS_11", "RSS_12", "RSS_14", "RSS_15", "RSS_16", "RSS_17", "RSS_18"],
  };

  // Saturday long run categories — alternate for variety
  const SAT_CATEGORIES = {
    easyLong: BE_CODES,
    moderateLong: GE_CODES,
    progressionLong: GE_PROG_CODES,
    mpWork: RP_ALTERNATION_CODES,
    mpContinuous: RP_CONTINUOUS_CODES,
    rseWork: [...RSE_ENDURANCE_CODES, ...RSE_ALTERNATION_CODES],
  };

  for (let w = 0; w < totalWeeks; w++) {
    const weeksOut = totalWeeks - w;
    const phase = getPhase(weeksOut, totalWeeks);
    const pidx = phaseProgress[phase];
    phaseProgress[phase]++;

    const weeklyMileage = computeTargetMileage(weeksOut, totalWeeks, inputs.currentWeeklyMileage, maxMileage);

    // Daily volume targets
    const satTargetMiles = Math.min(Math.round(weeklyMileage * 0.27), 24);
    const tueTargetMiles = Math.round(weeklyMileage * 0.17);
    const thuTargetMiles = Math.round(weeklyMileage * 0.17);

    const workouts: PlanOutput["weeks"][0]["workouts"] = [];

    // Helper: pick from pool avoiding previous week's code
    function pickAvoiding(pool: string[], targetMiles: number, prev: string, idx: number, total: number): string {
      const filtered = pool.filter(c => c !== prev);
      const usePool = filtered.length > 0 ? filtered : pool;
      return selectIntervalByFit(usePool, targetMiles, idx, total);
    }

    function pickByDistAvoiding(pool: string[], targetMiles: number, prev: string): string {
      const filtered = pool.filter(c => c !== prev);
      const usePool = filtered.length > 0 ? filtered : pool;
      return selectByDistance(usePool, targetMiles);
    }

    // ─── TUESDAY (Workout 1 / Speed) ───────────────────────────
    // Cycle through workout TYPES each week for variety:
    // progression → fartlek → track → tempo → repeat
    let tueCode: string;
    let tueMiles: number;

    if (phase === 0) {
      // Phase 0: Alternate progression and fartlek, no structured track
      const typeIdx = pidx % 2;
      const pool = typeIdx === 0
        ? TUE_CATEGORIES.progression
        : TUE_CATEGORIES.fartlek;
      tueCode = pickAvoiding(pool, tueTargetMiles, prevTueCode, pidx, phaseWeekCounts[0]);
      tueMiles = WORKOUT_DISTANCES[tueCode] || tueTargetMiles;

    } else if (phase === 1) {
      // Phase 1: Cycle track short → tempo/fartlek → track long → progression
      const typeOrder = ["trackShort", "fartlek", "trackLong", "progression"] as const;
      type P1Cat = typeof typeOrder[number];
      const catKey: P1Cat = typeOrder[pidx % typeOrder.length];
      const pool = TUE_CATEGORIES[catKey].filter(c => {
        const dist = WORKOUT_DISTANCES[c] || 10;
        return dist <= tueTargetMiles + 2 && dist >= tueTargetMiles - 3;
      });
      const usePool = pool.length > 0 ? pool : TUE_CATEGORIES[catKey];
      tueCode = pickAvoiding(usePool, tueTargetMiles, prevTueCode, pidx, phaseWeekCounts[1]);
      tueMiles = WORKOUT_DISTANCES[tueCode] || tueTargetMiles;

      // Hangover rule: lighter workout after big MP Saturday
      if (prevSatMPVolume > 14) {
        tueCode = pickAvoiding(TUE_CATEGORIES.fartlek, Math.min(tueTargetMiles, 10), prevTueCode, 0, 1);
        tueMiles = WORKOUT_DISTANCES[tueCode] || 10;
      }

    } else if (phase === 2) {
      // Phase 2: Cycle fartlek → track → tempo → fartlek
      const typeOrder = ["fartlek", "trackLong", "tempo", "fartlek"] as const;
      type P2Cat = typeof typeOrder[number];
      const catKey: P2Cat = typeOrder[pidx % typeOrder.length];
      tueCode = pickAvoiding(TUE_CATEGORIES[catKey], tueTargetMiles, prevTueCode, pidx, phaseWeekCounts[2]);
      tueMiles = WORKOUT_DISTANCES[tueCode] || tueTargetMiles;

      if (prevSatMPVolume > 14) {
        tueCode = pickAvoiding(TUE_CATEGORIES.fartlek, Math.min(tueTargetMiles, 10), prevTueCode, 0, 1);
        tueMiles = WORKOUT_DISTANCES[tueCode] || 10;
      }

    } else {
      // Phase 3: Peak → Taper → Race
      if (weeksOut >= 3) {
        // Peak: alternate tempo and track
        const peakPool = pidx % 2 === 0 ? TUE_CATEGORIES.tempo : TUE_CATEGORIES.trackLong;
        tueCode = pickAvoiding(peakPool, Math.min(tueTargetMiles, 12), prevTueCode, 0, 1);
      } else if (weeksOut === 2) {
        tueCode = pickAvoiding(TUE_CATEGORIES.trackShort, Math.min(tueTargetMiles, 8), prevTueCode, 0, 1);
      } else {
        // Race week: short race-specific sharpener
        tueCode = "RSS_17"; // 4xMile at 105%
      }
      tueMiles = WORKOUT_DISTANCES[tueCode] || tueTargetMiles;
    }

    prevTueCode = tueCode;
    workouts.push({ dayOfWeek: workout1Day, workoutCode: tueCode, totalDistanceMiles: tueMiles });

    // ─── THURSDAY (Medium Long Run) ────────────────────────────
    // Rotate through codes at target distance — not the same one every week
    let thuCode: string;
    if (phase <= 1) {
      // Alternate between BE and GE progressions for variety
      if (w % 3 === 2) {
        thuCode = pickByDistAvoiding(GE_PROG_CODES, thuTargetMiles, "");
      } else {
        thuCode = pickByDistAvoiding(BE_CODES, thuTargetMiles, "");
      }
    } else {
      // Phase 2-3: Rotate GE codes + occasional GE progression
      if (w % 4 === 3) {
        thuCode = pickByDistAvoiding(GE_PROG_CODES, thuTargetMiles, "");
      } else {
        thuCode = pickByDistAvoiding(GE_CODES, thuTargetMiles, "");
      }
    }
    const thuMiles = WORKOUT_DISTANCES[thuCode] || thuTargetMiles;

    workouts.push({ dayOfWeek: workout2Day, workoutCode: thuCode, totalDistanceMiles: thuMiles });

    // ─── SATURDAY (Workout 2 / Long Run) ───────────────────────
    // Alternate between long run types — no two same type in a row
    let satCode: string;
    let satMiles: number;
    prevSatMPVolume = 0;

    if (phase === 0) {
      // Phase 0: Alternate easy long and progression
      const satPool = pidx % 2 === 0
        ? SAT_CATEGORIES.easyLong
        : SAT_CATEGORIES.progressionLong;
      const satTarget = Math.min(satTargetMiles, 14);
      satCode = pickByDistAvoiding(satPool, satTarget, prevSatCode);
      satMiles = Math.min(WORKOUT_DISTANCES[satCode] || satTarget, 14);

    } else if (phase === 1) {
      // Phase 1: Cycle easy → moderate → RSE → progression
      const satTypes = [SAT_CATEGORIES.easyLong, SAT_CATEGORIES.moderateLong,
                        SAT_CATEGORIES.rseWork, SAT_CATEGORIES.progressionLong];
      const pool = satTypes[pidx % satTypes.length];
      satCode = pickByDistAvoiding(pool, satTargetMiles, prevSatCode);
      satMiles = WORKOUT_DISTANCES[satCode] || satTargetMiles;

    } else if (phase === 2) {
      // Phase 2: Cycle moderate → MP alternation → progression → MP continuous
      const satTypes = [SAT_CATEGORIES.moderateLong, SAT_CATEGORIES.mpWork,
                        SAT_CATEGORIES.progressionLong, SAT_CATEGORIES.mpContinuous];
      const pool = satTypes[pidx % satTypes.length];
      if (pool === SAT_CATEGORIES.mpWork || pool === SAT_CATEGORIES.mpContinuous) {
        satCode = pickAvoiding(pool, satTargetMiles, prevSatCode, pidx, phaseWeekCounts[2]);
        prevSatMPVolume = (WORKOUT_DISTANCES[satCode] || satTargetMiles) * 0.7;
      } else {
        satCode = pickByDistAvoiding(pool, satTargetMiles, prevSatCode);
      }
      satMiles = WORKOUT_DISTANCES[satCode] || satTargetMiles;

    } else {
      // Phase 3
      if (weeksOut === 4) {
        satCode = pickAvoiding(SAT_CATEGORIES.mpWork, Math.min(satTargetMiles, 18), prevSatCode, 3, 5);
        satMiles = WORKOUT_DISTANCES[satCode] || 18;
        prevSatMPVolume = satMiles * 0.7;
      } else if (weeksOut === 3) {
        satCode = pickAvoiding(SAT_CATEGORIES.mpWork, 12, prevSatCode, 0, 3);
        satMiles = WORKOUT_DISTANCES[satCode] || 12;
        prevSatMPVolume = satMiles * 0.7;
      } else if (weeksOut === 2) {
        satCode = pickByDistAvoiding(SAT_CATEGORIES.moderateLong, Math.min(satTargetMiles, 12), prevSatCode);
        satMiles = WORKOUT_DISTANCES[satCode] || 12;
      } else {
        satCode = "RACE";
        satMiles = RACE_MILES[inputs.raceDistance] || 26.219;
      }
    }

    prevSatCode = satCode;

    // Race week: put race on actual race day
    if (weeksOut === 1 && satCode === "RACE") {
      const raceDay = new Date(inputs.raceDate + "T00:00:00Z").getUTCDay();
      const raceDow = raceDay === 0 ? 7 : raceDay;
      workouts.push({ dayOfWeek: raceDow, workoutCode: "RACE", totalDistanceMiles: satMiles });
    } else {
      workouts.push({ dayOfWeek: longRunDay, workoutCode: satCode, totalDistanceMiles: satMiles });
    }

    // ─── EASY DAYS — plan all remaining days holistically ──────
    // Modeled on real training patterns: easy runs 7-10mi, strides 7-8mi,
    // recovery 4-7mi, doubles 4-5mi on weekdays when volume demands it.

    const qualityDowSet = new Set(workouts.map(wk => wk.dayOfWeek));
    const qualityMilesUsed = workouts.reduce((s, wk) => s + wk.totalDistanceMiles, 0);
    const easyBudget = Math.max(0, weeklyMileage - qualityMilesUsed);

    // Day roles relative to long run
    const dayAfterLR = longRunDay === 7 ? 1 : longRunDay + 1;
    let sd = longRunDay - 1;
    if (sd <= 0) sd = 7;
    while (qualityDowSet.has(sd) || sd === dayAfterLR) {
      sd--;
      if (sd <= 0) sd = 7;
    }

    // Collect easy days
    const allEasyDows: number[] = [];
    for (let d = 1; d <= 7; d++) {
      if (!qualityDowSet.has(d)) allEasyDows.push(d);
    }

    // Normal days = easy days that aren't strides or recovery
    const normalDows = allEasyDows.filter(d => d !== sd && d !== dayAfterLR);

    if (weeksOut === 1) {
      // Race week: day before race = 3mi + strides, rest days otherwise
      const raceDay = new Date(inputs.raceDate + "T00:00:00Z").getUTCDay();
      const raceDow = raceDay === 0 ? 7 : raceDay;
      const dayBeforeRace = raceDow === 1 ? 7 : raceDow - 1;
      for (const d of allEasyDows) {
        if (d === dayBeforeRace && !qualityDowSet.has(d)) {
          workouts.push({ dayOfWeek: d, workoutCode: "STRIDES", totalDistanceMiles: 3 });
        } else {
          workouts.push({ dayOfWeek: d, workoutCode: "REST", totalDistanceMiles: 0 });
        }
      }
    } else if (easyBudget <= 0) {
      // Very light week: all easy days are rest
      for (const d of allEasyDows) {
        workouts.push({ dayOfWeek: d, workoutCode: "REST", totalDistanceMiles: 0 });
      }
    } else {
      const isRestWeek = weeklyMileage < 55;
      const isIntro = phase === 0;

      // Base mileage — lighter in intro phase, no doubles
      const stridesMi = isIntro ? 6 : (weeklyMileage >= 70 ? 8 : 7);
      let recMi = isRestWeek ? 0 : isIntro ? 5 : (weeklyMileage >= 68 ? 4 : 6);
      let n1Mi = normalDows.length >= 1 ? (isIntro ? 7 : 8) : 0;
      let n2Mi = normalDows.length >= 2 ? (isIntro ? 7 : 8) : 0;

      let surplus = easyBudget - (stridesMi + recMi + n1Mi + n2Mi);

      // Doubles on weekday normals (4-5mi, never weekends, never in intro phase)
      let d1Mi = 0, d2Mi = 0;
      const n1Weekday = normalDows.length >= 1 && normalDows[0] !== 6 && normalDows[0] !== 7;
      const n2Weekday = normalDows.length >= 2 && normalDows[1] !== 6 && normalDows[1] !== 7;

      if (inputs.canRunDoubles && !isIntro && surplus >= 4 && n1Weekday) {
        d1Mi = weeklyMileage >= 85 ? 5 : 4;
        surplus -= d1Mi;
      }
      if (inputs.canRunDoubles && !isIntro && surplus >= 4 && n2Weekday) {
        d2Mi = weeklyMileage >= 95 ? 5 : 4;
        surplus -= d2Mi;
      }

      // Bump primaries with remaining surplus (Wed → Mon → recovery, cap 10/10/8)
      for (let pass = 0; pass < 8 && surplus > 0; pass++) {
        if (surplus > 0 && n2Mi > 0 && n2Mi < 10) { n2Mi++; surplus--; }
        if (surplus > 0 && n1Mi > 0 && n1Mi < 10) { n1Mi++; surplus--; }
        if (surplus > 0 && recMi > 0 && recMi < 8) { recMi++; surplus--; }
      }

      // Handle deficit (quality workouts exceeded target percentages)
      for (let pass = 0; pass < 8 && surplus < 0; pass++) {
        if (surplus < 0 && recMi > 4) { recMi--; surplus++; }
        if (surplus < 0 && n1Mi > 6) { n1Mi--; surplus++; }
        if (surplus < 0 && n2Mi > 6) { n2Mi--; surplus++; }
      }

      // Push strides
      workouts.push({ dayOfWeek: sd, workoutCode: "STRIDES", totalDistanceMiles: stridesMi });

      // Push recovery or rest
      if (isRestWeek) {
        workouts.push({ dayOfWeek: dayAfterLR, workoutCode: "REST", totalDistanceMiles: 0 });
      } else if (recMi > 0) {
        workouts.push({ dayOfWeek: dayAfterLR, workoutCode: "EASY", totalDistanceMiles: recMi });
      }

      // Push normal easy days + doubles
      if (normalDows.length >= 1 && n1Mi > 0) {
        workouts.push({ dayOfWeek: normalDows[0], workoutCode: "EASY", totalDistanceMiles: n1Mi });
        if (d1Mi > 0) {
          workouts.push({ dayOfWeek: normalDows[0], workoutCode: "EASY", totalDistanceMiles: d1Mi, session: 2 });
        }
      }
      if (normalDows.length >= 2 && n2Mi > 0) {
        workouts.push({ dayOfWeek: normalDows[1], workoutCode: "EASY", totalDistanceMiles: n2Mi });
        if (d2Mi > 0) {
          workouts.push({ dayOfWeek: normalDows[1], workoutCode: "EASY", totalDistanceMiles: d2Mi, session: 2 });
        }
      }
    }

    weeks.push({ weekNumber: w + 1, weeklyMileage, workouts });
  }

  const endDate = new Date(start);
  endDate.setUTCDate(endDate.getUTCDate() + (totalWeeks * 7) - 1);

  return {
    plan: {
      name: inputs.planName,
      startDate: inputs.startDate,
      endDate: endDate.toISOString().split("T")[0],
      targetRaceDistance: inputs.raceDistance,
      targetTimeSeconds: inputs.goalTimeSeconds,
    },
    weeks,
  };
}

// ── Input Parser ────────────────────────────────────────────────────

// ── Hybrid Skeleton Types ────────────────────────────────────────

export interface SkeletonRunnerProfile {
  fitnessLevel: 'beginner' | 'novice' | 'intermediate' | 'advanced' | 'elite';
  fitnessIndex: number | null;
  currentWeeklyMileage: number;
  goalDistance: string;
  canRunDoubles: boolean;
  trackAccess: boolean;
  maxSessionMinutes: number;
  preferredLongRunDay: number; // 1=Mon ... 7=Sun
  workout1Day: number; // 1=Mon..7=Sun — speed/tempo slot
  workout2Day: number; // 1=Mon..7=Sun — medium long slot
  runsPerWeek: number;
  maxMileageJumpPercent: number;
  maxWeeklyMileage: number | null;
}

export interface DailyWorkoutSkeleton {
  dayOfWeek: number; // 1=Monday through 7=Sunday
  isQualityDay: boolean;
  isDouble: boolean;
  assignedMileage: number;
  easyPaceCode: 'EASY' | 'REST' | 'STRIDES' | null;
  ai_workout_code: string | null;
}

export interface WeeklySkeleton {
  weekNumber: number;
  weeksOutFromRace: number;
  phase: 0 | 1 | 2 | 3;
  targetWeeklyMileage: number;
  days: DailyWorkoutSkeleton[];
}

export interface AIWorkoutSelection {
  weekNumber: number;
  tuesday_code: string;
  thursday_code: string;
  saturday_code: string;
}

export interface AIFinalOutput {
  coaching_strategy: string;
  selections: AIWorkoutSelection[];
}

// ── Skeleton Generator ───────────────────────────────────────────

export function generatePlanSkeleton(
  profile: SkeletonRunnerProfile,
  startDate: string,
  raceDate: string,
): WeeklySkeleton[] {
  const start = new Date(startDate + "T00:00:00Z");
  const end = new Date(raceDate + "T00:00:00Z");
  const totalWeeks = Math.max(4, Math.min(24,
    Math.ceil((end.getTime() - start.getTime()) / (7 * 86400000)),
  ));

  const maxMileage = profile.maxWeeklyMileage ||
    computeMaxMileage(profile.currentWeeklyMileage, profile.goalDistance);
  const longRunDay = profile.preferredLongRunDay;
  const workout1Day = profile.workout1Day || 2;
  const workout2Day = profile.workout2Day || 4;

  const skeleton: WeeklySkeleton[] = [];
  let prevMileage = profile.currentWeeklyMileage;

  for (let w = 0; w < totalWeeks; w++) {
    const weeksOut = totalWeeks - w;
    const phase = getPhase(weeksOut, totalWeeks);

    // Target mileage with smooth ramp
    let target = computeTargetMileage(
      weeksOut, totalWeeks, profile.currentWeeklyMileage, maxMileage,
    );

    // Enforce max weekly jump
    if (w > 0) {
      const maxJump = Math.round(prevMileage * (profile.maxMileageJumpPercent / 100));
      target = Math.min(target, prevMileage + maxJump);
    }
    prevMileage = target;

    // Quality day targets (27% long, 17% Tue, 17% Thu)
    const longMi = Math.min(Math.round(target * 0.27), 24);
    const tueMi = Math.round(target * 0.17);
    const thuMi = Math.round(target * 0.17);

    const qualitySet = new Set([workout1Day, workout2Day, longRunDay]);
    const easyBudget = Math.max(0, target - (longMi + tueMi + thuMi));

    // Day roles relative to long run
    const dayAfterLR = longRunDay === 7 ? 1 : longRunDay + 1;
    let stridesDay = longRunDay - 1;
    if (stridesDay <= 0) stridesDay = 7;
    while (qualitySet.has(stridesDay) || stridesDay === dayAfterLR) {
      stridesDay--;
      if (stridesDay <= 0) stridesDay = 7;
    }

    const easySlots: number[] = [];
    for (let d = 1; d <= 7; d++) {
      if (!qualitySet.has(d)) easySlots.push(d);
    }
    const normalSlots = easySlots.filter(d => d !== stridesDay && d !== dayAfterLR);

    // Easy day mileage allocation
    const isIntro = phase === 0;
    const isLight = target < 55;
    let stridesMi = isIntro ? 6 : (target >= 70 ? 8 : 7);
    let recoveryMi = isLight ? 0 : (isIntro ? 5 : (target >= 68 ? 4 : 6));
    const normalMi: number[] = normalSlots.map(() => isIntro ? 7 : 8);

    // Adjust to match budget
    let surplus = easyBudget - (stridesMi + recoveryMi + normalMi.reduce((a, b) => a + b, 0));

    for (let pass = 0; pass < 8 && surplus > 0; pass++) {
      for (let i = 0; i < normalMi.length && surplus > 0; i++) {
        if (normalMi[i] < 10) { normalMi[i]++; surplus--; }
      }
      if (surplus > 0 && recoveryMi > 0 && recoveryMi < 8) { recoveryMi++; surplus--; }
    }
    for (let pass = 0; pass < 8 && surplus < 0; pass++) {
      if (recoveryMi > 4 && surplus < 0) { recoveryMi--; surplus++; }
      for (let i = normalMi.length - 1; i >= 0 && surplus < 0; i--) {
        if (normalMi[i] > 6) { normalMi[i]--; surplus++; }
      }
    }

    const days: DailyWorkoutSkeleton[] = [];

    if (weeksOut === 1) {
      // Race week: pre-fill most days deterministically
      const raceDay = new Date(raceDate + "T00:00:00Z").getUTCDay();
      const raceDow = raceDay === 0 ? 7 : raceDay;
      const dayBeforeRace = raceDow === 1 ? 7 : raceDow - 1;
      const raceMiles = RACE_MILES[profile.goalDistance] || 26.219;

      for (let d = 1; d <= 7; d++) {
        if (d === raceDow) {
          days.push({ dayOfWeek: d, isQualityDay: true, isDouble: false, assignedMileage: raceMiles, easyPaceCode: null, ai_workout_code: "RACE" });
        } else if (d === workout1Day) {
          // Sharpener slot: AI picks a short workout
          days.push({ dayOfWeek: d, isQualityDay: true, isDouble: false, assignedMileage: 8, easyPaceCode: null, ai_workout_code: null });
        } else if (d === dayBeforeRace && !qualitySet.has(d)) {
          days.push({ dayOfWeek: d, isQualityDay: false, isDouble: false, assignedMileage: 3, easyPaceCode: 'STRIDES', ai_workout_code: null });
        } else if (d === workout2Day) {
          days.push({ dayOfWeek: d, isQualityDay: false, isDouble: false, assignedMileage: 4, easyPaceCode: 'EASY', ai_workout_code: null });
        } else {
          days.push({ dayOfWeek: d, isQualityDay: false, isDouble: false, assignedMileage: 0, easyPaceCode: 'REST', ai_workout_code: null });
        }
      }
    } else {
      // Normal week
      let normalIdx = 0;
      for (let d = 1; d <= 7; d++) {
        if (d === workout1Day) {
          days.push({ dayOfWeek: d, isQualityDay: true, isDouble: false, assignedMileage: tueMi, easyPaceCode: null, ai_workout_code: null });
        } else if (d === workout2Day) {
          days.push({ dayOfWeek: d, isQualityDay: true, isDouble: false, assignedMileage: thuMi, easyPaceCode: null, ai_workout_code: null });
        } else if (d === longRunDay) {
          days.push({ dayOfWeek: d, isQualityDay: true, isDouble: false, assignedMileage: longMi, easyPaceCode: null, ai_workout_code: null });
        } else if (d === dayAfterLR) {
          if (recoveryMi > 0) {
            days.push({ dayOfWeek: d, isQualityDay: false, isDouble: false, assignedMileage: recoveryMi, easyPaceCode: 'EASY', ai_workout_code: null });
          } else {
            days.push({ dayOfWeek: d, isQualityDay: false, isDouble: false, assignedMileage: 0, easyPaceCode: 'REST', ai_workout_code: null });
          }
        } else if (d === stridesDay) {
          days.push({ dayOfWeek: d, isQualityDay: false, isDouble: false, assignedMileage: stridesMi, easyPaceCode: 'STRIDES', ai_workout_code: null });
        } else if (normalSlots.includes(d)) {
          const mi = normalIdx < normalMi.length ? normalMi[normalIdx] : 0;
          normalIdx++;
          if (mi > 0) {
            days.push({ dayOfWeek: d, isQualityDay: false, isDouble: false, assignedMileage: mi, easyPaceCode: 'EASY', ai_workout_code: null });
          } else {
            days.push({ dayOfWeek: d, isQualityDay: false, isDouble: false, assignedMileage: 0, easyPaceCode: 'REST', ai_workout_code: null });
          }
        } else {
          days.push({ dayOfWeek: d, isQualityDay: false, isDouble: false, assignedMileage: 0, easyPaceCode: 'REST', ai_workout_code: null });
        }
      }
    }

    skeleton.push({
      weekNumber: w + 1,
      weeksOutFromRace: weeksOut,
      phase,
      targetWeeklyMileage: target,
      days,
    });
  }

  return skeleton;
}

// ── Input Parser ────────────────────────────────────────────────────

export function parseDeterministicInputs(
  body: Record<string, unknown>,
): DeterministicPlanInputs | null {
  if (!body.startDate || !body.raceDate || !body.currentWeeklyMileage) return null;

  const message = (body.message as string) || "";

  const distMatch = message.match(/Generate a\s+([\w\s-]+?)\s+training plan/i);
  let raceDistance = "marathon";
  if (distMatch) {
    const distMap: Record<string, string> = {
      "marathon": "marathon", "half marathon": "half_marathon",
      "half-marathon": "half_marathon", "10k": "10k", "5k": "5k",
    };
    raceDistance = distMap[distMatch[1].trim().toLowerCase()] || "marathon";
  }

  const peakMatch = message.match(/(?:Peak|Max) weekly mileage:\s*(\d+)/i);
  const runsMatch = message.match(/Runs per week:\s*(\d+)/i);
  const longRunDayMatch = message.match(/[Pp]referred long run day:\s*(\w+)/);
  const workout1Match = message.match(/[Pp]referred workout day 1:\s*(\w+)/);
  const workout2Match = message.match(/[Pp]referred workout day 2:\s*(\w+)/);
  const doublesMatch = message.match(/Can run doubles:\s*yes/i);
  const nameMatch = message.match(/Plan name:\s*(.+)/im);

  const dayMap: Record<string, number> = {
    monday: 1, tuesday: 2, wednesday: 3, thursday: 4,
    friday: 5, saturday: 6, sunday: 7,
  };

  const longRunDay = longRunDayMatch ? (dayMap[longRunDayMatch[1].toLowerCase()] || 6) : 6;
  let workout1Day = workout1Match ? (dayMap[workout1Match[1].toLowerCase()] || 2) : 2;
  let workout2Day = workout2Match ? (dayMap[workout2Match[1].toLowerCase()] || 4) : 4;
  // Guard: quality days must be distinct from each other and from long run
  if (workout1Day === longRunDay || workout1Day === workout2Day) workout1Day = 2;
  if (workout2Day === longRunDay || workout2Day === workout1Day) workout2Day = workout1Day === 4 ? 3 : 4;

  return {
    startDate: body.startDate as string,
    raceDate: body.raceDate as string,
    raceDistance,
    goalTimeSeconds: (body.goalTimeSeconds as number) || null,
    currentWeeklyMileage: body.currentWeeklyMileage as number,
    maxWeeklyMileage: peakMatch ? parseInt(peakMatch[1]) : null,
    preferredLongRunDay: longRunDay,
    workout1Day,
    workout2Day,
    runsPerWeek: runsMatch ? parseInt(runsMatch[1]) : 6,
    canRunDoubles: !!doublesMatch,
    planName: nameMatch ? nameMatch[1].trim() : `${raceDistance.replace("_", " ")} Training Plan`,
  };
}
