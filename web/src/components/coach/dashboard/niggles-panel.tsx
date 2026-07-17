"use client";

import type { NiggleGroup } from "@/lib/coach-dashboard/types";
import { useOpenWorkout } from "./drawer-context";

/**
 * NigglesPanel — body mentions grouped by area (verbatim quote, count, recency,
 * recurrence flag). Surface, never interpret: no diagnosis, no severity score,
 * no advice. Coral appears once per cluster — on the recurrence flag. Resolved
 * items are struck through. Each active group links to its session.
 */
export function NigglesPanel({ niggles }: { niggles: NiggleGroup[] }) {
  const openWorkout = useOpenWorkout();

  return (
    <div className="rounded-xl border border-divider bg-bg-card p-5">
      <h4 className="mb-3 font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
        Niggles · body mentions, 90 days
      </h4>

      {niggles.length === 0 ? (
        <p className="py-3 font-body text-[13px] italic text-text-tertiary">
          No body-part mentions in the last 90 days.
        </p>
      ) : null}

      {niggles.map((g, i) => (
        <div
          key={i}
          className={`border-t border-divider py-3.5 first:border-t-0 first:pt-0.5 ${
            g.resolved ? "opacity-55" : ""
          }`}
        >
          <div className="flex items-center gap-2.5">
            <span
              className={`font-display text-[16px] font-bold text-text-primary ${
                g.resolved ? "line-through" : ""
              }`}
            >
              {g.area}
            </span>
            <span className="font-mono text-[10px] uppercase tracking-[0.05em] text-text-secondary">
              {g.mentions} mention{g.mentions > 1 ? "s" : ""}
              {g.resolved ? "" : ` · latest ${g.latestDate}`}
            </span>
            {g.recurrence ? (
              <span className="ml-auto rounded-full border border-coral px-2 py-[3px] font-mono text-[9px] uppercase tracking-[0.1em] text-coral">
                Recurrence
              </span>
            ) : g.resolved ? (
              <span className="ml-auto rounded-full border border-divider px-2 py-[3px] font-mono text-[9px] uppercase tracking-[0.1em] text-text-tertiary">
                Resolved
              </span>
            ) : null}
          </div>

          <div className="mt-1.5 font-body text-[13.5px] italic leading-snug text-text-primary">
            &ldquo;{g.latestQuote}&rdquo;
          </div>

          <div className="mt-1.5 font-mono text-[10px] uppercase tracking-[0.03em] text-text-tertiary">
            {g.resolved ? `${g.latestDate} · marked resolved` : g.latestDate}
            {g.otherDates.length ? ` · also ${g.otherDates.join(", ")}` : ""}
            {g.linkDayId ? (
              <>
                {" · "}
                <button
                  type="button"
                  onClick={() => openWorkout(g.linkDayId!)}
                  className="border-b border-dotted border-pace-steady text-pace-mp"
                >
                  open session ›
                </button>
              </>
            ) : null}
          </div>
        </div>
      ))}

      <p className="mt-3 font-body text-[11.5px] italic leading-snug text-text-tertiary">
        Surface, never interpret — the athlete&apos;s own words, where and when.
        No diagnosis, no severity score, no advice. The coach reads it.
      </p>
    </div>
  );
}
