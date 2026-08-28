// ============================================================================
// floatLegs.ts — telling a FLOAT apart from a RECOVERY.
//
// WHY THIS EXISTS. The parser gives every non-work leg the role `recovery`, so
// a 6:39/mi float inside an alternation is filed next to a 30:00/mi standing
// jog. Both then get excluded from the session's work volume and from its pace.
// That is wrong in a specific and expensive way: in an alternation BOTH SIDES
// ARE AEROBIC SUPPORT, and the session's real number is the aggregate pace over
// the whole continuous span — not the pace of the fast legs alone.
//
// Measured on this athlete's own logs (2026-05-15 → 2026-08-28, 113 recovery
// legs), the two populations do not overlap:
//
//   floats     6:22 – 7:45/mi   (62–88% of MP speed)   21 legs, 5.5 mi
//   ...gap     nothing between 9:04 and 9:25...
//   recoveries 9:25 – 38:00/mi  (15–60% of MP speed)   92 legs, 6.7 mi
//
// So the cut is not a guess — it sits in an empty band. The threshold is
// expressed as a fraction of MP *speed* (the convention in paces.ts and the
// CLAUDE.md zone table), which makes it athlete-relative: a 5:38 marathoner and
// a 10:00 marathoner get proportionate lines, not the same clock number.
//
// Three real sessions change character under this read:
//   21 Jul  6.00 fast + 1.28 float =  7.28 continuous @ 5:40 (fast legs 5:27)
//    1 Aug 12.00 fast + 1.69 float = 13.69 continuous @ 6:21 (fast legs 6:13)
//    4 Aug  5.69 fast + 2.02 float =  7.71 continuous @ 5:59 (fast legs 5:39)
//
// NOT a re-parse. This reads `parsed_structure.blocks` that already exist — no
// model call, no migration, and it never writes. A user correction
// (`edited_by_user`) is upstream of this and is unaffected.
//
// Pure and dependency-free so it is unit-testable. No I/O.
// ============================================================================

/**
 * A leg faster than this fraction of MP *speed* is aerobic support (a float),
 * not rest. 0.60 of MP speed is MP pace / 0.60 — 9:23/mi for a 5:38 marathoner.
 *
 * Chosen by the coach and checked against the corpus above: it lands inside the
 * 9:04–9:25 gap rather than cutting through either population.
 */
export const FLOAT_MIN_FRACTION_OF_MP_SPEED = 0.60;

/**
 * A single leg above the line does not make a float session.
 *
 * Two interval sessions (15 May, 14 Jul) each have exactly ONE jog at 8:59 /
 * 9:04 — 63% and 62% of MP speed — while every other recovery in them is a
 * true 9:00–30:00 jog. Those are slow jogs that happen to graze the line, and
 * calling them floats would relabel two ordinary interval sessions as
 * alternations. Requiring most of a session's legs to clear the line removes
 * both without moving the threshold.
 */
export const FLOAT_SESSION_MIN_SHARE = 0.5;

/** Paces outside this range are parser noise (seen: "0", "2:06" on a 0.04mi blip). */
const MIN_PLAUSIBLE_PACE_SEC = 240;
const MAX_PLAUSIBLE_PACE_SEC = 2400;

export type LegKind = "work" | "float" | "recovery" | "other";

export interface BlockInput {
  role?: string | null;
  distance_miles?: number | string | null;
  duration_s?: number | string | null;
  avg_pace_per_mile?: string | null;
  recovery_style?: string | null;
}

export interface ClassifiedLeg {
  kind: LegKind;
  miles: number;
  seconds: number;
  paceSec: number | null;
  /** True when this leg was stored as `recovery` but reads as aerobic support. */
  reclassified: boolean;
}

export interface FloatRead {
  legs: ClassifiedLeg[];
  /** Most recovery legs clear the line — the session is fast/float, not rep/rest. */
  isFloatSession: boolean;
  fastMiles: number;
  floatMiles: number;
  recoveryMiles: number;
  /** fast + float. The span actually run without stopping to jog. */
  continuousMiles: number;
  fastPaceSec: number | null;
  floatPaceSec: number | null;
  /** Over `continuousMiles` — the number to quote for the session. */
  aggregatePaceSec: number | null;
  /** Fast legs. A 20k alternation is 10 cycles, not 20 reps. */
  cycles: number;
}

/** "5:26" → 326. Returns null for "—", "", nulls and implausible values. */
export function paceStringToSeconds(raw: string | null | undefined): number | null {
  if (typeof raw !== "string") return null;
  const m = raw.trim().match(/^(\d{1,3}):(\d{2})$/);
  if (!m) return null;
  const sec = Number(m[1]) * 60 + Number(m[2]);
  if (!Number.isFinite(sec)) return null;
  if (sec < MIN_PLAUSIBLE_PACE_SEC || sec > MAX_PLAUSIBLE_PACE_SEC) return null;
  return sec;
}

/** The slowest pace that still counts as aerobic support, for this athlete. */
export function floatPaceCeiling(mpSecPerMile: number): number {
  return mpSecPerMile / FLOAT_MIN_FRACTION_OF_MP_SPEED;
}

function num(v: number | string | null | undefined): number {
  const n = typeof v === "string" ? Number(v) : v;
  return typeof n === "number" && Number.isFinite(n) && n > 0 ? n : 0;
}

/**
 * Classify a session's blocks against the athlete's own marathon pace.
 *
 * `mpSecPerMile` should be the athlete's CURRENT marathon pace
 * (`athlete_pace_profiles.marathon_pace_seconds`), not their goal pace: a float
 * is a function of the aerobic engine they have today. With no profile there is
 * no line to draw, so every leg keeps the role the parser gave it.
 */
export function readFloatLegs(
  blocks: BlockInput[] | null | undefined,
  mpSecPerMile: number | null | undefined,
): FloatRead {
  const empty: FloatRead = {
    legs: [], isFloatSession: false,
    fastMiles: 0, floatMiles: 0, recoveryMiles: 0, continuousMiles: 0,
    fastPaceSec: null, floatPaceSec: null, aggregatePaceSec: null, cycles: 0,
  };
  if (!Array.isArray(blocks) || blocks.length === 0) return empty;

  const hasAnchor = typeof mpSecPerMile === "number" && Number.isFinite(mpSecPerMile) &&
    mpSecPerMile > 0;
  const ceiling = hasAnchor ? floatPaceCeiling(mpSecPerMile as number) : null;

  // Pass 1 — which recovery legs COULD be floats.
  const eligible = blocks.map((b) => {
    if (b?.role !== "recovery" || ceiling == null) return false;
    // A standing rest is rest whatever the pace field says.
    if (b.recovery_style === "standing") return false;
    const p = paceStringToSeconds(b.avg_pace_per_mile);
    return p != null && p <= ceiling;
  });

  // Pass 2 — the session rule. One straggler does not make an alternation.
  const recoveryCount = blocks.filter((b) => b?.role === "recovery").length;
  const eligibleCount = eligible.filter(Boolean).length;
  const isFloatSession = recoveryCount > 0 &&
    eligibleCount / recoveryCount >= FLOAT_SESSION_MIN_SHARE;

  const legs: ClassifiedLeg[] = blocks.map((b, i) => {
    const miles = num(b?.distance_miles);
    const seconds = num(b?.duration_s);
    const paceSec = paceStringToSeconds(b?.avg_pace_per_mile);
    let kind: LegKind = "other";
    let reclassified = false;
    if (b?.role === "work_rep") kind = "work";
    else if (b?.role === "recovery") {
      if (isFloatSession && eligible[i]) { kind = "float"; reclassified = true; }
      else kind = "recovery";
    }
    return { kind, miles, seconds, paceSec, reclassified };
  });

  const sum = (k: LegKind, f: (l: ClassifiedLeg) => number) =>
    legs.filter((l) => l.kind === k).reduce((a, l) => a + f(l), 0);

  const fastMiles = sum("work", (l) => l.miles);
  const floatMiles = sum("float", (l) => l.miles);
  const recoveryMiles = sum("recovery", (l) => l.miles);
  const fastSec = sum("work", (l) => l.seconds);
  const floatSec = sum("float", (l) => l.seconds);
  const continuousMiles = fastMiles + floatMiles;

  const pace = (mi: number, sec: number) => (mi > 0 && sec > 0 ? sec / mi : null);

  return {
    legs,
    isFloatSession,
    fastMiles: round2(fastMiles),
    floatMiles: round2(floatMiles),
    recoveryMiles: round2(recoveryMiles),
    continuousMiles: round2(continuousMiles),
    fastPaceSec: pace(fastMiles, fastSec),
    floatPaceSec: pace(floatMiles, floatSec),
    aggregatePaceSec: pace(continuousMiles, fastSec + floatSec),
    cycles: legs.filter((l) => l.kind === "work").length,
  };
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
