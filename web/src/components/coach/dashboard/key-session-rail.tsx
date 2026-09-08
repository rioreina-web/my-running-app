"use client";

import type { DashboardDay } from "@/lib/coach-dashboard/types";
import { MOOD_COLOR } from "./palette";
import { useOpenWorkout } from "./drawer-context";

/**
 * KeySessionRail — a horizontal rail of the athlete's key sessions (newest
 * first), each a card that opens the drill-down drawer. The explicit "drill in
 * very easily" affordance next to the overlay.
 */
export function KeySessionRail({ days }: { days: DashboardDay[] }) {
  const openWorkout = useOpenWorkout();
  const keys = days.filter((d) => d.key).reverse();

  return (
    <div className="flex gap-2.5 overflow-x-auto pb-2">
      {keys.map((d) => (
        <button
          key={d.id}
          type="button"
          onClick={() => openWorkout(d.id)}
          className="w-[158px] shrink-0 rounded-[11px] border border-divider bg-bg-elevated p-3 text-left transition hover:-translate-y-0.5 hover:border-text-secondary hover:shadow-[0_4px_12px_rgba(0,0,0,0.06)]"
        >
          <div className="font-mono text-[10px] uppercase tracking-[0.06em] text-text-tertiary">
            {d.dateLabel} · {d.dow}
          </div>
          <div className="mt-1.5 font-display text-[16px] font-bold leading-[1.05] text-text-primary">
            {d.label}
          </div>
          <div className="mt-1.5 font-mono text-[11px] tabular-nums text-text-secondary">
            {d.actual}
          </div>
          {d.niggle ? (
            <div className="mt-2 inline-flex items-center gap-1.5 font-mono text-[9px] uppercase tracking-[0.06em] text-coral">
              <span className="h-[5px] w-[5px] rounded-full bg-coral" />
              {d.niggle.area}
            </div>
          ) : null}
          <div className="mt-2.5 flex items-center gap-2">
            <span className="h-2.5 w-2.5 rounded-sm" style={{ background: MOOD_COLOR[d.mood] }} />
            <span className="font-mono text-[9px] uppercase tracking-[0.05em] text-text-tertiary">
              {d.mood}
            </span>
            <span className="ml-auto font-mono text-[9px] uppercase tracking-[0.08em] text-text-tertiary">
              drill ›
            </span>
          </div>
        </button>
      ))}
    </div>
  );
}
