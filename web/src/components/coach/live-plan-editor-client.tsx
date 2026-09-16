"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { DripButton } from "@/components/ui/drip-button";
import { WorkoutStepEditor } from "@/components/coach/workout-step-editor";
import { type WorkoutStep, totalWorkoutMiles } from "@/components/coach/workout-helpers";
import {
  BlockRewriteDraftPanel,
  type StagedDayChange,
} from "@/components/coach/block-rewrite-draft-panel";

// B5 — "Edit live plan" coach flow (R5 manual rewrite).
// Scope selector → per-week day grid → diff review → reason + confirm →
// POST /api/rewrite-block. Spec: outputs/adaptive-coach-plan-builder-spec-
// 2026-07-03.md §5; build plan §4.3.
//
// Phase-B scope: edits EXISTING future days (swap the session type, rename,
// re-mileage, drop to rest, add notes). Inserting brand-new days is still
// out of scope.
//
// Phase E (assisted rewrite) layers on top: "Draft with AI" opens
// BlockRewriteDraftPanel, which fetches a validated PROPOSAL from
// /api/draft-block-rewrite and lets the coach accept/deselect day changes.
// Accepted changes are STAGED into this editor's draft state — the apply
// path is unchanged (review → /api/rewrite-block with its audit rows and
// race-week confirm). AI advises, never acts.

// ── Workout-type vocabulary (matches the prod scheduled_workouts CHECK) ──
const WORKOUT_TYPE_GROUPS: { label: string; options: { value: string; label: string }[] }[] = [
  {
    label: "Effort",
    options: [
      { value: "easy", label: "Easy" },
      { value: "moderate", label: "Moderate" },
      { value: "steady", label: "Steady" },
      { value: "recovery", label: "Recovery" },
      { value: "long_run", label: "Long run" },
      { value: "long_wo", label: "Long w/ workout" },
    ],
  },
  {
    label: "Race pace",
    options: [
      { value: "mp", label: "MP" },
      { value: "hmp", label: "HMP" },
      { value: "lt", label: "LT" },
      { value: "10k", label: "10K" },
      { value: "5k", label: "5K" },
      { value: "3k", label: "3K" },
      { value: "mile", label: "Mile" },
    ],
  },
  {
    label: "Structured",
    options: [
      { value: "tempo", label: "Tempo" },
      { value: "intervals", label: "Intervals" },
      { value: "progression", label: "Progression" },
      { value: "fartlek", label: "Fartlek" },
      { value: "hills", label: "Hills" },
    ],
  },
  {
    label: "Other",
    options: [
      { value: "rest", label: "Rest" },
      { value: "race", label: "Race" },
      { value: "cross_train", label: "Cross-train" },
      { value: "strength", label: "Strength" },
    ],
  },
];

const TYPE_LABEL: Record<string, string> = Object.fromEntries(
  WORKOUT_TYPE_GROUPS.flatMap((g) => g.options.map((o) => [o.value, o.label])),
);

const REASONS: { value: string; label: string }[] = [
  { value: "sickness", label: "Sickness" },
  { value: "injury_niggle", label: "Injury / niggle" },
  { value: "race_change", label: "Race change" },
  { value: "life_event", label: "Life event" },
  { value: "performance", label: "Performance" },
  { value: "other", label: "Other" },
];

const DAY_SHORT = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

// ── Types ────────────────────────────────────────────────────────────────
type WorkoutData = {
  name?: string;
  total_distance_mi?: number;
  total_distance_km?: number;
  target_pace?: string;
  [k: string]: unknown;
};

export interface EditableWorkout {
  id: string;
  date: string; // YYYY-MM-DD
  day_of_week: number;
  week_number: number;
  workout_type: string;
  workout_data: WorkoutData | null;
  notes: string | null;
}

interface Draft {
  workoutType: string;
  name: string;
  miles: string; // kept as string for the input; parsed on submit
  notes: string;
  steps: WorkoutStep[]; // full workout structure (reps/pace/warmup), editable
}

interface Props {
  athleteUserId: string;
  planId: string;
  planName: string;
  raceEndDate: string | null; // plan end_date (race day), YYYY-MM-DD
  workouts: EditableWorkout[]; // future-dated only
}

function milesOf(w: EditableWorkout): string {
  const mi = w.workout_data?.total_distance_mi;
  if (typeof mi === "number") return String(mi);
  const km = w.workout_data?.total_distance_km;
  if (typeof km === "number") return (km * 0.621371).toFixed(1);
  return "";
}

function draftOf(w: EditableWorkout): Draft {
  return {
    workoutType: w.workout_type,
    name: w.workout_data?.name ?? "",
    miles: milesOf(w),
    notes: w.notes ?? "",
    steps: (w.workout_data?.steps as WorkoutStep[] | undefined) ?? [],
  };
}

function changed(w: EditableWorkout, d: Draft): boolean {
  const orig = draftOf(w);
  return (
    orig.workoutType !== d.workoutType ||
    orig.name !== d.name ||
    orig.miles !== d.miles ||
    orig.notes !== d.notes ||
    JSON.stringify(orig.steps) !== JSON.stringify(d.steps)
  );
}

export function LivePlanEditorClient({
  athleteUserId,
  planId,
  planName,
  raceEndDate,
  workouts,
}: Props) {
  const router = useRouter();

  const weeksAvailable = useMemo(
    () => [...new Set(workouts.map((w) => w.week_number))].sort((a, b) => a - b),
    [workouts],
  );
  const minWeek = weeksAvailable[0] ?? 0;
  const maxWeek = weeksAvailable[weeksAvailable.length - 1] ?? 0;

  const [phase, setPhase] = useState<"scope" | "edit" | "review" | "done">("scope");
  const [fromWeek, setFromWeek] = useState(minWeek);
  const [toWeek, setToWeek] = useState(minWeek);
  const [drafts, setDrafts] = useState<Record<string, Draft>>({});
  const [reasonCode, setReasonCode] = useState("sickness");
  const [reasonText, setReasonText] = useState("");
  const [confirmRaceWeek, setConfirmRaceWeek] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Which day rows have their step editor (reps/pace/warmup) expanded.
  const [openSteps, setOpenSteps] = useState<Record<string, boolean>>({});
  // Phase E — assisted rewrite panel visibility.
  const [showDraftPanel, setShowDraftPanel] = useState(false);
  const [result, setResult] = useState<{ changedWeeks: number[]; updatedCount: number } | null>(null);

  const inScope = useMemo(
    () =>
      workouts
        .filter((w) => w.week_number >= fromWeek && w.week_number <= toWeek)
        .sort((a, b) => a.date.localeCompare(b.date)),
    [workouts, fromWeek, toWeek],
  );

  const getDraft = (w: EditableWorkout): Draft => drafts[w.id] ?? draftOf(w);
  const setDraft = (id: string, patch: Partial<Draft>) =>
    setDrafts((prev) => ({ ...prev, [id]: { ...(prev[id] ?? draftOf(workouts.find((w) => w.id === id)!)), ...patch } }));

  const editedWorkouts = useMemo(
    () => inScope.filter((w) => drafts[w.id] && changed(w, drafts[w.id])),
    [inScope, drafts],
  );

  // Phase E — stage AI-drafted day changes into the normal editing state.
  // From here they're indistinguishable from manual edits: same review
  // phase, same /api/rewrite-block apply path, same audit rows.
  function stageDraftChanges(staged: StagedDayChange[], summary: string) {
    setDrafts((prev) => {
      const next = { ...prev };
      for (const c of staged) {
        const w = workouts.find((x) => x.id === c.scheduledWorkoutId);
        if (!w) continue;
        const base = next[c.scheduledWorkoutId] ?? draftOf(w);
        next[c.scheduledWorkoutId] = {
          ...base,
          workoutType: c.workoutType,
          name: c.name,
          miles: c.miles,
          // The library prescribes the day whole — drop any old step
          // structure so the staged mileage is what saves.
          steps: [],
        };
      }
      return next;
    });
    // Offer the AI's one-line summary as the default athlete-facing note;
    // never overwrite something the coach already typed.
    if (summary) {
      setReasonText((prev) => (prev.trim().length > 0 ? prev : summary.slice(0, 280)));
    }
    setShowDraftPanel(false);
  }

  // A race-week edit needs explicit confirmation (mirrors the edge fn guard).
  const touchesRaceWeek = useMemo(() => {
    if (!raceEndDate) return false;
    const start = new Date(raceEndDate);
    start.setDate(start.getDate() - 6);
    const startStr = start.toISOString().slice(0, 10);
    return editedWorkouts.some((w) => w.date >= startStr && w.date <= raceEndDate) ||
      editedWorkouts.some((w) => getDraft(w).workoutType === "race");
  }, [editedWorkouts, raceEndDate, drafts]);

  async function submit() {
    setSubmitting(true);
    setError(null);
    const changes = editedWorkouts.map((w) => {
      const d = getDraft(w);
      const typedMiles = d.miles.trim() === "" ? undefined : Number(d.miles);
      // When the day carries an edited step structure, its total mileage is
      // derived from the steps (source of truth); otherwise the typed mi wins.
      const derivedMiles =
        d.steps.length > 0 ? Math.round(totalWorkoutMiles(d.steps) * 10) / 10 : undefined;
      const milesNum = derivedMiles ?? typedMiles;
      const workoutData: WorkoutData | null =
        d.workoutType === "rest"
          ? null
          : {
              ...(w.workout_data ?? {}),
              name: d.name || undefined,
              steps: d.steps.length > 0 ? d.steps : undefined,
              total_distance_mi: milesNum != null && !Number.isNaN(milesNum) ? milesNum : undefined,
            };
      return {
        scheduledWorkoutId: w.id,
        date: w.date,
        weekNumber: w.week_number,
        workoutType: d.workoutType,
        workoutData,
        notes: d.notes.trim() === "" ? null : d.notes.trim(),
      };
    });

    try {
      const res = await fetch("/api/rewrite-block", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          athleteUserId,
          planId,
          weekRange: { fromWeek, toWeek },
          changes,
          reasonCode,
          reasonText: reasonText.trim() || undefined,
          confirmRaceWeek,
        }),
      });
      const data = await res.json();
      if (!res.ok) {
        if (data.code === "race_week_confirm_required") {
          setError("This block touches the race week. Tick the confirm box below to proceed.");
          setConfirmRaceWeek(false);
        } else {
          setError(data.error ?? "Something went wrong saving the rewrite.");
        }
        setSubmitting(false);
        return;
      }
      setResult({ changedWeeks: data.changedWeeks ?? [], updatedCount: data.updatedCount ?? 0 });
      setPhase("done");
    } catch (e) {
      setError(String(e));
    } finally {
      setSubmitting(false);
    }
  }

  // Eyebrow — mono + tracked per the design system (uppercase labels are
  // always monospaced), text-secondary for readable muted contrast.
  const eyebrow = "font-mono text-[10px] font-medium tracking-[0.12em] uppercase text-text-secondary";

  // ── Empty state: no future weeks to edit ───────────────────────────────
  if (weeksAvailable.length === 0) {
    return (
      <div className="space-y-3">
        <p className={eyebrow}>Edit live plan</p>
        <p className="font-body text-base text-text-tertiary leading-relaxed">
          There are no future weeks on {planName} to edit. Past weeks are kept as
          history and can&apos;t be changed.
        </p>
      </div>
    );
  }

  // ── Done ────────────────────────────────────────────────────────────────
  if (phase === "done" && result) {
    return (
      <div className="space-y-4">
        <p className={eyebrow}>Plan updated</p>
        <p className="font-body text-base text-text-primary leading-relaxed">
          Rewrote {result.updatedCount} workout{result.updatedCount === 1 ? "" : "s"} across
          week{result.changedWeeks.length === 1 ? "" : "s"} {result.changedWeeks.join(", ")}.
          The athlete will see the change on their plan.
        </p>
        <DripButton onClick={() => router.push(`/coach-portal/athletes/${athleteUserId}`)}>
          Back to athlete
        </DripButton>
      </div>
    );
  }

  // ── Scope selector ──────────────────────────────────────────────────────
  if (phase === "scope") {
    return (
      <div className="space-y-5">
        <div>
          <p className={eyebrow}>Edit live plan</p>
          <h2 className="mt-1 font-display text-[28px] leading-tight text-text-primary">
            {planName}
          </h2>
          <p className="mt-1 font-body text-sm text-text-secondary">
            Pick the future weeks to rewrite. Past weeks stay as history.
          </p>
        </div>
        <div className="flex items-end gap-4 flex-wrap">
          <label className="flex flex-col gap-1">
            <span className={eyebrow}>From week</span>
            <select
              className="rounded-md border border-divider bg-bg-card px-3 py-2 text-sm"
              value={fromWeek}
              onChange={(e) => {
                const v = Number(e.target.value);
                setFromWeek(v);
                if (toWeek < v) setToWeek(v);
              }}
            >
              {weeksAvailable.map((w) => (
                <option key={w} value={w}>Week {w}</option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className={eyebrow}>To week</span>
            <select
              className="rounded-md border border-divider bg-bg-card px-3 py-2 text-sm"
              value={toWeek}
              onChange={(e) => setToWeek(Number(e.target.value))}
            >
              {weeksAvailable.filter((w) => w >= fromWeek).map((w) => (
                <option key={w} value={w}>Week {w}</option>
              ))}
            </select>
          </label>
        </div>
        <DripButton onClick={() => setPhase("edit")}>
          Edit weeks {fromWeek}{toWeek !== fromWeek ? `–${toWeek}` : ""}
        </DripButton>
      </div>
    );
  }

  // ── Review ──────────────────────────────────────────────────────────────
  if (phase === "review") {
    return (
      <div className="space-y-5">
        <div>
          <p className={eyebrow}>Review changes</p>
          <p className="mt-1 font-body text-sm text-text-secondary">
            {editedWorkouts.length} day{editedWorkouts.length === 1 ? "" : "s"} changed.
            Confirm to apply.
          </p>
        </div>

        <ul className="space-y-2">
          {editedWorkouts.map((w) => {
            const before = draftOf(w);
            const after = getDraft(w);
            return (
              <li key={w.id} className="rounded-md border border-divider bg-bg-card px-4 py-3">
                <p className="font-body text-[11px] text-text-tertiary">
                  {DAY_SHORT[w.day_of_week]} · {w.date} · week {w.week_number}
                </p>
                <p className="mt-1 font-body text-sm text-text-primary">
                  <span className="text-text-tertiary line-through">
                    {TYPE_LABEL[before.workoutType] ?? before.workoutType}
                    {before.miles ? ` ${before.miles}mi` : ""}
                  </span>
                  {"  →  "}
                  <span className="font-semibold">
                    {TYPE_LABEL[after.workoutType] ?? after.workoutType}
                    {after.workoutType !== "rest" && after.miles ? ` ${after.miles}mi` : ""}
                  </span>
                </p>
                {after.notes && after.notes !== before.notes ? (
                  <p className="mt-1 font-body text-xs text-text-secondary">Note: {after.notes}</p>
                ) : null}
              </li>
            );
          })}
        </ul>

        <div className="space-y-3 border-t border-divider pt-4">
          <label className="flex flex-col gap-1 max-w-xs">
            <span className={eyebrow}>Reason</span>
            <select
              className="rounded-md border border-divider bg-bg-card px-3 py-2 text-sm"
              value={reasonCode}
              onChange={(e) => setReasonCode(e.target.value)}
            >
              {REASONS.map((r) => (
                <option key={r.value} value={r.value}>{r.label}</option>
              ))}
            </select>
          </label>
          <label className="flex flex-col gap-1">
            <span className={eyebrow}>Note to athlete (optional)</span>
            <input
              className="rounded-md border border-divider bg-bg-card px-3 py-2 text-sm max-w-lg"
              maxLength={280}
              value={reasonText}
              onChange={(e) => setReasonText(e.target.value)}
              placeholder="e.g. Flu recovery — easing back in, keeping the race date."
            />
          </label>

          {touchesRaceWeek ? (
            <label className="flex items-start gap-2 text-sm text-text-primary">
              <input
                type="checkbox"
                checked={confirmRaceWeek}
                onChange={(e) => setConfirmRaceWeek(e.target.checked)}
                className="mt-0.5 accent-[var(--color-text-primary)]"
              />
              <span>
                This block touches the <strong>race week</strong>. I&apos;ve reviewed it and want to proceed.
              </span>
            </label>
          ) : null}
        </div>

        {error ? (
          <p className="font-body text-sm text-coral">{error}</p>
        ) : null}

        <div className="flex gap-3">
          <DripButton variant="secondary" onClick={() => setPhase("edit")} disabled={submitting}>
            Back to edit
          </DripButton>
          <DripButton
            onClick={submit}
            isLoading={submitting}
            disabled={submitting || editedWorkouts.length === 0 || (touchesRaceWeek && !confirmRaceWeek)}
          >
            Apply rewrite
          </DripButton>
        </div>
      </div>
    );
  }

  // ── Edit grid ───────────────────────────────────────────────────────────
  const byWeek = new Map<number, EditableWorkout[]>();
  for (const w of inScope) {
    if (!byWeek.has(w.week_number)) byWeek.set(w.week_number, []);
    byWeek.get(w.week_number)!.push(w);
  }

  return (
    <div className="space-y-5">
      <div className="flex items-baseline justify-between flex-wrap gap-2">
        <div>
          <p className={eyebrow}>Editing weeks {fromWeek}{toWeek !== fromWeek ? `–${toWeek}` : ""}</p>
          <p className="mt-1 font-body text-sm text-text-secondary">
            {editedWorkouts.length} change{editedWorkouts.length === 1 ? "" : "s"} so far.
          </p>
        </div>
        <div className="flex items-baseline gap-4">
          {!showDraftPanel ? (
            <button
              type="button"
              onClick={() => setShowDraftPanel(true)}
              className="font-body text-xs text-text-secondary hover:text-coral"
            >
              Draft with AI
            </button>
          ) : null}
          <button
            type="button"
            onClick={() => setPhase("scope")}
            className="font-body text-xs text-text-tertiary hover:text-coral"
          >
            ← Change weeks
          </button>
        </div>
      </div>

      {showDraftPanel ? (
        <BlockRewriteDraftPanel
          athleteUserId={athleteUserId}
          planId={planId}
          fromWeek={fromWeek}
          toWeek={toWeek}
          workouts={inScope}
          onStage={stageDraftChanges}
          onClose={() => setShowDraftPanel(false)}
        />
      ) : null}

      {[...byWeek.entries()].map(([week, days]) => (
        <section key={week} className="space-y-2">
          <p className={eyebrow}>Week {week}</p>
          <div className="space-y-2">
            {days.map((w) => {
              const d = getDraft(w);
              const isChanged = drafts[w.id] && changed(w, drafts[w.id]);
              const isRest = d.workoutType === "rest";
              return (
                <div
                  key={w.id}
                  className={`rounded-md border px-3 py-2 ${isChanged ? "border-coral" : "border-divider"} bg-bg-card`}
                >
                  <div className="flex items-center gap-3 flex-wrap">
                    <span className="font-body text-[11px] text-text-tertiary w-20 shrink-0">
                      {DAY_SHORT[w.day_of_week]} {w.date.slice(5)}
                    </span>
                    <select
                      className="rounded-md border border-divider bg-bg-card px-2 py-1 text-sm"
                      value={d.workoutType}
                      onChange={(e) => setDraft(w.id, { workoutType: e.target.value })}
                    >
                      {WORKOUT_TYPE_GROUPS.map((g) => (
                        <optgroup key={g.label} label={g.label}>
                          {g.options.map((o) => (
                            <option key={o.value} value={o.value}>{o.label}</option>
                          ))}
                        </optgroup>
                      ))}
                    </select>
                    {!isRest ? (
                      <>
                        <input
                          className="rounded-md border border-divider bg-bg-card px-2 py-1 text-sm w-40"
                          placeholder="Name"
                          value={d.name}
                          onChange={(e) => setDraft(w.id, { name: e.target.value })}
                        />
                        <input
                          className="rounded-md border border-divider bg-bg-card px-2 py-1 text-sm w-20 disabled:opacity-60"
                          placeholder="mi"
                          inputMode="decimal"
                          title={d.steps.length > 0 ? "Derived from the workout structure below" : undefined}
                          value={
                            d.steps.length > 0
                              ? String(Math.round(totalWorkoutMiles(d.steps) * 10) / 10)
                              : d.miles
                          }
                          disabled={d.steps.length > 0}
                          onChange={(e) => setDraft(w.id, { miles: e.target.value })}
                        />
                      </>
                    ) : (
                      <span className="font-body text-sm text-text-tertiary">Rest day</span>
                    )}
                  </div>
                  <input
                    className="mt-2 w-full rounded-md border border-divider bg-bg-card px-2 py-1 text-xs"
                    placeholder="Coaching note for this day (optional)"
                    value={d.notes}
                    onChange={(e) => setDraft(w.id, { notes: e.target.value })}
                  />
                  {!isRest && (
                    <div className="mt-2">
                      <button
                        type="button"
                        onClick={() =>
                          setOpenSteps((o) => ({ ...o, [w.id]: !o[w.id] }))
                        }
                        className="font-mono text-[10px] uppercase tracking-wider text-text-tertiary hover:text-coral transition-colors"
                      >
                        {openSteps[w.id] ? "▾ hide structure" : "▸ edit structure"}
                        {d.steps.length > 0 ? ` · ${d.steps.length} steps` : ""}
                      </button>
                      {openSteps[w.id] && (
                        <div className="mt-2 rounded-md border border-divider-soft bg-bg-elevated p-2">
                          <WorkoutStepEditor
                            steps={d.steps}
                            onChange={(steps) => setDraft(w.id, { steps })}
                          />
                          <p className="mt-1 font-body text-[11px] italic text-text-tertiary">
                            Mileage is derived from these steps on save.
                          </p>
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>
        </section>
      ))}

      <div className="flex gap-3">
        <DripButton
          onClick={() => setPhase("review")}
          disabled={editedWorkouts.length === 0}
        >
          Review {editedWorkouts.length} change{editedWorkouts.length === 1 ? "" : "s"}
        </DripButton>
      </div>
    </div>
  );
}
