"use client";

import { BarChart, Bar, XAxis, YAxis, CartesianGrid, Tooltip, ResponsiveContainer } from "recharts";
import { CHART_COLORS, CHART_AXIS, CHART_GRID, CHART_TOOLTIP } from "@/lib/chart-theme";

interface FrequencyData {
  label: string;
  runs: number;
}

interface RunFrequencyChartProps {
  data: FrequencyData[];
  height?: number;
}

export function RunFrequencyChart({ data, height = 160 }: RunFrequencyChartProps) {
  if (!data.length) return null;

  return (
    <div style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 8, right: 8, left: -20, bottom: 0 }}>
          <CartesianGrid {...CHART_GRID} />
          <XAxis dataKey="label" {...CHART_AXIS} />
          <YAxis {...CHART_AXIS} allowDecimals={false} />
          <Tooltip {...CHART_TOOLTIP} />
          <Bar dataKey="runs" fill={CHART_COLORS.primary} radius={[3, 3, 0, 0]} opacity={0.7} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
