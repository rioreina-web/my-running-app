"use client";

import {
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Legend,
} from "recharts";
import { CHART_COLORS, CHART_AXIS, CHART_GRID, CHART_TOOLTIP } from "@/lib/chart-theme";

interface ComplianceData {
  label: string;
  planned: number;
  actual: number;
}

interface ComplianceChartProps {
  data: ComplianceData[];
  height?: number;
}

export function ComplianceChart({ data, height = 200 }: ComplianceChartProps) {
  if (!data.length) return null;

  return (
    <div style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <BarChart data={data} margin={{ top: 8, right: 8, left: -20, bottom: 0 }} barGap={2}>
          <CartesianGrid {...CHART_GRID} />
          <XAxis dataKey="label" {...CHART_AXIS} />
          <YAxis {...CHART_AXIS} />
          <Tooltip {...CHART_TOOLTIP} />
          <Legend
            iconType="square"
            iconSize={8}
            wrapperStyle={{ fontFamily: "var(--font-mono)", fontSize: "10px", color: "#9B9590" }}
          />
          <Bar dataKey="planned" fill={CHART_COLORS.primary} opacity={0.25} radius={[2, 2, 0, 0]} />
          <Bar dataKey="actual" fill={CHART_COLORS.primary} radius={[2, 2, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
