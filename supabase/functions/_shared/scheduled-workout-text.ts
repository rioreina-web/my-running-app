/**
 * Best-effort human-readable text for a scheduled_workouts row.
 *
 * FOUND WHILE WIRING plan-edit TO A LIVE ROW: the table has no free-text
 * description column. `session` — which every earlier draft of this feature
 * assumed held the coach's shorthand — is `integer` (which session of the
 * day; doubles use 1/2), not text; calling `.trim()` on it would have thrown
 * on the first real row. `rationale_short`/`rationale_full` exist in the
 * schema but nothing in this codebase writes to them. The only reliably
 * populated source of what a workout actually IS is `workout_data.steps[]`,
 * written in the same shape as the web `WorkoutStep` type (see
 * `coach-workout-read/index.ts`'s `plannedMilesFromSteps`, which reads the
 * same field names this module does).
 *
 * So: summarize the steps into shorthand-ish text ("2mi wu, 6x800 @ fiveK +
 * 400m jog, 2mi cd"), falling back through `notes`, then `workout_type`,
 * only when there's truly nothing structured to read.
 */

interface StepLike {
  stepType?: unknown;
  durationType?: unknown;
  durationValue?: unknown;
  paceZone?: unknown;
  repeats?: unknown;
  exactPaceSecPerMile?: unknown;
  recovery?: { durationType?: unknown; durationValue?: unknown } | null;
}

const UNIT: Record<string, string> = {
  distance_miles: "mi",
  distance_km: "km",
  distance_meters: "m",
};

function fmtPace(secPerMile: number): string {
  const m = Math.floor(secPerMile / 60);
  const s = Math.round(secPerMile % 60);
  return `${m}:${String(s).padStart(2, "0")}`;
}

function describeStep(raw: unknown): string | null {
  const s = (raw ?? {}) as StepLike;
  const durationType = typeof s.durationType === "string" ? s.durationType : null;
  const durationValue = typeof s.durationValue === "number" ? s.durationValue : null;
  if (!durationType || durationValue == null) return null;

  const isTime = durationType === "time_seconds";
  const unit = isTime ? "" : UNIT[durationType] ?? "";
  const value = isTime ? `${Math.round(durationValue / 60)}'` : `${durationValue}${unit}`;

  const repeats = typeof s.repeats === "number" && s.repeats > 1 ? `${s.repeats}x ` : "";

  const exact = typeof s.exactPaceSecPerMile === "number" ? s.exactPaceSecPerMile : null;
  const zone = typeof s.paceZone === "string" ? s.paceZone : null;
  const pace = exact != null ? ` @ ${fmtPace(exact)}` : zone ? ` @ ${zone}` : "";

  const prefix = s.stepType === "warmup" ? "wu " : s.stepType === "cooldown" ? "cd " : "";

  const recDur = typeof s.recovery?.durationValue === "number" ? s.recovery.durationValue : null;
  const recType = typeof s.recovery?.durationType === "string" ? s.recovery.durationType : null;
  const recovery = recDur != null && recType
    ? ` + ${recDur}${recType === "time_seconds" ? "s" : UNIT[recType] ?? ""} jog`
    : "";

  return `${prefix}${repeats}${value}${pace}${recovery}`;
}

/** Renders workout_data.steps[] into shorthand-ish text, or null if there's
 *  nothing structured to read (no steps, or every step is unparseable). */
export function summarizeSteps(workoutData: unknown): string | null {
  const steps = (workoutData as { steps?: unknown } | null)?.steps;
  if (!Array.isArray(steps) || steps.length === 0) return null;
  const parts = steps.map(describeStep).filter((p): p is string => p != null);
  return parts.length ? parts.join(", ") : null;
}

interface ScheduledWorkoutTextInput {
  notes?: string | null;
  workout_data?: unknown;
  workout_type?: string | null;
}

/** The text-source priority for a scheduled_workouts row. `session` (an
 *  integer) is deliberately never consulted — see the module doc. */
export function textForScheduledWorkout(row: ScheduledWorkoutTextInput): string {
  const notes = row.notes?.trim();
  if (notes) return notes;
  const fromSteps = summarizeSteps(row.workout_data);
  if (fromSteps) return fromSteps;
  return row.workout_type?.trim() || "Workout";
}
