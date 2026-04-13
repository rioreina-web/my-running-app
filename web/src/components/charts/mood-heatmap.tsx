"use client";

import { MOOD_CHART_COLORS } from "@/lib/chart-theme";

interface MoodDay {
  date: string;
  mood: string | null;
}

interface MoodHeatmapProps {
  data: MoodDay[];
  weeks?: number;
}

const DAY_LABELS = ["M", "T", "W", "T", "F", "S", "S"];

export function MoodHeatmap({ data, weeks = 12 }: MoodHeatmapProps) {
  // Build a grid: 7 rows (days) x N columns (weeks)
  const grid: (string | null)[][] = Array.from({ length: 7 }, () =>
    Array.from({ length: weeks }, () => null)
  );

  // Fill grid from data (most recent on right)
  const now = new Date();
  data.forEach((d) => {
    const date = new Date(d.date);
    const diffDays = Math.floor((now.getTime() - date.getTime()) / (1000 * 60 * 60 * 24));
    const weekIndex = weeks - 1 - Math.floor(diffDays / 7);
    const dayIndex = (date.getDay() + 6) % 7; // Mon=0
    if (weekIndex >= 0 && weekIndex < weeks) {
      grid[dayIndex][weekIndex] = d.mood;
    }
  });

  return (
    <div className="flex gap-1">
      {/* Day labels */}
      <div className="flex flex-col gap-[3px] mr-1">
        {DAY_LABELS.map((label, i) => (
          <div key={i} className="w-3 h-3 flex items-center justify-center text-[8px] text-text-tertiary font-mono">
            {i % 2 === 0 ? label : ""}
          </div>
        ))}
      </div>

      {/* Grid */}
      {Array.from({ length: weeks }, (_, weekIdx) => (
        <div key={weekIdx} className="flex flex-col gap-[3px]">
          {Array.from({ length: 7 }, (_, dayIdx) => {
            const mood = grid[dayIdx][weekIdx];
            const color = mood ? MOOD_CHART_COLORS[mood.toLowerCase()] : undefined;
            return (
              <div
                key={dayIdx}
                className="w-3 h-3 rounded-[2px]"
                style={{
                  backgroundColor: color || "#E8E4E0",
                  opacity: mood ? 0.8 : 0.3,
                }}
                title={mood || "No data"}
              />
            );
          })}
        </div>
      ))}
    </div>
  );
}
