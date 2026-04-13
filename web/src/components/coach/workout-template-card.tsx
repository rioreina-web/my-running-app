import Link from "next/link";
import {
  formatStepDuration,
  paceLabelWithAdjustment,
  totalWorkoutMiles,
  totalWorkoutDurationMinutes,
  type WorkoutStep,
  type PaceZone,
} from "./workout-helpers";

interface WorkoutTemplate {
  id: string;
  name: string;
  workout_type: string;
  description?: string | null;
  tags?: string[] | null;
  estimated_distance_miles?: number | null;
  estimated_duration_minutes?: number | null;
  use_count: number;
  workout_data?: {
    schema_version?: string;
    name?: string;
    steps?: WorkoutStep[];
    total_distance_km?: number;
  } | null;
}

// Default pace zone per workout type — used to synthesize a single fallback
// step for old workouts saved without a steps[] array, so cards never look blank.
const TYPE_DEFAULT_ZONE: Record<string, PaceZone> = {
  easy:        "easy",
  recovery:    "recovery",
  long_run:    "longRun",
  tempo:       "threshold",
  intervals:   "fiveK",
  progression: "moderate",
  strides:     "mile",
  race:        "mp",
};

// Reference number prefix per workout type — gives templates a coach-y "INT-01" style ID.
const TYPE_PREFIX: Record<string, string> = {
  easy:        "EZ",
  tempo:       "TMP",
  intervals:   "INT",
  long_run:    "LR",
  progression: "PRG",
  recovery:    "REC",
  strides:     "STR",
  race:        "RCE",
};

const TYPE_LABEL: Record<string, string> = {
  easy:        "Easy",
  tempo:       "Tempo",
  intervals:   "Intervals",
  long_run:    "Long Run",
  progression: "Progression",
  recovery:    "Recovery",
  strides:     "Strides",
  race:        "Race",
};

function describeStep(step: WorkoutStep): { label: string; pace: string } {
  const dur = formatStepDuration(step.durationType, step.durationValue);
  const reps = (step.repeats ?? 1) > 1 ? `${step.repeats} × ` : "";

  let label: string;
  if (step.stepType === "warmup") {
    label = `Warmup — ${dur}`;
  } else if (step.stepType === "cooldown") {
    label = `Cooldown — ${dur}`;
  } else if (reps) {
    label = `${reps}${dur}`;
  } else {
    label = `${dur}`;
  }

  return {
    label,
    pace: paceLabelWithAdjustment(step.paceZone, step.paceAdjustment),
  };
}

function formatNumber(n: number): string {
  if (Number.isInteger(n)) return n.toString();
  return n.toFixed(1);
}

function formatDuration(minutes: number): string {
  if (minutes >= 60) {
    const h = Math.floor(minutes / 60);
    const m = minutes % 60;
    return m > 0 ? `${h}:${m.toString().padStart(2, "0")}` : `${h}h`;
  }
  return `${minutes}`;
}

function durationUnit(minutes: number): string {
  return minutes >= 60 ? "hr" : "min";
}

export function WorkoutTemplateCard({
  template,
  color,
  refIndex,
}: {
  template: WorkoutTemplate;
  color: string;
  refIndex: number;
}) {
  const rawSteps = (template.workout_data?.steps ?? []) as WorkoutStep[];

  // Synthesize a single fallback step from estimated_distance_miles when the
  // workout has no structured steps. Without this, old workouts created before
  // the steps[] requirement render with a blank middle.
  const steps: WorkoutStep[] = rawSteps.length > 0
    ? rawSteps
    : (template.estimated_distance_miles && template.estimated_distance_miles > 0
        ? [{
            id: "synthetic",
            stepType: "active",
            durationType: "distance_miles",
            durationValue: template.estimated_distance_miles,
            paceZone: TYPE_DEFAULT_ZONE[template.workout_type] ?? "easy",
            notes: "",
          }]
        : []);

  const prefix = TYPE_PREFIX[template.workout_type] ?? "WO";
  const refNum = `${prefix}-${String(refIndex).padStart(2, "0")}`;

  // Prefer the stored stats (set on save), but fall back to computing them
  // from steps[] at render time. This handles workouts saved before the form
  // started writing estimated_duration_minutes, so old cards aren't blank.
  const computedMiles = totalWorkoutMiles(steps);
  const computedMinutes = totalWorkoutDurationMinutes(steps);

  const distance =
    template.estimated_distance_miles && template.estimated_distance_miles > 0
      ? template.estimated_distance_miles
      : computedMiles > 0
      ? computedMiles
      : null;

  const duration =
    template.estimated_duration_minutes && template.estimated_duration_minutes > 0
      ? template.estimated_duration_minutes
      : computedMinutes > 0
      ? Math.round(computedMinutes)
      : null;

  return (
    <Link
      href={`/coach-portal/workouts/${template.id}/edit`}
      className="block bg-white border border-[var(--color-divider)] rounded-md overflow-hidden hover:border-[var(--color-text-tertiary)] transition-colors"
    >
      {/* Colored header strip */}
      <div
        className="px-5 py-3 text-white flex items-baseline justify-between gap-3"
        style={{ backgroundColor: color }}
      >
        <h3 className="text-sm font-semibold leading-tight truncate">
          {template.name}
        </h3>
        <span className="font-mono text-[10px] opacity-70 tracking-wider flex-shrink-0">
          {refNum}
        </span>
      </div>

      {/* Stat grid */}
      <div className="grid grid-cols-2 border-b border-[var(--color-divider)]">
        <div className="px-3 py-3 text-center border-r border-[var(--color-divider)]">
          <div className="font-mono text-base font-semibold text-[var(--color-text-primary)] leading-none">
            {distance != null ? formatNumber(distance) : "—"}
            {distance != null && (
              <span className="text-[9px] text-[var(--color-text-tertiary)] font-normal ml-0.5">mi</span>
            )}
          </div>
          <div className="text-[8px] uppercase tracking-wider text-[var(--color-text-tertiary)] mt-1.5">
            Distance
          </div>
        </div>
        <div className="px-3 py-3 text-center">
          <div className="font-mono text-base font-semibold text-[var(--color-text-primary)] leading-none">
            {duration != null ? formatDuration(duration) : "—"}
            {duration != null && (
              <span className="text-[9px] text-[var(--color-text-tertiary)] font-normal ml-0.5">
                {durationUnit(duration)}
              </span>
            )}
          </div>
          <div className="text-[8px] uppercase tracking-wider text-[var(--color-text-tertiary)] mt-1.5">
            Duration
          </div>
        </div>
      </div>

      {/* Structure ledger */}
      {steps.length > 0 ? (
        <div className="px-5 py-3.5">
          <div className="text-[8px] uppercase tracking-wider text-[var(--color-text-tertiary)] font-semibold mb-2">
            Structure
          </div>
          <div className="space-y-1">
            {steps.map((step, idx) => {
              const { label, pace } = describeStep(step);
              return (
                <div
                  key={step.id ?? idx}
                  className="grid grid-cols-[18px_1fr_auto] items-baseline gap-2.5 font-mono text-[11px]"
                >
                  <span className="text-[9px] text-[var(--color-text-tertiary)] text-right">
                    {String(idx + 1).padStart(2, "0")}
                  </span>
                  <span className="text-[var(--color-text-primary)] truncate">
                    {label}
                  </span>
                  <span
                    className="text-[10px] font-semibold flex-shrink-0"
                    style={{ color }}
                  >
                    {pace}
                  </span>
                </div>
              );
            })}
          </div>
        </div>
      ) : template.description ? (
        <div className="px-5 py-3.5 text-[11px] text-[var(--color-text-secondary)] italic">
          {template.description}
        </div>
      ) : null}

      {/* Footer */}
      <div className="flex items-center justify-between px-5 py-2.5 border-t border-dashed border-[var(--color-divider)] bg-[var(--color-bg-elevated)]">
        <div className="flex gap-1.5 flex-wrap">
          {(template.tags ?? []).slice(0, 4).map((tag) => (
            <span
              key={tag}
              className="font-mono text-[8px] text-[var(--color-text-tertiary)] px-1.5 py-0.5 bg-white border border-[var(--color-divider)] rounded-full tracking-wider"
            >
              {tag}
            </span>
          ))}
          {(!template.tags || template.tags.length === 0) && (
            <span className="text-[9px] text-[var(--color-text-tertiary)] italic">
              {TYPE_LABEL[template.workout_type] ?? template.workout_type}
            </span>
          )}
        </div>
        {template.use_count > 0 && (
          <span className="font-mono text-[9px] text-[var(--color-text-tertiary)] tracking-wider">
            used {template.use_count}×
          </span>
        )}
      </div>
    </Link>
  );
}
