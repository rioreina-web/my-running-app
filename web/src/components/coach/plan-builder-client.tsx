"use client";

import { useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { WorkoutStepEditor, type WorkoutStep } from "./workout-step-editor";

interface WorkoutTemplate {
  id: string;
  name: string;
  workout_type: string;
  estimated_distance_miles?: number;
  estimated_duration_minutes?: number;
  tags?: string[];
  workout_data: Record<string, unknown>;
}

interface PlanTemplateWorkout {
  dayOfWeek: number;
  workoutTemplateId?: string;
  workoutType?: string;
  workoutData?: Record<string, unknown>;
  notes: string;
}

interface PlanTemplateWeek {
  weekNumber: number;
  theme: string;
  notes: string;
  targetMilesMin?: number;
  targetMilesMax?: number;
  workouts: PlanTemplateWorkout[];
}

const DAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const DISTANCES = ["marathon", "half_marathon", "10k", "5k"];
const DISTANCE_LABELS: Record<string, string> = {
  marathon: "Marathon",
  half_marathon: "Half Marathon",
  "10k": "10K",
  "5k": "5K",
};
const DURATIONS = [8, 10, 12, 14, 16, 18, 20];

const WORKOUT_COLORS: Record<string, string> = {
  easy: "#4A9E6B",
  tempo: "#E8764A",
  intervals: "#D4592A",
  long_run: "#2D8A4E",
  recovery: "#4A9E6B",
  race: "#D4592A",
  progression: "#E8764A",
  strides: "#2D8A4E",
  rest: "#9B9590",
};

const QUICK_TYPES = ["easy", "tempo", "intervals", "long_run", "progression", "recovery", "strides"];

const QUALITY_TYPES = new Set(["tempo", "intervals", "long_run", "progression", "race"]);

function isQualityWorkout(w: PlanTemplateWorkout): boolean {
  if (w.workoutTemplateId) return true;
  if (w.workoutType && QUALITY_TYPES.has(w.workoutType)) return true;
  return false;
}

function workoutMiles(w: PlanTemplateWorkout): number {
  const data = w.workoutData as Record<string, number> | undefined;
  if (data?.total_distance_km) return data.total_distance_km / 1.60934;
  return 0;
}

function buildBlankWeeks(count: number): PlanTemplateWeek[] {
  return Array.from({ length: count }, (_, i) => ({
    weekNumber: i + 1,
    theme: i === count - 1 ? "Race Week" : `Week ${i + 1}`,
    notes: "",
    targetMilesMin: 0,
    targetMilesMax: 0,
    workouts: Array.from({ length: 7 }, (_, d) => ({
      dayOfWeek: d,
      // workoutType undefined = unset (initial state)
      // workoutType "rest" = explicitly chosen rest day (set via picker)
      notes: "",
    })),
  }));
}

export function PlanBuilderClient({
  coachId,
  workoutTemplates,
  existingPlan,
}: {
  coachId: string;
  workoutTemplates: WorkoutTemplate[];
  existingPlan: Record<string, unknown> | null;
}) {
  const router = useRouter();
  const supabase = createClient();

  const [planType, setPlanType] = useState<"fixed" | "adaptive">(
    (existingPlan?.plan_type as "fixed" | "adaptive") ?? "fixed"
  );
  const [planName, setPlanName] = useState((existingPlan?.name as string) ?? "");
  const [targetDistance, setTargetDistance] = useState(
    (existingPlan?.target_distance as string) ?? "marathon"
  );
  const [durationWeeks, setDurationWeeks] = useState(
    (existingPlan?.duration_weeks as number) ?? 16
  );

  const [weeks, setWeeks] = useState<PlanTemplateWeek[]>(
    existingPlan
      ? (existingPlan.weeks as PlanTemplateWeek[]) ?? buildBlankWeeks(16)
      : buildBlankWeeks(16)
  );
  const [selectedWeekIdx, setSelectedWeekIdx] = useState(0);
  const [pickerDay, setPickerDay] = useState<number | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [searchText, setSearchText] = useState("");

  const selectedWeek = weeks[selectedWeekIdx];

  const getWorkout = useCallback(
    (day: number): PlanTemplateWorkout => {
      return (
        selectedWeek?.workouts.find((w) => w.dayOfWeek === day) ?? {
          dayOfWeek: day,
          // workoutType undefined means unset
          notes: "",
        }
      );
    },
    [selectedWeek]
  );

  const assignWorkout = (day: number, workout: PlanTemplateWorkout) => {
    setWeeks((prev) =>
      prev.map((week, idx) => {
        if (idx !== selectedWeekIdx) return week;
        const existing = week.workouts.findIndex((w) => w.dayOfWeek === day);
        if (existing >= 0) {
          const updated = [...week.workouts];
          updated[existing] = workout;
          return { ...week, workouts: updated };
        }
        return { ...week, workouts: [...week.workouts, workout] };
      })
    );
    setPickerDay(null);
  };

  const copyFromPreviousWeek = () => {
    if (selectedWeekIdx === 0) return;
    const prevWorkouts = weeks[selectedWeekIdx - 1].workouts;
    setWeeks((prev) =>
      prev.map((week, idx) => {
        if (idx !== selectedWeekIdx) return week;
        return {
          ...week,
          workouts: prevWorkouts.map((w) => ({ ...w })),
        };
      })
    );
  };

  const adjustDuration = (newDuration: number) => {
    setDurationWeeks(newDuration);
    if (newDuration > weeks.length) {
      const extra = buildBlankWeeks(newDuration - weeks.length).map((w) => ({
        ...w,
        weekNumber: weeks.length + w.weekNumber,
      }));
      setWeeks((prev) => [...prev, ...extra]);
    } else {
      setWeeks((prev) => prev.slice(0, newDuration));
    }
  };

  const setWeekTargetRange = (field: "targetMilesMin" | "targetMilesMax", value: number) => {
    setWeeks((prev) =>
      prev.map((week, idx) =>
        idx === selectedWeekIdx ? { ...week, [field]: value } : week
      )
    );
  };

  // Note: in adaptive mode, the smart-fill of easy days happens at subscribe
  // time (in the subscribe-to-plan edge function), not here. The template only
  // stores quality workouts + the weekly mileage range.

  const handleSave = async (publish: boolean) => {
    if (!planName.trim()) return;
    setIsSaving(true);
    setSaveError(null);

    const payload: Record<string, unknown> = {
      coach_id: coachId,
      name: planName,
      target_distance: targetDistance,
      duration_weeks: durationWeeks,
      plan_type: planType,
      weeks,
      is_published: publish,
      join_code: publish ? generateJoinCode() : null,
    };

    const { error } = existingPlan?.id
      ? await supabase
          .from("plan_templates")
          .update(payload)
          .eq("id", existingPlan.id as string)
      : await supabase.from("plan_templates").insert(payload);

    setIsSaving(false);

    if (error) {
      setSaveError(error.message);
      return;
    }

    router.push("/coach-portal/plans");
    router.refresh();
  };

  const filteredTemplates = workoutTemplates.filter(
    (t) =>
      searchText === "" ||
      t.name.toLowerCase().includes(searchText.toLowerCase()) ||
      (t.tags ?? []).some((tag) => tag.toLowerCase().includes(searchText.toLowerCase()))
  );

  return (
    <div className="flex h-[calc(100vh-80px)] gap-0 -m-4 md:-m-6">
      {/* Left: Week selector + day grid */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Plan header */}
        <div className="px-6 py-4 border-b border-[var(--color-divider)] bg-white space-y-3">
          <div className="flex items-center gap-4">
            <input
              type="text"
              placeholder="Plan name..."
              value={planName}
              onChange={(e) => setPlanName(e.target.value)}
              className="flex-1 text-lg font-semibold text-[var(--color-text-primary)] border-none outline-none bg-transparent placeholder:text-[var(--color-text-tertiary)]"
            />
            <div className="flex items-center gap-2">
              <button
                onClick={() => handleSave(false)}
                disabled={!planName.trim() || isSaving}
                className="px-3 py-1.5 text-sm border border-[var(--color-divider)] rounded-lg text-[var(--color-text-secondary)] hover:border-[var(--color-coral)] transition-colors disabled:opacity-50"
              >
                Save Draft
              </button>
              <button
                onClick={() => handleSave(true)}
                disabled={!planName.trim() || isSaving}
                className="px-3 py-1.5 text-sm bg-[var(--color-coral)] text-white rounded-lg hover:bg-[var(--color-coral-dark)] transition-colors disabled:opacity-50"
              >
                {isSaving ? "Saving..." : "Publish"}
              </button>
            </div>
          </div>

          {saveError && (
            <p className="text-xs text-red-600 font-mono">
              Save failed: {saveError}
            </p>
          )}

          <div className="flex items-center gap-4 flex-wrap">
            {/* Plan type toggle */}
            <div className="flex gap-0 rounded-lg border border-[var(--color-divider)] overflow-hidden">
              <button
                onClick={() => setPlanType("fixed")}
                className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                  planType === "fixed"
                    ? "bg-[var(--color-coral)] text-white"
                    : "text-[var(--color-text-secondary)] hover:bg-[var(--color-bg)]"
                }`}
                title="Coach plans every day explicitly"
              >
                Fixed
              </button>
              <button
                onClick={() => setPlanType("adaptive")}
                className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                  planType === "adaptive"
                    ? "bg-[var(--color-mood-positive)] text-white"
                    : "text-[var(--color-text-secondary)] hover:bg-[var(--color-bg)]"
                }`}
                title="Coach sets quality days + mileage range; easy days auto-fill per athlete"
              >
                Adaptive
              </button>
            </div>

            {/* Distance picker */}
            <div className="flex gap-1">
              {DISTANCES.map((d) => (
                <button
                  key={d}
                  onClick={() => setTargetDistance(d)}
                  className={`px-2.5 py-1 text-xs rounded-full border transition-colors ${
                    targetDistance === d
                      ? "bg-[var(--color-coral)] text-white border-[var(--color-coral)]"
                      : "border-[var(--color-divider)] text-[var(--color-text-secondary)]"
                  }`}
                >
                  {DISTANCE_LABELS[d]}
                </button>
              ))}
            </div>

            {/* Duration picker */}
            <div className="flex gap-1">
              {DURATIONS.map((w) => (
                <button
                  key={w}
                  onClick={() => adjustDuration(w)}
                  className={`px-2 py-1 text-xs rounded-md transition-colors ${
                    durationWeeks === w
                      ? "bg-[var(--color-coral)] text-white"
                      : "text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)]"
                  }`}
                >
                  {w}w
                </button>
              ))}
            </div>
          </div>
        </div>

        {/* Week selector */}
        <div className="px-4 py-2 border-b border-[var(--color-divider)] bg-[var(--color-bg)] overflow-x-auto">
          <div className="flex gap-1.5 min-w-max">
            {weeks.map((week, idx) => {
              const hasWorkouts = week.workouts.some((w) => w.workoutType !== "rest");
              return (
                <button
                  key={idx}
                  onClick={() => setSelectedWeekIdx(idx)}
                  className={`relative flex flex-col items-center justify-center w-10 h-10 text-xs rounded-lg border transition-colors ${
                    selectedWeekIdx === idx
                      ? "bg-[var(--color-coral)] text-white border-[var(--color-coral)]"
                      : "bg-white border-[var(--color-divider)] text-[var(--color-text-primary)]"
                  }`}
                >
                  <span className="font-medium">W{week.weekNumber}</span>
                  {hasWorkouts && (
                    <span
                      className={`w-1 h-1 rounded-full absolute bottom-1.5 ${
                        selectedWeekIdx === idx
                          ? "bg-white/70"
                          : "bg-[var(--color-coral)]"
                      }`}
                    />
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Week meta */}
        <div className="px-6 py-3 bg-white/60 border-b border-[var(--color-divider)] flex items-center justify-between gap-4 flex-wrap">
          <div className="flex items-center gap-3">
            <span className="text-sm font-medium text-[var(--color-text-primary)]">
              {selectedWeek?.theme ?? "Week"}
            </span>
            <span className="text-xs text-[var(--color-text-tertiary)]">
              {selectedWeek?.workouts.filter((w) => w.workoutType !== "rest").length ?? 0} workouts
            </span>
          </div>

          <div className="flex items-center gap-3">
            {/* ADAPTIVE-ONLY: Weekly mileage range */}
            {planType === "adaptive" && (
              <div className="flex items-center gap-1.5">
                <label className="text-[10px] uppercase tracking-wider text-[var(--color-text-tertiary)] font-semibold">
                  Range
                </label>
                <input
                  type="number"
                  min={0}
                  placeholder="min"
                  value={selectedWeek?.targetMilesMin || ""}
                  onChange={(e) => setWeekTargetRange("targetMilesMin", parseInt(e.target.value) || 0)}
                  className="w-12 text-center text-xs border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)] placeholder:text-[var(--color-text-tertiary)]"
                />
                <span className="text-[10px] text-[var(--color-text-tertiary)]">–</span>
                <input
                  type="number"
                  min={0}
                  placeholder="max"
                  value={selectedWeek?.targetMilesMax || ""}
                  onChange={(e) => setWeekTargetRange("targetMilesMax", parseInt(e.target.value) || 0)}
                  className="w-12 text-center text-xs border border-[var(--color-divider)] rounded px-1.5 py-1 focus:outline-none focus:border-[var(--color-coral)] placeholder:text-[var(--color-text-tertiary)]"
                />
                <span className="text-[10px] text-[var(--color-text-tertiary)]">mpw</span>
              </div>
            )}

            {/* Planned miles indicator */}
            {(() => {
              if (!selectedWeek) return null;
              const planned = selectedWeek.workouts.reduce((s, w) => s + workoutMiles(w), 0);

              if (planType === "adaptive") {
                // In adaptive mode, planned = quality miles only; color against range
                const min = selectedWeek.targetMilesMin ?? 0;
                const max = selectedWeek.targetMilesMax ?? 0;
                const hasRange = max > 0;
                let color = "text-[var(--color-text-tertiary)]";
                if (hasRange) {
                  // Quality miles should be a fraction of total range, not all of it
                  if (planned > max) color = "text-red-600";
                  else color = "text-emerald-600";
                }
                return (
                  <span className={`text-[10px] font-mono ${color}`}>
                    {planned.toFixed(1)} quality
                  </span>
                );
              }

              // Fixed mode: just show total planned miles
              return (
                <span className="text-[10px] font-mono text-[var(--color-text-tertiary)]">
                  {planned.toFixed(1)} mi
                </span>
              );
            })()}

            {selectedWeekIdx > 0 && (
              <button
                onClick={copyFromPreviousWeek}
                className="text-xs text-[var(--color-text-tertiary)] hover:text-[var(--color-coral)] transition-colors"
              >
                Copy W{selectedWeekIdx}
              </button>
            )}
          </div>
        </div>

        {/* Day grid */}
        <div className="flex-1 overflow-y-auto px-6 py-4 space-y-2">
          {planType === "adaptive" && (
            <p className="text-[10px] text-[var(--color-text-tertiary)] italic px-1 mb-1">
              Set quality workouts only — easy and recovery days are filled per athlete when they subscribe.
            </p>
          )}
          {DAYS.map((dayName, dayIdx) => {
            const workout = getWorkout(dayIdx);
            const isUnset = !workout.workoutType;
            const isRest = workout.workoutType === "rest";
            const isQuality = isQualityWorkout(workout);
            const color = WORKOUT_COLORS[workout.workoutType ?? "rest"] ?? "#9B9590";
            const miles = workoutMiles(workout);

            return (
              <button
                key={dayIdx}
                onClick={() => setPickerDay(pickerDay === dayIdx ? null : dayIdx)}
                className={`w-full flex items-center gap-4 px-4 rounded-xl border transition-all text-left ${
                  isQuality ? "py-4" : "py-2.5"
                } ${
                  pickerDay === dayIdx
                    ? "border-[var(--color-coral)] shadow-sm"
                    : isQuality
                    ? "border-[var(--color-divider)] hover:border-[var(--color-text-tertiary)]"
                    : isUnset
                    ? "border-dashed border-[var(--color-divider)] hover:border-[var(--color-text-tertiary)]"
                    : "border-transparent hover:border-[var(--color-divider)]"
                } ${
                  isUnset
                    ? "bg-transparent"
                    : isRest
                    ? "bg-white/40"
                    : isQuality
                    ? "bg-white"
                    : "bg-white/70"
                }`}
              >
                <span
                  className={`text-xs w-8 font-medium ${
                    isQuality
                      ? "text-[var(--color-text-secondary)]"
                      : "text-[var(--color-text-tertiary)]"
                  }`}
                >
                  {dayName}
                </span>
                {isUnset ? (
                  planType === "adaptive" ? (
                    <span className="text-xs text-[var(--color-text-tertiary)] italic">
                      Auto · easy run (per athlete)
                    </span>
                  ) : (
                    <span className="text-xs text-[var(--color-text-tertiary)]">Tap to add</span>
                  )
                ) : isRest ? (
                  <span className="text-xs text-[var(--color-text-tertiary)] italic">Rest</span>
                ) : (
                  <>
                    <span
                      className={`rounded-full flex-shrink-0 ${
                        isQuality ? "w-1.5 h-7" : "w-1 h-4"
                      }`}
                      style={{ backgroundColor: color }}
                    />
                    <div className="flex-1 min-w-0">
                      <p
                        className={`truncate ${
                          isQuality
                            ? "text-sm font-semibold text-[var(--color-text-primary)]"
                            : "text-xs text-[var(--color-text-secondary)]"
                        }`}
                      >
                        {(workout.workoutData as Record<string, string>)?.name ??
                          workout.workoutType?.replace("_", " ")}
                      </p>
                      {miles > 0 && (
                        <p
                          className={`font-mono ${
                            isQuality
                              ? "text-xs text-[var(--color-text-secondary)] mt-0.5"
                              : "text-[10px] text-[var(--color-text-tertiary)]"
                          }`}
                        >
                          {miles.toFixed(1)} mi
                        </p>
                      )}
                    </div>
                  </>
                )}
                <span className="ml-auto text-[var(--color-text-tertiary)] text-xs">
                  {pickerDay === dayIdx ? "✕" : "+"}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Right: Workout picker panel (shown when a day is selected) */}
      {pickerDay !== null && (
        <div className="w-80 border-l border-[var(--color-divider)] bg-white flex flex-col overflow-hidden">
          <div className="px-4 py-3 border-b border-[var(--color-divider)]">
            <p className="text-xs font-semibold text-[var(--color-text-tertiary)] uppercase tracking-wider">
              Assign — {DAYS[pickerDay]}
            </p>
          </div>

          {/* Rest option */}
          <button
            onClick={() => assignWorkout(pickerDay, { dayOfWeek: pickerDay, workoutType: "rest", notes: "" })}
            className="flex items-center gap-3 px-4 py-3 border-b border-[var(--color-divider)] hover:bg-[var(--color-bg)] transition-colors text-left"
          >
            <span className="text-lg">😴</span>
            <span className="text-sm text-[var(--color-text-secondary)]">Rest Day</span>
          </button>

          {/* Quick type buttons */}
          <div className="px-4 py-3 border-b border-[var(--color-divider)]">
            <p className="text-[10px] font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)] mb-2">
              Quick Add
            </p>
            <div className="flex flex-wrap gap-1.5">
              {QUICK_TYPES.map((type) => (
                <button
                  key={type}
                  onClick={() =>
                    assignWorkout(pickerDay, {
                      dayOfWeek: pickerDay,
                      workoutType: type,
                      notes: "",
                    })
                  }
                  className="px-2.5 py-1 text-[10px] rounded-full border border-[var(--color-divider)] hover:border-[var(--color-coral)] text-[var(--color-text-secondary)] hover:text-[var(--color-coral)] transition-colors"
                  style={{ borderColor: WORKOUT_COLORS[type] + "40" }}
                >
                  {type.replace("_", " ")}
                </button>
              ))}
            </div>
          </div>

          {/* Template search */}
          <div className="px-4 py-3 border-b border-[var(--color-divider)]">
            <p className="text-[10px] font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)] mb-2">
              From Library
            </p>
            <input
              type="text"
              placeholder="Search templates..."
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              className="w-full px-3 py-1.5 text-xs border border-[var(--color-divider)] rounded-lg focus:outline-none focus:border-[var(--color-coral)]"
            />
          </div>

          <div className="flex-1 overflow-y-auto">
            {filteredTemplates.length === 0 ? (
              <p className="text-xs text-[var(--color-text-tertiary)] text-center py-6">
                {workoutTemplates.length === 0
                  ? "No templates yet — create some in the Workout Library"
                  : "No results"}
              </p>
            ) : (
              filteredTemplates.map((template) => (
                <button
                  key={template.id}
                  onClick={() =>
                    assignWorkout(pickerDay, {
                      dayOfWeek: pickerDay,
                      workoutTemplateId: template.id,
                      workoutType: template.workout_type,
                      workoutData: template.workout_data,
                      notes: "",
                    })
                  }
                  className="w-full flex items-start gap-3 px-4 py-3 border-b border-[var(--color-divider)] hover:bg-[var(--color-bg)] transition-colors text-left"
                >
                  <span
                    className="w-1 h-full rounded-full mt-1 flex-shrink-0 self-stretch"
                    style={{
                      backgroundColor:
                        WORKOUT_COLORS[template.workout_type] ?? "#9B9590",
                      minHeight: 24,
                      width: 3,
                    }}
                  />
                  <div>
                    <p className="text-sm font-medium text-[var(--color-text-primary)]">
                      {template.name}
                    </p>
                    {template.estimated_distance_miles && (
                      <p className="text-xs text-[var(--color-text-secondary)] font-mono">
                        {template.estimated_distance_miles.toFixed(1)} mi
                      </p>
                    )}
                  </div>
                  <span className="ml-auto text-[var(--color-coral)] text-sm">+</span>
                </button>
              ))
            )}
          </div>

          {/* Workout step editor for the selected day */}
          {pickerDay !== null && getWorkout(pickerDay).workoutType !== "rest" && (
            <div className="px-4 py-3 border-t border-[var(--color-divider)]">
              <WorkoutStepEditor
                steps={((getWorkout(pickerDay).workoutData as Record<string, unknown>)?.steps as WorkoutStep[]) || []}
                onChange={(newSteps) => {
                  const workout = getWorkout(pickerDay);
                  assignWorkout(pickerDay, {
                    ...workout,
                    dayOfWeek: pickerDay,
                    workoutData: {
                      ...(workout.workoutData || {}),
                      name: (workout.workoutData as Record<string, string>)?.name || workout.workoutType?.replace("_", " "),
                      steps: newSteps,
                    },
                  });
                }}
              />
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function generateJoinCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  return Array.from({ length: 6 }, () =>
    chars[Math.floor(Math.random() * chars.length)]
  ).join("");
}
