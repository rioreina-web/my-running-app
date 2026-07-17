"use client";

import { useState } from "react";
import { PACE_ZONE_COLORS } from "@/components/coach/workout-helpers";
import { EmptyState } from "@/components/ui/empty-state";
import { MoodBadge } from "@/components/ui/mood-badge";
import type { DashboardDay } from "@/lib/coach-dashboard/types";
import { useOpenWorkout } from "./drawer-context";

/**
 * LogFeed — the last 14 days, prescribed vs. actual, with mood pill, inline
 * niggle chip, and expandable voice note. Key sessions are tinted and carry a
 * "Key · drill" badge that opens the drawer. Rest days use the empty-state
 * component (never an em-dash).
 */
export function LogFeed({ days }: { days: DashboardDay[] }) {
  // Show logged days (activity + explicit rest); skip no-log calendar gaps.
  const rows = days.filter((d) => d.logged !== false).slice(-14).reverse();
  return (
    <div className="rounded-xl border border-divider bg-bg-card p-5">
      {rows.map((d) => (
        <LogRow key={d.id} d={d} />
      ))}
    </div>
  );
}

function LogRow({ d }: { d: DashboardDay }) {
  const openWorkout = useOpenWorkout();
  const isRest = d.zone === null;

  return (
    <div
      className={`grid grid-cols-[78px_1fr] gap-4 border-t border-divider py-4 first:border-t-0 ${
        d.key
          ? "-mx-3 rounded-lg bg-[linear-gradient(90deg,rgba(26,24,21,0.035),transparent_60%)] px-3"
          : ""
      }`}
    >
      <div className="font-mono text-[11px] uppercase leading-normal text-text-secondary">
        <span className="text-[13px] font-semibold text-text-primary">{d.dateLabel}</span>
        <br />
        {d.dow}
      </div>

      <div className="min-w-0">
        {isRest ? (
          <>
            <div className="flex items-center gap-2.5">
              <span className="h-[9px] w-[9px] rounded-full bg-[#C3BCB2]" />
              <span className="font-display text-[16px] font-bold text-text-secondary">
                Rest day
              </span>
            </div>
            <div className="mt-1">
              <EmptyState
                variant="optional-empty"
                eyebrow="Nothing to reconcile"
                title="Planned rest. Recovery is part of the block."
                className="items-start py-2 text-left"
              />
            </div>
          </>
        ) : (
          <>
            <div className="flex flex-wrap items-center gap-2.5">
              <span
                className="h-[9px] w-[9px] rounded-full"
                style={{ background: d.zone ? PACE_ZONE_COLORS[d.zone] : "#93B9D6" }}
              />
              <span className="font-display text-[16px] font-bold text-text-primary">
                {d.label}
              </span>
              <span className="font-mono text-[13px] text-text-tertiary">→</span>
              <span className="font-mono text-[13px] font-medium tabular-nums text-text-primary">
                {d.actual}
              </span>
              {d.delta ? (
                <span
                  className={`rounded-full px-2 py-0.5 font-mono text-[10.5px] uppercase tracking-[0.04em] ${
                    d.onTarget ? "bg-pace-mp/12 text-pace-lt" : "bg-bg-calendar text-text-secondary"
                  }`}
                >
                  {d.delta}
                </span>
              ) : null}
              <MoodBadge mood={d.mood} />
              {d.niggle ? (
                <span className="inline-flex items-center gap-1.5 rounded-full bg-coral/12 px-2 py-0.5 font-mono text-[10px] uppercase tracking-[0.05em] text-coral-dark">
                  <span className="h-[5px] w-[5px] rounded-full bg-coral" />
                  {d.niggle.area}
                </span>
              ) : null}
              {d.key ? (
                <button
                  type="button"
                  onClick={() => openWorkout(d.id)}
                  className="inline-flex items-center gap-1 rounded-full bg-text-primary px-2.5 py-1 font-mono text-[9px] uppercase tracking-[0.1em] text-white hover:bg-black"
                >
                  ★ Key · drill
                </button>
              ) : null}
            </div>
            {d.note ? <Note text={d.note} /> : null}
          </>
        )}
      </div>
    </div>
  );
}

function Note({ text }: { text: string }) {
  const LIMIT = 116;
  const [expanded, setExpanded] = useState(false);
  if (text.length <= LIMIT) {
    return (
      <p className="mt-2.5 font-body text-[13.5px] italic leading-snug text-text-primary">
        &ldquo;{text}&rdquo;
      </p>
    );
  }
  return (
    <p className="mt-2.5 font-body text-[13.5px] italic leading-snug text-text-primary">
      &ldquo;{expanded ? text : `${text.slice(0, LIMIT)}… `}
      {!expanded ? (
        <button
          type="button"
          onClick={() => setExpanded(true)}
          className="ml-1 border-b border-dotted border-text-tertiary font-mono text-[10px] uppercase not-italic tracking-[0.06em] text-text-tertiary"
        >
          more
        </button>
      ) : null}
      &rdquo;
    </p>
  );
}
