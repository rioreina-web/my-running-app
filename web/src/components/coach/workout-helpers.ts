// Pure types and helpers for workout templates.
// This file deliberately has no "use client" directive so it can be imported
// by BOTH server components (the workout library card) and client components
// (the step editor and form). React Server Components can't call functions
// imported from "use client" modules, so the pure logic has to live here.

import { RACE_DISTANCE_CONSTANTS } from "@/lib/race-constants";

// ── Pace zones (matches iOS NamedPace enum) ──────────────

export type PaceZone =
  | "recovery"
  | "easy"
  | "longRun"
  | "moderate"
  | "steady"
  | "mp"
  | "hm"
  | "threshold"
  | "tenK"
  | "fiveK"
  | "threeK"
  | "mile";

export interface PaceZoneOption {
  value: PaceZone;
  shortName: string;
  displayName: string;
  description: string;
}

// ── Pace-zone colors (web mirror of PaceSpectrum.swift) ──
//
// THE THREE-PALETTE RULE: blue = pace, warm = mood, coral = alert. These
// map each pace zone to a stop on the single-hue blue depth ramp, defined
// as CSS custom properties in web/src/app/globals.css (`--color-pace-*`).
// Source of truth for the hex values: RunningLog/Workouts/PaceSpectrum.swift.
//
// Two zones share a stop by design: `longRun` reads as `moderate` (its band
// overlaps moderate) and `recovery` reads as `easy` (the palest sky — there
// is no dedicated recovery stop, and recovery miles sit at the base of the
// ramp alongside easy). This matches the prototype's ZONES color mapping in
// prototypes/adaptive-plan-builder.html. Never emit a green or coral fill
// here — those palettes are mood and alert only.
export const PACE_ZONE_COLORS: Record<PaceZone, string> = {
  recovery:  "var(--color-pace-easy)",
  easy:      "var(--color-pace-easy)",
  longRun:   "var(--color-pace-moderate)",
  moderate:  "var(--color-pace-moderate)",
  steady:    "var(--color-pace-steady)",
  mp:        "var(--color-pace-mp)",
  hm:        "var(--color-pace-hmp)",
  threshold: "var(--color-pace-lt)",
  tenK:      "var(--color-pace-10k)",
  fiveK:     "var(--color-pace-5k)",
  threeK:    "var(--color-pace-3k)",
  mile:      "var(--color-pace-mile)",
};

// `longRun` is intentionally NOT in this list (May 2026): the LR band
// (85–75% MP) overlaps Moderate and Easy, and coaches found it confusing
// to prescribe. The four core aerobic zones (Steady/Moderate/Easy/Recovery)
// now tile the spectrum without gaps. `longRun` remains in the PaceZone
// type and REFERENCE_PACE_SEC_PER_MILE for back-compat with already-stored
// data; workout-template-form migrates such steps to `easy` on load.
export const PACE_ZONES: PaceZoneOption[] = [
  { value: "recovery",  shortName: "Rec",       displayName: "Recovery",          description: "Very easy, fully conversational" },
  { value: "easy",      shortName: "Easy",      displayName: "Easy",              description: "Aerobic, conversational" },
  { value: "moderate",  shortName: "Mod",       displayName: "Moderate",          description: "Steady but working" },
  { value: "steady",    shortName: "Steady",    displayName: "Steady",            description: "Comfortably hard" },
  { value: "mp",        shortName: "MP",        displayName: "Marathon Pace",     description: "Goal marathon pace" },
  { value: "hm",        shortName: "HM",        displayName: "Half Marathon Pace", description: "Goal half marathon pace" },
  { value: "threshold", shortName: "LT",        displayName: "Threshold",         description: "Lactate threshold, ~1hr race effort" },
  { value: "tenK",      shortName: "10K",       displayName: "10K Pace",          description: "VO2-adjacent" },
  { value: "fiveK",     shortName: "5K",        displayName: "5K Pace",           description: "VO2 max work" },
  { value: "threeK",    shortName: "3K",        displayName: "3K Pace",           description: "Above VO2" },
  { value: "mile",      shortName: "Mile",      displayName: "Mile Pace",         description: "Neuromuscular" },
];

// ── WorkoutStep type ─────────────────────────────────────

// Optional fine-tuning of a base pace zone. A step can be off the base zone
// by EITHER a percentage (multiplicative) OR a seconds-per-distance delta
// (additive). Never both. Positive = slower than base; negative = faster.
//
// Convention examples:
//   { type: "seconds_per_mile", value:  10 }  →  base + 10s/mi   (slower)
//   { type: "seconds_per_mile", value: -10 }  →  base − 10s/mi   (faster)
//   { type: "seconds_per_km",   value:  10 }  →  base + 10s/km   (slower)
//   { type: "percent",          value:  +2 }  →  base × 1.02     (slower)
//   { type: "percent",          value:  -3 }  →  base × 0.97     (faster)
export type PaceAdjustmentType = "percent" | "seconds_per_mile" | "seconds_per_km";

export interface PaceAdjustment {
  type: PaceAdjustmentType;
  value: number;
}

export interface WorkoutStep {
  id: string;
  stepType: "warmup" | "active" | "recovery" | "rest" | "cooldown";
  durationType: "distance_miles" | "distance_km" | "distance_meters" | "time_seconds";
  durationValue: number;
  paceZone: PaceZone;
  paceAdjustment?: PaceAdjustment;
  // When set, overrides paceZone/paceAdjustment with a coach-prescribed exact
  // pace (e.g. "5:45/mi"). Lets a coach pin a specific number rather than
  // deriving it from MP/LT/etc. for this athlete.
  exactPaceSecPerMile?: number;
  notes: string;
  // Repeats > 1 → this step is an interval set (e.g., "6 × 800m"). Recovery
  // describes what happens between reps.
  repeats?: number;
  recovery?: {
    durationType: "distance_miles" | "distance_km" | "distance_meters" | "time_seconds";
    durationValue: number;
    /// Optional. When undefined, the recovery is "standing rest" — the
    /// athlete stops between reps rather than jogging. When set, the
    /// recovery is run at this pace zone (optionally adjusted). Matches
    /// the iOS `PlannedWorkoutRecovery.paceZone: NamedPace?` shape.
    paceZone?: PaceZone;
    paceAdjustment?: PaceAdjustment;
    exactPaceSecPerMile?: number;
  };
}

// ── Distance helpers ─────────────────────────────────────

export function stepDistanceMiles(s: {
  durationType: WorkoutStep["durationType"];
  durationValue: number;
}): number {
  if (s.durationType === "distance_miles")  return s.durationValue;
  if (s.durationType === "distance_km")     return s.durationValue / RACE_DISTANCE_CONSTANTS.kmPerMile;
  if (s.durationType === "distance_meters") return s.durationValue / RACE_DISTANCE_CONSTANTS.meterPerMile;
  return 0; // time-based steps don't count toward distance
}

export function totalStepMiles(step: WorkoutStep): number {
  const reps = step.repeats && step.repeats > 1 ? step.repeats : 1;
  const activeMiles   = stepDistanceMiles(step) * reps;
  const recoveryMiles = step.recovery ? stepDistanceMiles(step.recovery) * reps : 0;
  return activeMiles + recoveryMiles;
}

export function totalWorkoutMiles(steps: WorkoutStep[]): number {
  return steps.reduce((sum, s) => sum + totalStepMiles(s), 0);
}

// True when any segment of the workout is time-based — meaning the
// total-miles number is at least partly estimated from pace × time
// rather than literal distance. UI uses this to prefix totals with "~".
export function workoutHasTimeBasedSegment(steps: WorkoutStep[]): boolean {
  for (const s of steps) {
    if (s.durationType === "time_seconds") return true;
    if (s.recovery && s.recovery.durationType === "time_seconds") return true;
  }
  return false;
}

// Like `totalStepMiles`, but converts time-based segments to miles using
// the pace this step would run at (pace × time → distance). Used by the
// workout-totals chip and the persisted `estimated_distance_miles` so
// fartleks ("10 × 1 min @ 5K / 1 min easy") get a sensible mile estimate
// instead of 0.
//
// Pace resolution mirrors `stepSegmentDurationSeconds`:
//   exactPaceSecPerMile > paceZone+adjustment with athleteOverride > reference.
// Distance segments delegate to `stepDistanceMiles` so they remain exact.
function estimatedSegmentMiles(
  seg: {
    durationType: WorkoutStep["durationType"];
    durationValue: number;
    // Optional: a "standing rest" recovery has no paceZone. Time-based
    // standing-rest contributes 0 miles (you're not moving); distance-
    // based "rest" is treated as the literal distance regardless of pace.
    paceZone?: PaceZone;
    paceAdjustment?: PaceAdjustment;
    exactPaceSecPerMile?: number;
  },
  athletePaces?: AthletePaceTable,
): number {
  if (seg.durationType !== "time_seconds") {
    return stepDistanceMiles(seg);
  }
  // Time-based segment with no pace = standing rest = 0 miles covered.
  if (!seg.exactPaceSecPerMile && !seg.paceZone) return 0;
  const paceSec = seg.exactPaceSecPerMile
    ? seg.exactPaceSecPerMile
    : adjustedPaceSecPerMile(basePaceSecPerMile(seg.paceZone!, athletePaces), seg.paceAdjustment);
  if (paceSec <= 0) return 0;
  return seg.durationValue / paceSec;
}

export function estimatedStepMiles(step: WorkoutStep, athletePaces?: AthletePaceTable): number {
  const reps = step.repeats && step.repeats > 1 ? step.repeats : 1;
  const activeMiles = estimatedSegmentMiles(step, athletePaces) * reps;
  const recoveryMiles = step.recovery ? estimatedSegmentMiles(step.recovery, athletePaces) * reps : 0;
  return activeMiles + recoveryMiles;
}

export function estimatedWorkoutMiles(
  steps: WorkoutStep[],
  athletePaces?: AthletePaceTable,
): number {
  return steps.reduce((sum, s) => sum + estimatedStepMiles(s, athletePaces), 0);
}

// ── Zone-mile aggregation (for the pace-colored mileage ramp) ────────────
//
// Buckets a week's placed workout miles by pace zone, so the Plan-setup
// ramp can render each week as a stacked bar (easy fill at the base,
// deeper-blue quality miles stacked on top). Ported from the prototype's
// `weekZoneMiles` / `nearestZoneKey` (prototypes/adaptive-plan-builder.html);
// the prototype is the design reference when it disagrees with this code.

/** Miles-per-zone for one or more workouts. A partial map — a zone with no
 *  placed miles is simply absent. */
export type ZoneMiles = Partial<Record<PaceZone, number>>;

/**
 * The pace zone whose reference (or athlete) pace is closest to a given
 * exact seconds-per-mile pace. Used to color a step that pins an absolute
 * pace ("5:45/mi") instead of naming a zone. Mirrors the prototype's
 * `nearestZoneKey`.
 */
export function nearestZoneKey(
  paceSecPerMile: number,
  athletePaces?: AthletePaceTable,
): PaceZone {
  let best: PaceZone = "fiveK";
  let bestDelta = Infinity;
  for (const opt of PACE_ZONES) {
    const zoneSec = athletePaces?.[opt.value] ?? REFERENCE_PACE_SEC_PER_MILE[opt.value];
    const delta = Math.abs(zoneSec - paceSecPerMile);
    if (delta < bestDelta) {
      bestDelta = delta;
      best = opt.value;
    }
  }
  return best;
}

/**
 * The pace zone a step reads as — for coloring, zone dots, and labels:
 *   - an exact pinned pace wins (mirrors how miles are computed:
 *     estimatedSegmentMiles prefers exactPaceSecPerMile), mapped to its
 *     nearest zone.
 *   - `longRun` is preserved (its own structural zone) — callers that need
 *     a ramp color fold it into `moderate` themselves.
 *   - a named, resolvable zone is used as-is.
 *   - anything unresolvable falls to `easy` (the aerobic base).
 */
export function zoneForStep(step: WorkoutStep, athletePaces?: AthletePaceTable): PaceZone {
  if (step.exactPaceSecPerMile && step.exactPaceSecPerMile > 0) {
    return nearestZoneKey(step.exactPaceSecPerMile, athletePaces);
  }
  if (step.paceZone === "longRun") return "longRun";
  if (hasResolvableZone(step.paceZone)) return step.paceZone;
  return "easy";
}

/** A step's color on the single-hue blue pace ramp. `longRun` shares the
 *  `moderate` stop (no dedicated long-run blue). Never returns green/coral. */
export function zoneColorForStep(step: WorkoutStep, athletePaces?: AthletePaceTable): string {
  return PACE_ZONE_COLORS[zoneForStep(step, athletePaces)];
}

/**
 * Sum a week's placed workout miles into per-zone buckets. Each argument is
 * one workout's steps; a step's estimated miles (distance, or pace × time
 * for time-based segments) land wholesale in that step's zone — matching the
 * prototype, which counts a rep set's recovery jog as part of the quality
 * session rather than splitting it out.
 *
 * The caller adds the "easy fill" (a week's target mid-mileage minus the
 * placed total) when rendering, so this returns only what's actually placed.
 */
export function weekZoneMiles(
  stepGroups: WorkoutStep[][],
  athletePaces?: AthletePaceTable,
): ZoneMiles {
  const out: ZoneMiles = {};
  for (const steps of stepGroups) {
    for (const step of steps) {
      const miles = estimatedStepMiles(step, athletePaces);
      if (!miles || miles <= 0) continue;
      // Fold longRun into moderate for the ramp — it shares moderate's blue
      // stop and moderate is a stacking zone (longRun is not in PACE_ZONES).
      const z = zoneForStep(step, athletePaces);
      const zone: PaceZone = z === "longRun" ? "moderate" : z;
      out[zone] = (out[zone] ?? 0) + miles;
    }
  }
  return out;
}

/** Total placed miles across a ZoneMiles map. */
export function totalZoneMiles(zoneMiles: ZoneMiles): number {
  return Object.values(zoneMiles).reduce((sum, mi) => sum + (mi ?? 0), 0);
}

// ── 10-zone workout labels, dots & estimated line ───────────────────────
//
// The library and builder describe a workout by its pace zones, not the
// legacy workout_type ("tempo"/"intervals"). A tempo run is `LT 6 mi`; an
// interval set is `5K 5×1km`. Ported in intent from the prototype's
// `instZones` / `instSummary` (prototypes/workout-builder.html).

// Intensity rank (higher = harder). Slow → fast, with longRun sitting just
// above easy. Used to pick a workout's "headline" zone for its label.
const ZONE_INTENSITY_RANK: Record<PaceZone, number> = {
  recovery: 0,
  easy: 1,
  longRun: 2,
  moderate: 3,
  steady: 4,
  mp: 5,
  hm: 6,
  threshold: 7,
  tenK: 8,
  fiveK: 9,
  threeK: 10,
  mile: 11,
};

// Aerobic base zones — not counted as "quality" for zone-dot tags.
const BASE_ZONES = new Set<PaceZone>(["recovery", "easy", "longRun"]);

/** Short display label for a zone, with the structural `longRun` → "Long".
 *  Everything else uses the canonical short name ("MP", "LT", "5K", …). */
export function zoneLabelShort(zone: PaceZone): string {
  if (zone === "longRun") return "Long";
  return paceShort(zone);
}

function trimMiles(mi: number): string {
  return Number.isInteger(mi) ? `${mi}` : mi.toFixed(1);
}

// A step's distance as a compact bare label: "800m", "1km", "6 mi", or a
// clock for time-based reps ("2:00").
function stepDistLabel(seg: {
  durationType: WorkoutStep["durationType"];
  durationValue: number;
}): string {
  switch (seg.durationType) {
    case "distance_meters":
      return seg.durationValue % 1000 === 0
        ? `${seg.durationValue / 1000}km`
        : `${seg.durationValue}m`;
    case "distance_km":
      return `${trimMiles(seg.durationValue)}km`;
    case "distance_miles":
      return `${trimMiles(seg.durationValue)} mi`;
    case "time_seconds":
      return formatStepSeconds(seg.durationValue);
  }
}

// A step's pace shorthand for the estimated line: an exact pinned pace shows
// as "5:45/mi", otherwise the zone's short label.
function stepPaceShort(step: WorkoutStep, athletePaces?: AthletePaceTable): string {
  if (step.exactPaceSecPerMile && step.exactPaceSecPerMile > 0) {
    return `${formatPaceSecPerMile(step.exactPaceSecPerMile)}/mi`;
  }
  return zoneLabelShort(zoneForStep(step, athletePaces));
}

/**
 * Distinct quality zones present in a workout, in step order, excluding the
 * aerobic base (recovery/easy/longRun) and non-running steps. Drives the
 * zone-dot tags on library cards. Mirrors the prototype's `instZones`.
 */
export function stepZones(steps: WorkoutStep[], athletePaces?: AthletePaceTable): PaceZone[] {
  const out: PaceZone[] = [];
  for (const s of steps) {
    if (s.stepType !== "active") continue;
    const z = zoneForStep(s, athletePaces);
    if (BASE_ZONES.has(z)) continue;
    if (!out.includes(z)) out.push(z);
  }
  return out;
}

/**
 * A workout's 10-zone label, derived from its steps:
 *   - a rep set → "5K 5×1km", "3K 4×800m"
 *   - a single main block → "MP 7 mi", "LT 6 mi", "Long 16 mi"
 * The headline is the hardest active block (ties go to the rep set). Returns
 * null when there are no steps — callers fall back to the legacy type label.
 */
// The "headline" block of a workout — the hardest active block, with ties
// going to a rep set. Shared by workoutZoneLabel and headlineZone.
function headlineBlock(
  blocks: WorkoutStepBlock[],
  athletePaces?: AthletePaceTable,
): WorkoutStepBlock | null {
  let headline: WorkoutStepBlock | null = null;
  let headlineRank = -1;
  for (const b of blocks) {
    const rank = ZONE_INTENSITY_RANK[zoneForStep(b.step, athletePaces)];
    if (rank > headlineRank || (rank === headlineRank && b.kind === "reps")) {
      headlineRank = rank;
      headline = b;
    }
  }
  return headline;
}

/** The single zone that best characterizes a workout (its hardest block).
 *  Used for the library card's pace pill. Null when there are no steps. */
export function headlineZone(
  steps: WorkoutStep[],
  athletePaces?: AthletePaceTable,
): PaceZone | null {
  if (!steps || steps.length === 0) return null;
  const { blocks } = groupStepsIntoSections(steps);
  const headline = headlineBlock(blocks, athletePaces);
  return headline ? zoneForStep(headline.step, athletePaces) : null;
}

export function workoutZoneLabel(
  steps: WorkoutStep[],
  athletePaces?: AthletePaceTable,
): string | null {
  if (!steps || steps.length === 0) return null;
  const { blocks } = groupStepsIntoSections(steps);
  if (blocks.length === 0) return null;

  const headline = headlineBlock(blocks, athletePaces);
  if (!headline) return null;

  const short = stepPaceShort(headline.step, athletePaces);
  if (headline.kind === "reps") {
    const reps = headline.repeats ?? 2;
    return `${short} ${reps}×${stepDistLabel(headline.step)}`;
  }
  const miles = estimatedStepMiles(headline.step, athletePaces);
  return miles > 0 ? `${short} ${trimMiles(miles)} mi` : short;
}

/**
 * The mono "estimated" one-liner for a workout — "2 wu · 6 × 800m @ 5K · 2 cd".
 * Warmup/cooldown collapse to their mileage; each middle block reads as its
 * reps/distance @ zone. Mirrors the prototype's `instSummary`. Returns null
 * for an empty workout.
 */
export function describeWorkoutLine(
  steps: WorkoutStep[],
  athletePaces?: AthletePaceTable,
): string | null {
  if (!steps || steps.length === 0) return null;
  const { warmup, blocks, cooldown } = groupStepsIntoSections(steps);
  const parts: string[] = [];

  const wuMiles = estimatedWorkoutMiles(warmup, athletePaces);
  if (warmup.length > 0 && wuMiles > 0) parts.push(`${trimMiles(wuMiles)} wu`);

  for (const b of blocks) {
    const short = stepPaceShort(b.step, athletePaces);
    if (b.kind === "reps") {
      const reps = b.repeats ?? 2;
      parts.push(`${reps} × ${stepDistLabel(b.step)} @ ${short}`);
    } else {
      parts.push(`${stepDistLabel(b.step)} @ ${short}`);
    }
  }

  const cdMiles = estimatedWorkoutMiles(cooldown, athletePaces);
  if (cooldown.length > 0 && cdMiles > 0) parts.push(`${trimMiles(cdMiles)} cd`);

  return parts.length > 0 ? parts.join(" · ") : null;
}

// ── Duration helpers ─────────────────────────────────────

// Per-athlete pace table (seconds per mile, keyed by pace zone). When the
// athlete is known at estimate time — e.g., an assigned workout being viewed
// from a scheduled row — callers pass this so duration reflects their own
// fitness instead of the reference runner.
export type AthletePaceTable = Partial<Record<PaceZone, number>>;

// Reference paces (seconds per mile) for a moderately-trained runner. Used
// only as a fallback when no athlete pace table is available. Callers that
// rely on this should label the output as
// "est. for reference runner — personalized on save".
// Reference paces for a ~3:15 marathoner (MP 7:30). Derived from the same
// ladder as derivePaceTableFromGoal, so the editor's ranges stay self-consistent
// whether the coach set a goal time or not.
export const REFERENCE_PACE_SEC_PER_MILE: Record<PaceZone, number> = {
  recovery: 10 * 60 + 43, // MP / 0.70 (range: 75–65% MP speed)
  easy:      9 * 60 + 49, // MP / 0.765
  longRun:   9 * 60 + 23, // MP / 0.80
  moderate:  8 * 60 + 34, // MP / 0.875
  steady:    8 * 60 + 6, // MP / 0.925
  mp:        7 * 60 + 30, // anchor
  hm:        7 * 60 + 15, // MP − 15s
  threshold: 7 * 60 + 10, // MP − 20s
  tenK:      6 * 60 + 50, // MP − 40s
  fiveK:     6 * 60 + 30, // MP − 60s
  threeK:    6 * 60 + 10, // MP − 80s
  mile:      5 * 60 + 50, // MP − 100s
};

export const REFERENCE_RUNNER_LABEL = "est. for reference runner — personalized on save";

// Compute the effective seconds-per-mile for a step's pace zone, applying any
// adjustment. Used by the duration estimator. The same logic runs on the
// athlete side — just with their personal sec/mi for each zone.
export function adjustedPaceSecPerMile(
  basePaceSecPerMile: number,
  adjustment?: PaceAdjustment
): number {
  if (!adjustment || adjustment.value === 0) return basePaceSecPerMile;
  switch (adjustment.type) {
    case "percent":
      return basePaceSecPerMile * (1 + adjustment.value / 100);
    case "seconds_per_mile":
      return basePaceSecPerMile + adjustment.value;
    case "seconds_per_km":
      // Convert the per-km offset to a per-mile offset before adding.
      return basePaceSecPerMile + adjustment.value * RACE_DISTANCE_CONSTANTS.kmPerMile;
  }
}

function basePaceSecPerMile(zone: PaceZone, athletePaces?: AthletePaceTable): number {
  return athletePaces?.[zone] ?? REFERENCE_PACE_SEC_PER_MILE[zone] ?? REFERENCE_PACE_SEC_PER_MILE.easy;
}

function stepSegmentDurationSeconds(
  seg: {
    durationType: WorkoutStep["durationType"];
    durationValue: number;
    // Optional to support "standing rest" recoveries that have a
    // duration but no pace zone. For distance-based standing rest
    // (unusual but possible — "walk 100m"), we fall back to easy pace
    // so we don't produce zero duration estimates.
    paceZone?: PaceZone;
    paceAdjustment?: PaceAdjustment;
    exactPaceSecPerMile?: number;
  },
  athletePaces?: AthletePaceTable
): number {
  if (seg.durationType === "time_seconds") return seg.durationValue;
  const miles = stepDistanceMiles(seg);
  const paceSec = seg.exactPaceSecPerMile
    ? seg.exactPaceSecPerMile
    : adjustedPaceSecPerMile(basePaceSecPerMile(seg.paceZone ?? "easy", athletePaces), seg.paceAdjustment);
  return miles * paceSec;
}

export function totalStepDurationMinutes(step: WorkoutStep, athletePaces?: AthletePaceTable): number {
  const reps = step.repeats && step.repeats > 1 ? step.repeats : 1;
  const activeSec = stepSegmentDurationSeconds(step, athletePaces) * reps;
  const recoverySec = step.recovery ? stepSegmentDurationSeconds(step.recovery, athletePaces) * reps : 0;
  return (activeSec + recoverySec) / 60;
}

export function totalWorkoutDurationMinutes(
  steps: WorkoutStep[],
  athletePaces?: AthletePaceTable
): number {
  return steps.reduce((sum, s) => sum + totalStepDurationMinutes(s, athletePaces), 0);
}

// ── Display formatters ───────────────────────────────────

// Format a time-based duration (in seconds) for display in step rows.
//   < 60s          → "45s"
//   exactly N min  → "2 min"
//   otherwise      → "M:SS"  (e.g., 1:30, 2:45)
export function formatStepSeconds(totalSeconds: number): string {
  if (totalSeconds < 60) return `${Math.round(totalSeconds)}s`;
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = Math.round(totalSeconds - minutes * 60);
  if (seconds === 0) return `${minutes} min`;
  return `${minutes}:${seconds.toString().padStart(2, "0")}`;
}

// Format a single step's duration value for display. Time-based segments use
// the human-friendly formatter; distance segments append the unit suffix.
export function formatStepDuration(
  durationType: WorkoutStep["durationType"],
  durationValue: number
): string {
  if (durationType === "time_seconds") return formatStepSeconds(durationValue);
  return `${durationValue}${unitShort(durationType)}`;
}

export function unitShort(t: WorkoutStep["durationType"]): string {
  switch (t) {
    case "distance_miles":  return " mi";
    case "distance_km":     return " km";
    case "distance_meters": return " m";
    case "time_seconds":    return "s";
  }
}

export function paceShort(zone: PaceZone): string {
  return PACE_ZONES.find((p) => p.value === zone)?.shortName ?? zone;
}

// Format a pace zone with an optional adjustment. Examples:
//   ("mp", undefined)                                        → "MP"
//   ("hm", { type: "seconds_per_mile",  value:  10 })        → "HM +10s/mi"
//   ("hm", { type: "seconds_per_mile",  value: -10 })        → "HM −10s/mi"
//   ("mp", { type: "percent",           value:   2 })        → "MP +2%"
//   ("threshold", { type: "seconds_per_km", value: -5 })     → "LT −5s/km"
// Uses the Unicode minus sign (−, U+2212) for typographic correctness.
export function paceLabelWithAdjustment(
  zone: PaceZone,
  adjustment?: PaceAdjustment,
  exactPaceSecPerMile?: number,
): string {
  if (exactPaceSecPerMile && exactPaceSecPerMile > 0) {
    return `${formatPaceSecPerMile(exactPaceSecPerMile)}/mi`;
  }
  const base = paceShort(zone);
  if (!adjustment || adjustment.value === 0) return base;
  const sign = adjustment.value >= 0 ? "+" : "−";
  const magnitude = Math.abs(adjustment.value);
  switch (adjustment.type) {
    case "percent":
      return `${base} ${sign}${magnitude}%`;
    case "seconds_per_mile":
      return `${base} ${sign}${magnitude}s/mi`;
    case "seconds_per_km":
      return `${base} ${sign}${magnitude}s/km`;
  }
}

// Format a seconds/mile pace as "M:SS".
export function formatPaceSecPerMile(totalSeconds: number): string {
  const t = Math.max(0, Math.round(totalSeconds));
  const m = Math.floor(t / 60);
  const s = t % 60;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

// Derive a complete pace table from a goal race pace (seconds/mile for the
// race) and the race distance. MP is the anchor; other zones are offsets
// calibrated against Daniels' VDOT tables for a mid-range runner (~VDOT 45–55,
// 3:00–3:45 marathon). Offsets are approximations — faster runners should
// narrow them, slower runners widen them, which the per-zone override UI
// on the plan handles.
//
// Ladder (seconds per mile relative to marathon pace):
//   Mile     MP − 100   (short repeats / neuromuscular)
//   3K       MP −  80
//   5K       MP −  60   (Daniels "I" / 5K race pace)
//   10K      MP −  40
//   LT       MP −  20   (~1-hour race effort)
//   HM       MP −  15   (essentially LT; half marathon race pace)
//   MP        anchor
//   Steady   MP +  20   ("marathon-minus", race-pace-adjacent)
//   Moderate MP +  40
//   LR       MP +  60   (aerobic long-run pace)
//   Easy     MP +  90   (conversational)
//   Recovery MP + 150   (fully recovery effort)
//
// When the goal race isn't a marathon, collapse race pace → implied MP first
// using the reverse offset.
// ── Race-equivalence ratios (ported from iOS PaceCalculator.swift) ──────
//
// Race ratios, normalized to a 10K = 1.00 anchor. From any single race
// performance, multiplying by the target's ratio yields the equivalent
// time at that target distance. These are fitness-correct across the
// full VDOT range — unlike fixed pace offsets from MP, which overpredict
// short-distance speed at elite fitness and underprescribe recovery
// volume for slower runners.
//
// Keep these in sync with `RunningLog/RunningLog/Workouts/PaceCalculator.swift`.
const RACE_RATIOS_TO_10K = {
  mile:     0.139583,
  "1500m":  0.129167,
  threeK:   0.277083,
  fiveK:    0.481250,
  tenK:     1.000000,
  tenMi:    1.661000,
  half:     2.204167,
  marathon: 4.615625,
} as const;

type RaceKey = keyof typeof RACE_RATIOS_TO_10K;

// Race distance in miles — used to convert an equivalent race time into
// seconds per mile.
const RACE_DISTANCE_MI: Record<RaceKey, number> = {
  mile:     1.0,
  "1500m":  0.932056,  // 1500 m / 1.609344
  threeK:   1.864113,
  fiveK:    3.106856,
  tenK:     6.213712,
  tenMi:    10.0,
  half:     13.109375,
  marathon: 26.21875,
};

// Map the `derivePaceTableFromGoal` raceDistance string argument to the
// ratio-table key. Unknown values default to marathon (same as the old
// fallback behavior).
function raceKeyForInput(raceDistance: string): RaceKey {
  switch (raceDistance) {
    case "half_marathon": return "half";
    case "10k":           return "tenK";
    case "5k":            return "fiveK";
    case "mile":          return "mile";
    case "marathon":
    default:              return "marathon";
  }
}

// Given a known race performance (distance + pace), compute the equivalent
// race time at a different distance using the shared ratio table.
//
// Example: a 2:20 marathoner's equivalent 5K time →
//   equivalentRaceTimeSeconds("marathon", 8400, "fiveK") ≈ 874 s (14:34)
export function equivalentRaceTimeSeconds(
  fromDistance: RaceKey,
  fromTimeSeconds: number,
  toDistance: RaceKey,
): number {
  const fromRatio = RACE_RATIOS_TO_10K[fromDistance];
  const toRatio = RACE_RATIOS_TO_10K[toDistance];
  const base10K = fromTimeSeconds / fromRatio;
  return base10K * toRatio;
}

// Same as above but returns seconds/mile instead of total time.
export function equivalentRacePaceSecPerMile(
  fromDistance: RaceKey,
  fromTimeSeconds: number,
  toDistance: RaceKey,
): number {
  return equivalentRaceTimeSeconds(fromDistance, fromTimeSeconds, toDistance) / RACE_DISTANCE_MI[toDistance];
}

// ── Training pace ratios (% of marathon-pace SPEED) ─────────────────────
//
// Training paces are NOT race distances — they're aerobic zones derived
// from the athlete's marathon pace. Expressed as percentages of MP speed
// because that's the physiologically honest frame: "easy" is a range of
// aerobic intensity, not a single number.
//
// Canonical bands (May 2026 — tile the spectrum from MP-speed downward
// with no gaps and no overlaps between the four core zones):
//   Steady:   100–90%   ←  upper bound is MP itself; the floor of "marathon-minus"
//   Moderate:  90–80%
//   Easy:      80–70%
//   Recovery:  70–60%
//
// `TRAINING_MP_SPEED_RATIO` is the midpoint of each band — used by
// `derivePaceTableFromGoal` to populate a single pace per zone (legacy
// behavior, kept for callers that need one number).
//
// `TRAINING_MP_SPEED_RANGE` is the explicit fast/slow bounds — used by
// the pace-reference editor and pace chart to display each training
// zone as a range ("5:32–6:09/mi · 100–90% MP") rather than a single
// point. Coaches reason about training zones as ranges of effort, not
// exact targets.
//
// `longRun` is kept as a separate band (85–75% MP, midpoint 0.80)
// because long-run pace is sometimes coach-prescribed independently —
// but the editor and pace chart only display the four core zones to
// avoid presenting overlapping bands to the athlete.
const TRAINING_MP_SPEED_RATIO = {
  steady:    0.95,   // midpoint of 100–90%
  moderate:  0.85,   // midpoint of  90–80%
  longRun:   0.80,   // legacy band (85–75%), retained for callers
  easy:      0.75,   // midpoint of  80–70%
  recovery:  0.65,   // midpoint of  70–60%
} as const;

export interface TrainingZoneRange {
  /// Faster end as a ratio of MP speed (e.g., 1.00 → MP / 1.00 sec/mi = MP).
  fastRatio: number;
  /// Slower end as a ratio of MP speed (e.g., 0.90 → MP / 0.90 sec/mi).
  slowRatio: number;
  /// Display label for the %-MP band, e.g. "100–90% MP".
  bandLabel: string;
}

export const TRAINING_MP_SPEED_RANGE: Record<
  "steady" | "moderate" | "longRun" | "easy" | "recovery",
  TrainingZoneRange
> = {
  steady:    { fastRatio: 1.00, slowRatio: 0.90, bandLabel: "100–90% MP" },
  moderate:  { fastRatio: 0.90, slowRatio: 0.80, bandLabel: "90–80% MP" },
  longRun:   { fastRatio: 0.85, slowRatio: 0.75, bandLabel: "85–75% MP" },
  easy:      { fastRatio: 0.80, slowRatio: 0.70, bandLabel: "80–70% MP" },
  recovery:  { fastRatio: 0.70, slowRatio: 0.60, bandLabel: "70–60% MP" },
};

/**
 * Returns the fast / slow seconds-per-mile bounds for a training zone
 * given the athlete's marathon pace. Returns `null` for race-pace zones
 * (mp, hm, threshold, etc.) which should render as a single target, not
 * a range — see the `TOLERANCE_PERCENT` rationale higher in this file.
 */
export function trainingZoneRange(
  zone: PaceZone,
  mpSecPerMile: number,
): { fastSec: number; slowSec: number; bandLabel: string } | null {
  const band = (TRAINING_MP_SPEED_RANGE as Record<string, TrainingZoneRange | undefined>)[zone];
  if (!band || !(mpSecPerMile > 0)) return null;
  return {
    fastSec: mpSecPerMile / band.fastRatio,
    slowSec: mpSecPerMile / band.slowRatio,
    bandLabel: band.bandLabel,
  };
}

/**
 * Compute LT (threshold) as the athlete's 1-hour race pace, NOT collapsed
 * to HM. Linear interpolation between the athlete's 10K and HM paces:
 *   - 10K takes >1hr → LT = 10K pace (slow runner; even the 10K is
 *     longer than an hour, so the 1-hour pace is at most 10K pace)
 *   - HM takes <1hr → LT = HM pace (fast runner; HM is shorter than
 *     1 hour, so the 1-hour pace is at most HM pace)
 *   - Otherwise → interpolate by elapsed-time fraction to get the
 *     distance the athlete would cover in exactly 3600s, then derive
 *     pace from that.
 *
 * Mirrors iOS `PaceCalculator.calculateOneHourPace` exactly so the same
 * inputs produce the same threshold on both platforms. Pinned cross-
 * language so a change here implies the iOS function moves in lockstep.
 */
export function oneHourPaceSecPerMile(tenKSecPerMile: number, hmSecPerMile: number): number {
  const distance10K = RACE_DISTANCE_MI.tenK;
  const distanceHalf = RACE_DISTANCE_MI.half;
  const time10K = tenKSecPerMile * distance10K;
  const timeHalf = hmSecPerMile * distanceHalf;
  const target = 3600;
  if (time10K >= target) return tenKSecPerMile;
  if (timeHalf <= target) return hmSecPerMile;
  const fraction = (target - time10K) / (timeHalf - time10K);
  const distanceInOneHour = distance10K + fraction * (distanceHalf - distance10K);
  return target / distanceInOneHour;
}

// Derive the full pace table from a known race time + distance.
//
// Race-equivalent zones (mp, hm, tenK, fiveK, threeK, mile) are computed
// via the ratio table — correct across the full VDOT range.
//
// Training zones (recovery, easy, longRun, moderate, steady) are derived
// from MP as a fraction of MP speed — which scales correctly for both
// elites and recreational runners.
//
// `threshold` (LT) is now its own thing — the athlete's 1-hour race pace,
// not just HM pace. The two were collapsed prior to May 2026 ("VDOT
// convention"), which produced an LT that was identical to HM regardless
// of whether the athlete's actual 1-hour race effort matched HM intensity.
// Now they're separately computed via `oneHourPaceSecPerMile`, matching
// the iOS implementation.
export function derivePaceTableFromGoal(
  goalRaceSecPerMile: number,
  raceDistance: "marathon" | "half_marathon" | "10k" | "5k" | "mile" | string,
): Record<PaceZone, number> {
  const fromKey = raceKeyForInput(raceDistance);
  const fromTimeSeconds = goalRaceSecPerMile * RACE_DISTANCE_MI[fromKey];

  // Race-equivalent paces, ratio-based.
  const pace = (toKey: RaceKey) =>
    equivalentRacePaceSecPerMile(fromKey, fromTimeSeconds, toKey);

  const mpSec = pace("marathon");
  const hmSec = pace("half");
  const tenKSec = pace("tenK");

  // Training paces — percentages of MP speed.
  const trainingPace = (ratio: number) => mpSec / ratio;

  return {
    recovery:  trainingPace(TRAINING_MP_SPEED_RATIO.recovery),
    easy:      trainingPace(TRAINING_MP_SPEED_RATIO.easy),
    longRun:   trainingPace(TRAINING_MP_SPEED_RATIO.longRun),
    moderate:  trainingPace(TRAINING_MP_SPEED_RATIO.moderate),
    steady:    trainingPace(TRAINING_MP_SPEED_RATIO.steady),
    mp:        mpSec,
    hm:        hmSec,
    threshold: oneHourPaceSecPerMile(tenKSec, hmSec),
    tenK:      tenKSec,
    fiveK:     pace("fiveK"),
    threeK:    pace("threeK"),
    mile:      pace("mile"),
  };
}

// Dev-mode sanity check — verify the 2:20 marathon reference case. Catches
// regressions in the ratio table before they reach production.
//
// Reference (VDOT ~77, well-validated):
//   Marathon 2:20:00 → 5:20/mi   HM 1:06:46 → 5:06/mi
//   10K 30:18 → 4:53/mi           5K 14:34 → 4:41/mi
//   Mile 4:14 → 4:14/mi
if (typeof process !== "undefined" && process.env?.NODE_ENV !== "production") {
  const testTable = derivePaceTableFromGoal(320 /* 5:20/mi */, "marathon");
  const approx = (a: number, b: number, tolSec: number) => Math.abs(a - b) <= tolSec;
  const checks: Array<[string, number, number]> = [
    ["mp",    testTable.mp,   320],
    ["hm",    testTable.hm,   306], // 5:06
    ["tenK",  testTable.tenK, 293], // 4:53
    ["fiveK", testTable.fiveK, 281], // 4:41
    ["mile",  testTable.mile, 254], // 4:14
  ];
  for (const [label, actual, expected] of checks) {
    if (!approx(actual, expected, 3)) {
      console.warn(
        `[derivePaceTableFromGoal] ${label} drifted: expected ~${expected}s, got ${actual.toFixed(1)}s (2:20 marathon reference case)`,
      );
    }
  }
}

// Removed May 2026: `TOLERANCE_PERCENT` and `halfWindowSecPerMile`. The
// old ±5% flat tolerance around the zone midpoint was retired when
// paceRangeLabel switched to MP%-band rendering for training zones.
// Race zones now return a single point (no tolerance window); training
// zones return the true MP%-band via TRAINING_MP_SPEED_RANGE.

// Format a zone (optionally adjusted) as a pace range or single target.
//   - Race zones (mp, hm, threshold, tenK, fiveK, threeK, mile) → single
//     pace target. Race work is meant to hit a number, not a band.
//   - Training zones (steady, moderate, longRun, easy, recovery) → the
//     MP% band (e.g., Easy = 80–70% MP) anchored to MP. Adjustments
//     shift both ends equally so "Easy +30s/mi" returns a band shifted
//     slower by 30 seconds.
//   - Exact pace, when set, always wins as a single value.
//
// Previously these used `TOLERANCE_PERCENT` (a flat ±5% around the
// zone's midpoint), which produced a narrower band than what the
// PaceReferenceEditor showed in its expanded table. Coaches saw two
// different ranges for "Easy" depending on where in the UI they looked.
// Unified May 2026 to the MP% band as the single source of truth.
export function paceRangeLabel(
  zone: PaceZone,
  adjustment?: PaceAdjustment,
  exactPaceSecPerMile?: number,
  athletePaces?: AthletePaceTable,
): string {
  if (exactPaceSecPerMile && exactPaceSecPerMile > 0) {
    return `${formatPaceSecPerMile(exactPaceSecPerMile)}/mi`;
  }

  // Training zones: render the MP% band, shifted by adjustment.
  const mpSec = athletePaces?.mp ?? REFERENCE_PACE_SEC_PER_MILE.mp;
  const band = trainingZoneRange(zone, mpSec);
  if (band) {
    const fast = adjustedPaceSecPerMile(band.fastSec, adjustment);
    const slow = adjustedPaceSecPerMile(band.slowSec, adjustment);
    return `${formatPaceSecPerMile(fast)}–${formatPaceSecPerMile(slow)}/mi`;
  }

  // Race zones: single target.
  const base = athletePaces?.[zone] ?? REFERENCE_PACE_SEC_PER_MILE[zone];
  const center = adjustedPaceSecPerMile(base, adjustment);
  return `${formatPaceSecPerMile(center)}/mi`;
}

// ── Safe pace formatters ─────────────────────────────────
//
// `paceLabelWithAdjustment` and `paceRangeLabel` blindly trust that
// `zone` is a valid PaceZone. Old workouts authored before paceZone was
// a thing — or LLM-imported ones that stored only `target_pace_seconds_per_mile`
// — have `step.paceZone === undefined`, and the math then produces
// `NaN:NaN-NaN:NaN/mi`. These wrappers return `null` for that case so
// the renderer can hide the pace row instead of showing garbage.

const VALID_ZONES = new Set<string>(PACE_ZONES.map((z) => z.value));

function hasResolvableZone(zone: PaceZone | string | undefined): zone is PaceZone {
  return typeof zone === "string" && VALID_ZONES.has(zone);
}

export function safePaceLabel(
  zone: PaceZone | string | undefined,
  adjustment?: PaceAdjustment,
  exactPaceSecPerMile?: number,
): string | null {
  if (exactPaceSecPerMile && exactPaceSecPerMile > 0) {
    return `${formatPaceSecPerMile(exactPaceSecPerMile)}/mi`;
  }
  if (!hasResolvableZone(zone)) return null;
  return paceLabelWithAdjustment(zone, adjustment);
}

export function safePaceRangeLabel(
  zone: PaceZone | string | undefined,
  adjustment?: PaceAdjustment,
  exactPaceSecPerMile?: number,
  athletePaces?: AthletePaceTable,
): string | null {
  if (exactPaceSecPerMile && exactPaceSecPerMile > 0) {
    return `${formatPaceSecPerMile(exactPaceSecPerMile)}/mi`;
  }
  if (!hasResolvableZone(zone)) return null;
  return paceRangeLabel(zone, adjustment, undefined, athletePaces);
}

// ── Structure grouping ───────────────────────────────────
//
// Normalize the flat steps[] array into a three-section shape (warmup
// prefix, middle blocks, cooldown suffix) where the middle blocks
// collapse interval reps into a single `reps` entry. Works for two
// shapes of input:
//
//   1. New-format data where one step has `repeats > 1` and a nested
//      `recovery` sub-segment. The grouping helper passes it through.
//   2. Old flat-format data where the coach (or an LLM) stored
//      "800m, 2min, 800m, 2min, ..." as 11 separate steps. The helper
//      detects adjacent identical Active steps interleaved with a
//      consistent recovery and collapses them into one rep block.
//
// The renderer reads from this shape so it doesn't have to know which
// storage format the workout used.

export interface WorkoutStepBlock {
  kind: "single" | "reps";
  /// The primary step rendered (active body of the rep group, or the
  /// single step itself).
  step: WorkoutStep;
  /// When `kind === "reps"`, how many times the step repeats.
  repeats?: number;
  /// When `kind === "reps"`, the between-rep recovery. Stored either
  /// inline on the step (new format) or inferred from adjacent
  /// recovery rows (flat-format collapse).
  recovery?: {
    durationType: WorkoutStep["durationType"];
    durationValue: number;
    paceZone?: PaceZone | string;
    paceAdjustment?: PaceAdjustment;
    exactPaceSecPerMile?: number;
  };
}

export interface WorkoutSections {
  warmup: WorkoutStep[];
  blocks: WorkoutStepBlock[];
  cooldown: WorkoutStep[];
}

/**
 * Two steps look like "the same rep" when their type, duration, and
 * pace target match. Used by the flat-format collapse heuristic.
 */
function matchesAsRep(a: WorkoutStep, b: WorkoutStep): boolean {
  return (
    a.stepType === b.stepType &&
    a.durationType === b.durationType &&
    a.durationValue === b.durationValue &&
    (a.paceZone ?? "") === (b.paceZone ?? "") &&
    JSON.stringify(a.paceAdjustment ?? null) === JSON.stringify(b.paceAdjustment ?? null) &&
    (a.exactPaceSecPerMile ?? 0) === (b.exactPaceSecPerMile ?? 0)
  );
}

/**
 * Two recovery candidates "match" if they have the same shape. Used to
 * verify that every gap between adjacent identical Active reps looks
 * the same, so we don't false-positive-collapse a workout that just
 * happens to have repeated mains with different rests.
 */
function matchesAsRecovery(a: WorkoutStep, b: WorkoutStep): boolean {
  return (
    a.durationType === b.durationType &&
    a.durationValue === b.durationValue &&
    (a.paceZone ?? "") === (b.paceZone ?? "") &&
    JSON.stringify(a.paceAdjustment ?? null) === JSON.stringify(b.paceAdjustment ?? null)
  );
}

export function groupStepsIntoSections(steps: WorkoutStep[]): WorkoutSections {
  // 1. Warmup prefix
  let warmupEnd = 0;
  while (warmupEnd < steps.length && steps[warmupEnd].stepType === "warmup") {
    warmupEnd++;
  }
  // 2. Cooldown suffix
  let cooldownStart = steps.length;
  while (
    cooldownStart > warmupEnd &&
    steps[cooldownStart - 1].stepType === "cooldown"
  ) {
    cooldownStart--;
  }

  const warmup = steps.slice(0, warmupEnd);
  const cooldown = steps.slice(cooldownStart);
  const middle = steps.slice(warmupEnd, cooldownStart);

  const blocks: WorkoutStepBlock[] = [];
  let i = 0;
  while (i < middle.length) {
    const step = middle[i];

    // Pass-through: step already encodes its own repeats.
    if ((step.repeats ?? 1) > 1) {
      blocks.push({
        kind: "reps",
        step,
        repeats: step.repeats,
        recovery: step.recovery,
      });
      i++;
      continue;
    }

    // Flat-format collapse — only attempt on active steps. Walk forward
    // looking for the (rep, gap, rep, gap, ..., rep) pattern. The "gap"
    // is whatever step sits between two adjacent identical mains, which
    // could be typed as recovery/rest OR as active-at-a-different-pace
    // (which is how a lot of old data was stored). We don't try to infer
    // the gap's role from its step type — instead we require every gap
    // to look identical across the whole set, which gives a strong
    // signal that the coach meant it as recovery.
    if (step.stepType === "active") {
      let mainCount = 1;
      let recoveryRow: WorkoutStep | undefined;
      let j = i + 1;
      while (j < middle.length) {
        // Direct next-main match → adjacent identical reps with no gap.
        if (matchesAsRep(middle[j], step)) {
          mainCount++;
          j++;
          continue;
        }
        // Otherwise, treat middle[j] as a candidate gap and check that
        // middle[j+1] is the next matching main.
        if (j + 1 >= middle.length) break;
        if (!matchesAsRep(middle[j + 1], step)) break;
        const candidate = middle[j];
        // Guard: warmup/cooldown can never legitimately be a recovery
        // gap. Without this check, a misplaced warmup mid-workout
        // (rare but possible from LLM imports) gets silently swept
        // into a rep group as the recovery row, producing a confusing
        // structural reading.
        if (candidate.stepType === "warmup" || candidate.stepType === "cooldown") {
          break;
        }
        if (recoveryRow && !matchesAsRecovery(recoveryRow, candidate)) {
          // The gap pattern changed mid-set — stop collapsing.
          break;
        }
        if (!recoveryRow) recoveryRow = candidate;
        mainCount++;
        j += 2;
      }
      if (mainCount >= 2) {
        blocks.push({
          kind: "reps",
          step,
          repeats: mainCount,
          recovery: recoveryRow
            ? {
                durationType: recoveryRow.durationType,
                durationValue: recoveryRow.durationValue,
                paceZone: recoveryRow.paceZone,
                paceAdjustment: recoveryRow.paceAdjustment,
                exactPaceSecPerMile: recoveryRow.exactPaceSecPerMile,
              }
            : undefined,
        });
        i = j;
        continue;
      }
    }

    // Default: single step.
    blocks.push({ kind: "single", step });
    i++;
  }

  return { warmup, blocks, cooldown };
}

// Parse a coach-entered pace string like "5:45" or "5:45/mi" into seconds/mile.
// Returns null if unparseable. Bare integer is treated as minutes.
export function parsePaceSecPerMile(raw: string): number | null {
  const s = raw.trim().replace(/\/mi$/i, "").trim();
  if (s === "") return null;
  if (s.includes(":")) {
    const [mStr, sStr] = s.split(":");
    const m = mStr === "" ? 0 : parseInt(mStr, 10);
    const sec = sStr === "" ? 0 : parseInt(sStr, 10);
    if (isNaN(m) || isNaN(sec)) return null;
    const total = m * 60 + sec;
    return total > 0 ? total : null;
  }
  const n = parseFloat(s);
  if (isNaN(n) || n <= 0) return null;
  return Math.round(n * 60);
}

// Dev-mode sanity check — pace-adjustment math.
//
// Lives at the bottom so it runs after all const declarations in this
// file. Module-eval assertions that reference `const`-declared values
// must run after those declarations are initialized — placing this
// higher would TDZ-throw at import time. (Historical note: this block
// previously depended on TOLERANCE_PERCENT + halfWindowSecPerMile,
// which have been removed; we kept the bottom-of-file placement as
// defensive habit.)
//
// The coach-facing contract: "MP +20s/mi for a 6:00 marathoner should
// render 6:20/mi". MP-and-faster zones render as a single target, so
// the output is exact.
if (typeof process !== "undefined" && process.env?.NODE_ENV !== "production") {
  const mpTable: AthletePaceTable = { mp: 360 }; // 6:00/mi marathon pace
  const adjusted = paceRangeLabel(
    "mp",
    { type: "seconds_per_mile", value: 20 },
    undefined,
    mpTable,
  );
  if (adjusted !== "6:20/mi") {
    console.warn(
      `[paceRangeLabel] adjustment math drifted: expected "6:20/mi", got "${adjusted}" (mp=360, +20s/mi)`,
    );
  }
}
