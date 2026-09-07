/**
 * Pace zone utilities — shared source of truth for converting
 * fitness_snapshots predictions into the six reference paces used by plan
 * generation (easy, marathon, half, 10K, 5K, mile), with confidence flags.
 *
 * Ported from adaptive-workout/index.ts computePaceZones, extended to:
 *   (a) include mile pace,
 *   (b) tag each pace with 'high' | 'medium' | 'low' confidence,
 *   (c) return a source date for provenance.
 *
 * Confidence rule:
 *   'high'   — pace came directly from a fitness_snapshots prediction.
 *   'medium' — cascaded from at least two sibling predictions.
 *   'low'    — cascaded from only one sibling prediction.
 */

import { equivalentRacePaceSecPerMile, RACE_DISTANCE_MI, type RaceKey } from "./paces.ts";

/** Convert a pace at one race distance to the equivalent pace at another via
 *  the canonical ratio table. 0/falsy in → 0 out (keeps the `||` cascades
 *  short-circuiting). Mirrors pace-engine.ts `paceEquiv`. */
function paceEquiv(fromPace: number, fromKey: RaceKey, toKey: RaceKey): number {
  if (!fromPace) return 0;
  return equivalentRacePaceSecPerMile(fromKey, fromPace * RACE_DISTANCE_MI[fromKey], toKey);
}

export type PaceConfidence = "high" | "medium" | "low";

export interface ResolvedPace {
  secondsPerMile: number;
  confidence: PaceConfidence;
  sourceDate: string; // ISO 8601
}

export interface ResolvedPaceProfile {
  easy: ResolvedPace | null;
  marathon: ResolvedPace | null;
  half: ResolvedPace | null;
  tenK: ResolvedPace | null;
  fiveK: ResolvedPace | null;
  mile: ResolvedPace | null;
}

export interface FitnessSnapshotInput {
  predicted_marathon_seconds?: number | null;
  predicted_half_seconds?: number | null;
  predicted_10k_seconds?: number | null;
  predicted_5k_seconds?: number | null;
  predicted_mile_seconds?: number | null;
  created_at?: string | null;
}

const MARATHON_MI = 26.2188;
const HALF_MI = 13.1094;
const TEN_K_MI = 6.2137;
const FIVE_K_MI = 3.1069;
const MILE_MI = 1.0;

export function computePaceProfile(
  snap: FitnessSnapshotInput
): ResolvedPaceProfile | null {
  const present = {
    marathon: !!snap.predicted_marathon_seconds,
    half: !!snap.predicted_half_seconds,
    tenK: !!snap.predicted_10k_seconds,
    fiveK: !!snap.predicted_5k_seconds,
    mile: !!snap.predicted_mile_seconds,
  };
  const directCount = Object.values(present).filter(Boolean).length;
  if (directCount === 0) return null;

  const cascadedConfidence: PaceConfidence = directCount >= 2 ? "medium" : "low";
  const sourceDate = snap.created_at ?? new Date().toISOString();

  const marathonPace = snap.predicted_marathon_seconds
    ? snap.predicted_marathon_seconds / MARATHON_MI : 0;
  const halfPace = snap.predicted_half_seconds
    ? snap.predicted_half_seconds / HALF_MI : 0;
  const tenKPace = snap.predicted_10k_seconds
    ? snap.predicted_10k_seconds / TEN_K_MI : 0;
  const fiveKPace = snap.predicted_5k_seconds
    ? snap.predicted_5k_seconds / FIVE_K_MI : 0;
  const milePace = snap.predicted_mile_seconds
    ? snap.predicted_mile_seconds / MILE_MI : 0;

  // Cascade fallbacks — conversions go through the canonical race-equivalence
  // ratio table (paceEquiv), not hardcoded multipliers. The old chain
  // (10K→MP ×1.15, 5K→MP ×1.22, …) ran ~5–7% off the ladder and fed that
  // error into every plan generated from a snapshot without a marathon anchor.
  const mp = marathonPace || paceEquiv(halfPace, "half", "marathon") || paceEquiv(tenKPace, "tenK", "marathon") || paceEquiv(fiveKPace, "fiveK", "marathon");
  const hm = halfPace || paceEquiv(marathonPace, "marathon", "half") || paceEquiv(tenKPace, "tenK", "half") || paceEquiv(fiveKPace, "fiveK", "half");
  const tk = tenKPace || paceEquiv(halfPace, "half", "tenK") || paceEquiv(fiveKPace, "fiveK", "tenK") || paceEquiv(mp, "marathon", "tenK");
  const fk = fiveKPace || paceEquiv(tenKPace, "tenK", "fiveK") || paceEquiv(halfPace, "half", "fiveK") || paceEquiv(mp, "marathon", "fiveK");
  const ml = milePace || paceEquiv(fiveKPace, "fiveK", "mile") || paceEquiv(tenKPace, "tenK", "mile") || paceEquiv(halfPace, "half", "mile") || paceEquiv(mp, "marathon", "mile");
  const easy = mp + 90; // +90 s/mi off marathon pace — canonical easy target

  const pack = (value: number, hadDirect: boolean): ResolvedPace => ({
    secondsPerMile: Math.round(value * 10) / 10,
    confidence: hadDirect ? "high" : cascadedConfidence,
    sourceDate,
  });

  return {
    easy: pack(easy, present.marathon),
    marathon: pack(mp, present.marathon),
    half: pack(hm, present.half),
    tenK: pack(tk, present.tenK),
    fiveK: pack(fk, present.fiveK),
    mile: pack(ml, present.mile),
  };
}
