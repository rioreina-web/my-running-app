"use client";

import {
  Area,
  AreaChart,
  CartesianGrid,
  ReferenceArea,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from "recharts";
import { CHART_AXIS, CHART_GRID, CHART_TOOLTIP } from "@/lib/chart-theme";
import type { WorkoutChart } from "@/lib/coach-dashboard/types";

// Act 3 pace trace. Pace is plotted on an INVERTED y-axis so faster reads as
// higher — the intuition every runner already has. Fill is the blue pace ramp
// (pace = blue, always); the prescribed band is a neutral paper wash, never
// green, because a "safe zone" band goes gray under the three-palette rule.

function fmtPace(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function PaceTrace({ chart, height = 200 }: { chart: WorkoutChart; height?: number }) {
  const data = chart.laps.map((l) => ({ mi: l.mi, paceSec: l.paceSec }));
  if (data.length < 2) return null;

  const paces = data.map((d) => d.paceSec).filter((p) => p > 0);
  const min = Math.min(...paces);
  const max = Math.max(...paces);
  const pad = Math.max(8, (max - min) * 0.15);

  // Only draw the band when it's a real prescribed window, not the collapsed
  // single-value fallback the builder uses when there's no prescription.
  const hasBand = chart.bandHigh > chart.bandLow;

  return (
    <div style={{ height }}>
      <ResponsiveContainer width="100%" height="100%">
        <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 4, left: 4 }}>
          <defs>
            <linearGradient id="paceTraceFill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="var(--color-pace-lt)" stopOpacity={0.28} />
              <stop offset="100%" stopColor="var(--color-pace-lt)" stopOpacity={0.02} />
            </linearGradient>
          </defs>
          <CartesianGrid {...CHART_GRID} />
          {hasBand && (
            <ReferenceArea
              y1={chart.bandLow}
              y2={chart.bandHigh}
              fill="var(--color-text-tertiary)"
              fillOpacity={0.1}
              strokeOpacity={0}
            />
          )}
          <XAxis
            {...CHART_AXIS}
            dataKey="mi"
            type="number"
            domain={[0, "dataMax"]}
            tickFormatter={(v: number) => `${v.toFixed(1)}`}
            unit=" mi"
          />
          <YAxis
            {...CHART_AXIS}
            reversed
            domain={[min - pad, max + pad]}
            tickFormatter={fmtPace}
            width={44}
          />
          <Tooltip
            {...CHART_TOOLTIP}
            formatter={(value) => [`${fmtPace(Number(value))}/mi`, "Pace"]}
            labelFormatter={(label) => `${Number(label).toFixed(2)} mi`}
          />
          <Area
            type="monotone"
            dataKey="paceSec"
            stroke="var(--color-pace-lt)"
            strokeWidth={1.5}
            fill="url(#paceTraceFill)"
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  );
}
