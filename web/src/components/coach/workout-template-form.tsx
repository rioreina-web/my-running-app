"use client";

import { useState, useMemo, useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import { WorkoutStepEditor } from "./workout-step-editor";
import { ProgressionSuggestions } from "./progression-suggestions";
import {
  estimatedWorkoutMiles,
  totalWorkoutDurationMinutes,
  workoutHasTimeBasedSegment,
  REFERENCE_RUNNER_LABEL,
  type WorkoutStep,
} from "./workout-helpers";
import { PaceReferenceEditor, resolvePaceTable, type PaceAnchor } from "./pace-reference-editor";
import { CUSTOM_TYPE_PREFIX, slugifyWorkoutLabel } from "@/lib/utils";

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

// Blue pace-depth ramp only (THE THREE-PALETTE RULE: blue = pace, warm =
// mood, coral = alert). These mirror WORKOUT_COLORS in plan-builder-client;
// the previous greens/coral here were a palette violation. Source of truth
// for the hex values: RunningLog/Workouts/PaceSpectrum.swift.
type CustomLabel = { slug: string; label: string; color: string };

// On-brand swatches for custom "add your own" labels: pace-ramp blues +
// warm gray. Coral is alert-only (three-palette rule), so it's absent.
const CUSTOM_LABEL_SWATCHES = [
  "#93B9D6", "#74A8CC", "#578FC0", "#3F7CB5",
  "#2F66A8", "#27549B", "#1A3679", "#0E1D4E", "#B4ADA4",
];

const WORKOUT_TYPES = [
  { value: "easy",        label: "Easy",             color: "#93B9D6" }, // easy
  { value: "steady",      label: "Steady",           color: "#578FC0" }, // steady
  { value: "tempo",       label: "Tempo",            color: "#27549B" }, // LT
  { value: "intervals",   label: "Intervals",        color: "#1A3679" }, // 5K
  { value: "fartlek",     label: "Fartlek",          color: "#74A8CC" }, // moderate — variable effort
  { value: "long_run",    label: "Long Run",         color: "#578FC0" }, // steady (Long runs sit at ~steady effort)
  { value: "long_wo",     label: "Long Run Workout", color: "#2F66A8" }, // HMP — long run w/ embedded quality
  { value: "progression", label: "Progression",      color: "#3F7CB5" }, // MP
  { value: "recovery",    label: "Recovery",         color: "#B4ADA4" }, // warm gray, below easy
  { value: "strides",     label: "Strides",          color: "#142964" }, // 3K
  { value: "race",        label: "Race",             color: "#0E1D4E" }, // navy — hardest
];

export interface ExistingWorkout {
  id: string;
  name: string;
  workout_type: string;
  description?: string | null;
  tags?: string[] | null;
  workout_data?: { steps?: WorkoutStep[] } | null;
}

// Duplicate flow: a clone of an existing template used to pre-fill a NEW
// template (no id — nothing exists in the DB until the coach saves).
// Built server-side by workouts/new/page.tsx from `?from=<templateId>`.
export interface DuplicateSeed {
  sourceTemplateId: string;
  name: string;
  workout_type: string;
  description?: string | null;
  tags?: string[] | null;
  workout_data?: { steps?: WorkoutStep[] } | null;
}

export function WorkoutTemplateForm({
  coachId,
  existingWorkout,
  seed,
}: {
  coachId: string;
  existingWorkout?: ExistingWorkout | null;
  seed?: DuplicateSeed | null;
}) {
  const router = useRouter();
  const supabase = createClient();

  const isEdit = !!existingWorkout;

  // Draft autosave — keyed by coach + (workout id | dup source | 'new').
  // Duplicates get their own key so a stale plain-"new" draft can't
  // clobber the clone (and vice versa). Survives nav and tab close but
  // not multi-device editing. Cleared on successful save or delete. We
  // deliberately stash in localStorage rather than a DB drafts table to
  // avoid a migration; revisit if cross-device matters.
  const draftKey = `wt-draft:${coachId}:${
    existingWorkout?.id ?? (seed ? `dup:${seed.sourceTemplateId}` : "new")
  }`;

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

  const [name, setName] = useState(
    initialDraft?.name ?? existingWorkout?.name ?? seed?.name ?? ""
  );
  const [workoutType, setWorkoutType] = useState(
    initialDraft?.workoutType ?? existingWorkout?.workout_type ?? seed?.workout_type ?? "tempo"
  );
  const [description, setDescription] = useState(
    initialDraft?.description ?? existingWorkout?.description ?? seed?.description ?? ""
  );
  const [tagsInput, setTagsInput] = useState(
    initialDraft?.tagsInput ?? (existingWorkout?.tags ?? seed?.tags ?? []).join(", ")
  );
  const [steps, setSteps] = useState<WorkoutStep[]>(
    migrateSteps(
      (initialDraft?.steps ??
        existingWorkout?.workout_data?.steps ??
        seed?.workout_data?.steps ??
        []) as WorkoutStep[],
    ),
  );
  // Source steps for the "Suggested progressions" strip — the clone as it
  // was duplicated (zone-migrated, not draft-mutated), so the deterministic
  // candidates stay stable while the coach edits below.
  const seedSteps = useMemo(
    () => migrateSteps((seed?.workout_data?.steps ?? []) as WorkoutStep[]),
    // seed comes from the server and never changes for a mounted form
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [],
  );
  const [isSaving, setIsSaving] = useState(false);
  const [isDeleting, setIsDeleting] = useState(false);
  const [saveError, setSaveError] = useState<string | null>(null);

  // ── Custom workout labels ("add your own") ────────────────────────────
  // A per-coach library of labels (name + color) stored in
  // coach_workout_labels, rendered as chips after the built-ins. The
  // selected value saves on the workout as `custom:<slug>`. Fetch fails
  // soft so the builder still works before the migration is deployed.
  const [customLabels, setCustomLabels] = useState<CustomLabel[]>([]);
  const [showAddLabel, setShowAddLabel] = useState(false);
  const [newLabelName, setNewLabelName] = useState("");
  const [newLabelColor, setNewLabelColor] = useState(CUSTOM_LABEL_SWATCHES[0]);
  const [savingLabel, setSavingLabel] = useState(false);
  const [labelError, setLabelError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data, error } = await supabase
        .from("coach_workout_labels")
        .select("slug,label,color")
        .eq("coach_id", coachId)
        .order("created_at", { ascending: true });
      if (cancelled || error || !data) return;
      setCustomLabels(data as CustomLabel[]);
    })();
    return () => {
      cancelled = true;
    };
    // supabase client is recreated each render; coachId is the real dep.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [coachId]);

  function resetAddLabel() {
    setNewLabelName("");
    setNewLabelColor(CUSTOM_LABEL_SWATCHES[0]);
    setShowAddLabel(false);
    setLabelError(null);
  }

  async function handleAddLabel() {
    const name = newLabelName.trim();
    const slug = slugifyWorkoutLabel(name);
    if (!slug) {
      setLabelError("Enter a label name.");
      return;
    }
    // Already in the library — just select it, no duplicate row.
    const existing = customLabels.find((l) => l.slug === slug);
    if (existing) {
      setWorkoutType(`${CUSTOM_TYPE_PREFIX}${existing.slug}`);
      resetAddLabel();
      return;
    }
    setSavingLabel(true);
    setLabelError(null);
    const { data, error } = await supabase
      .from("coach_workout_labels")
      .insert({ coach_id: coachId, slug, label: name, color: newLabelColor })
      .select("slug,label,color")
      .single();
    setSavingLabel(false);
    if (error || !data) {
      setLabelError("Couldn't save this label — you may need the latest app update.");
      return;
    }
    setCustomLabels((prev) => [...prev, data as CustomLabel]);
    setWorkoutType(`${CUSTOM_TYPE_PREFIX}${data.slug}`);
    resetAddLabel();
  }
  const [showDetails, setShowDetails] = useState(
    !!(
      initialDraft?.description ||
      (initialDraft?.tagsInput?.trim().length ?? 0) > 0 ||
      existingWorkout?.description ||
      (existingWorkout?.tags ?? []).length > 0 ||
      seed?.description ||
      (seed?.tags ?? []).length > 0
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
              className="px-3 py-1.5 text-xs text-coral hover:text-coral-dark hover:bg-coral/8 rounded-lg transition-colors disabled:opacity-50"
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
        <p className="text-xs text-coral font-mono">
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
              type="button"
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

          {/* Coach's own saved labels — the "add your own" library. */}
          {customLabels.map((t) => {
            const value = `${CUSTOM_TYPE_PREFIX}${t.slug}`;
            const selected = workoutType === value;
            return (
              <button
                key={value}
                type="button"
                onClick={() => setWorkoutType(value)}
                className={`px-3 py-1 text-xs rounded-full border transition-colors ${
                  selected
                    ? "text-white font-medium"
                    : "text-[var(--color-text-secondary)] border-[var(--color-divider)] hover:border-[var(--color-text-tertiary)]"
                }`}
                style={{
                  backgroundColor: selected ? t.color : "transparent",
                  borderColor: selected ? t.color : undefined,
                }}
              >
                {t.label}
              </button>
            );
          })}

          {/* Add-your-own affordance — opens the inline composer below. */}
          <button
            type="button"
            onClick={() => setShowAddLabel((s) => !s)}
            className="px-3 py-1 text-xs rounded-full border border-dashed border-[var(--color-divider)] text-[var(--color-text-secondary)] hover:border-[var(--color-text-tertiary)] transition-colors"
          >
            + Add your own
          </button>
        </div>

        {showAddLabel && (
          <div className="rounded-lg border border-[var(--color-divider)] p-3 space-y-2.5">
            <input
              type="text"
              autoFocus
              value={newLabelName}
              onChange={(e) => setNewLabelName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  void handleAddLabel();
                }
              }}
              maxLength={40}
              placeholder="Label name — e.g., Hill repeats"
              className="w-full text-sm border-none outline-none bg-transparent placeholder:text-[var(--color-text-tertiary)] text-[var(--color-text-primary)]"
            />
            <div className="flex items-center gap-1.5">
              {CUSTOM_LABEL_SWATCHES.map((c) => (
                <button
                  key={c}
                  type="button"
                  aria-label={`Use color ${c}`}
                  onClick={() => setNewLabelColor(c)}
                  className={`h-5 w-5 rounded-full border-2 transition-transform ${
                    newLabelColor === c
                      ? "scale-110 border-[var(--color-text-primary)]"
                      : "border-transparent"
                  }`}
                  style={{ backgroundColor: c }}
                />
              ))}
            </div>
            {labelError && <p className="text-xs text-coral">{labelError}</p>}
            <div className="flex items-center gap-2">
              <button
                type="button"
                onClick={() => void handleAddLabel()}
                disabled={savingLabel || !newLabelName.trim()}
                className="px-3 py-1 text-xs rounded-full text-white font-medium disabled:opacity-40"
                style={{ backgroundColor: newLabelColor }}
              >
                {savingLabel ? "Saving…" : "Add label"}
              </button>
              <button
                type="button"
                onClick={resetAddLabel}
                className="px-3 py-1 text-xs rounded-full text-[var(--color-text-secondary)] hover:text-[var(--color-text-primary)] transition-colors"
              >
                Cancel
              </button>
            </div>
          </div>
        )}
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

      {/* Smart duplicate — suggested progressions of the source template.
          Deterministic candidates, optional LLM notes, coach decides. Only
          rendered in the duplicate flow (seed present with steps). */}
      {seed && seedSteps.length > 0 && (
        <ProgressionSuggestions
          sourceName={seed.name}
          sourceSteps={seedSteps}
          onApply={(nextSteps) => setSteps(nextSteps)}
        />
      )}

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
