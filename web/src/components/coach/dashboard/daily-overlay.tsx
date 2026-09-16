"use client";

import { useRef, useState, type ReactNode } from "react";
import {
  PACE_ZONE_COLORS,
  zoneLabelShort,
  type PaceZone,
} from "@/components/coach/workout-helpers";
import type { DashboardDay } from "@/lib/coach-dashboard/types";
import { MOOD_COLOR, ZONE_STACK_ORDER } from "./palette";
import { useOpenWorkout } from "./drawer-context";

// Geometry — one SVG, three tracks sharing a date axis.
const W = 1000;
const H = 300;
const M = { l: 24, r: 14 };
const PW = W - M.l - M.r;
const Y_BASE = 176; // workout-bar baseline
const Y_TOP = 34; // top of the tallest bar
const MOOD_Y = 194;
const MOOD_H = 15;
const NIG_Y = 224;
const DAY_Y = 248;
const MON_Y = 262;

// A day's stacked segments: use aggregated zoneMiles, else a single-zone bar.
function segmentsFor(d: DashboardDay): Partial<Record<PaceZone, number>> {
  if (d.zoneMiles && Object.keys(d.zoneMiles).length) return d.zoneMiles;
  if (d.miles > 0 && d.zone) return { [d.zone]: d.miles } as Partial<Record<PaceZone, number>>;
  return {};
}
const sumZones = (zm: Partial<Record<PaceZone, number>>) =>
  Object.values(zm).reduce((s, v) => s + (v ?? 0), 0);

/**
 * DailyOverlay — the hero. One bar PER CALENDAR DAY (multiple uploads summed),
 * stacked by pace zone with quality hatched, over a mood row and a niggle row
 * on the same date axis. Per-day labels; key days get an ink ★ + drill-in.
 */
export function DailyOverlay({
  days,
  paceKey,
}: {
  days: DashboardDay[];
  paceKey?: Array<{ zone: PaceZone; label: string; pace: string }>;
}) {
  const openWorkout = useOpenWorkout();
  const wrapRef = useRef<HTMLDivElement>(null);
  const [tip, setTip] = useState<{ left: number; top: number; node: ReactNode } | null>(null);

  const n = days.length;
  const colW = PW / n;
  const bw = Math.min(15, colW * 0.62);
  const cx = (i: number) => M.l + colW * (i + 0.5);

  const maxTotal = Math.max(...days.map((d) => sumZones(segmentsFor(d))), 1);
  const miMax = Math.max(15, Math.ceil(maxTotal / 5) * 5);
  const barH = (v: number) => (v / miMax) * (Y_BASE - Y_TOP);
  const gridVals: number[] = [];
  for (let v = 0; v <= miMax; v += 5) gridVals.push(v);

  function showTip(e: React.MouseEvent, node: ReactNode) {
    const rect = wrapRef.current?.getBoundingClientRect();
    if (!rect) return;
    let left = e.clientX - rect.left + 12;
    const top = Math.max(0, e.clientY - rect.top - 8);
    if (left + 236 > rect.width) left = e.clientX - rect.left - 236;
    setTip({ left, top, node });
  }
  const hideTip = () => setTip(null);

  return (
    <div ref={wrapRef} className="relative">
      <svg viewBox={`0 0 ${W} ${H}`} preserveAspectRatio="xMidYMid meet" className="block h-auto w-full overflow-visible">
        {/* miles gridlines */}
        {gridVals.map((v) => {
          const y = Y_BASE - barH(v);
          return (
            <g key={`grid-${v}`}>
              <line x1={M.l} y1={y} x2={M.l + PW} y2={y} stroke={v === 0 ? "#E0DAD3" : "#F0ECE6"} strokeWidth="1" />
              <text x={M.l - 4} y={y + 3} textAnchor="end" className="font-mono" fontSize="8.5" fill="#B4ADA5">
                {v === miMax ? `${v} mi` : String(v)}
              </text>
            </g>
          );
        })}

        <text x={M.l + PW + 6} y={MOOD_Y + 11} className="font-mono" fontSize="8.5" fill="#B4ADA5">MOOD</text>
        <text x={M.l + PW + 6} y={NIG_Y + 4} className="font-mono" fontSize="8.5" fill="#B4ADA5">NIG</text>

        {days.map((d, i) => {
          const x = cx(i);
          const isLast = i === n - 1;
          const zm = segmentsFor(d);
          const total = sumZones(zm);
          const isLogged = d.logged !== false;
          const bx = x - bw / 2;

          const dt = new Date(d.date + "T00:00:00");
          const dayNum = String(dt.getDate());
          const monthChanged = i === 0 || new Date(days[i - 1].date + "T00:00:00").getMonth() !== dt.getMonth();

          const tipNode = (
            <>
              <b>{d.dateLabel} · {d.dow}</b>
              <div className="mt-1 text-[#C9C2BA]">{d.label}</div>
              {ZONE_STACK_ORDER.filter((z) => zm[z]).map((z) => (
                <div key={z} className="mt-0.5 flex justify-between gap-3 text-[#C9C2BA]">
                  <span style={{ color: PACE_ZONE_COLORS[z] }}>■ {zoneLabelShort(z)}</span>
                  <b className="text-white">{trim(zm[z]!)} mi</b>
                </div>
              ))}
              {d.key ? <div className="mt-1 text-[#E8B9A6]">★ Key — click to drill in</div> : null}
              {d.niggle ? <div className="mt-1 font-body italic text-[#F0C3AE]">niggle: {d.niggle.area}</div> : null}
            </>
          );

          // stacked segments
          const segs: ReactNode[] = [];
          let acc = 0;
          for (const z of ZONE_STACK_ORDER) {
            const mi = zm[z];
            if (!mi) continue;
            const yTopSeg = Y_BASE - barH(acc + mi);
            const h = barH(acc + mi) - barH(acc);
            segs.push(<rect key={`s-${z}`} x={bx} y={yTopSeg} width={bw} height={Math.max(h, 0.6)} fill={PACE_ZONE_COLORS[z]} rx={acc === 0 ? 1.5 : 0} />);
            if (acc > 0) segs.push(<rect key={`d-${z}`} x={bx} y={Y_BASE - barH(acc) - 0.5} width={bw} height={1} fill="#FFFFFF" pointerEvents="none" />);
            acc += mi;
          }
          const barTop = Y_BASE - barH(total);

          return (
            <g key={d.id}>
              {total > 0 ? (
                <>
                  {segs}
                  {d.key ? (
                    <>
                      <rect x={bx - 1.5} y={barTop - 1.5} width={bw + 3} height={barH(total) + 1.5} rx={2.5} fill="none" stroke="#1A1815" strokeWidth="1.3" pointerEvents="none" />
                      <text x={x} y={barTop - 6} textAnchor="middle" className="font-mono" fontSize="11" fill="#1A1815" pointerEvents="none">★</text>
                    </>
                  ) : null}
                  {/* hover / click hit-area */}
                  <rect
                    x={bx - colW * 0.19}
                    y={Y_TOP}
                    width={bw + colW * 0.38}
                    height={Y_BASE - Y_TOP}
                    fill="transparent"
                    className={d.key ? "cursor-pointer" : ""}
                    onMouseMove={(e) => showTip(e, tipNode)}
                    onMouseLeave={hideTip}
                    onClick={d.key ? () => openWorkout(d.id) : undefined}
                  />
                </>
              ) : (
                <line x1={bx} y1={Y_BASE} x2={x + bw / 2} y2={Y_BASE} stroke="#C3BCB2" strokeWidth="2" />
              )}

              {/* mood cell (faint when unlogged) */}
              <rect
                x={x - MOOD_H / 2}
                y={MOOD_Y}
                width={MOOD_H}
                height={MOOD_H}
                rx={3}
                fill={isLogged ? MOOD_COLOR[d.mood] : "#E4E0DA"}
                onMouseMove={(e) =>
                  showTip(
                    e,
                    <>
                      <b>{d.dateLabel} · {d.dow}</b>
                      <div className="mt-1 text-[#C9C2BA]">{isLogged ? `Mood — ${d.mood}` : "No log this day"}</div>
                    </>,
                  )
                }
                onMouseLeave={hideTip}
              />

              {/* niggle tick */}
              {d.niggle ? (
                <circle
                  cx={x}
                  cy={NIG_Y}
                  r={4.5}
                  fill="#D4592A"
                  onMouseMove={(e) =>
                    showTip(
                      e,
                      <>
                        <b>{d.dateLabel} · {d.dow}</b>
                        <div className="mt-1 tracking-[0.08em] text-[#E8B9A6]">{d.niggle!.area}</div>
                        <div className="mt-1 font-body italic text-[#F0C3AE]">&ldquo;{d.niggle!.quote}&rdquo;</div>
                      </>,
                    )
                  }
                  onMouseLeave={hideTip}
                />
              ) : (
                <circle cx={x} cy={NIG_Y} r={1.4} fill="#DAD5CE" />
              )}

              {/* per-day label + month marker on change */}
              <text x={x} y={DAY_Y} textAnchor="middle" className="font-mono" fontSize="8" fill={isLast ? "#D4592A" : "#9B9590"}>
                {dayNum}
              </text>
              {monthChanged ? (
                <text x={x} y={MON_Y} textAnchor="middle" className="font-mono" fontSize="8" fill="#B4ADA5" letterSpacing="0.04em">
                  {MONTH_ABBR[dt.getMonth()]}
                </text>
              ) : null}
            </g>
          );
        })}
      </svg>

      {/* pace key — swatch + zone + the athlete's own pace */}
      {paceKey && paceKey.length ? (
        <div className="mt-3 flex flex-wrap items-center gap-x-3.5 gap-y-1.5 border-t border-divider pt-3">
          <span className="font-mono text-[9px] uppercase tracking-[0.12em] text-text-tertiary">Pace zones</span>
          {paceKey.map((k) => (
            <span
              key={k.zone}
              className="inline-flex items-center gap-1.5 font-mono text-[9.5px] uppercase tracking-[0.04em] text-text-secondary"
            >
              <span className="h-2.5 w-2.5 rounded-[2px]" style={{ background: PACE_ZONE_COLORS[k.zone] }} />
              {k.label} <span className="tabular-nums text-text-tertiary">{k.pace}</span>
            </span>
          ))}
        </div>
      ) : (
        <div className="mt-3">
          <div
            className="h-2 rounded-[5px]"
            style={{ background: "linear-gradient(90deg,#93B9D6,#74A8CC,#578FC0,#3F7CB5,#2F66A8,#27549B,#20448B,#1A3679,#142964,#0E1D4E)" }}
          />
          <div className="mt-1.5 flex justify-between font-mono text-[9px] uppercase tracking-[0.06em] text-text-tertiary">
            <span className="text-pace-easy-text">Easy</span>
            <span>Steady</span>
            <span>MP</span>
            <span>LT</span>
            <span>5K</span>
            <span className="text-pace-mile">Mile</span>
          </div>
        </div>
      )}

      {tip ? (
        <div
          className="pointer-events-none absolute z-10 max-w-[236px] rounded-[9px] bg-text-primary px-2.5 py-2 font-mono text-[11px] text-white shadow-[0_8px_24px_rgba(0,0,0,0.22)]"
          style={{ left: tip.left, top: tip.top }}
        >
          {tip.node}
        </div>
      ) : null}
    </div>
  );
}

const MONTH_ABBR = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"];
const trim = (mi: number) => (Number.isInteger(mi) ? `${mi}` : mi.toFixed(1));
