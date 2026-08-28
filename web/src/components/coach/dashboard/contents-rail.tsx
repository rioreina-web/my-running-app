"use client";

import { useEffect, useState } from "react";

/**
 * ContentsRail — a contents column, not a nav sidebar.
 *
 * No panel, no fill, no hover chrome: numbered labels on hairlines, and the
 * section you are in carries the 2px red rule the system already uses for an
 * active state. It also holds the two actions, so the page has ONE persistent
 * element beside the content rather than a rail arguing with a sticky bar.
 *
 * Sections with no data are filtered out by the caller — a contents column
 * that points at an empty band is worse than no column.
 */
export interface RailItem {
  id: string;
  n: string;
  label: string;
}

export function ContentsRail({
  items,
  who,
  meta,
  flag,
  onAdjust,
}: {
  items: RailItem[];
  who: string;
  meta?: string;
  flag?: string;
  onAdjust?: () => void;
}) {
  const [active, setActive] = useState(items[0]?.id);

  // Last section head to cross the line wins. A plain scroll read, on purpose:
  // an IntersectionObserver ratio comparison marks the NEXT section while the
  // current one still fills the screen.
  useEffect(() => {
    const spy = () => {
      let current = items[0]?.id;
      for (const it of items) {
        const el = document.getElementById(it.id);
        if (el && el.getBoundingClientRect().top <= 140) current = it.id;
      }
      setActive(current);
    };
    spy();
    window.addEventListener("scroll", spy, { passive: true });
    window.addEventListener("resize", spy);
    return () => {
      window.removeEventListener("scroll", spy);
      window.removeEventListener("resize", spy);
    };
  }, [items]);

  return (
    <nav aria-label="Contents" className="sticky top-14 hidden self-start pt-6 lg:block">
      <span className="drip-title block text-[17px]">{who}</span>
      {meta ? <span className="drip-stat mt-1.5 block text-[11px] font-normal text-text-tertiary">{meta}</span> : null}
      {flag ? <span className="drip-eyebrow drip-eyebrow--red mt-2 block text-[9px]">{flag}</span> : null}

      <div className="mt-5 border-t-2 border-text-primary">
        {items.map((it) => {
          const on = active === it.id;
          return (
            <a
              key={it.id}
              href={`#${it.id}`}
              aria-current={on ? "true" : undefined}
              className={`-ml-[11px] flex items-baseline gap-2.5 border-b border-l-2 border-divider py-2.5 pl-2.5 font-mono text-[10px] uppercase tracking-[0.11em] transition-colors ${
                on
                  ? "border-l-coral text-text-primary"
                  : "border-l-transparent text-text-tertiary hover:text-text-primary"
              }`}
            >
              <span className={`tabular-nums text-[9.5px] ${on ? "text-coral-dark" : "text-text-tertiary"}`}>
                {it.n}
              </span>
              {it.label}
            </a>
          );
        })}
      </div>

      {onAdjust ? (
        <div className="mt-5 flex flex-col gap-2">
          <button
            type="button"
            onClick={onAdjust}
            className="w-full border border-text-primary bg-text-primary px-4 py-2.5 font-mono text-[10.5px] font-bold uppercase tracking-[0.1em] text-bg-card"
          >
            Adjust the training
          </button>
          <p className="drip-dek mt-1 text-[11.5px] leading-snug">
            Nothing reaches the athlete until you apply it.
          </p>
        </div>
      ) : null}
    </nav>
  );
}
