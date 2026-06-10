"use client";

import { useState, useMemo, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { WorkoutStepEditor } from "./workout-step-editor";
import {
  estimatedWorkoutMiles,
  totalWorkoutDurationMinutes,
  workoutHasTimeBasedSegment,
  REFERENCE_RUNNER_LABEL,
  type WorkoutStep,
} from "./workout-helpers";
import { PaceReferenceEditor, resolvePaceTable, type PaceAnchor } from "./pace-reference-editor";

// Migrate the deprecated `longRun` pace zone to `easy` on load. The LR
// band (85–75% MP) was retired May 2026 because it overlapped Moderate
// and Easy. Old workouts and drafts may still reference it; this keeps
// them rendering correctly until the next save naturally rewrites them.
function migrateSteps(steps: WorkoutStep[] | undefined): WorkoutStep[] {
  if (!steps || steps.length === 0) return [];
  return steps.map((s) => {
    const migrated: WorkoutStep = { ...s };
    if ((s.paceZone as string) === "longRun") {
      migrated.paceZone = "easy";
    }
    if (s.recovery && (s.recovery.paceZone as string) === "longRun") {
      migrated.recovery = { ...s.recovery, paceZone: "easy" };
    }
    return migrated;
  });
}

// Format the running total minutes for the top-bar chip. Matches the
// workout-template-card's formatter so the editor and library show the
// same number for the same workout.
function formatTotalDuration(minutes: number): string {
  const rounded = Math.round(minutes);
  if (rounded >= 60) {
    const h = Math.floor(rounded / 60);
    const m = rounded % 60;
    return m > 0 ? `${h}h ${m}m` : `${h}h`;
  }
  return `${rounded} min`;
}

function formatTotalMiles(miles: number): string {
  if (Number.isInteger(miles)) return `${miles}`;
  return miles.toFixed(1);
}

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

  // Draft autosave — keyed by coach + (workout id | 'new'). Survives nav
  // and tab close but not multi-device editing. Cleared on successful save
  // or delete. We deliberately stash in localStorage rather than a DB
  // drafts table to avoid a migration; revisit if cross-device matters.
  const draftKey = `wt-draft:${coachId}:${existingWorkout?.id ?? "new"}`;

  // Read once on mount. We only restore when the persisted snapshot is
  // newer than the existingWorkout we got from the server — otherwise an
  // edit that's been saved server-side would be silently overwritten by
  // a stale draft.
  interface DraftSnapshot {
    name: string;
    workoutType: string;
    description: string;
    tagsInput: string;
    steps: WorkoutStep[];
    savedAt: number;
  }
  const initialDraft: DraftSnapshot | null = (() => {
    if (typeof window === "undefined") return null;
    try {
      const raw = window.localStorage.getItem(draftKey);
      if (!raw) return null;
      return JSON.parse(raw) as DraftSnapshot;
    } catch {
      return null;
    }
  })();

  const [name, setName] = useState(initialDraft?.name ?? existingWorkout?.name ?? "");
  const [workoutType, setWorkoutType] = useState(
    initialDraft?.workoutType ?? existingWorkout?.workout_type ?? "tempo"
  );
  const [description, setDescription] = useState(
    initialDraft?.description ?? existingWorkout?.description ?? ""
  );
  const [tagsInput, setTagsInput] = useState(
    initialDraft?.tagsInput ?? (existingWorkout?.tags ?? []).join(", ")
  );
  const [steps, setSteps] = useState<WorkoutStep[]>(
    migrateSteps(
      (initialDraft?.steps ?? existingWorkout?.workout_data?.steps ?? []) as WorkoutStep[],
    ),
  );
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);
  const [showDetails, setShowDetails] = useState(
    !!(
      initialDraft?.description ||
      (initialDraft?.tagsInput?.trim().length ?? 0) > 0 ||
      existingWorkout?.description ||
      (existingWorkout?.tags ?? []).length > 0
    )
  );
  // Whether the form was populated from a persisted draft on mount. Static
  // for the lifetime of the form — once we've shown the badge, it stays as a
  // subtle reminder that you're editing recovered work.
  const draftRestored = !!initialDraft;
  const [draftSavedAt, setDraftSavedAt] = useState<number | null>(
    initialDraft?.savedAt ?? null
  );

  // "Preview as" pace anchor — the coach picks a goal race time so the
  // pace dropdowns, per-row ranges, and totals show real numbers instead
  // of the 7:30 reference runner. Persisted per coach so the choice
  // sticks across templates. The template itself stays athlete-agnostic
  // (this never gets serialized into workout_data).
  const previewAnchorKey = `wt-preview-paces:${coachId}`;
  const [previewAnchor, setPreviewAnchor] = useState<PaceAnchor>(() => {
    if (typeof window === "undefined") return {};
    try {
      const raw = window.localStorage.getItem(previewAnchorKey);
      if (!raw) return {};
      return JSON.parse(raw) as PaceAnchor;
    } catch {
      return {};
    }
  });
  // The preview anchor isn't tied to any single plan distance — let the
  // anchor self-describe its goal distance, defaulting to marathon when
  // the coach hasn't picked one. Matches PaceReferenceEditor's expectation.
  const previewDistance = previewAnchor.goalRaceDistance ?? "marathon";
  const previewPaceTable = useMemo(
    () => resolvePaceTable(previewAnchor, previewDistance),
    [previewAnchor, previewDistance],
  );
  // Only treat the table as "real" once the coach actually set a goal —
  // otherwise we'd be silently rendering reference paces as if they were
  // calibrated. The editor still receives the table (for adjustment math),
  // but the source label flips between "reference runner" and "from 3:00 marathon".
  const hasCalibratedPaces =
    !!previewAnchor.goalRaceSeconds && previewAnchor.goalRaceSeconds > 0;

  useEffect(() => {
    if (typeof window === "undefined") return;
    try {
      window.localStorage.setItem(previewAnchorKey, JSON.stringify(previewAnchor));
    } catch {
      /* noop */
    }
  }, [previewAnchor, previewAnchorKey]);

  // Debounced write-through to localStorage. Skips the first render so we
  // don't immediately re-persist what we just hydrated from.
  const skipNextWrite = useRef(true);
  useEffect(() => {
    if (skipNextWrite.current) {
      skipNextWrite.current = false;
      return;
    }
    if (typeof window === "undefined") return;
    const handle = window.setTimeout(() => {
      // If the user has cleared the form back to empty, drop the draft
      // entirely rather than persisting an empty snapshot.
      const isEmpty =
        !name.trim() &&
        steps.length === 0 &&
        !description.trim() &&
        !tagsInput.trim();
      if (isEmpty) {
        window.localStorage.removeItem(draftKey);
        setDraftSavedAt(null);
        return;
      }
      const snapshot: DraftSnapshot = {
        name,
        workoutType,
        description,
        tagsInput,
        steps,
        savedAt: Date.now(),
      };
      try {
        window.localStorage.setItem(draftKey, JSON.stringify(snapshot));
        setDraftSavedAt(snapshot.savedAt);
      } catch {
        // localStorage quota or disabled — fail silently; the form still works.
      }
    }, 500);
    return () => window.clearTimeout(handle);
  }, [name, workoutType, description, tagsInput, steps, draftKey]);

  function clearDraft() {
    if (typeof window === "undefined") return;
    try {
      window.localStorage.removeItem(draftKey);
    } catch {
      /* noop */
    }
  }

  // Canonical totals — both account for repeats AND recovery.
  // Distance estimation now folds in time-based segments (fartleks etc.)
  // by multiplying pace × time. When `previewPaceTable` is set, paces
  // resolve to the coach's preview goal; otherwise the reference runner
  // is used. Either way the editor stays athlete-agnostic — the saved
  // `estimated_distance_miles` reflects the preview context.
  const totalMiles = useMemo(
    () => estimatedWorkoutMiles(steps, previewPaceTable),
    [steps, previewPaceTable],
  );
  const totalDurationMinutes = useMemo(
    () => totalWorkoutDurationMinutes(steps, previewPaceTable),
    [steps, previewPaceTable],
  );
  const hasTimeBasedSegment = useMemo(() => workoutHasTimeBasedSegment(steps), [steps]);

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

    // Persisted estimates are computed against the REFERENCE runner so
    // every coach sees the same number on a given template, regardless of
    // their preview anchor. The coach's preview affects the chip in the
    // editor (helps them sanity-check) but never bleeds into the saved row.
    const persistedMiles = estimatedWorkoutMiles(steps, undefined);
    const persistedMinutes = totalWorkoutDurationMinutes(steps, undefined);

    // workout_data is the JSONB blob the plan-builder picker reads.
    // Schema versions:
    //   v1 — paces stored as percentages of race pace (legacy)
    //   v2 — paces stored as named zones (paceZone field)
    //   v3 — adds optional paceAdjustment per step + recovery
    const workoutData = {
      schema_version: "v3",
      name,
      steps,
      total_distance_km: persistedMiles * 1.60934,
    };

    const payload = {
      coach_id: coachId,
      name,
      workout_type: workoutType,
      description: description.trim() || null,
      tags,
      workout_data: workoutData,
      estimated_distance_miles: persistedMiles > 0 ? persistedMiles : null,
      estimated_duration_minutes:
        persistedMinutes > 0 ? Math.round(persistedMinutes) : null,
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

    clearDraft();
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

    clearDraft();
    router.push("/coach-portal/workouts");
    router.refresh();
  };

  return (
    <div className="max-w-3xl mx-auto space-y-6">
      {/* Top bar */}
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <Link
          href="/coach-portal/workouts"
          className="text-xs text-[var(--color-text-tertiary)] hover:text-[var(--color-text-primary)] transition-colors"
        >
          ← Back to library
        </Link>

        {/* Live totals — only shown once there are steps. Miles is rounded
            to 1dp; duration uses the same formatter as workout-template-card
            so the editor and library agree. The "~" prefix appears whenever
            (a) the workout contains time-based segments whose distance was
            estimated, or (b) no preview goal is set so paces are reference
            values. Mousing over the chip explains the source. */}
        {steps.length > 0 && (
          <div
            className="flex items-center gap-2 font-mono text-[11px] text-[var(--color-text-secondary)]"
            title={
              hasCalibratedPaces
                ? `Totals estimated from your preview goal${
                    hasTimeBasedSegment ? " — includes time-based segments" : ""
                  }`
                : REFERENCE_RUNNER_LABEL
            }
          >
            {totalMiles > 0 && (
              <>
                <span className="text-[var(--color-text-primary)] font-semibold">
                  {(hasTimeBasedSegment || !hasCalibratedPaces) ? "~" : ""}
                  {formatTotalMiles(totalMiles)}
                </span>
                <span className="text-[var(--color-text-tertiary)]">mi</span>
              </>
            )}
            {totalMiles > 0 && totalDurationMinutes > 0 && (
              <span className="text-[var(--color-text-tertiary)]">·</span>
            )}
            {totalDurationMinutes > 0 && (
              <span className="text-[var(--color-text-secondary)]">
                ~{formatTotalDuration(totalDurationMinutes)}
              </span>
            )}
          </div>
        )}

        <div className="flex items-center gap-2 ml-auto">
          {draftRestored && draftSavedAt && (
            <span
              className="text-[10px] text-[var(--color-text-tertiary)] italic"
              title={`Auto-saved ${new Date(draftSavedAt).toLocaleString()}`}
            >
              Draft restored
            </span>
          )}
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
            disabled={!name.trim() || steps.length === 0 || isSaving}
            className="px-4 py-1.5 text-sm bg-[var(--color-coral)] text-white rounded-lg hover:bg-[var(--color-coral-dark)] transition-colors disabled:opacity-50"
            title={
              !name.trim()
                ? "Name is required"
                : steps.length === 0
                ? "Add at least one step"
                : undefined
            }
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

      {/* Preview pace anchor — coach picks a goal time so pace dropdowns,
          adjustments, and the totals chip resolve to real numbers. Stored
          per coach in localStorage. The template's workout_data never
          references this; it's purely an authoring affordance. */}
      <PaceReferenceEditor
        anchor={previewAnchor}
        onChange={setPreviewAnchor}
        planDistance={previewDistance}
      />

      {/* Steps editor (the meat) */}
      <div className="bg-white border border-[var(--color-divider)] rounded-xl p-5">
        <WorkoutStepEditor
          steps={steps}
          onChange={setSteps}
          athletePaces={hasCalibratedPaces ? previewPaceTable : undefined}
        />
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
