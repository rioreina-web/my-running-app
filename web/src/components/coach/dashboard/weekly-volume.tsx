"use client";

import { useRef, useState, type ReactNode } from "react";
import {
  PACE_ZONE_COLORS,
  zoneLabelShort,
  type PaceZone,
} from "@/components/coach/workout-helpers";
import { EmptyState } from "@/components/ui/empty-state";
import type { WeeklyVolumeWeek } from "@/lib/coach-dashboard/types";
import { ZONE_STACK_ORDER, isQualityZone } from "./palette";

const W = 660;
const H = 260;
const M = { l: 30, r: 12, t: 14, b: 30 };
const PW = W - M.l - M.r;
const PH = H - M.t - M.b;

const weekTotal = (w: WeeklyVolumeWeek) =>
  Object.values(w.zoneMiles).reduce((s, v) => s + (v ?? 0), 0);

/**
 * WeeklyVolume — 12 weeks of mileage as stacked bars by pace zone (pale Easy
 * → navy quality, quality hatched), with a dashed target cap per week and the
 * current week outlined in coral. Macro view alongside the daily overlay.
 */
export function WeeklyVolume({ weeks }: { weeks: WeeklyVolumeWeek[] }) {
  const wrapRef = useRef<HTMLDivElement>(null);
  const [tip, setTip] = useState<{ left: number; top: number; node: ReactNode } | null>(null);

  const n = weeks.length;
  const grandTotal = weeks.reduce((s, w) => s + weekTotal(w), 0);
  if (grandTotal <= 0) {
    return <EmptyState variant="data-pending" title="No weekly volume to chart yet." />;
  }
  const maxV = Math.max(...weeks.map((w) => Math.max(weekTotal(w), w.targetMiles)), 1);
  const yMax = Math.ceil(maxV / 10) * 10;
  const y = (v: number) => M.t + PH - (v / yMax) * PH;
  const slot = PW / n;
  const bw = Math.min(30, slot * 0.6);

  const cur = weeks[n - 1];
  const prev = weeks[n - 2];
  const curTotal = Math.round(weekTotal(cur));
  const prevTotal = Math.round(weekTotal(prev));
  const delta = curTotal - prevTotal;
  const easyMi = Object.entries(cur.zoneMiles).reduce(
    (s, [z, mi]) => s + (isQualityZone(z as PaceZone) ? 0 : mi ?? 0),
    0,
  );
  const easyPct = curTotal > 0 ? Math.round((easyMi / curTotal) * 100) : 0;

  function showTip(e: React.MouseEvent, w: WeeklyVolumeWeek) {
    const rect = wrapRef.current?.getBoundingClientRect();
    if (!rect) return;
    const total = Math.round(weekTotal(w));
    const rows = ZONE_STACK_ORDER.filter((z) => w.zoneMiles[z]).map((z) => (
      <div key={z} className="mt-0.5 flex justify-between gap-3.5 text-[#C9C2BA]">
        <span style={{ color: PACE_ZONE_COLORS[z] }}>■ {zoneLabelShort(z)}</span>
        <b className="font-semibold text-white">{w.zoneMiles[z]} mi</b>
      </div>
    ));
    let left = e.clientX - rect.left + 12;
    const top = Math.max(0, e.clientY - rect.top - 10);
    if (left + 150 > rect.width) left = e.clientX - rect.left - 150;
    setTip({
      left,
      top,
      node: (
        <>
          <b className="text-white">{w.label}</b>
          {rows}
          <div className="mt-1.5 flex justify-between gap-3.5 border-t border-white/20 pt-1 text-[#C9C2BA]">
            <span>Total</span>
            <b className="font-semibold text-white">{total} mi</b>
          </div>
          <div className="mt-0.5 flex justify-between gap-3.5 text-[#C9C2BA]">
            <span>Target</span>
            <b className="font-semibold text-white">{w.targetMiles} mi</b>
          </div>
        </>
      ),
    });
  }

  return (
    <div>
      <div className="my-3 grid grid-cols-3">
        <Tile label="Target" value={`${cur.targetMiles}`} unit="mi" sub="this week" />
        <Tile
          label="Vs. prior"
          value={`${delta >= 0 ? "+" : ""}${delta}`}
          unit="mi"
          sub={`${delta >= 0 ? "▲" : "▼"} ${prevTotal > 0 ? Math.abs(Math.round((delta / prevTotal) * 100)) : 0}%`}
        />
        <Tile label="Easy / hard" value={`${easyPct}/${100 - easyPct}`} unit="%" sub={`${Math.round(easyMi)} easy mi`} />
      </div>

      <div ref={wrapRef} className="relative">
        <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet" className="block h-auto w-full overflow-visible">
          <defs>
            <pattern id="volHatch" width="5" height="5" patternTransform="rotate(45)" patternUnits="userSpaceOnUse">
              <line x1="0" y1="0" x2="0" y2="5" stroke="#F5F3F0" strokeWidth="1.2" strokeOpacity="0.5" />
            </pattern>
          </defs>

          {[0, 20, 40, 60].filter((v) => v <= yMax).map((v) => (
            <g key={v}>
              <line x1={M.l} y1={y(v)} x2={M.l + PW} y2={y(v)} stroke={v === 0 ? "#E0DAD3" : "#EFEBE6"} strokeWidth="1" />
              <text x={M.l - 6} y={y(v) + 3} textAnchor="end" className="font-mono" fontSize="9" fill="#9B9590">
                {v === 60 ? "60 MI" : String(v)}
              </text>
            </g>
          ))}

          {weeks.map((w, i) => {
            const cx = M.l + slot * (i + 0.5);
            const x = cx - bw / 2;
            let acc = 0;
            const segs: ReactNode[] = [];
            for (const z of ZONE_STACK_ORDER) {
              const mi = w.zoneMiles[z];
              if (!mi) continue;
              const yTop = y(acc + mi);
              const h = y(acc) - yTop;
              segs.push(
                <rect key={`s-${z}`} x={x} y={yTop} width={bw} height={Math.max(h, 0.5)} fill={PACE_ZONE_COLORS[z]} />,
              );
              if (isQualityZone(z)) {
                segs.push(<rect key={`h-${z}`} x={x} y={yTop} width={bw} height={Math.max(h, 0.5)} fill="url(#volHatch)" pointerEvents="none" />);
              }
              if (acc > 0) {
                segs.push(<rect key={`d-${z}`} x={x} y={y(acc) - 0.75} width={bw} height={1.5} fill="#F5F3F0" pointerEvents="none" />);
              }
              acc += mi;
            }
            const ty = y(w.targetMiles);
            const total = weekTotal(w);
            return (
              <g key={w.label}>
                {segs}
                {w.targetMiles > 0 ? (
                  <line x1={x - 3} y1={ty} x2={x + bw + 3} y2={ty} stroke="#1A1815" strokeWidth="1.3" strokeDasharray="3 2" opacity="0.5" />
                ) : null}
                {w.current ? (
                  <rect x={x - 2} y={y(total) - 2} width={bw + 4} height={M.t + PH - y(total) + 2} rx={3} fill="none" stroke="#D4592A" strokeWidth="1.5" />
                ) : null}
                <text x={cx} y={M.t + PH + 16} textAnchor="middle" className="font-mono" fontSize="9" fill={w.current ? "#D4592A" : "#9B9590"}>
                  {w.label.toUpperCase()}
                </text>
                {/* transparent hover hit-area for the whole column */}
                <rect
                  x={cx - slot / 2}
                  y={M.t}
                  width={slot}
                  height={PH}
                  fill="transparent"
                  onMouseMove={(e) => showTip(e, w)}
                  onMouseLeave={() => setTip(null)}
                />
              </g>
            );
          })}
        </svg>

        {tip ? (
          <div
            className="pointer-events-none absolute z-10 min-w-[120px] rounded-[9px] bg-text-primary px-2.5 py-2 font-mono text-[11px] text-white shadow-[0_8px_24px_rgba(0,0,0,0.22)]"
            style={{ left: tip.left, top: tip.top }}
          >
            {tip.node}
          </div>
        ) : null}
      </div>

      <div className="mt-4">
        <div className="h-2 rounded-[5px]" style={{ background: "linear-gradient(90deg,#93B9D6,#74A8CC,#578FC0,#3F7CB5,#2F66A8,#27549B,#20448B,#1A3679,#142964,#0E1D4E)" }} />
        <div className="mt-1.5 flex justify-between font-mono text-[9px] uppercase tracking-[0.06em] text-text-tertiary">
          <span className="text-pace-easy-text">Easy 9:10</span>
          <span>MP 7:57</span>
          <span>LT 7:31</span>
          <span>5K 6:56</span>
          <span className="text-pace-mile">Mile 6:20</span>
        </div>
      </div>
    </div>
  );
}

function Tile({ label, value, unit, sub }: { label: string; value: string; unit: string; sub: string }) {
  return (
    <div className="border-r border-divider py-1 pr-4 last:border-r-0">
      <div className="font-mono text-[9px] uppercase tracking-[0.1em] text-text-tertiary">{label}</div>
      <div className="mt-1 font-mono text-[21px] font-semibold tabular-nums text-text-primary">
        {value}
        <span className="text-[11px] text-text-tertiary"> {unit}</span>
      </div>
      <div className="mt-0.5 font-mono text-[9px] uppercase tracking-[0.06em] text-text-secondary">{sub}</div>
    </div>
  );
}
