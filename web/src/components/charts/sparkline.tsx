"use client";

import { LineChart, Line, ResponsiveContainer } from "recharts";
import { CHART_COLORS } from "@/lib/chart-theme";

interface SparklineProps {
  data: { value: number }[];
  color?: string;
  width?: number;
  height?: number;
}

export function Sparkline({ data, color = CHART_COLORS.primary, width = 80, height = 24 }: SparklineProps) {
  if (!data.length) return null;

  return (
    <div style={{ width, height }}>
      <ResponsiveContainer width="100%" height="100%">
        <LineChart data={data}>
          <Line
            type="monotone"
            dataKey="value"
            stroke={color}
            strokeWidth={1.5}
            dot={false}
            isAnimationActive={false}
          />
        </LineChart>
      </ResponsiveContainer>
    </div>
  );
}
