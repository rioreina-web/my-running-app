"use client";

import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from "recharts";
import { CHART_COLORS, CHART_AXIS, CHART_GRID, CHART_TOOLTIP } from "@/lib/chart-theme";

interface PaceData {
  label: string;
  pace: number; // pace in decimal minutes (e.g. 8.75 = 8:45/mi)
}

function formatPace(decimal: number): string {
  const mins = Math.floor(decimal);
  const secs = Math.round((decimal - mins) * 60);
  return `${mins}:${secs.toString().padStart(2, "0")}`;
}

interface PaceTrendChartProps {
  data: PaceData[];
  height?: number;
}

export function PaceTrendChart({ data, height = 240 }: PaceTrendChartProps) {
  if (!data.length) return null;

  return (
    <div style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data} margin={{ top: 8, right: 8, left: -10, bottom: 0 }}>
          <CartesianGrid {...CHART_GRID} />
          <XAxis dataKey="label" {...CHART_AXIS} />
          <YAxis
            {...CHART_AXIS}
            reversed
            tickFormatter={formatPace}
            domain={["dataMin - 0.5", "dataMax + 0.5"]}
          />
          <Tooltip
            {...CHART_TOOLTIP}
            formatter={(value) => [formatPace(Number(value)), "Pace"]}
          />
          <Line
            type="monotone"
            dataKey="pace"
            stroke={CHART_COLORS.primary}
            strokeWidth={1.5}
            dot={{ r: 3, fill: CHART_COLORS.primary, stroke: "#FFFFFF", strokeWidth: 1.5 }}
            activeDot={{ r: 5, fill: CHART_COLORS.primary }}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
