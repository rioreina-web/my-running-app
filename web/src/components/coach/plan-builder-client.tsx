"use client";

import { useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { WorkoutStepEditor, type WorkoutStep } from "./workout-step-editor";
import { totalWorkoutMiles, totalWorkoutDurationMinutes, formatPaceSecPerMile } from "./workout-helpers";
import { PaceReferenceEditor, resolvePaceTable, type PaceAnchor } from "./pace-reference-editor";

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
const DISTANCES = ["marathon", "half_marathon", "10k", "5k", "custom"];
const DISTANCE_LABELS: Record<string, string> = {
  marathon: "Marathon",
  half_marathon: "Half Marathon",
  "10k": "10K",
  "5k": "5K",
  custom: "Custom",
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

/**
 * Translate the iOS/server `pace_reference` field (easy|marathon|half|10K|5K|mile)
 * into the web editor's `paceZone` field (easy|mp|hm|tenK|fiveK|mile). Without
 * this, plans uploaded or LLM-parsed by iOS land in the web editor with every
 * step showing the default pace zone instead of the coach's intent.
 */
const PACE_REFERENCE_TO_ZONE: Record<string, string> = {
  easy: "easy",
  marathon: "mp",
  half: "hm",
  "10K": "tenK",
  "10k": "tenK",
  "5K": "fiveK",
  "5k": "fiveK",
  mile: "mile",
};

function normalizeWeeks(weeks: PlanTemplateWeek[]): PlanTemplateWeek[] {
  return weeks.map((week) => ({
    ...week,
    workouts: (week.workouts ?? []).map((w) => {
      const data = w.workoutData as Record<string, unknown> | null | undefined;
      const steps = data?.steps as Record<string, unknown>[] | undefined;
      if (!steps || steps.length === 0) return w;
      const patched = steps.map((s) => {
        if (s.paceZone) return s;
        const ref = s.pace_reference as string | undefined;
        if (ref && PACE_REFERENCE_TO_ZONE[ref]) {
          return { ...s, paceZone: PACE_REFERENCE_TO_ZONE[ref] };
        }
        return s;
      });
      return {
        ...w,
        workoutData: { ...(data ?? {}), steps: patched },
      };
    }),
  }));
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

  const initialAnchor: PaceAnchor =
    ((existingPlan?.phase_config as Record<string, unknown> | undefined)?.paceAnchor as PaceAnchor | undefined) ?? {
      goalRaceSeconds: null,
      goalRaceDistance: null,
      overrides: {},
    };
  const [paceAnchor, setPaceAnchor] = useState<PaceAnchor>(initialAnchor);
  const paceTable = resolvePaceTable(paceAnchor, targetDistance);

  const [weeks, setWeeks] = useState<PlanTemplateWeek[]>(
    existingPlan
      ? normalizeWeeks((existingPlan.weeks as PlanTemplateWeek[]) ?? buildBlankWeeks(16))
      : buildBlankWeeks(16)
  );
  const [selectedWeekIdx, setSelectedWeekIdx] = useState(0);
  const [pickerDay, setPickerDay] = useState<number | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [searchText, setSearchText] = useState("");
  const [localTemplates, setLocalTemplates] = useState<WorkoutTemplate[]>([]);
  const [savingTemplate, setSavingTemplate] = useState(false);
  const [templateSaveMsg, setTemplateSaveMsg] = useState<string | null>(null);
  const [builderOpen, setBuilderOpen] = useState(false);
  const [builderName, setBuilderName] = useState("");
  const [builderType, setBuilderType] = useState("tempo");
  const [builderSteps, setBuilderSteps] = useState<WorkoutStep[]>([]);
  const [builderError, setBuilderError] = useState<string | null>(null);

  const openBuilder = () => {
    setBuilderName("");
    setBuilderType("tempo");
    setBuilderSteps([]);
    setBuilderError(null);
    setBuilderOpen(true);
  };

  const saveBuilderTemplate = async () => {
    if (pickerDay === null) return;
    if (!builderName.trim()) { setBuilderError("Name is required"); return; }
    if (builderSteps.length === 0) { setBuilderError("Add at least one step"); return; }
    setSavingTemplate(true);
    setBuilderError(null);

    const miles = totalWorkoutMiles(builderSteps);
    const mins = totalWorkoutDurationMinutes(builderSteps);
    const payload = {
      coach_id: coachId,
      name: builderName.trim(),
      workout_type: builderType,
      description: null,
      tags: [],
      workout_data: {
        schema_version: "v3",
        name: builderName.trim(),
        steps: builderSteps,
        total_distance_km: miles * 1.60934,
      },
      estimated_distance_miles: miles > 0 ? miles : null,
      estimated_duration_minutes: mins > 0 ? Math.round(mins) : null,
    };

    const { data: inserted, error } = await supabase
      .from("workout_templates")
      .insert(payload)
      .select()
      .single();

    setSavingTemplate(false);
    if (error) { setBuilderError(error.message); return; }
    if (inserted) {
      const tmpl = inserted as WorkoutTemplate;
      setLocalTemplates((prev) => [...prev, tmpl]);
      assignWorkout(
        pickerDay,
        {
          dayOfWeek: pickerDay,
          workoutTemplateId: tmpl.id,
          workoutType: tmpl.workout_type,
          workoutData: tmpl.workout_data,
          notes: "",
        },
        true
      );
      setBuilderOpen(false);
    }
  };

  const allTemplates = [...workoutTemplates, ...localTemplates];

  const saveCurrentAsTemplate = async () => {
    if (pickerDay === null) return;
    const workout = getWorkout(pickerDay);
    const data = (workout.workoutData as Record<string, unknown>) || {};
    const steps = (data.steps as WorkoutStep[]) || [];
    if (steps.length === 0) {
      setTemplateSaveMsg("Add at least one step before saving");
      return;
    }
    const defaultName = (data.name as string) || workout.workoutType?.replace("_", " ") || "Workout";
    const name = window.prompt("Template name:", defaultName);
    if (!name || !name.trim()) return;

    setSavingTemplate(true);
    setTemplateSaveMsg(null);
    const miles = totalWorkoutMiles(steps);
    const mins = totalWorkoutDurationMinutes(steps);
    const payload = {
      coach_id: coachId,
      name: name.trim(),
      workout_type: workout.workoutType ?? "easy",
      description: null,
      tags: [],
      workout_data: {
        schema_version: "v3",
        name: name.trim(),
        steps,
        total_distance_km: miles * 1.60934,
      },
      estimated_distance_miles: miles > 0 ? miles : null,
      estimated_duration_minutes: mins > 0 ? Math.round(mins) : null,
    };

    const { data: inserted, error } = await supabase
      .from("workout_templates")
      .insert(payload)
      .select()
      .single();

    setSavingTemplate(false);
    if (error) {
      setTemplateSaveMsg("Error: " + error.message);
      return;
    }
    if (inserted) {
      setLocalTemplates((prev) => [...prev, inserted as WorkoutTemplate]);
      setTemplateSaveMsg("Saved to library");
      setTimeout(() => setTemplateSaveMsg(null), 2500);
    }
  };

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

  const assignWorkout = (day: number, workout: PlanTemplateWorkout, closePicker = true) => {
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
    if (closePicker) setPickerDay(null);
  };

  /** Clears whatever is assigned to a day — reverts it to the "Tap to add"
   *  unset state. Different from assigning rest: unset days can be re-filled
   *  by adaptive plans, rest days are explicit. */
  const removeWorkout = (day: number) => {
    setWeeks((prev) =>
      prev.map((week, idx) => {
        if (idx !== selectedWeekIdx) return week;
        return {
          ...week,
          workouts: week.workouts.filter((w) => w.dayOfWeek !== day),
        };
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
    // Force-blur the focused element + yield a tick before reading state.
    //
    // Inputs in the right-panel step editor (NumberCell, duration text)
    // commit on blur, not on every keystroke — see the comment in
    // workout-step-editor.tsx NumberCell. If the user types "10" into a
    // reps field and clicks Save Draft directly, the click handler races
    // the blur event: the blur queues a setWeeks() update, but handleSave
    // reads `weeks` synchronously before React flushes the update. Result:
    // we serialize stale state and the user's last edit is lost.
    //
    // Forcing blur here, then yielding via setTimeout(0), gives the queued
    // state update one microtask to flush before we touch `weeks`.
    if (typeof document !== "undefined") {
      (document.activeElement as HTMLElement | null)?.blur?.();
      await new Promise((resolve) => setTimeout(resolve, 0));
    }

    if (!planName.trim()) return;
    setIsSaving(true);
    setSaveError(null);

    const existingPhaseConfig =
      (existingPlan?.phase_config as Record<string, unknown> | undefined) ?? {};
    const payload: Record<string, unknown> = {
      coach_id: coachId,
      name: planName,
      target_distance: targetDistance,
      duration_weeks: durationWeeks,
      plan_type: planType,
      weeks,
      is_published: publish,
      join_code: publish ? generateJoinCode() : null,
      phase_config: { ...existingPhaseConfig, paceAnchor },
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

  const filteredTemplates = allTemplates.filter(
    (t) =>
      searchText === "" ||
      t.name.toLowerCase().includes(searchText.toLowerCase()) ||
      (t.tags ?? []).some((tag) => tag.toLowerCase().includes(searchText.toLowerCase()))
  );

  return (
    <div className="flex h-[calc(100vh-80px)] gap-0 -m-4 md:-m-6 bg-bg-base">
      {/* Left: Week selector + day grid */}
      <div className="flex-1 flex flex-col overflow-hidden">
        {/* Plan header — editorial title block.
            Sits on warm paper (bg-base), with elevated cream as its own surface.
            Plan name uses Playfair Display for editorial weight; metadata
            (distance, weeks, pace ref) reads as a quiet kicker beneath. */}
        <div className="px-6 pt-6 pb-5 border-b border-divider bg-bg-elevated space-y-4">
          <div className="flex items-start gap-6">
            <div className="flex-1 min-w-0">
              <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary mb-1">
                {existingPlan?.id ? "Editing plan" : "New plan"}
              </p>
              <input
                type="text"
                placeholder="Name this plan"
                value={planName}
                onChange={(e) => setPlanName(e.target.value)}
                className="w-full font-display text-3xl tracking-tight text-text-primary border-none outline-none bg-transparent placeholder:text-text-tertiary/70 placeholder:font-display placeholder:italic"
              />
            </div>
            <div className="flex items-center gap-2 pt-5 flex-shrink-0">
              <button
                onClick={() => handleSave(false)}
                disabled={!planName.trim() || isSaving}
                className="px-3.5 py-1.5 text-sm border border-divider rounded-lg text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                Save draft
              </button>
              <button
                onClick={() => handleSave(true)}
                disabled={!planName.trim() || isSaving}
                className="px-3.5 py-1.5 text-sm font-medium bg-coral text-white rounded-lg hover:bg-coral-dark transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {isSaving ? "Saving…" : "Publish"}
              </button>
            </div>
          </div>

          {saveError && (
            <p className="text-xs font-mono text-[var(--color-danger)]">
              Save failed: {saveError}
            </p>
          )}

          {/* Configuration row — distance, length, type. Reads left to right
              like a sentence: "{distance} · {N} weeks · {fixed|adaptive}." */}
          <div className="flex items-center gap-x-5 gap-y-3 flex-wrap">
            {/* Distance picker — race target reads first because it's the
                anchor for every pace in the plan. */}
            <div className="flex items-center gap-2 flex-wrap">
              <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                Race
              </span>
              <div className="flex items-center gap-1 flex-wrap">
                {DISTANCES.map((d) => {
                  const isCustom = d === "custom";
                  const isFixedKnown = !isCustom && targetDistance === d;
                  const isCustomSelected = isCustom && !["marathon", "half_marathon", "10k", "5k"].includes(targetDistance);
                  const selected = isFixedKnown || isCustomSelected;
                  return (
                    <button
                      key={d}
                      onClick={() => setTargetDistance(isCustom ? "" : d)}
                      className={`px-3 py-1 text-xs rounded-full transition-colors ${
                        selected
                          ? "bg-coral text-white"
                          : "text-text-secondary hover:text-text-primary hover:bg-bg-base"
                      }`}
                    >
                      {DISTANCE_LABELS[d]}
                    </button>
                  );
                })}
                {!["marathon", "half_marathon", "10k", "5k"].includes(targetDistance) && (
                  <input
                    type="text"
                    placeholder="e.g., 50K"
                    value={targetDistance}
                    onChange={(e) => setTargetDistance(e.target.value)}
                    className="ml-1 px-2 py-1 text-xs border border-divider rounded-md focus:outline-none focus:border-coral w-20"
                  />
                )}
              </div>
            </div>

            {/* Duration — editorial number, underline-only, with the unit
                set after it like running prose ("16 weeks"). */}
            <div className="flex items-baseline gap-2">
              <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                Length
              </span>
              <input
                type="number"
                min={1}
                max={24}
                value={durationWeeks}
                onChange={(e) => {
                  const n = parseInt(e.target.value, 10);
                  if (!isNaN(n) && n >= 1 && n <= 24) adjustDuration(n);
                }}
                className="w-12 font-display text-xl text-text-primary border-b border-divider bg-transparent focus:outline-none focus:border-coral text-center tabular-nums"
              />
              <span className="text-xs text-text-secondary">weeks</span>
            </div>

            {/* Plan type — verbs the coach reads as a setting, not a tab.
                Quiet pill group; the active one earns the color. */}
            <div className="flex items-center gap-2 ml-auto">
              <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                Mode
              </span>
              <div className="flex gap-0 rounded-full border border-divider overflow-hidden bg-bg-base">
                <button
                  onClick={() => setPlanType("fixed")}
                  className={`px-3 py-1 text-xs font-medium transition-colors ${
                    planType === "fixed"
                      ? "bg-text-primary text-white"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                  title="Coach plans every day explicitly"
                >
                  Fixed
                </button>
                <button
                  onClick={() => setPlanType("adaptive")}
                  className={`px-3 py-1 text-xs font-medium transition-colors ${
                    planType === "adaptive"
                      ? "bg-[var(--color-mood-positive)] text-white"
                      : "text-text-secondary hover:text-text-primary"
                  }`}
                  title="Coach sets quality days + mileage range; easy days auto-fill per athlete"
                >
                  Adaptive
                </button>
              </div>
            </div>
          </div>

          {/* Pace reference — race effort is folded into the expanded zone table */}
          <PaceReferenceEditor
            anchor={paceAnchor}
            onChange={setPaceAnchor}
            planDistance={targetDistance}
          />
        </div>

        {/* Week selector — pill row reading like tabs in a magazine TOC.
            Active week earns coral; touched weeks earn a quiet dot. */}
        <div className="px-6 py-3 border-b border-divider bg-bg-base overflow-x-auto">
          <div className="flex gap-1.5 min-w-max">
            {weeks.map((week, idx) => {
              const hasWorkouts = week.workouts.some((w) => w.workoutType !== "rest");
              const active = selectedWeekIdx === idx;
              return (
                <button
                  key={idx}
                  onClick={() => setSelectedWeekIdx(idx)}
                  className={`relative flex flex-col items-center justify-center w-11 h-11 rounded-lg transition-colors ${
                    active
                      ? "bg-coral text-white"
                      : "text-text-secondary hover:text-text-primary hover:bg-bg-elevated"
                  }`}
                  aria-label={`Week ${week.weekNumber}`}
                >
                  <span className="font-mono text-[10px] uppercase tracking-wider opacity-70 leading-none">
                    W
                  </span>
                  <span className="font-display text-base leading-tight tabular-nums">
                    {week.weekNumber}
                  </span>
                  {hasWorkouts && (
                    <span
                      className={`w-1 h-1 rounded-full absolute bottom-1 ${
                        active ? "bg-white/70" : "bg-coral"
                      }`}
                    />
                  )}
                </button>
              );
            })}
          </div>
        </div>

        {/* Week meta — like a chapter header in the plan. Week theme in
            editorial display, week stats in a quiet kicker, planned vs.
            range mileage on the right. */}
        <div className="px-6 py-4 bg-bg-elevated border-b border-divider flex items-center justify-between gap-6 flex-wrap">
          <div>
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
              Week {selectedWeek?.weekNumber ?? ""}
            </p>
            <div className="flex items-baseline gap-3 mt-0.5">
              <h2 className="font-display text-xl text-text-primary leading-none">
                {selectedWeek?.theme ?? "Untitled"}
              </h2>
              <span className="text-xs text-text-secondary">
                {selectedWeek?.workouts.filter((w) => w.workoutType !== "rest").length ?? 0}{" "}
                {(selectedWeek?.workouts.filter((w) => w.workoutType !== "rest").length ?? 0) === 1 ? "workout" : "workouts"}
              </span>
            </div>
          </div>

          <div className="flex items-center gap-5">
            {/* ADAPTIVE-ONLY: Weekly mileage range — coach sets the band,
                runner's easy days fill it. */}
            {planType === "adaptive" && (
              <div className="flex items-baseline gap-2">
                <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                  Range
                </span>
                <div className="flex items-baseline gap-1 font-mono text-sm text-text-primary">
                  <input
                    type="number"
                    min={0}
                    placeholder="min"
                    value={selectedWeek?.targetMilesMin || ""}
                    onChange={(e) => setWeekTargetRange("targetMilesMin", parseInt(e.target.value) || 0)}
                    className="w-10 text-center bg-transparent border-b border-divider focus:outline-none focus:border-coral placeholder:text-text-tertiary/60 placeholder:text-[10px] placeholder:italic tabular-nums"
                  />
                  <span className="text-text-tertiary">to</span>
                  <input
                    type="number"
                    min={0}
                    placeholder="max"
                    value={selectedWeek?.targetMilesMax || ""}
                    onChange={(e) => setWeekTargetRange("targetMilesMax", parseInt(e.target.value) || 0)}
                    className="w-10 text-center bg-transparent border-b border-divider focus:outline-none focus:border-coral placeholder:text-text-tertiary/60 placeholder:text-[10px] placeholder:italic tabular-nums"
                  />
                </div>
                <span className="text-[10px] text-text-tertiary">mpw</span>
              </div>
            )}

            {/* Planned mileage — the headline number on this row. */}
            {(() => {
              if (!selectedWeek) return null;
              const planned = selectedWeek.workouts.reduce((s, w) => s + workoutMiles(w), 0);

              if (planType === "adaptive") {
                // In adaptive mode, planned = quality miles only; color against range
                const max = selectedWeek.targetMilesMax ?? 0;
                const hasRange = max > 0;
                let color = "text-text-tertiary";
                if (hasRange) {
                  if (planned > max) color = "text-[var(--color-danger)]";
                  else color = "text-[var(--color-success)]";
                }
                return (
                  <div className="text-right">
                    <span className={`font-display text-xl tabular-nums ${color}`}>
                      {planned.toFixed(1)}
                    </span>
                    <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary ml-1.5">
                      quality
                    </span>
                  </div>
                );
              }

              return (
                <div className="text-right">
                  <span className="font-display text-xl tabular-nums text-text-primary">
                    {planned.toFixed(1)}
                  </span>
                  <span className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary ml-1.5">
                    mi
                  </span>
                </div>
              );
            })()}

            {selectedWeekIdx > 0 && (
              <button
                onClick={copyFromPreviousWeek}
                className="text-xs text-text-tertiary hover:text-coral transition-colors underline-offset-4 hover:underline"
              >
                Copy from W{selectedWeekIdx}
              </button>
            )}
          </div>
        </div>

        {/* Day grid — the week as seven rows. Each row is the workout in
            plain prose: name, miles, pace. Quality days earn a confident
            white card and a thicker color rule; easy/rest days stay quiet.
            Empty days use the empty-state pattern (eyebrow + nudge), never
            an em-dash — see CLAUDE.md hard rules. */}
        <div className="flex-1 overflow-y-auto px-6 py-5 space-y-1.5">
          {planType === "adaptive" && (
            <p className="coach-note text-sm mb-4">
              Mark the quality days. Easy and recovery fill in once an athlete
              subscribes.
            </p>
          )}
          {DAYS.map((dayName, dayIdx) => {
            const workout = getWorkout(dayIdx);
            const isUnset = !workout.workoutType;
            const isRest = workout.workoutType === "rest";
            const isQuality = isQualityWorkout(workout);
            const color = WORKOUT_COLORS[workout.workoutType ?? "rest"] ?? "#9B9590";
            const miles = workoutMiles(workout);
            const isPickerOpen = pickerDay === dayIdx;

            return (
              <button
                key={dayIdx}
                onClick={() => setPickerDay(pickerDay === dayIdx ? null : dayIdx)}
                className={`group w-full flex items-stretch gap-4 px-4 rounded-xl text-left transition-all ${
                  isQuality ? "py-3.5" : "py-2.5"
                } ${
                  isPickerOpen
                    ? "bg-bg-card ring-1 ring-coral/40 shadow-[0_2px_8px_rgba(0,0,0,0.04)]"
                    : isQuality
                    ? "bg-bg-card hover:bg-white border border-divider-soft"
                    : isUnset
                    ? "bg-transparent hover:bg-bg-elevated border border-dashed border-divider"
                    : isRest
                    ? "bg-transparent hover:bg-bg-elevated"
                    : "bg-bg-elevated hover:bg-bg-card"
                }`}
              >
                {/* Day label — uppercase mono kicker, matches the rest of
                    the editorial typography. */}
                <span
                  className={`font-mono text-[10px] uppercase tracking-[0.18em] w-8 pt-1 flex-shrink-0 ${
                    isQuality ? "text-text-secondary" : "text-text-tertiary"
                  }`}
                >
                  {dayName}
                </span>

                {/* Color rule — present only for actual workouts. Thicker
                    on quality days so the eye finds them at a glance. */}
                {!isUnset && !isRest && (
                  <span
                    className={`rounded-full flex-shrink-0 self-center ${
                      isQuality ? "w-1 h-10" : "w-0.5 h-5"
                    }`}
                    style={{ backgroundColor: color }}
                  />
                )}

                <div className="flex-1 min-w-0 flex items-center">
                  {isUnset ? (
                    planType === "adaptive" ? (
                      <span className="text-sm italic text-text-tertiary">
                        Auto · easy run, sized per athlete
                      </span>
                    ) : (
                      <span className="text-sm text-text-tertiary group-hover:text-text-secondary transition-colors">
                        Add a workout
                      </span>
                    )
                  ) : isRest ? (
                    <span className="text-sm italic text-text-tertiary">
                      Rest
                    </span>
                  ) : (
                    <div className="flex-1 min-w-0 flex items-baseline justify-between gap-3">
                      <p
                        className={`truncate ${
                          isQuality
                            ? "font-display text-lg text-text-primary leading-tight"
                            : "text-sm text-text-secondary"
                        }`}
                      >
                        {(workout.workoutData as Record<string, string>)?.name ??
                          workout.workoutType?.replace("_", " ")}
                      </p>
                      {miles > 0 && (
                        <p
                          className={`font-mono tabular-nums flex-shrink-0 ${
                            isQuality
                              ? "text-sm text-text-secondary"
                              : "text-xs text-text-tertiary"
                          }`}
                        >
                          {miles.toFixed(1)} mi
                        </p>
                      )}
                    </div>
                  )}
                </div>

                {/* Affordance — quiet plus, becomes a close glyph when this
                    day's picker is open. */}
                <span
                  className={`flex-shrink-0 self-center font-mono text-base transition-colors ${
                    isPickerOpen
                      ? "text-coral"
                      : "text-text-tertiary/60 group-hover:text-text-secondary"
                  }`}
                  aria-hidden="true"
                >
                  {isPickerOpen ? "×" : "+"}
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {/* Right: Workout picker panel (shown when a day is selected) */}
      {pickerDay !== null && (() => {
        const current = getWorkout(pickerDay);
        const hasAssignment = !!current.workoutType;
        const isActiveWorkout = hasAssignment && current.workoutType !== "rest";
        return (
        <div className="w-80 border-l border-divider bg-bg-card flex flex-col overflow-hidden">
          <div className="flex-shrink-0 px-5 py-4 border-b border-divider flex items-baseline justify-between">
            <div>
              <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                {hasAssignment ? "Edit" : "Assign"}
              </p>
              <p className="font-display text-lg text-text-primary leading-tight mt-0.5">
                {DAYS[pickerDay]}
              </p>
            </div>
            {hasAssignment && (
              <button
                type="button"
                onClick={() => removeWorkout(pickerDay)}
                className="text-[10px] uppercase tracking-wider font-medium text-text-tertiary hover:text-[var(--color-danger)] transition-colors"
                title="Clear this day (reverts to unset / auto-fill)"
              >
                Remove
              </button>
            )}
          </div>

          {/* Scrollable content — everything below the header scrolls as
              one unit so a long step editor can't clip the library below. */}
          <div className="flex-1 overflow-y-auto">

          {/* Inline step editor — shown first when a workout is already
              assigned so editing is the primary affordance. */}
          {isActiveWorkout && (
            <div className="px-5 py-4 border-b border-divider">
              <div className="flex items-center justify-between mb-3">
                <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                  Steps
                </p>
                <button
                  type="button"
                  onClick={saveCurrentAsTemplate}
                  disabled={savingTemplate}
                  className="px-2.5 py-1 text-[10px] font-medium rounded-full border border-coral text-coral hover:bg-coral hover:text-white transition-colors disabled:opacity-50"
                >
                  {savingTemplate ? "Saving…" : "Save to library"}
                </button>
              </div>
              {templateSaveMsg && (
                <p className="text-[10px] text-text-secondary mb-2">{templateSaveMsg}</p>
              )}
              <WorkoutStepEditor
                steps={((current.workoutData as Record<string, unknown>)?.steps as WorkoutStep[]) || []}
                athletePaces={paceTable}
                onChange={(newSteps) => {
                  assignWorkout(
                    pickerDay,
                    {
                      ...current,
                      dayOfWeek: pickerDay,
                      workoutData: {
                        ...(current.workoutData || {}),
                        name: (current.workoutData as Record<string, string>)?.name || current.workoutType?.replace("_", " "),
                        steps: newSteps,
                      },
                    },
                    false
                  );
                }}
              />
            </div>
          )}

          {/* Rest option */}
          <button
            onClick={() => assignWorkout(pickerDay, { dayOfWeek: pickerDay, workoutType: "rest", notes: "" })}
            className="flex items-center gap-3 px-5 py-3 border-b border-divider hover:bg-bg-elevated transition-colors text-left w-full"
          >
            <span
              className="w-0.5 h-5 rounded-full flex-shrink-0"
              style={{ backgroundColor: WORKOUT_COLORS.rest }}
            />
            <span className="text-sm italic text-text-secondary">
              {hasAssignment ? "Replace with rest" : "Rest day"}
            </span>
          </button>

          {/* Build a new workout */}
          <div className="px-5 py-4 border-b border-divider">
            <button
              type="button"
              onClick={openBuilder}
              className="w-full px-3 py-2 text-sm font-medium bg-coral text-white rounded-lg hover:bg-coral-dark transition-colors"
            >
              {hasAssignment ? "Replace with a new workout" : "Build a new workout"}
            </button>
          </div>

          {/* Template library */}
          <div className="px-5 py-4 border-b border-divider">
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary mb-2">
              {hasAssignment ? "Replace from library" : "From library"}
            </p>
            <input
              type="text"
              placeholder="Search workouts"
              value={searchText}
              onChange={(e) => setSearchText(e.target.value)}
              className="w-full px-3 py-2 text-sm border border-divider rounded-lg bg-bg-elevated focus:outline-none focus:border-coral focus:bg-bg-card transition-colors placeholder:text-text-tertiary/70"
            />
          </div>

          <div>
            {filteredTemplates.length === 0 ? (
              <div className="px-5 py-8 text-center">
                <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary mb-2">
                  Empty library
                </p>
                <p className="text-sm text-text-secondary leading-relaxed">
                  {allTemplates.length === 0
                    ? "Build a workout above. It'll be ready next time."
                    : "Nothing matches that search."}
                </p>
              </div>
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
                  className="w-full flex items-start gap-3 px-5 py-3 border-b border-divider hover:bg-bg-elevated transition-colors text-left"
                >
                  <span
                    className="w-1 rounded-full mt-1 flex-shrink-0 self-stretch"
                    style={{
                      backgroundColor:
                        WORKOUT_COLORS[template.workout_type] ?? "#9B9590",
                      minHeight: 24,
                    }}
                  />
                  <div className="min-w-0">
                    <p className="text-sm font-medium text-text-primary truncate">
                      {template.name}
                    </p>
                    {template.estimated_distance_miles && (
                      <p className="text-xs text-text-secondary font-mono tabular-nums mt-0.5">
                        {template.estimated_distance_miles.toFixed(1)} mi
                      </p>
                    )}
                  </div>
                  <span className="ml-auto text-coral text-sm">+</span>
                </button>
              ))
            )}
          </div>
          </div>
        </div>
        );
      })()}

      {/* Workout Builder Modal — editorial dialog. Title in Playfair,
          name field becomes the headline as the coach types. */}
      {builderOpen && (
        <div
          className="fixed inset-0 z-50 bg-text-primary/40 flex items-center justify-center p-4 backdrop-blur-[2px]"
          onClick={() => setBuilderOpen(false)}
        >
          <div
            className="bg-bg-card rounded-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto p-7 space-y-5 shadow-[0_20px_60px_rgba(0,0,0,0.15)]"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between">
              <div>
                <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                  Workout
                </p>
                <h2 className="font-display text-2xl text-text-primary mt-0.5 leading-none">
                  New
                </h2>
              </div>
              <button
                onClick={() => setBuilderOpen(false)}
                className="text-text-tertiary hover:text-text-primary text-2xl leading-none -mt-1"
                aria-label="Close"
              >
                ×
              </button>
            </div>

            <input
              type="text"
              placeholder="6×800m at 5K pace"
              value={builderName}
              onChange={(e) => setBuilderName(e.target.value)}
              className="w-full font-display text-2xl text-text-primary border-b border-divider pb-2 outline-none bg-transparent placeholder:text-text-tertiary/60 placeholder:italic focus:border-coral transition-colors"
            />

            <div className="flex flex-wrap gap-1.5">
              {QUICK_TYPES.map((type) => (
                <button
                  key={type}
                  onClick={() => setBuilderType(type)}
                  className={`px-3 py-1 text-xs rounded-full border transition-colors ${
                    builderType === type
                      ? "text-white font-medium"
                      : "text-text-secondary border-divider hover:border-text-tertiary"
                  }`}
                  style={{
                    backgroundColor: builderType === type ? WORKOUT_COLORS[type] : "transparent",
                    borderColor: builderType === type ? WORKOUT_COLORS[type] : undefined,
                  }}
                >
                  {type.replace("_", " ")}
                </button>
              ))}
            </div>

            <div className="border border-divider rounded-xl p-4 bg-bg-elevated">
              <WorkoutStepEditor steps={builderSteps} onChange={setBuilderSteps} athletePaces={paceTable} />
            </div>

            {builderError && (
              <p className="text-xs text-[var(--color-danger)]">{builderError}</p>
            )}

            <div className="flex items-center justify-end gap-3 pt-2">
              <button
                onClick={() => setBuilderOpen(false)}
                className="px-4 py-1.5 text-sm text-text-secondary hover:text-text-primary transition-colors"
              >
                Cancel
              </button>
              <button
                onClick={saveBuilderTemplate}
                disabled={savingTemplate}
                className="px-4 py-1.5 text-sm font-medium bg-coral text-white rounded-lg hover:bg-coral-dark transition-colors disabled:opacity-50"
              >
                {savingTemplate ? "Saving…" : "Save & assign"}
              </button>
            </div>
          </div>
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

