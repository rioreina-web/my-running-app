"use client";

import { useMemo, useRef, useState } from "react";
import type { WorkoutChart } from "@/lib/coach-dashboard/types";

/**
 * WorkoutTelemetryChart — Plate 23's "Combined" chart, ported to the web and
 * coach-layered (spec §3 row 3, redesign doc 2026-07-16).
 *
 * Grammar carried over from design-system/ui_kits/ios_app/charts-analytics.jsx
 * `CombinedChart`: a readout-chip row, pace + HR lines over an elevation
 * terrain, an HR-zone ribbon, and a drag-to-scrub crosshair.
 *
 * TWO coach layers the athlete view doesn't have:
 *   - the prescribed target band (the pace window this run was measured against)
 *   - the cut marker + unrun ghost (where the athlete stopped, and the tail
 *     they didn't run, dashed)
 *
 * RE-INKED on port (three-palette rule, 2026-07-03): the athlete-side JSX draws
 * the pace line and pace-axis labels in CORAL. Coral is alerts only. Here the
 * pace line is the blue depth ramp (--color-pace-steady) and pace labels use
 * --color-pace-easy-text. Coral is reserved for the cut marker alone.
 */

// SVG geometry — mirrors the mock (coach-workout-detail-mock.html #tele).
const W = 392;
const PAD_L = 30;
const PAD_R = 20;
const PAD_T = 14;
const PLOT_B = 132;
const RIB_Y = 140;
const RIB_H = 8;
const AXIS_Y = 162;
const H = 186;

// HR-zone ribbon colors. Per open question #5 in the redesign doc, the mock
// keeps the app's current zone colors for fidelity (HR treated as a sanctioned
// fourth palette pending a decision). Thresholds are upper bounds (bpm).
const HR_ZONES = [
  { name: "Z1", max: 130, color: "#4A9E6B" },
  { name: "Z2", max: 142, color: "#2D8A4E" },
  { name: "Z3", max: 150, color: "#C4873A" },
  { name: "Z4", max: 158, color: "#C45A3A" },
  { name: "Z5", max: Infinity, color: "#B83A4A" },
] as const;

function zoneForHR(hr: number) {
  return HR_ZONES.find((z) => hr < z.max) ?? HR_ZONES[HR_ZONES.length - 1];
}

function fmtPace(sec: number): string {
  const s = Math.max(0, Math.round(sec));
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

export function WorkoutTelemetryChart({ chart }: { chart: WorkoutChart }) {
  const svgRef = useRef<SVGSVGElement | null>(null);

  const laps = chart.laps;
  const hasHR = laps.some((l) => typeof l.hr === "number");
  const ranMi = laps.length ? laps[laps.length - 1].mi : 0;
  const plannedMi = Math.max(chart.plannedMi, ranMi);

  // Scales. Pace is inverted on-screen? No — smaller sec = faster; we keep the
  // mock's convention where faster (smaller sec) sits higher toward padT.
  const scales = useMemo(() => {
    const paces = laps.map((l) => l.paceSec);
    const hrs = laps.map((l) => l.hr).filter((v): v is number => typeof v === "number");
    const elevs = laps.map((l) => l.elevFt);
    const pMin = Math.min(...paces, chart.bandLow) - 8;
    const pMax = Math.max(...paces, chart.bandHigh) + 8;
    const hMin = hrs.length ? Math.min(...hrs) - 4 : 120;
    const hMax = hrs.length ? Math.max(...hrs) + 4 : 170;
    const eMin = Math.min(...elevs);
    const eMax = Math.max(...elevs);

    const x = (mi: number) => PAD_L + (mi * (W - PAD_L - PAD_R)) / plannedMi;
    // faster (smaller sec) → higher on screen (nearer PAD_T)
    const yP = (sec: number) => PAD_T + ((sec - pMin) * (PLOT_B - PAD_T)) / (pMax - pMin || 1);
    const yH = (hr: number) => PAD_T + 4 + ((hMax - hr) * (PLOT_B - PAD_T - 8)) / (hMax - hMin || 1);
    const yE = (ft: number) => PLOT_B - ((ft - eMin) * 44) / (eMax - eMin || 1);
    return { x, yP, yH, yE, pMin, pMax, hMin, hMax };
  }, [laps, chart.bandLow, chart.bandHigh, plannedMi]);

  // Crosshair index — opens mid-fade (last third) like the mock.
  const [idx, setIdx] = useState(() => Math.min(laps.length - 1, Math.round(laps.length * 0.66)));
  const cur = laps[Math.min(idx, laps.length - 1)] ?? laps[0];

  function onMove(e: React.PointerEvent<SVGSVGElement> | React.TouchEvent<SVGSVGElement>) {
    const svg = svgRef.current;
    if (!svg) return;
    const rect = svg.getBoundingClientRect();
    const clientX = "touches" in e ? e.touches[0]?.clientX ?? 0 : e.clientX;
    const vx = ((clientX - rect.left) / rect.width) * W;
    const mi = Math.max(0, Math.min(ranMi, ((vx - PAD_L) * plannedMi) / (W - PAD_L - PAD_R)));
    // nearest sample by distance
    let best = 0;
    let bestD = Infinity;
    for (let i = 0; i < laps.length; i++) {
      const d = Math.abs(laps[i].mi - mi);
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    setIdx(best);
  }

  const { x, yP, yH, yE } = scales;

  // Path builders.
  const paceLine = laps.map((l) => `${x(l.mi)},${yP(l.paceSec)}`).join(" ");
  const hrLine = hasHR
    ? laps.filter((l) => typeof l.hr === "number").map((l) => `${x(l.mi)},${yH(l.hr!)}`).join(" ")
    : "";
  const terrain = (() => {
    let d = `M${x(laps[0]?.mi ?? 0)},${yE(laps[0]?.elevFt ?? 0)}`;
    for (const l of laps) d += ` L${x(l.mi)},${yE(l.elevFt)}`;
    d += ` L${x(ranMi)},${PLOT_B} L${x(0)},${PLOT_B} Z`;
    return d;
  })();

  const paceTickVals = [chart.bandLow, chart.bandHigh].map((v) => Math.round(v / 15) * 15);
  const mileTicks = plannedMi > 12 ? [5, 10] : plannedMi > 6 ? [3, 6, 9] : [2, 4, 6];
  const cutMi = chart.cutAtMi;

  const curZone = cur && typeof cur.hr === "number" ? zoneForHR(cur.hr) : null;

  return (
    <div>
      {/* readout chips — Plate 23 pattern */}
      <div className="mb-2.5 grid grid-cols-4 gap-px overflow-hidden rounded-lg border border-divider bg-divider">
        <div className="flex flex-col gap-[3px] bg-bg-elevated px-2.5 py-2">
          <span className="font-mono text-[8px] uppercase tracking-[0.08em] text-text-tertiary">
            Distance
          </span>
          <span className="font-mono text-[13.5px] font-semibold tabular-nums text-text-primary">
            {cur.mi.toFixed(2)}
            <span className="ml-0.5 text-[8.5px] font-medium text-text-tertiary">mi</span>
          </span>
        </div>
        <div className="flex flex-col gap-[3px] bg-bg-elevated px-2.5 py-2">
          <span className="font-mono text-[8px] uppercase tracking-[0.08em] text-text-tertiary">
            Pace
          </span>
          <span
            className="font-mono text-[13.5px] font-semibold tabular-nums"
            style={{ color: "var(--color-pace-steady)" }}
          >
            {fmtPace(cur.paceSec)}
            <span className="ml-0.5 text-[8.5px] font-medium text-text-tertiary">/mi</span>
          </span>
        </div>
        <div className="flex flex-col gap-[3px] bg-bg-elevated px-2.5 py-2">
          <span className="font-mono text-[8px] uppercase tracking-[0.08em] text-text-tertiary">
            Heart rate
          </span>
          <span className="font-mono text-[13.5px] font-semibold tabular-nums text-text-primary">
            {typeof cur.hr === "number" ? cur.hr : "—"}
            {curZone ? (
              <span className="ml-0.5 text-[8.5px] font-medium text-text-tertiary">· {curZone.name}</span>
            ) : null}
          </span>
        </div>
        <div className="flex flex-col gap-[3px] bg-bg-elevated px-2.5 py-2">
          <span className="font-mono text-[8px] uppercase tracking-[0.08em] text-text-tertiary">
            Elevation
          </span>
          <span className="font-mono text-[13.5px] font-semibold tabular-nums text-text-primary">
            {Math.round(cur.elevFt)}
            <span className="ml-0.5 text-[8.5px] font-medium text-text-tertiary">ft</span>
          </span>
        </div>
      </div>

      <svg
        ref={svgRef}
        viewBox={`0 0 ${W} ${H}`}
        width="100%"
        className="block cursor-crosshair touch-none select-none"
        onPointerMove={onMove}
        onPointerDown={onMove}
        onTouchStart={onMove}
        onTouchMove={onMove}
      >
        {/* prescribed target band (coach layer) */}
        <rect
          x={PAD_L}
          y={yP(chart.bandLow)}
          width={x(ranMi) - PAD_L}
          height={Math.abs(yP(chart.bandHigh) - yP(chart.bandLow))}
          fill="rgba(147,185,214,0.26)"
        />
        {/* pace gridlines + blue labels */}
        {paceTickVals.map((s) => (
          <g key={`p${s}`}>
            <line
              x1={PAD_L}
              x2={x(plannedMi)}
              y1={yP(s)}
              y2={yP(s)}
              stroke="var(--color-divider)"
              strokeWidth={1}
              strokeDasharray="1 4"
            />
            <text
              x={PAD_L - 4}
              y={yP(s) + 2.5}
              textAnchor="end"
              fontFamily="var(--font-mono, monospace)"
              fontSize={7.5}
              fill="var(--color-pace-easy-text)"
            >
              {fmtPace(s)}
            </text>
          </g>
        ))}
        {/* mile gridlines */}
        {mileTicks.map((m) => (
          <line
            key={`gm${m}`}
            x1={x(m)}
            x2={x(m)}
            y1={PAD_T}
            y2={PLOT_B}
            stroke="var(--color-divider)"
            strokeWidth={1}
            strokeDasharray="1 4"
          />
        ))}
        {/* elevation terrain */}
        <path d={terrain} fill="var(--color-bg-calendar)" opacity={0.9} />
        {chart.climbLabel ? (
          <text
            x={x(Math.max(1, plannedMi * 0.52))}
            y={PLOT_B - 3}
            fontFamily="var(--font-mono, monospace)"
            fontSize={7}
            fill="var(--color-text-tertiary)"
            letterSpacing="0.04em"
          >
            {`ELEV ${chart.climbLabel.toUpperCase()}`}
          </text>
        ) : null}
        {/* HR line (rose per fidelity note) */}
        {hasHR ? (
          <polyline
            points={hrLine}
            fill="none"
            stroke="#B83A4A"
            strokeWidth={1.4}
            opacity={0.85}
            strokeLinejoin="round"
          />
        ) : null}
        {/* pace line — BLUE (three-palette rule) */}
        <polyline
          points={paceLine}
          fill="none"
          stroke="var(--color-pace-steady)"
          strokeWidth={2.2}
          strokeLinejoin="round"
          strokeLinecap="round"
        />
        {/* unrun ghost (coach layer) */}
        {ranMi < plannedMi && laps.length ? (
          <line
            x1={x(ranMi)}
            y1={yP(laps[laps.length - 1].paceSec)}
            x2={x(plannedMi)}
            y2={yP(laps[laps.length - 1].paceSec)}
            stroke="var(--color-text-tertiary)"
            strokeWidth={1.5}
            strokeDasharray="3 4"
          />
        ) : null}
        {/* HR-zone ribbon */}
        {hasHR
          ? laps.slice(0, -1).map((l, i) =>
              typeof l.hr === "number" ? (
                <rect
                  key={`rib${i}`}
                  x={x(l.mi)}
                  y={RIB_Y}
                  width={x(laps[i + 1].mi) - x(l.mi) + 0.4}
                  height={RIB_H}
                  fill={zoneForHR(l.hr).color}
                  opacity={0.9}
                />
              ) : null,
            )
          : null}
        {/* distance axis */}
        {mileTicks.map((m) => (
          <text
            key={`ax${m}`}
            x={x(m)}
            y={AXIS_Y}
            textAnchor="middle"
            fontFamily="var(--font-mono, monospace)"
            fontSize={7.5}
            fill="var(--color-text-tertiary)"
          >
            {m}
          </text>
        ))}
        <text
          x={x(plannedMi)}
          y={AXIS_Y}
          textAnchor="end"
          fontFamily="var(--font-mono, monospace)"
          fontSize={7.5}
          fill="var(--color-text-tertiary)"
        >
          {`${Math.round(plannedMi)} MI`}
        </text>
        {/* cut marker (coach layer — the one coral element in this cluster) */}
        {typeof cutMi === "number" ? (
          <>
            <line
              x1={x(cutMi)}
              y1={10}
              x2={x(cutMi)}
              y2={RIB_Y + RIB_H}
              stroke="var(--color-coral)"
              strokeWidth={1.5}
            />
            <text
              x={x(cutMi) - 3}
              y={8}
              textAnchor="end"
              fontFamily="var(--font-mono, monospace)"
              fontSize={7.5}
              fontWeight={600}
              fill="var(--color-coral)"
              letterSpacing="0.06em"
            >
              {`CUT · MI ${Math.round(cutMi)}`}
            </text>
          </>
        ) : null}
        {/* crosshair */}
        <line
          x1={x(cur.mi)}
          x2={x(cur.mi)}
          y1={PAD_T}
          y2={RIB_Y + RIB_H}
          stroke="var(--color-text-primary)"
          strokeWidth={1}
          opacity={0.5}
        />
        <circle
          cx={x(cur.mi)}
          cy={yP(cur.paceSec)}
          r={3.5}
          fill="var(--color-pace-steady)"
          stroke="var(--color-bg-base)"
          strokeWidth={1.5}
        />
        {typeof cur.hr === "number" ? (
          <circle
            cx={x(cur.mi)}
            cy={yH(cur.hr)}
            r={3}
            fill="#B83A4A"
            stroke="var(--color-bg-base)"
            strokeWidth={1.5}
          />
        ) : null}
      </svg>

      {/* legend */}
      <div className="mt-2 flex flex-wrap gap-x-3.5 gap-y-1.5 font-mono text-[8.5px] uppercase tracking-[0.06em] text-text-tertiary">
        <span className="flex items-center gap-1">
          <span className="inline-block h-[2px] w-3.5" style={{ background: "var(--color-pace-steady)" }} />
          pace
        </span>
        {hasHR ? (
          <span className="flex items-center gap-1">
            <span className="inline-block h-[2px] w-3.5" style={{ background: "#B83A4A" }} />
            heart rate
          </span>
        ) : null}
        <span className="flex items-center gap-1">
          <span className="inline-block h-2 w-2.5" style={{ background: "var(--color-bg-calendar)" }} />
          elevation
        </span>
        <span className="flex items-center gap-1">
          <span className="inline-block h-2 w-2.5" style={{ background: "rgba(147,185,214,0.26)" }} />
          {`${fmtPace(chart.bandLow)}–${fmtPace(chart.bandHigh)}`}
        </span>
        {ranMi < plannedMi ? (
          <span className="flex items-center gap-1">
            <span
              className="inline-block w-3.5"
              style={{ borderTop: "1.5px dashed var(--color-text-tertiary)" }}
            />
            not run
          </span>
        ) : null}
      </div>

      {chart.caption ? (
        <p className="mt-2.5 font-body text-[12.5px] italic leading-[1.5] text-text-secondary">
          {chart.caption}
        </p>
      ) : null}
    </div>
  );
}
