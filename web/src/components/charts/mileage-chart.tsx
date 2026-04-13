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
import { CHART_COLORS, CHART_AXIS, CHART_GRID, CHART_TOOLTIP } from "@/lib/chart-theme";

interface MileageData {
  label: string;
  miles: number;
}

interface MileageChartProps {
  data: MileageData[];
  height?: number;
}

export function MileageChart({ data, height = 240 }: MileageChartProps) {
  if (!data.length) return null;

  return (
    <div style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 8, right: 8, left: -20, bottom: 0 }}>
          <defs>
            <linearGradient id="mileageGradient" x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor={CHART_COLORS.primary} stopOpacity={0.2} />
              <stop offset="95%" stopColor={CHART_COLORS.primary} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid {...CHART_GRID} />
          <XAxis dataKey="label" {...CHART_AXIS} />
          <YAxis {...CHART_AXIS} />
          <Tooltip {...CHART_TOOLTIP} />
          <Area
            type="monotone"
            dataKey="miles"
            stroke={CHART_COLORS.primary}
            strokeWidth={1.5}
            fill="url(#mileageGradient)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
