"use client";

import { useState } from "react";
import { DailyVolumeChart, type DayVolume } from "./daily-volume-chart";

/**
 * Athlete-facing wrapper for the daily volume-by-pace chart: a small week
 * picker over the athlete's materialized plan weeks, feeding the shared
 * DailyVolumeChart. Every day here is concrete (real scheduled_workouts), so
 * nothing is estimated — the coach sees the athlete's actual daily shape.
 */
export interface WeekVolume {
  weekNumber: number;
  label: string;
  days: DayVolume[];
}

export function AthleteWeekVolume({
  weeks,
  initialWeekNumber,
}: {
  weeks: WeekVolume[];
  initialWeekNumber?: number;
}) {
  const fallback = weeks[0]?.weekNumber;
  const start = weeks.some((w) => w.weekNumber === initialWeekNumber)
    ? initialWeekNumber!
    : fallback;
  const [weekNumber, setWeekNumber] = useState<number | undefined>(start);
  const current = weeks.find((w) => w.weekNumber === weekNumber) ?? weeks[0];
  if (!current) return null;

  return (
    <div>
      <div className="flex items-center justify-between gap-3 mb-3 flex-wrap">
        <p className="font-mono text-[10px] font-medium tracking-[0.12em] uppercase text-text-secondary">
          Daily volume · by pace
        </p>
        <div className="flex items-center gap-1 flex-wrap">
          {weeks.map((w) => {
            const selected = w.weekNumber === current.weekNumber;
            return (
              <button
                key={w.weekNumber}
                type="button"
                onClick={() => setWeekNumber(w.weekNumber)}
                className={`font-mono text-[10px] uppercase tracking-wider px-2 py-1 rounded-md transition-colors ${
                  selected
                    ? "bg-text-primary text-bg-base"
                    : "text-text-tertiary hover:text-text-secondary"
                }`}
              >
                W{w.weekNumber}
              </button>
            );
          })}
        </div>
      </div>
      <DailyVolumeChart days={current.days} emptyLabel="No scheduled volume this week." />
    </div>
  );
}
