"use client";

/**
 * Small button that opens MoveDaySheet. Lives as a client island so the
 * parent plan page can stay a server component. Rendering variants:
 *   - "primary" → the labeled "Move day" button inside the TodayBand
 *   - "icon"    → the ⋯ icon button at the end of each DayRow
 */

import { useState } from "react";
import { MoveDaySheet, type MoveDaySheetWorkout } from "./move-day-sheet";

interface Props {
  workout: MoveDaySheetWorkout;
  weekStartDate: string;
  todayDate: string;
  isQuality: boolean;
  variant?: "primary" | "icon";
  label?: string;
}

export function MoveDayButton({
  workout,
  weekStartDate,
  todayDate,
  isQuality,
  variant = "primary",
  label = "Move day",
}: Props) {
  const [open, setOpen] = useState(false);
  return (
    <>
      {variant === "icon" ? (
        <button
          type="button"
          onClick={() => setOpen(true)}
          title="Move this workout"
          className="shrink-0 rounded-md px-2 py-1 text-sm text-text-tertiary hover:text-text-primary hover:bg-bg-elevated"
        >
          ⋯
        </button>
      ) : (
        <button
          type="button"
          onClick={() => setOpen(true)}
          className="rounded-lg border border-divider px-3 py-1.5 text-xs text-text-secondary hover:text-text-primary hover:bg-bg-elevated"
        >
          {label}
        </button>
      )}
      <MoveDaySheet
        workout={workout}
        weekStartDate={weekStartDate}
        todayDate={todayDate}
        isQuality={isQuality}
        open={open}
        onClose={() => setOpen(false)}
      />
    </>
  );
}
