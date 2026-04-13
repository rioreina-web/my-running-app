"use client";

import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";
import { MOOD_CHART_COLORS, CHART_AXIS, CHART_GRID, CHART_TOOLTIP } from "@/lib/chart-theme";

interface MoodWeekData {
  label: string;
  energized: number;
  positive: number;
  neutral: number;
  tired: number;
  struggling: number;
  injured: number;
}

interface MoodDistributionChartProps {
  data: MoodWeekData[];
  height?: number;
}

const MOOD_KEYS = ["energized", "positive", "neutral", "tired", "struggling", "injured"] as const;

export function MoodDistributionChart({ data, height = 200 }: MoodDistributionChartProps) {
  if (!data.length) return null;

  return (
    <div style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 8, right: 8, left: -20, bottom: 0 }}>
          <CartesianGrid {...CHART_GRID} />
          <XAxis dataKey="label" {...CHART_AXIS} />
          <YAxis {...CHART_AXIS} />
          <Tooltip {...CHART_TOOLTIP} />
          {MOOD_KEYS.map((mood) => (
            <Area
              key={mood}
              type="monotone"
              dataKey={mood}
              stackId="1"
              stroke={MOOD_CHART_COLORS[mood]}
              fill={MOOD_CHART_COLORS[mood]}
              fillOpacity={0.6}
              strokeWidth={0}
            />
          ))}
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
