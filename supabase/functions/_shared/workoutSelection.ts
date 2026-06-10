/**
 * Shared Workout Selection Logic
 *
 * Used by both the adaptive plan subscription and the adaptive workout refresh.
 * Selects specific workout codes from the library based on:
 * - Day role (speed/moderate/long_run/easy/recovery/strides)
 * - Training phase (base/build/specific/taper)
 * - Target mileage
 * - Athlete's pace zones
 */

// ── Workout Code Groups ──────────────────────────────────────

const BE_CODES = ["BE_1", "BE_2", "BE_3", "BE_4", "BE_5", "BE_6", "BE_7"];
const GE_CODES = ["GE_1", "GE_2", "GE_3", "GE_4", "GE_5", "GE_6"];
const GE_PROG_CODES = ["GE_7", "GE_8", "GE_9"];
const RSE_ENDURANCE_CODES = ["RSE_1", "RSE_2", "RSE_3", "RSE_4", "RSE_5", "RSE_6"];
const RSE_ALTERNATION_CODES = ["RSE_7", "RSE_8"];
const RCE_CONTINUOUS_CODES = ["RCE_1", "RCE_2", "RCE_3", "RCE_4"];
const RCE_ALTERNATION_CODES = ["RCE_5", "RCE_6", "RCE_7", "RCE_8"];
const GS_CODES = ["GS_1", "GS_2", "GS_3", "GS_4", "GS_5", "GS_6", "GS_7"];
const RSPS_CODES = ["RSPS_1", "RSPS_2", "RSPS_3", "RSPS_5", "RSPS_6", "RSPS_7"];
const RSS_FARTLEK_CODES = ["RSS_1", "RSS_2", "RSS_3", "RSS_4"];
const RSS_INTERVAL_CODES = ["RSS_5", "RSS_6", "RSS_7", "RSS_8", "RSS_9", "RSS_10"];
const RP_ALTERNATION_CODES = ["RP_3", "RP_4", "RP_5", "RP_6", "RP_7", "RP_8", "RP_9", "RP_10"];

export const WORKOUT_DISTANCES: Record<string, number> = {
  BE_1: 10, BE_2: 12, BE_3: 15, BE_4: 18, BE_5: 20, BE_6: 22, BE_7: 24,
  GE_1: 10, GE_2: 12, GE_3: 15, GE_4: 18, GE_5: 20, GE_6: 22,
  GE_7: 8, GE_8: 11, GE_9: 16,
  RSE_1: 8, RSE_2: 10, RSE_3: 12, RSE_4: 15, RSE_5: 18, RSE_6: 20,
  RSE_7: 16, RSE_8: 16,
  RCE_1: 10, RCE_2: 12, RCE_3: 15, RCE_4: 18,
  RCE_5: 16, RCE_6: 20, RCE_7: 19, RCE_8: 19,
  RP_3: 14, RP_4: 14, RP_5: 17, RP_6: 16, RP_7: 17,
  RP_8: 12, RP_9: 18, RP_10: 14,
  RSS_1: 12, RSS_2: 10, RSS_3: 10, RSS_4: 10,
  RSS_5: 10, RSS_6: 12, RSS_7: 10, RSS_8: 10, RSS_9: 12, RSS_10: 10,
  RSPS_1: 10, RSPS_2: 9, RSPS_3: 10, RSPS_5: 10, RSPS_6: 8, RSPS_7: 9,
  GS_1: 7, GS_2: 7, GS_3: 7, GS_4: 8, GS_5: 5, GS_6: 5, GS_7: 5,
  EASY: 0, REST: 0, STRIDES: 0, RACE: 0, FARTLEK: 12,
};

// ── Selection Functions ──────────────────────────────────────

function selectByDistance(codes: string[], targetMiles: number): string {
  let best = codes[0];
  let bestDiff = Infinity;
  for (const code of codes) {
    const dist = WORKOUT_DISTANCES[code] || 10;
    const diff = Math.abs(dist - targetMiles);
    if (diff < bestDiff) { bestDiff = diff; best = code; }
  }
  return best;
}

function selectByProgression(codes: string[], targetMiles: number, weekInPhase: number, totalPhaseWeeks: number): string {
  const fitting = codes.filter(c => {
    const dist = WORKOUT_DISTANCES[c] || 10;
    return dist <= targetMiles + 2 && dist >= targetMiles - 3;
  });
  const pool = fitting.length > 0 ? fitting : codes;
  const idx = Math.min(
    Math.floor((weekInPhase / Math.max(totalPhaseWeeks, 1)) * pool.length),
    pool.length - 1
  );
  return pool[idx];
}

// ── Main Selection API ───────────────────────────────────────

export interface WorkoutSelectionInput {
  role: string;           // "speed" | "moderate" | "long_run" | "easy" | "recovery" | "strides" | "rest"
  phase: string;          // "base" | "build" | "specific" | "taper"
  targetMiles: number;    // target session distance
  weekInPhase: number;    // 0-indexed week within this phase
  totalPhaseWeeks: number;
  prevCode?: string;      // avoid repeating the same workout
}

export function selectWorkoutForRole(input: WorkoutSelectionInput): string {
  const { role, phase, targetMiles, weekInPhase, totalPhaseWeeks } = input;

  if (role === "rest") return "REST";
  if (role === "strides") return "STRIDES";
  if (role === "recovery" || role === "easy") return "EASY";

  // ── Speed day (Tuesday-style) ──
  if (role === "speed") {
    switch (phase) {
      case "base":
        // Progressions + easy fartleks
        return weekInPhase % 2 === 0
          ? selectByDistance(GE_PROG_CODES, Math.min(targetMiles, 11))
          : selectByDistance(RSS_FARTLEK_CODES, Math.min(targetMiles, 12));

      case "build":
        // Cycle: fartlek → track short → track long → tempo
        const buildCycle = [RSS_FARTLEK_CODES, RSPS_CODES, RSS_INTERVAL_CODES, GE_PROG_CODES];
        const buildPool = buildCycle[weekInPhase % buildCycle.length];
        return selectByProgression(buildPool, targetMiles, weekInPhase, totalPhaseWeeks);

      case "specific":
        // Harder intervals, MP work
        const specCycle = [RSS_INTERVAL_CODES, RSPS_CODES, RP_ALTERNATION_CODES, RSS_FARTLEK_CODES];
        const specPool = specCycle[weekInPhase % specCycle.length];
        return selectByProgression(specPool, targetMiles, weekInPhase, totalPhaseWeeks);

      case "taper":
        // Short, sharp speed
        return selectByDistance(GS_CODES, Math.min(targetMiles, 6));

      default:
        return selectByDistance(RSS_FARTLEK_CODES, targetMiles);
    }
  }

  // ── Moderate day (Thursday-style) ──
  if (role === "moderate") {
    const modPool = [...GE_CODES.slice(0, 2), ...BE_CODES.slice(0, 2), "GE_7"];
    return selectByDistance(modPool, targetMiles);
  }

  // ── Long run day (Saturday-style) ──
  if (role === "long_run") {
    switch (phase) {
      case "base":
        // Easy long runs, some progressions
        return weekInPhase % 3 === 2
          ? selectByDistance(GE_PROG_CODES, Math.min(targetMiles, 16))
          : selectByDistance(BE_CODES, targetMiles);

      case "build":
        // Alternate easy/moderate/steady
        const buildSatCycle = [BE_CODES, GE_CODES, RSE_ENDURANCE_CODES, GE_PROG_CODES];
        return selectByDistance(buildSatCycle[weekInPhase % buildSatCycle.length], targetMiles);

      case "specific":
        // Race-specific long runs
        const specSatCycle = [GE_CODES, RSE_ENDURANCE_CODES, RCE_CONTINUOUS_CODES, RP_ALTERNATION_CODES];
        return selectByProgression(specSatCycle[weekInPhase % specSatCycle.length], targetMiles, weekInPhase, totalPhaseWeeks);

      case "taper":
        // Short easy long runs
        return selectByDistance(BE_CODES, Math.min(targetMiles, 12));

      default:
        return selectByDistance(BE_CODES, targetMiles);
    }
  }

  return "EASY";
}

// ── Pace Zone Computation ────────────────────────────────────

export interface PaceZones {
  easy: number;       // seconds per mile
  moderate: number;
  steady: number;
  marathon: number;
  halfMarathon: number;
  threshold: number;
  tenK: number;
  fiveK: number;
}

// Pace zones come from the central PaceEngine. See _shared/pace-engine.ts.
// Local function kept as a thin shim so existing call sites (and the local
// PaceZones interface) don't need to change in this migration.
import { legacyZonesFromSnapshot } from "./pace-engine.ts";

export function computePaceZones(snapshot: {
  predicted_marathon_seconds?: number;
  predicted_half_seconds?: number;
  predicted_10k_seconds?: number;
  predicted_5k_seconds?: number;
}): PaceZones | null {
  return legacyZonesFromSnapshot(snapshot);
}
