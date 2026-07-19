import Link from "next/link";
import {
  estimatedWorkoutMiles,
  totalWorkoutDurationMinutes,
  workoutHasTimeBasedSegment,
  headlineZone,
  zoneLabelShort,
  stepZones,
  PACE_ZONE_COLORS,
  type WorkoutStep,
  type PaceZone,
} from "./workout-helpers";
import { WorkoutStructure } from "./workout-structure";
import { prettyCustomWorkoutType } from "@/lib/utils";

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
// `long_run` workouts default to `easy` (the LR pace zone was retired May 2026;
// see workout-helpers.ts PACE_ZONES comment).
const TYPE_DEFAULT_ZONE: Record<string, PaceZone> = {
  easy:        "easy",
  recovery:    "recovery",
  long_run:    "easy",
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
  // `estimatedWorkoutMiles` (vs the older `totalWorkoutMiles`) folds time-
  // based segments into the mile count so fartleks don't show "—".
  const computedMiles = estimatedWorkoutMiles(steps);
  const computedMinutes = totalWorkoutDurationMinutes(steps);
  const hasTimeBased = workoutHasTimeBasedSegment(steps);

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

  // Pace-zone label (10-zone taxonomy) derived from the steps: a tempo run
  // reads "LT", an interval set "5K", a long run "Long". Falls back to the
  // legacy workout_type label only when a workout has no steps to read.
  // "tempo"/"threshold" survive as stored data, never as new UI copy.
  const zone = headlineZone(steps);
  const typeLabel = zone
    ? zoneLabelShort(zone)
    : TYPE_LABEL[template.workout_type] ??
      prettyCustomWorkoutType(template.workout_type) ??
      template.workout_type;
  // Quality zones present, for the footer's zone-dot tags (blue = pace).
  const dotZones = stepZones(steps);

  // Soft tinted pill background derived from the workout-type color.
  // The card itself stays white; color only shows as a chip + on the
  // structure stripes inside, so the page reads as a calm grid of
  // workouts rather than a wall of color blocks (the previous design's
  // biggest readability problem).

  return (
    <div className="relative block bg-white border border-[var(--color-divider)] rounded-xl overflow-hidden hover:border-[var(--color-text-tertiary)] transition-colors">
      {/* Whole-card click target for editing. An overlay link (rather than
          wrapping the card in <Link>) so the Duplicate action below can be
          its own link — nested anchors are invalid HTML. */}
      <Link
        href={`/coach-portal/workouts/${template.id}/edit`}
        className="absolute inset-0 z-0"
        aria-label={`Edit ${template.name}`}
      />
      {/* Header — pill + ref code, then the name. Replaces the previous
          colored-bleed header that drowned out everything else. */}
      <div className="px-4 pt-4 pb-2.5">
        <div className="flex items-center gap-2 mb-1.5">
          <span
            className="text-[11px] font-medium px-2 py-0.5 rounded-full"
            style={{
              backgroundColor: `${color}1A`, // 10% alpha
              color,
            }}
          >
            {typeLabel}
          </span>
          <span className="font-mono text-[10px] text-[var(--color-text-tertiary)]">
            {refNum}
          </span>
        </div>
        <h3 className="font-display text-[17px] font-bold leading-tight text-[var(--color-text-primary)]">
          {template.name}
        </h3>
        {/* Inline stat row — distance and duration as one mono line
            instead of a 2-cell grid. ~ prefix when miles include
            time-based estimates. */}
        <div
          className="mt-2.5 flex items-center gap-2.5 font-mono text-[13px]"
          title={hasTimeBased ? "Includes estimated distance for time-based segments" : undefined}
        >
          {distance != null && (
            <>
              <span className="font-semibold text-[var(--color-text-primary)]">
                {hasTimeBased ? "~" : ""}
                {formatNumber(distance)}
              </span>
              <span className="text-[11px] text-[var(--color-text-tertiary)] -ml-1">mi</span>
            </>
          )}
          {distance != null && duration != null && (
            <span className="text-[var(--color-border-secondary)]">·</span>
          )}
          {duration != null && (
            <>
              <span className="font-semibold text-[var(--color-text-primary)]">
                {formatDuration(duration)}
              </span>
              <span className="text-[11px] text-[var(--color-text-tertiary)] -ml-1">
                {durationUnit(duration)}
              </span>
            </>
          )}
          {distance == null && duration == null && (
            <span className="text-[11px] text-[var(--color-text-tertiary)] italic">
              No stats yet
            </span>
          )}
        </div>
      </div>

      {/* Structure — grouped sections (warmup / main blocks / cooldown)
          via the shared WorkoutStructure component. Replaces the flat
          numbered ledger that turned a 6-rep workout into 14 rows. */}
      {steps.length > 0 ? (
        <div className="px-4 py-2.5 border-t border-[var(--color-divider)]">
          <WorkoutStructure steps={steps} variant="compact" />
        </div>
      ) : template.description ? (
        <div className="px-4 py-3 border-t border-[var(--color-divider)] text-[12px] text-[var(--color-text-secondary)] italic">
          {template.description}
        </div>
      ) : null}

      {/* Zone-dot tags — the quality zones this workout touches, derived
          from its steps (blue = pace). Only shows when there's quality
          work; a pure easy run has no dots. */}
      {dotZones.length > 0 && (
        <div className="flex items-center gap-2.5 px-4 py-1.5 border-t border-[var(--color-divider)]">
          {dotZones.map((z) => (
            <span key={z} className="flex items-center gap-1">
              <span
                className="w-1.5 h-1.5 rounded-full"
                style={{ background: PACE_ZONE_COLORS[z] }}
              />
              <span className="font-mono text-[10px] text-[var(--color-text-tertiary)]">
                {zoneLabelShort(z)}
              </span>
            </span>
          ))}
        </div>
      )}

      {/* Footer */}
      <div className="flex items-center justify-between px-4 py-2 border-t border-[var(--color-divider)] bg-[var(--color-bg-elevated)]">
        <div className="flex gap-1.5 flex-wrap">
          {(template.tags ?? []).slice(0, 4).map((tag) => (
            <span
              key={tag}
              className="font-mono text-[10px] text-[var(--color-text-tertiary)] px-1.5 py-0.5 bg-white border border-[var(--color-divider)] rounded-full"
            >
              {tag}
            </span>
          ))}
          {(!template.tags || template.tags.length === 0) && (
            <span className="text-[10px] text-[var(--color-text-tertiary)] italic">
              {typeLabel.toLowerCase()}
            </span>
          )}
        </div>
        <div className="flex items-center gap-3">
          {template.use_count > 0 && (
            <span className="font-mono text-[10px] text-[var(--color-text-tertiary)]">
              used {template.use_count}×
            </span>
          )}
          {/* Duplicate — opens the editor pre-filled with a clone. Nothing
              writes to the DB until the coach saves. Sits above the overlay
              link (z-10) so it wins the click. */}
          <Link
            href={`/coach-portal/workouts/new?from=${template.id}`}
            className="relative z-10 font-mono text-[10px] uppercase tracking-wider text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] transition-colors"
            title={`Duplicate "${template.name}" into a new template`}
          >
            duplicate
          </Link>
        </div>
      </div>
    </div>
  );
}
