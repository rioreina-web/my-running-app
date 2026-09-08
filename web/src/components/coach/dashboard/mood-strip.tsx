import type { MoodSummary } from "@/lib/coach-dashboard/types";
import { MOOD_COLOR } from "./palette";
import { Rich } from "./rich-text";

/**
 * MoodStrip — a 28-day strip of mood labels (mood-only warm palette) plus a
 * whole-window distribution bar. Mood is a TEXT label rendered as color, never
 * coerced to a number.
 */
const NOT_LOGGED_COLOR = "#E4E0DA"; // --rule step — a labeled state, not an undocumented gray cell

export function MoodStrip({ mood }: { mood: MoodSummary }) {
  const total = mood.distribution.reduce((s, d) => s + d.count, 0) || 1;
  const notLoggedCount = mood.strip.filter((c) => c.logged === false).length;

  return (
    <div className="border-b border-divider py-5">
      <h4 className="mb-3 font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
        Mood · 28 days
      </h4>

      <div className="flex gap-[3px]">
        {mood.strip.map((c, i) => (
          <span
            key={i}
            title={c.logged === false ? `${c.dateLabel} · not logged` : `${c.dateLabel} · ${c.mood}`}
            className="h-[34px] flex-1 rounded-[3px]"
            style={{ background: c.logged === false ? NOT_LOGGED_COLOR : MOOD_COLOR[c.mood] }}
          />
        ))}
      </div>
      <div className="mt-1.5 flex justify-between font-mono text-[9px] uppercase text-text-tertiary">
        <span>4 wks ago</span>
        <span>Today</span>
      </div>

      <div className="mt-4 flex h-3 overflow-hidden rounded-md">
        {mood.distribution.map((d) => (
          <span
            key={d.mood}
            title={`${d.mood}: ${d.count} days`}
            className="h-full"
            style={{ background: MOOD_COLOR[d.mood], width: `${((d.count / total) * 100).toFixed(1)}%` }}
          />
        ))}
      </div>
      <div className="mt-3 flex flex-wrap gap-x-3.5 gap-y-2">
        {mood.distribution.map((d) => (
          <span
            key={d.mood}
            className="inline-flex items-center gap-1.5 font-mono text-[9.5px] uppercase tracking-[0.04em] text-text-secondary"
          >
            <span className="h-[9px] w-[9px] rounded-sm" style={{ background: MOOD_COLOR[d.mood] }} />
            {d.mood} {d.count}
          </span>
        ))}
        {notLoggedCount ? (
          <span className="inline-flex items-center gap-1.5 font-mono text-[9.5px] uppercase tracking-[0.04em] text-text-tertiary">
            <span className="h-[9px] w-[9px] rounded-sm" style={{ background: NOT_LOGGED_COLOR }} />
            not logged {notLoggedCount}
          </span>
        ) : null}
      </div>

      <p className="mt-4 border-t border-divider pt-3.5 font-body text-[13.5px] leading-snug text-text-primary">
        <Rich text={mood.caption} />
      </p>
    </div>
  );
}
