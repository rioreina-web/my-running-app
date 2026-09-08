"use client";

import type { NiggleGroup } from "@/lib/coach-dashboard/types";
import { useOpenWorkout } from "./drawer-context";

/**
 * NigglesPanel — body mentions grouped by area, newest area first. Surface,
 * never interpret: no diagnosis, no severity score, no advice, and the count
 * alone is never trustworthy on its own — the extractor can and does file a
 * clearing statement ("felt good today") as a mention, so every verbatim
 * quote renders, not just the latest. Coral appears once per cluster — on
 * the recurrence flag. Resolved items are struck through.
 */
export function NigglesPanel({ niggles }: { niggles: NiggleGroup[] }) {
  const openWorkout = useOpenWorkout();
  const RECENT_CHIPS = 3;

  return (
    <div className="border-b border-divider py-5">
      <h4 className="mb-3 font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
        Niggles · body mentions, 90 days
      </h4>

      {niggles.length === 0 ? (
        <p className="py-3 font-body text-[13px] italic text-text-tertiary">
          No body-part mentions in the last 90 days.
        </p>
      ) : null}

      {niggles.map((g, i) => (
        <article
          key={i}
          className={`border-t border-divider py-3.5 first:border-t-0 first:pt-0.5 ${
            g.resolved ? "opacity-55" : ""
          }`}
        >
          <div className="flex items-baseline justify-between gap-3">
            <span
              className={`font-display text-[16px] font-bold text-text-primary ${
                g.resolved ? "line-through" : ""
              }`}
            >
              {g.area}
            </span>
            {g.recurrence ? (
              <span className="shrink-0 rounded-full border border-coral px-2 py-[3px] font-mono text-[9px] uppercase tracking-[0.1em] text-coral">
                Recurrence
              </span>
            ) : g.resolved ? (
              <span className="shrink-0 rounded-full border border-divider px-2 py-[3px] font-mono text-[9px] uppercase tracking-[0.1em] text-text-tertiary">
                Resolved
              </span>
            ) : (
              <span className="font-mono text-[10px] uppercase tracking-[0.05em] text-text-secondary">
                {g.mentions} mention{g.mentions > 1 ? "s" : ""}
              </span>
            )}
          </div>

          {/* Date chips — every mention, most recent highlighted. */}
          <div className="mt-2 flex flex-wrap gap-1.5">
            {g.quotes.map((q, qi) => (
              <span
                key={q.date + qi}
                className={`rounded-[3px] border px-1.5 py-[2px] font-mono text-[9.5px] tabular-nums ${
                  qi >= g.quotes.length - RECENT_CHIPS
                    ? "border-text-tertiary text-text-primary"
                    : "border-divider text-text-tertiary"
                }`}
              >
                {q.dateLabel}
              </span>
            ))}
          </div>

          {/* Every verbatim quote — the count alone doesn't say what was
              actually said, and not every mention is a complaint. */}
          <div className="mt-2 space-y-2">
            {g.quotes
              .slice()
              .reverse()
              .map((q, qi) => (
                <div key={q.date + qi}>
                  <p className="font-body text-[13px] italic leading-snug text-text-primary">
                    &ldquo;{q.quote}&rdquo;
                  </p>
                  <span className="font-mono text-[9.5px] uppercase tracking-[0.03em] text-text-tertiary">
                    {q.dateLabel}
                  </span>
                </div>
              ))}
          </div>

          {g.linkDayId ? (
            <button
              type="button"
              onClick={() => openWorkout(g.linkDayId!)}
              className="mt-2 border-b border-dotted border-pace-steady font-mono text-[10px] uppercase tracking-[0.03em] text-pace-mp"
            >
              open session ›
            </button>
          ) : null}
        </article>
      ))}

      <p className="mt-3 font-body text-[11.5px] italic leading-snug text-text-tertiary">
        Surface, never interpret — the athlete&apos;s own words, where and when.
        No diagnosis, no severity score, no advice. The coach reads it.
      </p>
    </div>
  );
}
