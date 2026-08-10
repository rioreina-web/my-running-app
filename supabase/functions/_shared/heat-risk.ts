// ============================================================================
// heat-risk.ts — how RISKY the day is, as distinct from how much SLOWER it is.
//
// WHY THIS IS A SEPARATE MODEL
// ----------------------------
// `pace-heat-adjustment.ts` is a dew-point PACE model, built from the "Dew
// Point Calculator Emy" chart. It answers "how much slower for the same
// effort", and on that axis it is sound: humidity really does dominate at
// comparable temperatures, because evaporative cooling is what fails first.
//
// It was never built to answer "is this dangerous", and it cannot. Its
// composite is `temp + dew × multiplier`, which weights a degree of air
// temperature the same as a degree of dew point and carries no radiant term at
// all. The consequence, measured:
//
//   100°F / 30°F dew  →  composite 130.3  →  "hot",  1.22%  (+5 sec/mi)
//
// A hundred degrees, and the chart says run five seconds slower. Worse, at a
// 30°F dew point the composite can never reach "dangerous" (170) — it would
// need 140°F air. Dry heat is arithmetically incapable of tripping the top
// band. And the existing out-of-domain guard (`isBeyondChart`, composite > 185)
// is keyed on that same composite, so the case most outside the model's domain
// is exactly the case that never trips it.
//
// WHAT THIS MODULE USES INSTEAD
// -----------------------------
// WBGT (Wet Bulb Globe Temperature) — the index World Athletics, World
// Triathlon, the UCI and the ACSM actually use to decide whether a race runs.
// It carries the radiant and dry-bulb terms the Emy chart lacks.
//
// Both halves are sourced, not invented — the same standard the Emy table is
// held to:
//   • Formula: the Australian Bureau of Meteorology approximation,
//     WBGT = 0.567·Ta + 0.393·e + 3.94   (Ta in °C, vapour pressure e in hPa)
//     https://www.bom.gov.au/info/thermal_stress/
//   • Flags: the World Athletics / ACSM colour system —
//     black (cancel or recommend withdrawal) above 82°F / 28°C,
//     red (participants at increased risk) 73–82°F / 23–28°C.
//
// KNOWN BIAS, STATED
// ------------------
// The BoM approximation assumes moderately high solar radiation and light
// wind. It reads HIGH in cloud or wind. For an athlete running in the sun that
// bias points the safe way, but this is a MODEL, not a measurement — same
// posture as the grade model in `effortModel.ts`. Label it as such wherever it
// surfaces; never present a WBGT as an observed value.
//
// WHAT THIS MODULE WILL NOT DO
// ----------------------------
// It does not diagnose, and it does not tell anyone to stop training — the
// flags are reported with their published meaning and the call stays with the
// human (CLAUDE.md hard rule #2). It also does not touch the pace percentage:
// the Emy chart still owns "how much slower", because inventing a dry-heat
// coefficient we have no calibration for is exactly the fabrication the
// no-hallucination principle forbids.
//
// Pure functions, no I/O. See heat-risk.test.ts.
// ============================================================================

import { heatCategory, type HeatCategory } from "./pace-heat-adjustment.ts";

const f2c = (f: number): number => ((f - 32) * 5) / 9;
const c2f = (c: number): number => (c * 9) / 5 + 32;

/** Saturation vapour pressure (hPa) at a given temperature, Magnus formula.
 *  Evaluated at the DEW POINT it gives the actual vapour pressure directly —
 *  no relative-humidity round trip, and we already store dew point. */
export function vapourPressureHPa(dewPointF: number): number {
  const d = f2c(dewPointF);
  return 6.105 * Math.exp((17.27 * d) / (237.7 + d));
}

/**
 * WBGT in °F from air temperature and dew point (BoM approximation).
 *
 * Assumes moderate solar load and light wind — see the header. Returns null on
 * unusable input rather than a guessed number.
 */
export function wbgtF(tempF: number, dewPointF: number): number | null {
  if (!isFinite(tempF) || !isFinite(dewPointF)) return null;
  // Dew point above air temperature is unphysical (bad sensor / bad join).
  if (dewPointF > tempF + 1) return null;
  const wbgtC = 0.567 * f2c(tempF) + 0.393 * vapourPressureHPa(dewPointF) + 3.94;
  return c2f(wbgtC);
}

// ── Flags ────────────────────────────────────────────────────────────────
//
// World Athletics / ACSM colour system, in °F (the °C originals are the
// authority; these are the published Fahrenheit equivalents).

export const WBGT_AMBER_F = 65; // 18.3°C
export const WBGT_RED_F = 73; // 23°C
export const WBGT_BLACK_F = 82; // 28°C

export type HeatRiskFlag = "green" | "amber" | "red" | "black";

export function heatRiskFlag(wbgtFahrenheit: number): HeatRiskFlag {
  if (wbgtFahrenheit > WBGT_BLACK_F) return "black";
  if (wbgtFahrenheit >= WBGT_RED_F) return "red";
  if (wbgtFahrenheit >= WBGT_AMBER_F) return "amber";
  return "green";
}

/** The published meaning of each flag. Reported, never turned into an
 *  instruction — the decision stays with the athlete or coach. */
export function heatRiskMeaning(flag: HeatRiskFlag): string {
  switch (flag) {
    case "black":
      return "Above the level at which race organisers are advised to cancel or offer withdrawal";
    case "red":
      return "Participants at increased risk of heat illness";
    case "amber":
      return "Heat is a factor; increased risk for the heat-sensitive";
    case "green":
      return "Heat is not a limiting factor";
  }
}

// ── Reconciling the two models ───────────────────────────────────────────

export interface HeatRisk {
  wbgtF: number | null;
  flag: HeatRiskFlag | null;
  meaning: string | null;
  /** The dew-point chart's own label, before any escalation. */
  paceModelCategory: HeatCategory;
  /** What to display: `paceModelCategory` raised to at least the floor the
   *  risk flag implies. */
  category: HeatCategory;
  /**
   * TRUE when the two models disagree materially — the risk flag is red or
   * black while the dew-point composite still reads mild. This is the dry-heat
   * signature (100°F/30°F dew: composite says "hot", WBGT says red), and it is
   * the honest signal that the PACE percentage is an extrapolation here rather
   * than a reading. Surfaces should stop quoting the number as precise.
   */
  paceModelUnderReads: boolean;
}

const SEVERITY: Record<HeatCategory, number> = {
  ideal: 0,
  warm: 1,
  hot: 2,
  very_hot: 3,
  dangerous: 4,
};

/** Category floor implied by each flag. Red means the day is at least very
 *  hot no matter what the dew-point composite says; black means dangerous. */
function floorForFlag(flag: HeatRiskFlag): HeatCategory {
  switch (flag) {
    case "black": return "dangerous";
    case "red": return "very_hot";
    default: return "ideal"; // no floor
  }
}

const worse = (a: HeatCategory, b: HeatCategory): HeatCategory =>
  SEVERITY[a] >= SEVERITY[b] ? a : b;

/**
 * The full risk read for a set of conditions. `compositeScore` is the
 * dew-point chart's own score (from `pace-heat-adjustment.compositeScore`), so
 * the two models are reconciled in one place rather than at every call site.
 *
 * Degrades to a bare pace-model category when WBGT can't be computed — never a
 * guessed flag.
 */
export function assessHeatRisk(
  compositeScore: number,
  tempF: number | null | undefined,
  dewPointF: number | null | undefined,
): HeatRisk {
  const paceModelCategory = heatCategory(compositeScore);

  const w = tempF != null && dewPointF != null ? wbgtF(tempF, dewPointF) : null;
  if (w == null) {
    return {
      wbgtF: null,
      flag: null,
      meaning: null,
      paceModelCategory,
      category: paceModelCategory,
      paceModelUnderReads: false,
    };
  }

  const flag = heatRiskFlag(w);
  const category = worse(paceModelCategory, floorForFlag(flag));
  // Compare against the RAW pace-model category, before the floor closes the
  // gap — otherwise the escalation would mask the very disagreement it exists
  // to report.
  const severeFlag = flag === "red" || flag === "black";
  const mildPaceRead = SEVERITY[paceModelCategory] < SEVERITY["very_hot"];

  return {
    wbgtF: Math.round(w * 10) / 10,
    flag,
    meaning: heatRiskMeaning(flag),
    paceModelCategory,
    category,
    paceModelUnderReads: severeFlag && mildPaceRead,
  };
}

/** Fact lines for a prompt or a UI panel. Reports the flag and its published
 *  meaning; states plainly when the pace number is an extrapolation. No
 *  instruction, no diagnosis. */
export function describeHeatRisk(r: HeatRisk): string[] {
  if (r.wbgtF == null || r.flag == null) return [];
  const lines = [
    `Heat risk: ${r.flag.toUpperCase()} flag (WBGT ${r.wbgtF}F, modelled from ` +
    `temperature + dew point). ${r.meaning}.`,
  ];
  if (r.paceModelUnderReads) {
    lines.push(
      `The dew-point pace model reads this as "${r.paceModelCategory}" — it ` +
      `carries no radiant-heat term, so on a hot dry day its pace adjustment ` +
      `is an extrapolation, not a measurement.`,
    );
  }
  return lines;
}
