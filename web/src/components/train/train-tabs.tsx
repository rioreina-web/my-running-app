"use client";

import { useState, type ReactNode } from "react";

// Train's three modes, mirroring the iOS Train tab segmenter:
//   CURRENT  — this week + today
//   CALENDAR — month view, past runs + planned workouts together
//   HISTORY  — longer-arc analytics (pace × volume, weekly volume)
// All three panels arrive server-rendered as children; this component only
// owns which one is visible.

type Mode = "current" | "calendar" | "history";

const MODES: Array<{ value: Mode; label: string }> = [
  { value: "current", label: "Current" },
  { value: "calendar", label: "Calendar" },
  { value: "history", label: "History" },
];

export function TrainTabs({
  current,
  calendar,
  history,
}: {
  current: ReactNode;
  calendar: ReactNode;
  history: ReactNode;
}) {
  const [mode, setMode] = useState<Mode>("current");

  return (
    <div>
      <div
        role="tablist"
        aria-label="Train view"
        className="flex items-center gap-1 border-b border-divider mb-6"
      >
        {MODES.map((m) => {
          const isActive = mode === m.value;
          return (
            <button
              key={m.value}
              role="tab"
              aria-selected={isActive}
              type="button"
              onClick={() => setMode(m.value)}
              className={`px-4 py-2.5 font-mono text-[11px] uppercase tracking-[0.14em] transition-colors border-b-2 -mb-px ${
                isActive
                  ? "text-coral border-coral"
                  : "text-text-secondary border-transparent hover:text-text-primary"
              }`}
            >
              {m.label}
            </button>
          );
        })}
      </div>

      <div hidden={mode !== "current"}>{current}</div>
      <div hidden={mode !== "calendar"}>{calendar}</div>
      <div hidden={mode !== "history"}>{history}</div>
    </div>
  );
}
