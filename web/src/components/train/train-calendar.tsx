"use client";

import { useState } from "react";
import {
  PACE_ZONE_COLORS,
  type PaceZone,
} from "@/components/coach/workout-helpers";

// Month calendar — past and planned together, the journey on one grid.
// Logged runs render as a filled dot on the blue pace ramp (neutral ink
// when no pace table anchors the zones); planned workouts render as a
// hollow dot. `activePlan == nil` is first-class: with no plan the grid
// simply shows the training that happened.

export interface CalendarEntry {
  /** Local YYYY-MM-DD. */
  date: string;
  /** Deduped logged miles for the day (0 = none). */
  loggedMiles: number;
  /** Pace zone of the day's longest run, when a pace table anchors it. */
  zone: PaceZone | null;
  /** Planned workout, if a scheduled_workouts row exists for the day. */
  plannedType: string | null;
  plannedMiles: number | null;
  plannedCompleted: boolean;
}

const DAY_HEADERS = ["M", "T", "W", "T", "F", "S", "S"];

function monthKey(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function formatType(t: string | null): string {
  if (!t) return "";
  return t
    .split("_")
    .map((p) => (p ? p.charAt(0).toUpperCase() + p.slice(1) : ""))
    .join(" ");
}

export function TrainCalendar({
  entries,
  today,
}: {
  entries: CalendarEntry[];
  today: string; // local YYYY-MM-DD
}) {
  const byDate = new Map(entries.map((e) => [e.date, e]));

  // Month paging, clamped to the span of the data (plus today's month).
  const months = new Set(entries.map((e) => e.date.slice(0, 7)));
  months.add(today.slice(0, 7));
  const sorted = [...months].sort();
  const minMonth = sorted[0];
  const maxMonth = sorted[sorted.length - 1];

  const [viewMonth, setViewMonth] = useState(() => {
    const [y, m] = today.slice(0, 7).split("-").map(Number);
    return new Date(y, m - 1, 1);
  });
  const viewKey = monthKey(viewMonth);

  const shiftMonth = (delta: number) => {
    setViewMonth((d) => new Date(d.getFullYear(), d.getMonth() + delta, 1));
  };

  // Build the grid: Monday-first, leading blanks before the 1st.
  const year = viewMonth.getFullYear();
  const month = viewMonth.getMonth();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const leadingBlanks = (new Date(year, month, 1).getDay() + 6) % 7;
  const cells: Array<{ day: number; date: string } | null> = [
    ...Array.from({ length: leadingBlanks }, () => null),
    ...Array.from({ length: daysInMonth }, (_, i) => {
      const day = i + 1;
      return {
        day,
        date: `${year}-${String(month + 1).padStart(2, "0")}-${String(day).padStart(2, "0")}`,
      };
    }),
  ];

  const monthLabel = viewMonth.toLocaleDateString("en-US", {
    month: "long",
    year: "numeric",
  });
  const monthMiles = entries
    .filter((e) => e.date.startsWith(viewKey))
    .reduce((sum, e) => sum + e.loggedMiles, 0);

  return (
    <div>
      {/* Month header */}
      <div className="flex items-baseline justify-between gap-4 mb-4">
        <div className="flex items-baseline gap-3">
          <h2 className="font-display text-2xl text-text-primary leading-none">
            {monthLabel}
          </h2>
          {monthMiles > 0 && (
            <span className="font-mono text-xs text-text-tertiary tabular-nums">
              {monthMiles.toFixed(1)} mi logged
            </span>
          )}
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={() => shiftMonth(-1)}
            disabled={viewKey <= minMonth}
            aria-label="Previous month"
            className="rounded-md px-2.5 py-1 font-mono text-sm text-text-secondary hover:text-text-primary hover:bg-bg-elevated disabled:opacity-30 disabled:cursor-not-allowed"
          >
            ‹
          </button>
          <button
            type="button"
            onClick={() => shiftMonth(1)}
            disabled={viewKey >= maxMonth}
            aria-label="Next month"
            className="rounded-md px-2.5 py-1 font-mono text-sm text-text-secondary hover:text-text-primary hover:bg-bg-elevated disabled:opacity-30 disabled:cursor-not-allowed"
          >
            ›
          </button>
        </div>
      </div>

      {/* Day-of-week header */}
      <div className="grid grid-cols-7 gap-1 mb-1">
        {DAY_HEADERS.map((h, i) => (
          <div
            key={i}
            className="text-center font-mono text-[9px] uppercase tracking-wider text-text-tertiary"
          >
            {h}
          </div>
        ))}
      </div>

      {/* Grid */}
      <div className="grid grid-cols-7 gap-1">
        {cells.map((cell, i) => {
          if (!cell) return <div key={`blank-${i}`} />;
          const e = byDate.get(cell.date);
          const isToday = cell.date === today;
          const isFuture = cell.date > today;
          const logged = e && e.loggedMiles > 0;
          const planned = e?.plannedType && e.plannedType.toLowerCase() !== "rest";
          const zoneColor = e?.zone
            ? PACE_ZONE_COLORS[e.zone]
            : "var(--color-text-secondary)";

          return (
            <div
              key={cell.date}
              className={`min-h-[64px] rounded-md p-1.5 ${
                isToday
                  ? "bg-bg-card shadow-[0_1px_4px_rgba(0,0,0,0.06)]"
                  : logged || planned
                    ? "bg-bg-elevated/60"
                    : ""
              }`}
              title={
                [
                  logged ? `${e!.loggedMiles.toFixed(1)} mi logged` : null,
                  planned
                    ? `${formatType(e!.plannedType)}${e!.plannedMiles != null ? ` ${e!.plannedMiles} mi` : ""} planned`
                    : null,
                ]
                  .filter(Boolean)
                  .join(" · ") || undefined
              }
            >
              <div
                className={`font-mono text-[10px] tabular-nums leading-none ${
                  isToday
                    ? "text-coral font-semibold"
                    : "text-text-tertiary"
                }`}
              >
                {cell.day}
              </div>

              {logged ? (
                <div className="mt-1.5 flex items-center gap-1">
                  <span
                    className="w-2 h-2 rounded-full shrink-0"
                    style={{ background: zoneColor }}
                    aria-hidden
                  />
                  <span className="font-mono text-[10px] tabular-nums text-text-primary">
                    {e!.loggedMiles.toFixed(1)}
                  </span>
                </div>
              ) : null}

              {planned && (!logged || isFuture) ? (
                <div className="mt-1 flex items-center gap-1">
                  <span
                    className="w-2 h-2 rounded-full border shrink-0"
                    style={{ borderColor: "var(--color-text-tertiary)" }}
                    aria-hidden
                  />
                  <span className="font-mono text-[10px] tabular-nums text-text-tertiary truncate">
                    {e!.plannedMiles != null ? e!.plannedMiles : formatType(e!.plannedType)}
                  </span>
                </div>
              ) : null}
            </div>
          );
        })}
      </div>

      {/* Legend */}
      <div className="mt-3 flex items-center gap-4">
        <span className="flex items-center gap-1.5">
          <span
            className="w-2 h-2 rounded-full"
            style={{ background: "var(--color-pace-steady)" }}
            aria-hidden
          />
          <span className="font-mono text-[9px] uppercase tracking-wider text-text-tertiary">
            Logged (pace ramp)
          </span>
        </span>
        <span className="flex items-center gap-1.5">
          <span
            className="w-2 h-2 rounded-full border"
            style={{ borderColor: "var(--color-text-tertiary)" }}
            aria-hidden
          />
          <span className="font-mono text-[9px] uppercase tracking-wider text-text-tertiary">
            Planned
          </span>
        </span>
      </div>
    </div>
  );
}
