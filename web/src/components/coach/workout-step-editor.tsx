"use client";

// All pure types/helpers/formatters live in workout-helpers.ts so server
// components (like the workout library card) can also import them. This file
// only contains the React component(s) and quick-add factories.
import {
  PACE_ZONES,
  REFERENCE_PACE_SEC_PER_MILE,
  totalStepMiles,
  totalWorkoutMiles,
  totalWorkoutDurationMinutes,
  formatStepDuration,
  paceLabelWithAdjustment,
  paceRangeLabel,
  formatPaceSecPerMile,
  parsePaceSecPerMile,
  trainingZoneRange,
  type AthletePaceTable,
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
  // When a plan or athlete has its own pace table, pass it in so every
  // dropdown option, step-row range, and the bottom reference card all
  // show the real seconds-per-mile for that context. Falls back to the
  // generic reference runner when absent.
  athletePaces?: AthletePaceTable;
}

const STEP_TYPES = [
  { value: "warmup",   label: "Warmup",   color: "#4A9E6B", defaultZone: "easy"     as PaceZone },
  { value: "active",   label: "Active",   color: "#D4592A", defaultZone: "tempo" as never }, // never used; explicit per quick-add
  { value: "recovery", label: "Recovery", color: "#9B9590", defaultZone: "easy"     as PaceZone },
  { value: "rest",     label: "Rest",     color: "#9B9590", defaultZone: "recovery" as PaceZone },
  { value: "cooldown", label: "Cooldown", color: "#4A9E6B", defaultZone: "recovery" as PaceZone },
] as const;

const DURATION_TYPES = [
  { value: "distance_miles",  label: "mi"  },
  { value: "distance_km",     label: "km"  },
  { value: "distance_meters", label: "m"   },
  { value: "time_seconds",    label: "min" },
] as const;

// Parse "M:SS" / "MM:SS" / "0:30" / bare "2" (minutes) / bare ":30" → seconds.
// Returns null for unparseable input so the caller can ignore the keystroke.
function parseMinutesSeconds(raw: string): number | null {
  const s = raw.trim();
  if (s === "") return 0;
  if (s.includes(":")) {
    const [mStr, sStr] = s.split(":");
    const m = mStr === "" ? 0 : parseInt(mStr, 10);
    const sec = sStr === "" ? 0 : parseInt(sStr, 10);
    if (isNaN(m) || isNaN(sec)) return null;
    return m * 60 + sec;
  }
  const n = parseFloat(s);
  if (isNaN(n)) return null;
  return Math.round(n * 60);
}

function formatSecondsAsMinSec(totalSeconds: number): string {
  const total = Math.max(0, Math.round(totalSeconds));
  const m = Math.floor(total / 60);
  const sec = total % 60;
  return `${m}:${sec.toString().padStart(2, "0")}`;
}

// Numeric input that behaves like a plain text box: user can clear, retype,
// and we only commit the value on blur (or Enter). Avoids the "can't clear 2
// to type 10" problem caused by controlled onChange that coerces "" back to 0.
function NumberCell({
  value,
  onCommit,
  integer = false,
  min,
  className,
  placeholder,
  title,
}: {
  value: number;
  onCommit: (n: number) => void;
  integer?: boolean;
  min?: number;
  className?: string;
  /// Shown when the field's value is 0/empty. Useful for distinguishing
  /// the pace-adjustment cell (±) from the duration cell (numeric only).
  placeholder?: string;
  /// Native tooltip; used for the adjustment cell to explain that
  /// negative is faster, positive is slower.
  title?: string;
}) {
  return (
    <input
      type="text"
      inputMode={integer ? "numeric" : "decimal"}
      defaultValue={value === 0 ? "" : String(value)}
      placeholder={placeholder}
      title={title}
      key={`num-${value}`}
      onFocus={(e) => e.target.select()}
      onBlur={(e) => {
        const raw = e.target.value.trim();
        if (raw === "") {
          onCommit(min ?? 0);
          return;
        }
        const n = integer ? parseInt(raw, 10) : parseFloat(raw);
        if (Number.isNaN(n)) return;
        onCommit(min !== undefined ? Math.max(min, n) : n);
      }}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          (e.target as HTMLInputElement).blur();
        }
      }}
      className={className}
    />
  );
}

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
    label: "+ 800m reps",
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
          paceZone: "recovery",
        },
      }),
  },
  {
    label: "+ Mile reps",
    build: () =>
      newStep({
        stepType: "active",
        durationType: "distance_miles",
        durationValue: 1,
        paceZone: "threshold",
        repeats: 6,
        recovery: {
          durationType: "distance_miles",
          durationValue: 0.25,
          paceZone: "recovery",
        },
      }),
  },
  {
    label: "+ K reps",
    build: () =>
      newStep({
        stepType: "active",
        durationType: "distance_km",
        durationValue: 1,
        paceZone: "tenK",
        repeats: 5,
        recovery: {
          durationType: "time_seconds",
          durationValue: 90,
          paceZone: "recovery",
        },
      }),
  },
  {
    // Long-run quick-add now defaults to Easy (the most common prescription
    // for an aerobic long run). The deprecated `longRun` pace zone was
    // retired May 2026 — see the comment on PACE_ZONES in workout-helpers.ts.
    label: "+ Long run",
    build: () => newStep({ stepType: "active",   durationType: "distance_miles",  durationValue: 12,  paceZone: "easy" }),
  },
  {
    label: "+ Cooldown",
    build: () => newStep({ stepType: "cooldown", durationType: "distance_miles",  durationValue: 1,   paceZone: "recovery" }),
  },
];

// ─────────────────────────────────────────────────────────

export function WorkoutStepEditor({ steps, onChange, athletePaces }: WorkoutStepEditorProps) {
  function basePace(zone: PaceZone): number {
    return athletePaces?.[zone] ?? REFERENCE_PACE_SEC_PER_MILE[zone];
  }

  // Per-zone dropdown label. Training zones display the MP% band so the
  // dropdown matches the per-row pace range shown at the right side of
  // the step (which also uses the MP% band as of May 2026). Race zones
  // stay single-point because race targets aren't a negotiation.
  function zoneOptionLabel(zone: PaceZone): string {
    const mpSec = athletePaces?.mp ?? REFERENCE_PACE_SEC_PER_MILE.mp;
    const band = trainingZoneRange(zone, mpSec);
    if (band) {
      return `${formatPaceSecPerMile(band.fastSec)}–${formatPaceSecPerMile(band.slowSec)}/mi`;
    }
    return `${formatPaceSecPerMile(basePace(zone))}/mi`;
  }
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

  // Duplicate a step. Inserts the clone immediately after the source so
  // the coach sees it in the obvious next slot (vs. appending to the end,
  // which is jarring on long workouts). New step gets a fresh UUID; the
  // recovery sub-object and any nested adjustments are spread-cloned so
  // edits to the duplicate don't mutate the original.
  function duplicateStep(idx: number) {
    const source = steps[idx];
    if (!source) return;
    const clone: WorkoutStep = {
      ...source,
      id: crypto.randomUUID(),
      paceAdjustment: source.paceAdjustment ? { ...source.paceAdjustment } : undefined,
      recovery: source.recovery
        ? {
            ...source.recovery,
            paceAdjustment: source.recovery.paceAdjustment
              ? { ...source.recovery.paceAdjustment }
              : undefined,
          }
        : undefined,
    };
    const next = [...steps];
    next.splice(idx + 1, 0, clone);
    onChange(next);
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

  // Phase A of plan-builder-ui-redesign.md: removed the duplicate
  // "Workout Structure" header + ≈ total + proportion bar. The right
  // panel already shows the step list (which contains the same info
  // per row), and plan-builder-client.tsx's "STEPS" label is the
  // section heading. Two labels for the same content was visual noise.
  // The proportion bar can come back later as a hover-only summary.

  return (
    <div className="space-y-4">
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

                {step.durationType === "time_seconds" ? (
                  <input
                    type="text"
                    inputMode="numeric"
                    placeholder="2:30"
                    defaultValue={formatSecondsAsMinSec(step.durationValue)}
                    key={`dur-${idx}-${step.durationValue}`}
                    onBlur={(e) => {
                      const parsed = parseMinutesSeconds(e.target.value);
                      if (parsed !== null) updateStep(idx, { durationValue: parsed });
                    }}
                    className="w-16 text-center text-sm font-mono border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                  />
                ) : (
                  <NumberCell
                    value={step.durationValue}
                    onCommit={(n) => updateStep(idx, { durationValue: n })}
                    className="w-16 text-center text-sm font-mono border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                  />
                )}
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

                {/* Pace: either a zone (with optional adjustment) or an exact pace */}
                <div className="flex items-center gap-1">
                  <span className="text-[10px] text-[var(--color-text-tertiary)]">@</span>
                  {step.exactPaceSecPerMile ? (
                    <>
                      <input
                        type="text"
                        inputMode="numeric"
                        placeholder="5:45"
                        defaultValue={formatPaceSecPerMile(step.exactPaceSecPerMile)}
                        key={`exact-${idx}-${step.exactPaceSecPerMile}`}
                        onBlur={(e) => {
                          const parsed = parsePaceSecPerMile(e.target.value);
                          if (parsed !== null) updateStep(idx, { exactPaceSecPerMile: parsed });
                        }}
                        className="w-16 text-center text-xs font-mono border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                        title="Exact pace in M:SS per mile"
                      />
                      <span className="text-[10px] text-[var(--color-text-tertiary)]">/mi</span>
                      <button
                        onClick={() => updateStep(idx, { exactPaceSecPerMile: undefined })}
                        className="text-[10px] text-[var(--color-text-tertiary)] hover:text-[var(--color-coral)] px-1"
                        title="Use a pace zone instead"
                      >
                        use zone
                      </button>
                    </>
                  ) : (
                    <>
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
                            {p.shortName} · {zoneOptionLabel(p.value)}
                          </option>
                        ))}
                      </select>
                      {/* Pace-adjustment value uses NumberCell so clearing
                          and retyping (including negatives) works the same
                          as the duration cell. Empty / 0 → strip the
                          adjustment entirely. The ± placeholder distinguishes
                          this empty cell from the duration field next to it. */}
                      <NumberCell
                        value={step.paceAdjustment?.value ?? 0}
                        placeholder="±"
                        title="Adjust the base pace. Negative = faster, positive = slower."
                        onCommit={(n) => {
                          if (!Number.isFinite(n) || n === 0) {
                            updateStep(idx, { paceAdjustment: undefined });
                            return;
                          }
                          const type: PaceAdjustmentType =
                            step.paceAdjustment?.type ?? "seconds_per_mile";
                          updateStep(idx, { paceAdjustment: { type, value: n } });
                        }}
                        className="w-12 text-center text-xs font-mono border border-[var(--color-divider)] rounded px-1 py-1 focus:outline-none focus:border-[var(--color-coral)]"
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
                      <button
                        onClick={() => updateStep(idx, { exactPaceSecPerMile: 6 * 60 + 30 })}
                        className="text-[10px] text-[var(--color-text-tertiary)] hover:text-[var(--color-coral)] px-1"
                        title="Pin an exact pace (e.g. 5:45/mi)"
                      >
                        exact
                      </button>
                    </>
                  )}
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
                    <NumberCell
                      value={step.repeats ?? 2}
                      onCommit={(n) => updateStep(idx, { repeats: Math.max(2, Math.round(n)) })}
                      integer
                      min={2}
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
                    aria-label={`Move step ${idx + 1} up`}
                  >
                    ↑
                  </button>
                  <button
                    onClick={() => moveStep(idx, 1)}
                    disabled={idx === steps.length - 1}
                    className="text-xs text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] disabled:opacity-30 px-1"
                    title="Move down"
                    aria-label={`Move step ${idx + 1} down`}
                  >
                    ↓
                  </button>
                  <button
                    onClick={() => duplicateStep(idx)}
                    className="text-xs text-[var(--color-text-tertiary)] hover:text-[var(--color-coral)] px-1"
                    title="Duplicate this step"
                    aria-label={`Duplicate step ${idx + 1}`}
                  >
                    ⎘
                  </button>
                  <button
                    onClick={() => removeStep(idx)}
                    className="text-xs text-[var(--color-text-tertiary)] hover:text-red-600 px-1.5"
                    title="Remove"
                    aria-label={`Remove step ${idx + 1}`}
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
                  {(step.recovery?.durationType ?? "time_seconds") === "time_seconds" ? (
                    <input
                      type="text"
                      inputMode="numeric"
                      placeholder="1:00"
                      defaultValue={formatSecondsAsMinSec(step.recovery?.durationValue ?? 60)}
                      key={`rec-${idx}-${step.recovery?.durationValue ?? 60}`}
                      onBlur={(e) => {
                        const parsed = parseMinutesSeconds(e.target.value);
                        if (parsed !== null) updateRecovery(idx, { durationValue: parsed });
                      }}
                      className="w-14 text-center text-xs font-mono border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                    />
                  ) : (
                    <NumberCell
                      value={step.recovery?.durationValue ?? 60}
                      onCommit={(n) => updateRecovery(idx, { durationValue: n })}
                      className="w-14 text-center text-xs font-mono border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)]"
                    />
                  )}
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
                  {/* Pace-zone select for recovery — includes a "Standing
                      rest" sentinel option at the top. Selecting it clears
                      paceZone + paceAdjustment so the recovery represents
                      "stop and rest between reps" rather than "jog at pace".
                      Matches the iOS PlannedWorkoutRecovery shape, where
                      paceZone is already optional (NamedPace?). */}
                  <select
                    value={step.recovery?.paceZone ?? "__rest__"}
                    onChange={(e) => {
                      const v = e.target.value;
                      if (v === "__rest__") {
                        updateRecovery(idx, {
                          paceZone: undefined,
                          paceAdjustment: undefined,
                        });
                      } else {
                        updateRecovery(idx, { paceZone: v as PaceZone });
                      }
                    }}
                    className="text-xs border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)] cursor-pointer"
                  >
                    <option value="__rest__">Standing rest</option>
                    {PACE_ZONES.map((p) => (
                      <option key={p.value} value={p.value}>
                        {p.shortName} · {zoneOptionLabel(p.value)}
                      </option>
                    ))}
                  </select>
                  {/* Adjustment controls only make sense when there's a pace
                      to adjust. Hidden in standing-rest mode. */}
                  {step.recovery?.paceZone && (
                    <>
                      <NumberCell
                        value={step.recovery?.paceAdjustment?.value ?? 0}
                        placeholder="±"
                        title="Adjust the recovery pace. Negative = faster, positive = slower."
                        onCommit={(n) => {
                          if (!Number.isFinite(n) || n === 0) {
                            updateRecovery(idx, { paceAdjustment: undefined });
                            return;
                          }
                          const type: PaceAdjustmentType =
                            step.recovery?.paceAdjustment?.type ?? "seconds_per_mile";
                          updateRecovery(idx, { paceAdjustment: { type, value: n } });
                        }}
                        className="w-12 text-center text-xs font-mono border border-[var(--color-divider)] rounded px-1 py-1 focus:outline-none focus:border-[var(--color-coral)]"
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
                    </>
                  )}
                  <button
                    onClick={() => toggleRepeats(idx)}
                    className="text-[10px] text-[var(--color-text-tertiary)] hover:text-red-600 ml-auto"
                  >
                    Remove reps
                  </button>
                </div>
              )}

              {/* Notes */}
              <div className="px-3 pb-2">
                <input
                  type="text"
                  placeholder="Notes (e.g. 'build effort mile 4', 'stay relaxed')"
                  defaultValue={step.notes}
                  key={`notes-${idx}-${step.id}`}
                  onBlur={(e) => updateStep(idx, { notes: e.target.value })}
                  className="w-full text-xs border border-transparent hover:border-[var(--color-divider)] focus:border-[var(--color-coral)] rounded px-2 py-1 bg-transparent text-[var(--color-text-secondary)] placeholder:text-[var(--color-text-tertiary)] placeholder:italic focus:outline-none"
                />
              </div>

              {/* Plain-language summary + pace range */}
              <div className="px-3 pb-2 flex items-center justify-between gap-3 text-[10px] text-[var(--color-text-tertiary)] font-mono">
                <span className="truncate">{summarizeStep(step)}</span>
                <span className="flex-shrink-0 text-[var(--color-text-secondary)]">
                  {paceRangeLabel(step.paceZone, step.paceAdjustment, step.exactPaceSecPerMile, athletePaces)}
                </span>
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

      {/* Pace zone reference removed — Phase A of plan-builder-ui-redesign.md.
          The plan header's PaceReferenceEditor card is the single source of
          truth. The PaceZoneReference function below is preserved for future
          re-use (e.g., a collapsible drawer) but is no longer rendered. */}
    </div>
  );
}

// Reference card shown under the editor so the coach can see what pace each
// zone maps to while building. Paces shown are the reference (used when we
// don't yet know the athlete's fitness); per-athlete paces replace these
// once the athlete has a goal time / fitness snapshot.
function PaceZoneReference({ athletePaces }: { athletePaces?: AthletePaceTable }) {
  const zones = PACE_ZONES;
  const hasOverride = !!athletePaces && Object.keys(athletePaces).length > 0;
  return (
    <div className="pt-3 border-t border-[var(--color-divider)]">
      <div className="flex items-baseline justify-between mb-2">
        <span className="text-[9px] uppercase tracking-wider text-[var(--color-text-tertiary)] font-semibold">
          Pace reference
        </span>
        <span className="text-[9px] italic text-[var(--color-text-tertiary)]">
          {hasOverride ? "from plan's goal time / overrides" : "reference runner — personalized per athlete"}
        </span>
      </div>
      <div className="grid grid-cols-2 sm:grid-cols-3 gap-x-3 gap-y-1">
        {zones.map((z) => (
          <div
            key={z.value}
            className="flex items-baseline justify-between gap-2 text-[11px] font-mono"
            title={z.description}
          >
            <span className="text-[var(--color-text-primary)] font-semibold">
              {z.shortName}
            </span>
            <span className="text-[var(--color-text-secondary)]">
              {paceRangeLabel(z.value, undefined, undefined, athletePaces)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────

function summarizeStep(step: WorkoutStep): string {
  const dur = formatStepDuration(step.durationType, step.durationValue);
  const pace = paceLabelWithAdjustment(step.paceZone, step.paceAdjustment, step.exactPaceSecPerMile);
  const reps = step.repeats && step.repeats > 1 ? `${step.repeats} × ` : "";
  const main = `${reps}${dur} @ ${pace}`;
  if (step.recovery && (step.repeats ?? 1) > 1) {
    const rdur = formatStepDuration(step.recovery.durationType, step.recovery.durationValue);
    // paceZone is optional now (undefined = standing rest). For a standing-
    // rest recovery, summarize as "{dur} rest" rather than "{dur} @ {pace} recovery".
    if (!step.recovery.paceZone && !step.recovery.exactPaceSecPerMile) {
      return `${main}  /  ${rdur} rest`;
    }
    const rpace = paceLabelWithAdjustment(
      step.recovery.paceZone!,
      step.recovery.paceAdjustment,
      step.recovery.exactPaceSecPerMile,
    );
    return `${main}  /  ${rdur} ${rpace} recovery`;
  }
  return main;
}
