"use client";

import { useState, useMemo } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { WorkoutStepEditor } from "./workout-step-editor";
import {
  totalWorkoutMiles,
  totalWorkoutDurationMinutes,
  type WorkoutStep,
} from "./workout-helpers";

const WORKOUT_TYPES = [
  { value: "easy",        label: "Easy",        color: "#4A9E6B" },
  { value: "tempo",       label: "Tempo",       color: "#E8764A" },
  { value: "intervals",   label: "Intervals",   color: "#D4592A" },
  { value: "long_run",    label: "Long Run",    color: "#2D8A4E" },
  { value: "progression", label: "Progression", color: "#E8764A" },
  { value: "recovery",    label: "Recovery",    color: "#4A9E6B" },
  { value: "strides",     label: "Strides",     color: "#2D8A4E" },
  { value: "race",        label: "Race",        color: "#D4592A" },
];

export interface ExistingWorkout {
  id: string;
  name: string;
  workout_type: string;
  description?: string | null;
  tags?: string[] | null;
  workout_data?: { steps?: WorkoutStep[] } | null;
}

export function WorkoutTemplateForm({
  coachId,
  existingWorkout,
}: {
  coachId: string;
  existingWorkout?: ExistingWorkout | null;
}) {
  const router = useRouter();
  const supabase = createClient();

  const isEdit = !!existingWorkout;

  const [name, setName] = useState(existingWorkout?.name ?? "");
  const [workoutType, setWorkoutType] = useState(existingWorkout?.workout_type ?? "tempo");
  const [description, setDescription] = useState(existingWorkout?.description ?? "");
  const [tagsInput, setTagsInput] = useState((existingWorkout?.tags ?? []).join(", "));
  const [steps, setSteps] = useState<WorkoutStep[]>(
    (existingWorkout?.workout_data?.steps ?? []) as WorkoutStep[]
  );
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [showDetails, setShowDetails] = useState(
    !!(existingWorkout?.description || (existingWorkout?.tags ?? []).length > 0)
  );

  // Canonical totals — both account for repeats AND recovery.
  // Duration uses reference paces (one moderately-trained runner) since
  // workouts store pace zones, not absolute paces. The athlete-specific
  // duration is computed when the workout is materialized into their plan.
  const totalMiles = useMemo(() => totalWorkoutMiles(steps), [steps]);
  const totalDurationMinutes = useMemo(() => totalWorkoutDurationMinutes(steps), [steps]);

  const handleSave = async () => {
    if (!name.trim()) {
      setSaveError("Name is required");
      return;
    }
    if (steps.length === 0) {
      setSaveError("Add at least one step before saving");
      return;
    }
    setIsSaving(true);
    setSaveError(null);

    const tags = tagsInput
      .split(",")
      .map((t) => t.trim())
      .filter((t) => t.length > 0);

    // workout_data is the JSONB blob the plan-builder picker reads.
    // Schema versions:
    //   v1 — paces stored as percentages of race pace (legacy)
    //   v2 — paces stored as named zones (paceZone field)
    //   v3 — adds optional paceAdjustment per step + recovery
    const workoutData = {
      schema_version: "v3",
      name,
      steps,
      total_distance_km: totalMiles * 1.60934,
    };

    const payload = {
      coach_id: coachId,
      name,
      workout_type: workoutType,
      description: description.trim() || null,
      tags,
      workout_data: workoutData,
      estimated_distance_miles: totalMiles > 0 ? totalMiles : null,
      estimated_duration_minutes:
        totalDurationMinutes > 0 ? Math.round(totalDurationMinutes) : null,
    };

    const { error } = isEdit && existingWorkout
      ? await supabase
          .from("workout_templates")
          .update(payload)
          .eq("id", existingWorkout.id)
      : await supabase.from("workout_templates").insert(payload);

    setIsSaving(false);

    if (error) {
      setSaveError(error.message);
      return;
    }

    router.push("/coach-portal/workouts");
    router.refresh();
  };

  const handleDelete = async () => {
    if (!existingWorkout) return;
    if (!window.confirm(`Delete "${existingWorkout.name}"? This cannot be undone.`)) return;

    setIsDeleting(true);
    setSaveError(null);

    const { error } = await supabase
      .from("workout_templates")
      .delete()
      .eq("id", existingWorkout.id);

    setIsDeleting(false);

    if (error) {
      setSaveError(error.message);
      return;
    }

    router.push("/coach-portal/workouts");
    router.refresh();
  };

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      {/* Top bar */}
      <div className="flex items-center justify-between">
        <Link
          href="/coach-portal/workouts"
          className="text-xs text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] transition-colors"
        >
          ← Back to library
        </Link>
        <div className="flex items-center gap-2">
          {isEdit && (
            <button
              onClick={handleDelete}
              disabled={isDeleting || isSaving}
              className="px-3 py-1.5 text-xs text-red-600 hover:text-red-700 hover:bg-red-50 rounded-lg transition-colors disabled:opacity-50"
            >
              {isDeleting ? "Deleting..." : "Delete"}
            </button>
          )}
          <button
            onClick={handleSave}
            disabled={!name.trim() || isSaving}
            className="px-4 py-1.5 text-sm bg-[var(--color-coral)] text-white rounded-lg hover:bg-[var(--color-coral-dark)] transition-colors disabled:opacity-50"
          >
            {isSaving ? "Saving..." : isEdit ? "Save changes" : "Save template"}
          </button>
        </div>
      </div>

      {saveError && (
        <p className="text-xs text-red-600 font-mono">
          Save failed: {saveError}
        </p>
      )}

      {/* Hero: name + type pill row */}
      <div className="space-y-3">
        <input
          type="text"
          placeholder="Name this workout — e.g., 6×800m at 5K pace"
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="w-full text-2xl font-semibold border-none outline-none bg-transparent placeholder:text-[var(--color-text-tertiary)] text-[var(--color-text-primary)]"
        />
        <div className="flex flex-wrap gap-1.5">
          {WORKOUT_TYPES.map((t) => (
            <button
              key={t.value}
              onClick={() => setWorkoutType(t.value)}
              className={`px-3 py-1 text-xs rounded-full border transition-colors ${
                workoutType === t.value
                  ? "text-white font-medium"
                  : "text-[var(--color-text-secondary)] border-[var(--color-divider)] hover:border-[var(--color-text-tertiary)]"
              }`}
              style={{
                backgroundColor:
                  workoutType === t.value ? t.color : "transparent",
                borderColor:
                  workoutType === t.value ? t.color : undefined,
              }}
            >
              {t.label}
            </button>
          ))}
        </div>
      </div>

      {/* Steps editor (the meat) */}
      <div className="bg-white border border-[var(--color-divider)] rounded-xl p-5">
        <WorkoutStepEditor steps={steps} onChange={setSteps} />
      </div>

      {/* Optional details — collapsed by default to reduce noise */}
      <div className="space-y-3">
        <button
          onClick={() => setShowDetails((v) => !v)}
          className="text-[10px] uppercase tracking-wider text-[var(--color-text-tertiary)] hover:text-[var(--color-text-secondary)] font-semibold"
        >
          {showDetails ? "− Hide" : "+ Add"} description &amp; tags
        </button>

        {showDetails && (
          <div className="bg-white border border-[var(--color-divider)] rounded-xl p-5 space-y-4">
            <div className="space-y-1.5">
              <label className="text-[10px] font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
                Description
              </label>
              <textarea
                placeholder="Notes about this workout — when to use it, target effort, etc."
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={2}
                className="w-full text-sm border border-[var(--color-divider)] rounded-lg px-3 py-2 focus:outline-none focus:border-[var(--color-coral)] placeholder:text-[var(--color-text-tertiary)] resize-none"
              />
            </div>

            <div className="space-y-1.5">
              <label className="text-[10px] font-semibold uppercase tracking-wider text-[var(--color-text-tertiary)]">
                Tags <span className="text-[var(--color-text-tertiary)] normal-case">(comma-separated)</span>
              </label>
              <input
                type="text"
                placeholder="track, vo2max, threshold"
                value={tagsInput}
                onChange={(e) => setTagsInput(e.target.value)}
                className="w-full text-sm border border-[var(--color-divider)] rounded-lg px-3 py-2 focus:outline-none focus:border-[var(--color-coral)] placeholder:text-[var(--color-text-tertiary)]"
              />
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
