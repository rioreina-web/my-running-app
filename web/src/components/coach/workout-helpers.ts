// Pure types and helpers for workout templates.
// This file deliberately has no "use client" directive so it can be imported
// by BOTH server components (the workout library card) and client components
// (the step editor and form). React Server Components can't call functions
// imported from "use client" modules, so the pure logic has to live here.

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

export const PACE_ZONES: PaceZoneOption[] = [
  { value: "recovery",  shortName: "Rec",       displayName: "Recovery",          description: "Very easy, fully conversational" },
  { value: "easy",      shortName: "Easy",      displayName: "Easy",              description: "Aerobic, conversational" },
  { value: "longRun",   shortName: "LR",        displayName: "Long Run",          description: "Steady aerobic effort" },
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
  notes: string;
  // Repeats > 1 → this step is an interval set (e.g., "6 × 800m"). Recovery
  // describes what happens between reps.
  repeats?: number;
  recovery?: {
    durationType: "distance_miles" | "distance_km" | "distance_meters" | "time_seconds";
    durationValue: number;
    paceZone: PaceZone;
    paceAdjustment?: PaceAdjustment;
  };
}

// ── Distance helpers ─────────────────────────────────────

export function stepDistanceMiles(s: {
  durationType: WorkoutStep["durationType"];
  durationValue: number;
}): number {
  if (s.durationType === "distance_miles")  return s.durationValue;
  if (s.durationType === "distance_km")     return s.durationValue / 1.60934;
  if (s.durationType === "distance_meters") return s.durationValue / 1609.34;
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

// ── Duration helpers ─────────────────────────────────────

// Reference paces (seconds per mile) for a moderately-trained runner.
// Used to estimate workout duration at template-creation time. Each athlete
// will see their own true duration when the workout is materialized into their
// scheduled_workouts row from their fitness_snapshot.
const REFERENCE_PACE_SEC_PER_MILE: Record<PaceZone, number> = {
  recovery:  10 * 60 + 30,
  easy:       9 * 60,
  longRun:    8 * 60 + 30,
  moderate:   8 * 60,
  steady:     7 * 60 + 30,
  mp:         7 * 60,
  hm:         6 * 60 + 45,
  threshold:  6 * 60 + 30,
  tenK:       6 * 60 + 15,
  fiveK:      6 * 60,
  threeK:     5 * 60 + 45,
  mile:       5 * 60 + 30,
};

// Compute the effective seconds-per-mile for a step's pace zone, applying any
// adjustment. Used by the duration estimator. The same logic will run on the
// athlete side (with their personal sec/mi for each zone) to get the actual
// prescribed pace they should run.
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
      return basePaceSecPerMile + adjustment.value * 1.60934;
  }
}

function stepSegmentDurationSeconds(seg: {
  durationType: WorkoutStep["durationType"];
  durationValue: number;
  paceZone: PaceZone;
  paceAdjustment?: PaceAdjustment;
}): number {
  if (seg.durationType === "time_seconds") return seg.durationValue;
  const miles = stepDistanceMiles(seg);
  const basePace = REFERENCE_PACE_SEC_PER_MILE[seg.paceZone] ?? REFERENCE_PACE_SEC_PER_MILE.easy;
  const paceSec = adjustedPaceSecPerMile(basePace, seg.paceAdjustment);
  return miles * paceSec;
}

export function totalStepDurationMinutes(step: WorkoutStep): number {
  const reps = step.repeats && step.repeats > 1 ? step.repeats : 1;
  const activeSec = stepSegmentDurationSeconds(step) * reps;
  const recoverySec = step.recovery ? stepSegmentDurationSeconds(step.recovery) * reps : 0;
  return (activeSec + recoverySec) / 60;
}

export function totalWorkoutDurationMinutes(steps: WorkoutStep[]): number {
  return steps.reduce((sum, s) => sum + totalStepDurationMinutes(s), 0);
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
  adjustment?: PaceAdjustment
): string {
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
