"use client";

import { useState } from "react";
import { zoneLabelShort } from "@/components/coach/workout-helpers";
import type { DashboardDay, Mood } from "@/lib/coach-dashboard/types";
import { EmptyState } from "@/components/ui/empty-state";
import { Cell } from "./editorial";
import { useOpenWorkout } from "./drawer-context";
import { fmtWeekOf, useWeekFlipper, type WeekRow, type WeekTotals } from "./use-week-flipper";

type TrainMode = "current" | "calendar" | "history";

const MOOD_LABEL: Record<Mood, string> = {
  energized: "Energized",
  positive: "Positive",
  neutral: "Neutral",
  tired: "Tired",
  struggling: "Struggling",
  injured: "Injured",
};

/**
 * TrainSection — §02, Train.
 *
 * The iOS TRAIN tab's own shape (CURRENT / CALENDAR / HISTORY), not a
 * plan-adherence table — replaces "Against the plan" entirely rather than
 * sitting beside it. Only CURRENT is built; the segmenter's other two modes
 * are present but inert, matching iOS's own TrainMode.
 */
export function TrainSection({ days }: { days: DashboardDay[] }) {
  const [mode, setMode] = useState<TrainMode>("current");
  const todayISO = new Date().toISOString().slice(0, 10);
  const { weeks, cur, goTo, weekRows, weekTotals, weekStripMiles, isCurrentWeek } = useWeekFlipper(
    days,
    todayISO,
  );

  if (!weeks.length) {
    return (
      <EmptyState
        variant="data-pending"
        eyebrow="Train"
        title="No logged runs yet. The week view fills in with the first session the athlete records."
      />
    );
  }

  const rows = weekRows(weeks[cur]);
  const totals = weekTotals(rows);
  const maxStripMi = Math.max(1, ...weekStripMiles);

  return (
    <div className="py-5">
      <div className="flex flex-wrap items-center justify-between gap-3 border-b border-divider pb-3">
        <div className="flex gap-1">
          {(["current", "calendar", "history"] as const).map((m) => (
            <button
              key={m}
              type="button"
              onClick={() => setMode(m)}
              className={`border-b-2 px-2.5 pb-2 font-mono text-[10.5px] font-semibold uppercase tracking-[0.08em] ${
                mode === m ? "border-coral text-text-primary" : "border-transparent text-text-tertiary"
              }`}
            >
              {m === "current" ? "Current" : m === "calendar" ? "Calendar" : "History"}
            </button>
          ))}
        </div>

        {mode === "current" ? (
          <div className="flex items-center gap-3">
            <button
              type="button"
              aria-label="Previous week"
              disabled={cur === 0}
              onClick={() => goTo(cur - 1)}
              className="drip-eyebrow px-1 text-text-secondary disabled:opacity-30"
            >
              ‹
            </button>
            <span className="drip-eyebrow min-w-[110px] text-center">{fmtWeekOf(weeks[cur])}</span>
            <button
              type="button"
              aria-label="Next week"
              disabled={isCurrentWeek}
              onClick={() => goTo(cur + 1)}
              className="drip-eyebrow px-1 text-text-secondary disabled:opacity-30"
            >
              ›
            </button>
            {!isCurrentWeek ? (
              <button
                type="button"
                onClick={() => goTo(weeks.length - 1)}
                className="drip-eyebrow text-text-tertiary underline decoration-dotted underline-offset-2"
              >
                This week
              </button>
            ) : null}
          </div>
        ) : null}
      </div>

      {mode !== "current" ? (
        <EmptyState
          variant="optional-empty"
          eyebrow={mode === "calendar" ? "Calendar" : "History"}
          title="Not built yet on the coach portal — see the athlete's Train tab on iOS."
        />
      ) : (
        <>
          {/* Week strip — bar height = miles, doubles as the week selector. */}
          <div className="mt-4 flex h-14 items-end gap-[3px]" role="tablist" aria-label="Week">
            {weeks.map((w, i) => (
              <button
                key={w}
                type="button"
                role="tab"
                title={`${fmtWeekOf(w)} · ${weekStripMiles[i].toFixed(1)} mi`}
                aria-selected={i === cur}
                onClick={() => goTo(i)}
                className={`min-w-[6px] flex-1 ${i === cur ? "bg-text-primary" : "bg-divider hover:bg-text-tertiary"}`}
                style={{ height: `${Math.max(4, (weekStripMiles[i] / maxStripMi) * 100)}%` }}
              />
            ))}
          </div>

          {/* Stat row: Miles / Longest / Quality / Load. */}
          <div className="mt-4 grid grid-cols-2 border-b border-divider md:grid-cols-4">
            <Cell label="Miles" value={totals.mi.toFixed(1)} meta={`${totals.n} sessions · ${totals.days} days`} />
            <Cell
              label="Longest"
              value={totals.longest ? totals.longest.toFixed(1) : "None"}
              unit={totals.longest ? "mi" : undefined}
              meta={totals.longest ? totals.longestDay : "No runs this week"}
            />
            <Cell label="Quality" value={String(totals.quality)} meta={totals.quality ? "Keyed sessions" : "Nothing keyed"} />
            <Cell label="Load" value={String(Math.round(totals.load))} meta="Weighted minutes" />
          </div>

          <DayTable rows={rows} totals={totals} />
        </>
      )}
    </div>
  );
}

function DayTable({ rows, totals }: { rows: WeekRow[]; totals: WeekTotals }) {
  const open = useOpenWorkout();
  return (
    <div className="mt-1">
      <div className="grid grid-cols-5 gap-2 border-b border-divider py-2">
        <span className="drip-eyebrow text-text-tertiary">Day</span>
        <span className="drip-eyebrow text-text-tertiary">Session</span>
        <span className="drip-eyebrow text-right text-text-tertiary">Miles</span>
        <span className="drip-eyebrow text-right text-text-tertiary">Load</span>
        <span className="drip-eyebrow text-text-tertiary">Mood</span>
      </div>
      {rows.map((r) => (
        <DayRow key={r.iso} row={r} onOpen={r.day ? () => open(r.day!.id) : undefined} />
      ))}
      <div className="grid grid-cols-5 gap-2 py-2">
        <span className="drip-eyebrow text-text-tertiary">Total</span>
        <span />
        <span className="drip-stat text-right text-[13px]">{totals.mi.toFixed(2)}</span>
        <span className="drip-stat text-right text-[13px]">{Math.round(totals.load)}</span>
        <span />
      </div>
    </div>
  );
}

function DayRow({ row, onOpen }: { row: WeekRow; onOpen?: () => void }) {
  const d = row.day;
  // A day with no row is not a zero — before today it's rest, after it, it
  // simply hasn't happened. Never collapse either to a 0-mile session.
  const hasRun = d && d.logged !== false && d.miles > 0;

  return (
    <button
      type="button"
      onClick={onOpen}
      disabled={!hasRun}
      className={`grid w-full grid-cols-5 items-center gap-2 border-b border-divider py-2.5 text-left ${
        hasRun ? "hover:bg-bg-elevated" : "cursor-default"
      } ${row.today ? "bg-bg-elevated" : ""}`}
    >
      <span className="drip-stat text-[12.5px]">{row.label}</span>
      {hasRun ? (
        <span className="min-w-0">
          <span className="drip-stat block truncate text-[12.5px]">{d.zone ? zoneLabelShort(d.zone) : "Session"}</span>
          {d.sessions && d.sessions > 1 ? (
            <span className="drip-eyebrow block text-text-tertiary">{d.sessions} sessions</span>
          ) : null}
        </span>
      ) : (
        <span className="drip-stat text-[12.5px] text-text-tertiary">{row.future ? "To come" : "Rest"}</span>
      )}
      <span className="drip-stat text-right text-[12.5px]">{hasRun ? d.miles.toFixed(2) : ""}</span>
      <span className="drip-stat text-right text-[12.5px]">{hasRun && d.load != null ? Math.round(d.load) : ""}</span>
      <span className="drip-stat text-[12.5px]">
        {hasRun ? (
          d.moodLogged === false ? (
            <span className="text-text-tertiary">Not logged</span>
          ) : (
            MOOD_LABEL[d.mood]
          )
        ) : (
          ""
        )}
      </span>
    </button>
  );
}
