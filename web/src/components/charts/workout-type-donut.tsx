"use client";

import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from "recharts";
import { WORKOUT_CHART_COLORS, CHART_TOOLTIP } from "@/lib/chart-theme";

interface WorkoutTypeData {
  type: string;
  count: number;
  label: string;
}

interface WorkoutTypeDonutProps {
  data: WorkoutTypeData[];
  height?: number;
}

export function WorkoutTypeDonut({ data, height = 220 }: WorkoutTypeDonutProps) {
  if (!data.length) return null;
  const total = data.reduce((sum, d) => sum + d.count, 0);

  return (
    <div style={{ height }} className="flex items-center gap-6">
      <div className="flex-1" style={{ height }}>
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie
              data={data}
              cx="50%"
              cy="50%"
              innerRadius={50}
              outerRadius={80}
              dataKey="count"
              strokeWidth={2}
              stroke="#FFFFFF"
            >
              {data.map((entry) => (
                <Cell key={entry.type} fill={WORKOUT_CHART_COLORS[entry.type] || "#9B9590"} />
              ))}
            </Pie>
            <Tooltip {...CHART_TOOLTIP} />
            <text x="50%" y="50%" textAnchor="middle" dominantBaseline="middle">
              <tspan className="font-mono text-lg font-semibold" fill="#1A1815">{total}</tspan>
              <tspan className="font-body text-[10px]" fill="#9B9590" x="50%" dy="16">runs</tspan>
            </text>
          </PieChart>
        </ResponsiveContainer>
      </div>

      <div className="flex flex-col gap-2">
        {data.map((entry) => (
          <div key={entry.type} className="flex items-center gap-2">
            <div
              className="w-2 h-2 rounded-full"
              style={{ backgroundColor: WORKOUT_CHART_COLORS[entry.type] || "#9B9590" }}
            />
            <span className="text-xs text-text-secondary">{entry.label}</span>
            <span className="font-mono text-xs text-text-tertiary">{entry.count}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
