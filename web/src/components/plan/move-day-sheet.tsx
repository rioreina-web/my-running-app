"use client";

/**
 * Move-day sheet — athlete picks a new day for a scheduled workout within
 * the current Mon–Sun week.
 *
 * Opens as a bottom sheet on small screens, right drawer on larger ones.
 * Source day and past days are disabled. Quality days get a small warning
 * ("moving a quality day — rest of the week may shift too"); actual
 * rebalance is the `reshape-week` verb, separate flow.
 *
 * Source: docs/athlete-plan-ux.md §2A.
 */

import { useEffect, useState, useTransition } from "react";
import { useRouter } from "next/navigation";

const DAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

export interface MoveDaySheetWorkout {
  id: string;
  scheduled_date: string;
  workout_type: string | null;
  description?: string | null;
  target_distance_miles?: number | null;
  target_pace?: string | null;
}

interface MoveDaySheetProps {
  workout: MoveDaySheetWorkout;
  weekStartDate: string; // YYYY-MM-DD (Monday)
  todayDate: string;     // YYYY-MM-DD
  isQuality: boolean;
  open: boolean;
  onClose: () => void;
}

function addDays(iso: string, days: number): string {
  const [y, m, d] = iso.split("-").map(Number);
  const dt = new Date(y, m - 1, d);
  dt.setDate(dt.getDate() + days);
  return `${dt.getFullYear()}-${String(dt.getMonth() + 1).padStart(2, "0")}-${String(dt.getDate()).padStart(2, "0")}`;
}

function formatWorkoutType(t: string | null | undefined): string {
  if (!t) return "Rest";
  return t.split("_").map((p) => (p ? p.charAt(0).toUpperCase() + p.slice(1) : "")).join(" ");
}

export function MoveDaySheet({
  workout,
  weekStartDate,
  todayDate,
  isQuality,
  open,
  onClose,
}: MoveDaySheetProps) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [error, setError] = useState<string | null>(null);
  const [selected, setSelected] = useState<string | null>(null);

  // Seven days of the current week, each with flags.
  const days = Array.from({ length: 7 }, (_, i) => {
    const iso = addDays(weekStartDate, i);
    return {
      iso,
      label: DAY_LABELS[i],
      isSource: iso === workout.scheduled_date,
      isPast: iso < todayDate,
    };
  });

  // Reset selection whenever the sheet transitions closed → open. Done during
  // render (not in an effect) via the "adjust state when a prop changes"
  // pattern, avoiding the cascading-render hazard of setState-in-effect.
  const [wasOpen, setWasOpen] = useState(open);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open) {
      setSelected(null);
      setError(null);
    }
  }

  // Close on Escape
  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && onClose();
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  async function submit() {
    if (!selected) return;
    setError(null);
    startTransition(async () => {
      try {
        const res = await fetch("/api/shift-day", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            scheduled_workout_id: workout.id,
            new_date: selected,
          }),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok) {
          setError(data.error ?? "Failed to move workout");
          return;
        }
        onClose();
        router.refresh();
      } catch (e) {
        setError(e instanceof Error ? e.message : "Network error");
      }
    });
  }

  if (!open) return null;

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-40 bg-black/30 backdrop-blur-sm"
        onClick={onClose}
      />
      {/* Panel: bottom sheet on mobile, right drawer on wider screens */}
      <div className="fixed z-50 inset-x-0 bottom-0 sm:inset-y-0 sm:right-0 sm:left-auto sm:w-[400px] max-h-[85vh] sm:max-h-none overflow-auto rounded-t-2xl sm:rounded-none bg-bg-card shadow-2xl flex flex-col">
        <div className="px-5 py-4 border-b border-divider flex items-center justify-between">
          <h2 className="font-display text-lg text-text-primary">Move workout</h2>
          <button
            type="button"
            onClick={onClose}
            className="text-text-tertiary hover:text-text-primary text-sm"
          >
            ✕
          </button>
        </div>

        {/* Current workout context */}
        <div className="px-5 py-4 border-b border-divider">
          <div className="font-mono text-[10px] uppercase tracking-wider text-text-tertiary">
            Currently
          </div>
          <div className="mt-1 text-sm font-medium text-text-primary">
            {formatWorkoutType(workout.workout_type)}
            {workout.target_distance_miles != null ? ` · ${workout.target_distance_miles} mi` : ""}
          </div>
          <div className="mt-0.5 font-mono text-[11px] text-text-tertiary">
            on {workout.scheduled_date}
          </div>
        </div>

        {isQuality && (
          <div className="mx-5 mt-4 rounded-md border border-coral/30 bg-coral/5 px-3 py-2 text-xs text-text-secondary">
            Moving a quality day — the rest of your week may need to shift too.
            Use <em>Reshape this week</em> for bigger changes.
          </div>
        )}

        {/* Day picker */}
        <div className="px-5 py-4 flex-1">
          <div className="font-mono text-[10px] uppercase tracking-wider text-text-tertiary mb-2">
            Move to
          </div>
          <div className="grid grid-cols-7 gap-2">
            {days.map((d) => {
              const disabled = d.isSource || d.isPast;
              const isSelected = selected === d.iso;
              return (
                <button
                  key={d.iso}
                  type="button"
                  disabled={disabled}
                  onClick={() => setSelected(d.iso)}
                  className={`flex flex-col items-center rounded-md py-2 px-1 text-xs transition ${
                    isSelected
                      ? "bg-coral text-white"
                      : disabled
                        ? "bg-bg-elevated text-text-tertiary opacity-50 cursor-not-allowed"
                        : "bg-bg-elevated text-text-primary hover:bg-divider"
                  }`}
                  title={
                    d.isSource
                      ? "Current day"
                      : d.isPast
                        ? "Past — can't move here"
                        : ""
                  }
                >
                  <span className="font-mono text-[10px] uppercase tracking-wider opacity-80">
                    {d.label}
                  </span>
                  <span className="mt-0.5 font-mono text-sm">
                    {parseInt(d.iso.split("-")[2], 10)}
                  </span>
                </button>
              );
            })}
          </div>
        </div>

        {error && (
          <div className="mx-5 mb-3 rounded-md border border-red-400/30 bg-red-50 px-3 py-2 text-xs text-red-700">
            {error}
          </div>
        )}

        {/* Actions */}
        <div className="px-5 pt-3 pb-5 border-t border-divider flex items-center justify-end gap-2">
          <button
            type="button"
            onClick={onClose}
            className="rounded-md px-3 py-2 text-sm text-text-secondary hover:text-text-primary"
          >
            Cancel
          </button>
          <button
            type="button"
            disabled={!selected || pending}
            onClick={submit}
            className="rounded-md bg-coral px-4 py-2 text-sm text-white disabled:opacity-50"
          >
            {pending ? "Moving…" : "Move"}
          </button>
        </div>
      </div>
    </>
  );
}
