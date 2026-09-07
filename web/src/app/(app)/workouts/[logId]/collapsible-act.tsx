"use client";

import { useState, type ReactNode } from "react";
import { ChevronDown } from "lucide-react";

// Act 3 row: eyebrow + one-line mono summary + chevron, collapsed by default.
// The caller default-expands only the section most relevant to the workout
// type — everything else stays shut so Act 1 keeps the screen.

export function CollapsibleAct({
  eyebrow,
  summary,
  defaultOpen = false,
  children,
}: {
  eyebrow: string;
  summary: string;
  defaultOpen?: boolean;
  children: ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);

  return (
    <div className="border-t border-divider-soft">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        className="flex w-full items-baseline justify-between gap-4 py-4 text-left transition-colors hover:text-coral"
      >
        <span className="font-mono text-[10px] font-medium uppercase tracking-[0.12em] text-text-secondary">
          {eyebrow}
        </span>
        <span className="flex items-baseline gap-3">
          <span className="font-mono text-[11px] tabular-nums text-text-tertiary">{summary}</span>
          <ChevronDown
            size={14}
            className={`shrink-0 self-center text-text-tertiary transition-transform ${
              open ? "rotate-180" : ""
            }`}
            aria-hidden
          />
        </span>
      </button>
      {open && <div className="pb-6">{children}</div>}
    </div>
  );
}
