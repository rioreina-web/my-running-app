"use client";

import { useMemo, useState } from "react";
import { DripButton } from "@/components/ui/drip-button";

// Phase E — "Draft with AI" panel for the live-plan editor (R5 assisted
// rewrite, outputs/adaptive-coach-plan-builder-spec-2026-07-03.md §5).
//
// The coach types a plain-language request ("Sarah's fading on back-to-back
// quality — soften weeks 7–9, keep the long runs"); /api/draft-block-rewrite
// returns a validated PROPOSAL (never applied). This panel renders it as a
// week-by-week before → after diff — unchanged days collapsed, changed days
// listed with per-day reasons, one plain-prose reason line per week. The
// coach deselects any day, then "Load into editor" stages the accepted
// changes into LivePlanEditorClient's draft state; the EXISTING save path
// (/api/rewrite-block) applies them with its validation and audit rows.
//
// Design notes (Post Run Drip): coral is punctuation — at most one coral
// element per week cluster (the changed-day count). Before-values are muted
// with line-through; after-values are ink, semibold. No em-dash empty states.

const DAY_SHORT = ["", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

interface DaySnapshot {
  workoutType: string;
  name: string | null;
  miles: number | null;
}

export interface ProposalDay {
  scheduledWorkoutId: string;
  date: string;
  weekNumber: number;
  dayOfWeek: number;
  changed: boolean;
  code: string | null;
  reason: string | null;
  before: DaySnapshot;
  after: DaySnapshot;
}

export interface ProposalWeek {
  weekNumber: number;
  reason: string | null;
  changedCount: number;
  mileageBefore: number;
  mileageAfter: number;
  target: { min: number; max: number } | null;
}

interface Proposal {
  message: string;
  summary: string;
  weeks: ProposalWeek[];
  days: ProposalDay[];
}

/** What the panel hands back to the editor when the coach accepts. */
export interface StagedDayChange {
  scheduledWorkoutId: string;
  workoutType: string;
  /** Display name for the day ("" for rest). */
  name: string;
  /** Miles as a string for the editor's input ("" for rest / 0). */
  miles: string;
}

/** Minimal view of the editor's workouts the panel needs to send along. */
export interface DraftableWorkout {
  id: string;
  date: string;
  day_of_week: number;
  week_number: number;
  workout_type: string;
  workout_data: {
    name?: string;
    total_distance_mi?: number;
    total_distance_km?: number;
    [k: string]: unknown;
  } | null;
}

interface Props {
  athleteUserId: string;
  planId: string;
  fromWeek: number;
  toWeek: number;
  workouts: DraftableWorkout[]; // the in-scope days, future-dated
  onStage: (changes: StagedDayChange[], summary: string) => void;
  onClose: () => void;
}

function milesOf(w: DraftableWorkout): number | undefined {
  const mi = w.workout_data?.total_distance_mi;
  if (typeof mi === "number") return mi;
  const km = w.workout_data?.total_distance_km;
  if (typeof km === "number") return Math.round(km * 0.621371 * 10) / 10;
  return undefined;
}

function snapLabel(s: DaySnapshot): string {
  const base = s.name && s.name.trim().length > 0 ? s.name : s.workoutType.replace(/_/g, " ");
  return s.miles != null && s.miles > 0 && !/\d/.test(base) ? `${base} ${s.miles}mi` : base;
}

export function BlockRewriteDraftPanel({
  athleteUserId,
  planId,
  fromWeek,
  toWeek,
  workouts,
  onStage,
  onClose,
}: Props) {
  const [request, setRequest] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [violations, setViolations] = useState<Array<{ code: string; detail: string }>>([]);
  const [proposal, setProposal] = useState<Proposal | null>(null);
  // Changed days the coach has deselected (default: all accepted).
  const [rejected, setRejected] = useState<Record<string, boolean>>({});
  const [showUnchanged, setShowUnchanged] = useState<Record<number, boolean>>({});

  // Eyebrow — mono + tracked per the design system (uppercase labels are
  // always monospaced), text-secondary for readable muted contrast.
  const eyebrow = "font-mono text-[10px] font-medium tracking-[0.12em] uppercase text-text-secondary";

  const acceptedDays = useMemo(
    () => (proposal?.days ?? []).filter((d) => d.changed && !rejected[d.scheduledWorkoutId]),
    [proposal, rejected],
  );

  async function draft() {
    setLoading(true);
    setError(null);
    setViolations([]);
    try {
      const res = await fetch("/api/draft-block-rewrite", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          athleteUserId,
          planId,
          weekRange: { fromWeek, toWeek },
          workouts: workouts.map((w) => ({
            scheduledWorkoutId: w.id,
            date: w.date,
            weekNumber: w.week_number,
            dayOfWeek: w.day_of_week,
            workoutType: w.workout_type,
            name: w.workout_data?.name || undefined,
            miles: milesOf(w),
          })),
          request: request.trim(),
        }),
      });
      const data = await res.json();
      if (!res.ok) {
        if (data.code === "draft_validation_failed" && Array.isArray(data.violations)) {
          setViolations(data.violations);
          setError("The draft broke a plan constraint and was rejected. Nothing changed — try rephrasing the request.");
        } else if (res.status === 429) {
          setError("This athlete's AI draft for today is already used. Edit manually, or try again tomorrow.");
        } else {
          setError(data.error ?? "The draft could not be generated.");
        }
        return;
      }
      setProposal({
        message: data.message ?? "",
        summary: data.summary ?? "",
        weeks: data.weeks ?? [],
        days: data.days ?? [],
      });
      setRejected({});
    } catch (e) {
      setError(String(e));
    } finally {
      setLoading(false);
    }
  }

  function stage() {
    if (!proposal) return;
    const changes: StagedDayChange[] = acceptedDays.map((d) => ({
      scheduledWorkoutId: d.scheduledWorkoutId,
      workoutType: d.after.workoutType,
      name: d.after.workoutType === "rest" ? "" : d.after.name ?? "",
      miles: d.after.miles != null && d.after.miles > 0 ? String(d.after.miles) : "",
    }));
    onStage(changes, proposal.summary);
  }

  // ── Compose ─────────────────────────────────────────────────────────────
  if (!proposal) {
    return (
      <div className="rounded-md border border-divider bg-bg-elevated p-4 space-y-3">
        <div className="flex items-baseline justify-between gap-2">
          <p className={eyebrow}>Draft with AI · weeks {fromWeek}{toWeek !== fromWeek ? `–${toWeek}` : ""}</p>
          <button
            type="button"
            onClick={onClose}
            className="font-body text-xs text-text-tertiary hover:text-coral"
          >
            Close
          </button>
        </div>
        <p className="font-body text-sm text-text-secondary leading-relaxed">
          Describe the change in your own words. You get a proposal to review —
          nothing is applied until you load it into the editor and save it yourself.
        </p>
        <textarea
          className="w-full rounded-md border border-divider bg-bg-card px-3 py-2 text-sm font-body min-h-[72px]"
          maxLength={600}
          value={request}
          onChange={(e) => setRequest(e.target.value)}
          placeholder="e.g. She's fading on back-to-back quality — soften these weeks to one hard day each, keep the long runs."
        />
        {error ? (
          <div className="space-y-1">
            <p className="font-body text-sm text-coral">{error}</p>
            {violations.length > 0 ? (
              <ul className="font-body text-xs text-text-secondary list-disc pl-5 space-y-0.5">
                {violations.map((v, i) => (
                  <li key={i}>{v.detail}</li>
                ))}
              </ul>
            ) : null}
          </div>
        ) : null}
        <DripButton onClick={draft} isLoading={loading} disabled={loading || request.trim().length === 0}>
          Draft rewrite
        </DripButton>
      </div>
    );
  }

  // ── Proposal diff ────────────────────────────────────────────────────────
  const totalChanged = proposal.days.filter((d) => d.changed).length;

  return (
    <div className="rounded-md border border-divider bg-bg-elevated p-4 space-y-4">
      <div className="flex items-baseline justify-between gap-2">
        <p className={eyebrow}>AI draft · review before loading</p>
        <button
          type="button"
          onClick={onClose}
          className="font-body text-xs text-text-tertiary hover:text-coral"
        >
          Discard draft
        </button>
      </div>

      {proposal.message ? (
        <p className="font-body text-sm text-text-secondary leading-relaxed">{proposal.message}</p>
      ) : null}

      {totalChanged === 0 ? (
        <p className="font-body text-sm text-text-primary">
          The draft proposes no day changes for this block. Adjust the request and try
          again tomorrow, or edit the days manually below.
        </p>
      ) : (
        proposal.weeks.map((wk) => {
          const wkDays = proposal.days.filter((d) => d.weekNumber === wk.weekNumber);
          const changedDays = wkDays.filter((d) => d.changed);
          const unchangedDays = wkDays.filter((d) => !d.changed);
          return (
            <section key={wk.weekNumber} className="space-y-2">
              <div className="flex items-baseline gap-2 flex-wrap">
                <p className={eyebrow}>Week {wk.weekNumber}</p>
                {changedDays.length > 0 ? (
                  <span className="font-body text-[11px] text-coral">
                    {changedDays.length} day{changedDays.length === 1 ? "" : "s"} change
                  </span>
                ) : null}
                <span className="font-body text-[11px] text-text-tertiary">
                  {wk.mileageBefore} → {wk.mileageAfter} mi
                  {wk.target ? ` (target ${wk.target.min}–${wk.target.max})` : ""}
                </span>
              </div>
              {wk.reason ? (
                <p className="font-body text-sm text-text-secondary leading-relaxed">{wk.reason}</p>
              ) : null}

              <ul className="space-y-1.5">
                {changedDays.map((d) => {
                  const off = Boolean(rejected[d.scheduledWorkoutId]);
                  return (
                    <li
                      key={d.scheduledWorkoutId}
                      className={`rounded-md border border-divider bg-bg-card px-3 py-2 ${off ? "opacity-50" : ""}`}
                    >
                      <label className="flex items-start gap-2 cursor-pointer">
                        <input
                          type="checkbox"
                          className="mt-1 accent-[var(--color-text-primary)]"
                          checked={!off}
                          onChange={(e) =>
                            setRejected((prev) => ({
                              ...prev,
                              [d.scheduledWorkoutId]: !e.target.checked,
                            }))
                          }
                        />
                        <span className="min-w-0">
                          <span className="block font-body text-[11px] text-text-tertiary">
                            {DAY_SHORT[d.dayOfWeek]} · {d.date}
                          </span>
                          <span className="block font-body text-sm text-text-primary">
                            <span className="text-text-tertiary line-through">{snapLabel(d.before)}</span>
                            {"  →  "}
                            <span className="font-semibold">{snapLabel(d.after)}</span>
                          </span>
                          {d.reason ? (
                            <span className="block font-body text-xs text-text-secondary mt-0.5">
                              {d.reason}
                            </span>
                          ) : null}
                        </span>
                      </label>
                    </li>
                  );
                })}
              </ul>

              {unchangedDays.length > 0 ? (
                <div>
                  <button
                    type="button"
                    onClick={() =>
                      setShowUnchanged((prev) => ({ ...prev, [wk.weekNumber]: !prev[wk.weekNumber] }))
                    }
                    className="font-mono text-[10px] uppercase tracking-wider text-text-tertiary hover:text-text-secondary transition-colors"
                  >
                    {showUnchanged[wk.weekNumber] ? "▾" : "▸"} {unchangedDays.length} unchanged day
                    {unchangedDays.length === 1 ? "" : "s"}
                  </button>
                  {showUnchanged[wk.weekNumber] ? (
                    <ul className="mt-1 space-y-0.5">
                      {unchangedDays.map((d) => (
                        <li key={d.scheduledWorkoutId} className="font-body text-xs text-text-tertiary pl-3">
                          {DAY_SHORT[d.dayOfWeek]} · {d.date} · {snapLabel(d.before)}
                        </li>
                      ))}
                    </ul>
                  ) : null}
                </div>
              ) : null}
            </section>
          );
        })
      )}

      {totalChanged > 0 ? (
        <div className="flex items-center gap-3 border-t border-divider pt-3 flex-wrap">
          <DripButton onClick={stage} disabled={acceptedDays.length === 0}>
            Load {acceptedDays.length} change{acceptedDays.length === 1 ? "" : "s"} into editor
          </DripButton>
          <p className="font-body text-xs text-text-tertiary">
            Loading stages the changes — you still review and save through the normal
            apply flow.
          </p>
        </div>
      ) : null}
    </div>
  );
}
