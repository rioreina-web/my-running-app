"use client";

// All pure types/helpers/formatters live in workout-helpers.ts so server
// components (like the workout library card) can also import them. This file
// only contains the React component(s) and quick-add factories.
import {
  PACE_ZONES,
  totalStepMiles,
  totalWorkoutMiles,
  totalWorkoutDurationMinutes,
  formatStepDuration,
  paceLabelWithAdjustment,
  type PaceZone,
  type PaceAdjustment,
  type PaceAdjustmentType,
  type WorkoutStep,
} from "./workout-helpers";

// Re-export for backwards compatibility with existing imports.
export {
  totalWorkoutMiles,
  totalWorkoutDurationMinutes,
  formatStepDuration,
  type WorkoutStep,
  type PaceZone,
};

const ADJUSTMENT_UNITS: { value: PaceAdjustmentType; label: string }[] = [
  { value: "percent",          label: "%" },
  { value: "seconds_per_mile", label: "s/mi" },
  { value: "seconds_per_km",   label: "s/km" },
];

interface WorkoutStepEditorProps {
  steps: WorkoutStep[];
  onChange: (steps: WorkoutStep[]) => void;
}

const STEP_TYPES = [
  { value: "warmup",   label: "Warmup",   color: "#4A9E6B", defaultZone: "easy"     as PaceZone },
  { value: "active",   label: "Active",   color: "#D4592A", defaultZone: "tempo" as never }, // never used; explicit per quick-add
  { value: "recovery", label: "Recovery", color: "#9B9590", defaultZone: "easy"     as PaceZone },
  { value: "rest",     label: "Rest",     color: "#9B9590", defaultZone: "recovery" as PaceZone },
  { value: "cooldown", label: "Cooldown", color: "#4A9E6B", defaultZone: "easy"     as PaceZone },
] as const;

const DURATION_TYPES = [
  { value: "distance_miles",  label: "mi"  },
  { value: "distance_km",     label: "km"  },
  { value: "distance_meters", label: "m"   },
  { value: "time_seconds",    label: "sec" },
] as const;

// ── Step factories ───────────────────────────────────────

function newStep(
  partial: Partial<WorkoutStep> & { stepType: WorkoutStep["stepType"] }
): WorkoutStep {
  return {
    id: crypto.randomUUID(),
    durationType: "distance_miles",
    durationValue: 1,
    paceZone: "easy",
    notes: "",
    ...partial,
  };
}

const QUICK_ADDS: { label: string; build: () => WorkoutStep }[] = [
  {
    label: "+ Warmup",
    build: () => newStep({ stepType: "warmup",   durationType: "distance_miles",  durationValue: 2,   paceZone: "easy" }),
  },
  {
    label: "+ Easy run",
    build: () => newStep({ stepType: "active",   durationType: "distance_miles",  durationValue: 5,   paceZone: "easy" }),
  },
  {
    label: "+ Tempo block",
    build: () => newStep({ stepType: "active",   durationType: "distance_miles",  durationValue: 4,   paceZone: "threshold" }),
  },
  {
    label: "+ MP block",
    build: () => newStep({ stepType: "active",   durationType: "distance_miles",  durationValue: 6,   paceZone: "mp" }),
  },
  {
    label: "+ Interval set",
    build: () =>
      newStep({
        stepType: "active",
        durationType: "distance_meters",
        durationValue: 800,
        paceZone: "fiveK",
        repeats: 6,
        recovery: {
          durationType: "time_seconds",
          durationValue: 90,
          paceZone: "easy",
        },
      }),
  },
  {
    label: "+ Long run",
    build: () => newStep({ stepType: "active",   durationType: "distance_miles",  durationValue: 12,  paceZone: "longRun" }),
  },
  {
    label: "+ Cooldown",
    build: () => newStep({ stepType: "cooldown", durationType: "distance_miles",  durationValue: 1,   paceZone: "easy" }),
  },
];

// ─────────────────────────────────────────────────────────

export function WorkoutStepEditor({ steps, onChange }: WorkoutStepEditorProps) {
  function addStep(builder: () => WorkoutStep) {
    onChange([...steps, builder()]);
  }

  function updateStep(idx: number, patch: Partial<WorkoutStep>) {
    onChange(steps.map((s, i) => (i === idx ? { ...s, ...patch } : s)));
  }

  function updateRecovery(
    idx: number,
    patch: Partial<NonNullable<WorkoutStep["recovery"]>>
  ) {
    onChange(
      steps.map((s, i) => {
        if (i !== idx) return s;
        const recovery = s.recovery ?? {
          durationType: "time_seconds" as const,
          durationValue: 60,
          paceZone: "easy" as PaceZone,
        };
        return { ...s, recovery: { ...recovery, ...patch } };
      })
    );
  }

  function removeStep(idx: number) {
    onChange(steps.filter((_, i) => i !== idx));
  }

  function moveStep(idx: number, direction: -1 | 1) {
    const newIdx = idx + direction;
    if (newIdx < 0 || newIdx >= steps.length) return;
    const updated = [...steps];
    [updated[idx], updated[newIdx]] = [updated[newIdx], updated[idx]];
    onChange(updated);
  }

  function toggleRepeats(idx: number) {
    const step = steps[idx];
    if (step.repeats && step.repeats > 1) {
      updateStep(idx, { repeats: undefined, recovery: undefined });
    } else {
      onChange(
        steps.map((s, i) =>
          i === idx
            ? {
                ...s,
                repeats: 4,
                recovery: s.recovery ?? {
                  durationType: "time_seconds",
                  durationValue: 60,
                  paceZone: "easy",
                },
              }
            : s
        )
      );
    }
  }

  const totalMiles = totalWorkoutMiles(steps);

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
          Workout Structure
        </span>
        {totalMiles > 0 && (
          <span className="text-sm font-mono text-[var(--color-text-secondary)]">
            ≈ {totalMiles.toFixed(1)} mi
          </span>
        )}
      </div>

      {/* Visual proportion bar */}
      {steps.length > 0 && (
        <div className="flex rounded-lg overflow-hidden h-2">
          {steps.map((step) => {
            const typeConfig = STEP_TYPES.find((t) => t.value === step.stepType);
            const proportion =
              totalStepMiles(step) / Math.max(totalMiles, 0.01);
            return (
              <div
                key={step.id}
                style={{
                  width: `${Math.max(proportion * 100, 3)}%`,
                  backgroundColor: typeConfig?.color || "#9B9590",
                }}
                title={`${typeConfig?.label}: ${totalStepMiles(step).toFixed(1)}mi`}
              />
            );
          })}
        </div>
      )}

      {/* Step list */}
      <div className="space-y-2">
        {steps.length === 0 && (
          <div className="text-center py-8 border border-dashed border-[var(--color-divider)] rounded-xl">
            <p className="text-xs text-[var(--color-text-tertiary)]">
              No steps yet — pick a building block below
            </p>
          </div>
        )}

        {steps.map((step, idx) => {
          const typeConfig = STEP_TYPES.find((t) => t.value === step.stepType);
          const isRepeated = (step.repeats ?? 1) > 1;

          return (
            <div
              key={step.id}
              className="border border-[var(--color-divider)] rounded-xl bg-white"
            >
              {/* Main row */}
              <div className="flex items-center gap-2 px-3 py-2.5 flex-wrap">
                <div className="flex items-center gap-2 mr-1">
                  <span
                    className="w-1 h-6 rounded-full flex-shrink-0"
                    style={{ backgroundColor: typeConfig?.color }}
                  />
                  <select
                    value={step.stepType}
                    onChange={(e) =>
                      updateStep(idx, {
                        stepType: e.target.value as WorkoutStep["stepType"],
                      })
                    }
                    className="text-xs font-medium border-none bg-transparent text-[var(--color-text-primary)] focus:outline-none cursor-pointer"
                  >
                    {STEP_TYPES.map((t) => (
                      <option key={t.value} value={t.value}>
                        {t.label}
                      </option>
                    ))}
                  </select>
                </div>

                <input
                  type="number"
                  step="0.1"
                  value={step.durationValue}
                  onChange={(e) =>
                    updateStep(idx, {
                      durationValue: parseFloat(e.target.value) || 0,
                    })
                  }
                  className="w-16 text-center text-sm font-mono border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                />
                <select
                  value={step.durationType}
                  onChange={(e) =>
                    updateStep(idx, {
                      durationType: e.target
                        .value as WorkoutStep["durationType"],
                    })
                  }
                  className="text-xs border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)] cursor-pointer"
                >
                  {DURATION_TYPES.map((d) => (
                    <option key={d.value} value={d.value}>
                      {d.label}
                    </option>
                  ))}
                </select>

                {/* Pace zone dropdown + optional adjustment */}
                <div className="flex items-center gap-1">
                  <span className="text-[10px] text-[var(--color-text-tertiary)]">@</span>
                  <select
                    value={step.paceZone}
                    onChange={(e) =>
                      updateStep(idx, { paceZone: e.target.value as PaceZone })
                    }
                    className="text-xs border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)] cursor-pointer text-[var(--color-text-primary)]"
                    title="Pace reference (computed per athlete from fitness snapshot)"
                  >
                    {PACE_ZONES.map((p) => (
                      <option key={p.value} value={p.value}>
                        {p.shortName}
                      </option>
                    ))}
                  </select>
                  <input
                    type="number"
                    placeholder="±"
                    value={step.paceAdjustment?.value ?? ""}
                    onChange={(e) => {
                      const raw = e.target.value;
                      if (raw === "" || raw === "-") {
                        updateStep(idx, { paceAdjustment: undefined });
                        return;
                      }
                      const value = parseFloat(raw);
                      if (Number.isNaN(value) || value === 0) {
                        updateStep(idx, { paceAdjustment: undefined });
                        return;
                      }
                      const type: PaceAdjustmentType =
                        step.paceAdjustment?.type ?? "seconds_per_mile";
                      updateStep(idx, { paceAdjustment: { type, value } });
                    }}
                    className="w-12 text-center text-xs font-mono border border-[var(--color-divider)] rounded px-1 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                    title="Adjust the base pace. Negative = faster, positive = slower."
                  />
                  <select
                    value={step.paceAdjustment?.type ?? "seconds_per_mile"}
                    onChange={(e) => {
                      const type = e.target.value as PaceAdjustmentType;
                      if (step.paceAdjustment) {
                        updateStep(idx, { paceAdjustment: { ...step.paceAdjustment, type } });
                      }
                    }}
                    disabled={!step.paceAdjustment}
                    className="text-[10px] border border-[var(--color-divider)] rounded px-1 py-1 focus:outline-none focus:border-[var(--color-coral)] cursor-pointer disabled:opacity-50"
                  >
                    {ADJUSTMENT_UNITS.map((u) => (
                      <option key={u.value} value={u.value}>
                        {u.label}
                      </option>
                    ))}
                  </select>
                </div>

                {!isRepeated && step.stepType === "active" && (
                  <button
                    onClick={() => toggleRepeats(idx)}
                    className="text-[10px] text-[var(--color-text-tertiary)] hover:text-[var(--color-coral)] px-1.5 py-1"
                    title="Make this an interval set"
                  >
                    + reps
                  </button>
                )}
                {isRepeated && (
                  <div className="flex items-center gap-1">
                    <span className="text-xs text-[var(--color-text-tertiary)]">×</span>
                    <input
                      type="number"
                      min={2}
                      value={step.repeats ?? 2}
                      onChange={(e) =>
                        updateStep(idx, {
                          repeats: Math.max(2, parseInt(e.target.value) || 2),
                        })
                      }
                      className="w-12 text-center text-sm font-mono border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                    />
                  </div>
                )}

                <div className="ml-auto flex items-center gap-0.5">
                  <button
                    onClick={() => moveStep(idx, -1)}
                    disabled={idx === 0}
                    className="text-xs text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] disabled:opacity-30 px-1"
                    title="Move up"
                  >
                    ↑
                  </button>
                  <button
                    onClick={() => moveStep(idx, 1)}
                    disabled={idx === steps.length - 1}
                    className="text-xs text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] disabled:opacity-30 px-1"
                    title="Move down"
                  >
                    ↓
                  </button>
                  <button
                    onClick={() => removeStep(idx)}
                    className="text-xs text-[var(--color-text-tertiary)] hover:text-red-600 px-1.5"
                    title="Remove"
                  >
                    ✕
                  </button>
                </div>
              </div>

              {/* Recovery sub-row (only when repeated) */}
              {isRepeated && (
                <div className="flex items-center gap-2 px-3 pb-2.5 -mt-1 flex-wrap">
                  <span className="text-[10px] text-[var(--color-text-tertiary)] uppercase tracking-wider pl-3 ml-0.5 border-l-2 border-[var(--color-divider)]">
                    recovery
                  </span>
                  <input
                    type="number"
                    step="0.1"
                    value={step.recovery?.durationValue ?? 60}
                    onChange={(e) =>
                      updateRecovery(idx, {
                        durationValue: parseFloat(e.target.value) || 0,
                      })
                    }
                    className="w-14 text-center text-xs font-mono border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                  />
                  <select
                    value={step.recovery?.durationType ?? "time_seconds"}
                    onChange={(e) =>
                      updateRecovery(idx, {
                        durationType: e.target.value as WorkoutStep["durationType"],
                      })
                    }
                    className="text-xs border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)] cursor-pointer"
                  >
                    {DURATION_TYPES.map((d) => (
                      <option key={d.value} value={d.value}>
                        {d.label}
                      </option>
                    ))}
                  </select>
                  <span className="text-[10px] text-[var(--color-text-tertiary)]">@</span>
                  <select
                    value={step.recovery?.paceZone ?? "easy"}
                    onChange={(e) =>
                      updateRecovery(idx, {
                        paceZone: e.target.value as PaceZone,
                      })
                    }
                    className="text-xs border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)] cursor-pointer"
                  >
                    {PACE_ZONES.map((p) => (
                      <option key={p.value} value={p.value}>
                        {p.shortName}
                      </option>
                    ))}
                  </select>
                  <input
                    type="number"
                    placeholder="±"
                    value={step.recovery?.paceAdjustment?.value ?? ""}
                    onChange={(e) => {
                      const raw = e.target.value;
                      if (raw === "" || raw === "-") {
                        updateRecovery(idx, { paceAdjustment: undefined });
                        return;
                      }
                      const value = parseFloat(raw);
                      if (Number.isNaN(value) || value === 0) {
                        updateRecovery(idx, { paceAdjustment: undefined });
                        return;
                      }
                      const type: PaceAdjustmentType =
                        step.recovery?.paceAdjustment?.type ?? "seconds_per_mile";
                      updateRecovery(idx, { paceAdjustment: { type, value } });
                    }}
                    className="w-12 text-center text-xs font-mono border border-[var(--color-divider)] rounded px-1 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                    title="Adjust the recovery pace. Negative = faster, positive = slower."
                  />
                  <select
                    value={step.recovery?.paceAdjustment?.type ?? "seconds_per_mile"}
                    onChange={(e) => {
                      const type = e.target.value as PaceAdjustmentType;
                      if (step.recovery?.paceAdjustment) {
                        updateRecovery(idx, {
                          paceAdjustment: { ...step.recovery.paceAdjustment, type },
                        });
                      }
                    }}
                    disabled={!step.recovery?.paceAdjustment}
                    className="text-[10px] border border-[var(--color-divider)] rounded px-1 py-1 focus:outline-none focus:border-[var(--color-coral)] cursor-pointer disabled:opacity-50"
                  >
                    {ADJUSTMENT_UNITS.map((u) => (
                      <option key={u.value} value={u.value}>
                        {u.label}
                      </option>
                    ))}
                  </select>
                  <button
                    onClick={() => toggleRepeats(idx)}
                    className="text-[10px] text-[var(--color-text-tertiary)] hover:text-red-600 ml-auto"
                  >
                    Remove reps
                  </button>
                </div>
              )}

              {/* Plain-language summary */}
              <div className="px-3 pb-2 text-[10px] text-[var(--color-text-tertiary)] font-mono">
                {summarizeStep(step)}
              </div>
            </div>
          );
        })}
      </div>

      {/* Quick add */}
      <div className="space-y-2 pt-1">
        <span className="text-[10px] font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
          Add a block
        </span>
        <div className="flex flex-wrap gap-1.5">
          {QUICK_ADDS.map((q) => (
            <button
              key={q.label}
              onClick={() => addStep(q.build)}
              className="px-2.5 py-1.5 text-xs rounded-lg border border-[var(--color-divider)] text-[var(--color-text-secondary)] hover:border-[var(--color-coral)] hover:text-[var(--color-coral)] transition-colors"
            >
              {q.label}
            </button>
          ))}
        </div>
      </div>

      {/* Pace zone legend */}
      <div className="pt-2 border-t border-[var(--color-divider)]">
        <p className="text-[9px] uppercase tracking-wider text-[var(--color-text-tertiary)] mb-1.5 font-semibold">
          Pace zones
        </p>
        <p className="text-[10px] text-[var(--color-text-tertiary)] leading-relaxed">
          Workouts reference pace <em>zones</em>, not absolute paces. Each athlete sees real seconds-per-mile computed from their fitness snapshot.{" "}
          <span className="text-[var(--color-text-secondary)]">Easy</span> · <span className="text-[var(--color-text-secondary)]">LR</span> · <span className="text-[var(--color-text-secondary)]">Mod</span> · <span className="text-[var(--color-text-secondary)]">Steady</span> · <span className="text-[var(--color-text-secondary)]">MP</span> · <span className="text-[var(--color-text-secondary)]">HM</span> · <span className="text-[var(--color-text-secondary)]">LT</span> · <span className="text-[var(--color-text-secondary)]">10K</span> · <span className="text-[var(--color-text-secondary)]">5K</span> · <span className="text-[var(--color-text-secondary)]">3K</span> · <span className="text-[var(--color-text-secondary)]">Mile</span>
        </p>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────

function summarizeStep(step: WorkoutStep): string {
  const dur = formatStepDuration(step.durationType, step.durationValue);
  const pace = paceLabelWithAdjustment(step.paceZone, step.paceAdjustment);
  const reps = step.repeats && step.repeats > 1 ? `${step.repeats} × ` : "";
  const main = `${reps}${dur} @ ${pace}`;
  if (step.recovery && (step.repeats ?? 1) > 1) {
    const rdur = formatStepDuration(step.recovery.durationType, step.recovery.durationValue);
    const rpace = paceLabelWithAdjustment(step.recovery.paceZone, step.recovery.paceAdjustment);
    return `${main}  /  ${rdur} ${rpace} recovery`;
  }
  return main;
}
