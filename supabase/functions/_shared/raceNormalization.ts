// ============================================================================
// raceNormalization.ts — neutral-equivalent race times for anchor comparison.
//
// THE RULE THIS IMPLEMENTS (CURRENT-FITNESS-APPLY.md §1.3): rung-1 evidence is
// compared only after conditions normalization. A raw race time is
// course + weather + fitness, and only the last part is capacity.
//
// THE CASE THAT FORCED IT (2026-08-15). The athlete's Apr Cap10K (33:02)
// read as 102s of detraining against the Feb anchor (31:20) — until the
// conditions were measured: 69°F / 68°F dew / 98% humidity + ~100m of climb,
// against February's 47°F / 36°F dew and a flat course. Normalized, most of
// the gap is weather and hills, not fitness.
//
// ONE OPINION PER PHYSICAL EFFECT — this module owns NO model of its own:
//   heat      → `pace-heat-adjustment.heatAdjustmentPct` (dew-point chart).
//               Races are continuous, at/above threshold intensity → the full
//               adjustment applies (no rep-length or intensity discount).
//   elevation → effortModel's grade constants (GRADE_K_UP / GRADE_K_DOWN,
//               re-exported here to keep the dependency one-way). Loop-course
//               approximation: gain ≈ loss, half the distance climbing at the
//               mean grade, half descending — up costs more than down returns,
//               so net cost = (K_UP − K_DOWN) · grade / 2. DELIBERATELY
//               CONSERVATIVE: a net-elevation model cannot see a rolling
//               profile, and under-crediting hills beats inventing fitness.
//
// WHAT NORMALIZATION IS FOR — and the one thing it must never do:
//   • COMPARE anchors (most-recent-wins runs on normalized times).
//   • EXPLAIN a slow race honestly ("worth ~31:50 in neutral conditions").
//   • It must NEVER mint a PR. `race_prs` stays raw actual times — an athlete
//     did not run 31:50, and a product that says she did is lying politely.
//
// ⚠️ PARITY (hard constraint). Anchor selection is implemented twice by
// design — `fitnessPrediction.ts` here and `FitnessPredictorService.swift`
// on iOS — and the two must never diverge. This module is therefore NOT yet
// wired into `scoredRaces`: it ships pure with tests, and the wiring lands on
// BOTH platforms in one change (see RACE-CONFIRM-ONBOARDING-APPLY.md §4).
//
// Pure functions, no I/O. Tests: raceNormalization.test.ts — the Cap10K is
// the fixture, with its real measured conditions.
// ============================================================================

import { heatAdjustmentPct } from "./pace-heat-adjustment.ts";
import { GRADE_K_DOWN, GRADE_K_UP, GRADE_MAX_PCT } from "./effortModel.ts";
import { RACE_DISTANCE_MI, type RaceKey } from "./paces.ts";

const METERS_PER_MILE = 1609.344;

// ── Inputs ───────────────────────────────────────────────────────────────

export interface RaceConditions {
  /** Race-hour weather. Null/undefined fields mean "not on file" — that part
   *  of the adjustment is skipped and reported as missing, never guessed. */
  tempF?: number | null;
  dewPointF?: number | null;
  /** Total elevation GAIN over the race, meters (loss assumed ≈ gain). */
  elevationGainM?: number | null;
}

export interface NormalizedRace {
  /** The actual recorded time — always carried, never overwritten. */
  rawSeconds: number;
  /** Neutral-equivalent seconds: raw minus the conditions cost. */
  neutralSeconds: number;
  /** Breakdown, so any surface can say WHY — seconds attributed to each. */
  heatCostSeconds: number;
  elevationCostSeconds: number;
  /** Adjustment fractions actually applied (0 when a term was skipped). */
  heatFraction: number;
  elevationFraction: number;
  /** Which inputs were absent — the honest-coverage note. */
  missing: string[];
}

// ── The model ────────────────────────────────────────────────────────────

/**
 * Net time fraction for a loop/out-and-back course with `gainM` of climb over
 * `distanceM`. Half the distance climbs at mean grade g, half descends at −g;
 * uphill slows by K_UP·g, downhill returns only K_DOWN·g (effortModel's
 * asymmetry), so the net fraction is (K_UP − K_DOWN)·g/2. Grade is capped at
 * effortModel's GRADE_MAX_PCT like every other grade read in the codebase.
 */
export function elevationCostFraction(
  gainM: number,
  distanceM: number,
): number {
  if (!(gainM > 0) || !(distanceM > 0)) return 0;
  const meanGradePct = Math.min(
    GRADE_MAX_PCT,
    (gainM / (distanceM / 2)) * 100,
  );
  return ((GRADE_K_UP - GRADE_K_DOWN) * meanGradePct) / 2;
}

/**
 * Neutral-equivalent time for one race. Missing conditions skip their term —
 * `neutralSeconds` equals `rawSeconds` when nothing is on file, and `missing`
 * says so. Never throws, never guesses.
 */
export function normalizeRaceTime(
  rawSeconds: number,
  distanceKey: RaceKey,
  conditions: RaceConditions | null | undefined,
): NormalizedRace {
  const missing: string[] = [];
  const distanceM = (RACE_DISTANCE_MI[distanceKey] ?? 0) * METERS_PER_MILE;

  let heatFraction = 0;
  if (
    conditions?.tempF != null && conditions?.dewPointF != null &&
    isFinite(conditions.tempF) && isFinite(conditions.dewPointF)
  ) {
    // Full adjustment: a race is one continuous at-intensity effort, the case
    // the dew-point chart was built for. (The rep-length and intensity
    // discounts exist for short/easy TRAINING segments — see
    // pace-heat-adjustment.ts — and do not apply here.)
    heatFraction = Math.max(0, heatAdjustmentPct(conditions.tempF, conditions.dewPointF));
  } else {
    missing.push("race-hour weather");
  }

  let elevationFraction = 0;
  if (conditions?.elevationGainM != null && isFinite(conditions.elevationGainM)) {
    elevationFraction = distanceM > 0
      ? elevationCostFraction(conditions.elevationGainM, distanceM)
      : 0;
  } else {
    missing.push("course elevation");
  }

  const heatCostSeconds = Math.round(rawSeconds * heatFraction);
  const elevationCostSeconds = Math.round(rawSeconds * elevationFraction);

  return {
    rawSeconds,
    neutralSeconds: rawSeconds - heatCostSeconds - elevationCostSeconds,
    heatCostSeconds,
    elevationCostSeconds,
    heatFraction,
    elevationFraction,
    missing,
  };
}

