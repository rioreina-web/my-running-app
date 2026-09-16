/**
 * Editorial primitives for the v2 (training-first) coach dashboard.
 *
 * The v1 bands were boxes: `rounded-xl border border-divider bg-bg-card p-5`.
 * Direction I has no cards — "hairlines replace cards, tints and shadows", and
 * depth is not part of the brand. These are the replacements: a section head
 * that is a 2px ink rule, and a hairline-divided cell grid where v1 used a
 * padded tinted panel.
 *
 * Type comes from the `.drip-*` roles in globals.css, so a callsite here reads
 * the same as the iOS one and a token change moves both.
 */
import type { ReactNode } from "react";

/**
 * The numbered section rule. Replaces BandHead: a 2px ink rule instead of a
 * hairline, the number set in the data face, and an optional italic note on
 * the right that says what the section is for.
 */
export function Band({
  n,
  title,
  note,
  id,
}: {
  n: string;
  title: string;
  note?: string;
  id?: string;
}) {
  return (
    <div
      id={id}
      className="mt-11 flex scroll-mt-20 items-baseline justify-between gap-4 border-b-2 border-text-primary pb-2"
    >
      <span className="drip-eyebrow">
        <span className="mr-2.5 font-mono text-[10px] tabular-nums text-text-tertiary">{n}</span>
        {title}
      </span>
      {note ? <span className="drip-dek shrink-0 text-[12.5px]">{note}</span> : null}
    </div>
  );
}

/** A tracked label over a tabular figure — the system's StatTile, unboxed. */
export function Cell({
  label,
  value,
  unit,
  meta,
  accent,
  size = "md",
}: {
  label: string;
  value: ReactNode;
  unit?: string;
  meta?: string;
  /** Renders the figure in red. Reserve it for the one number that is asking
   *  for a decision — a red every cell is a red that points at nothing. */
  accent?: boolean;
  size?: "sm" | "md" | "lg";
}) {
  const px = size === "lg" ? "text-[27px]" : size === "sm" ? "text-[17px]" : "text-[24px]";
  return (
    <div className="min-w-0 border-r border-divider py-3.5 pr-5 last:border-r-0 last:pr-0">
      <span className={`drip-eyebrow block ${accent ? "drip-eyebrow--red" : ""}`}>{label}</span>
      <span
        className={`drip-stat mt-2 block whitespace-nowrap leading-none ${px} ${
          accent ? "text-coral-dark" : ""
        }`}
      >
        {value}
        {unit ? <span className="ml-0.5 text-[11px] font-medium text-text-tertiary">{unit}</span> : null}
      </span>
      {meta ? (
        <span className="drip-eyebrow mt-1.5 block whitespace-normal text-[9px] text-text-tertiary">
          {meta}
        </span>
      ) : null}
    </div>
  );
}

/** A row of Cells, hairline-divided, wrapping on narrow screens. */
export function CellRow({ children, cols }: { children: ReactNode; cols?: string }) {
  return (
    <div
      className={`grid border-b border-divider ${cols ?? "grid-cols-2 md:grid-cols-4"}`}
    >
      {children}
    </div>
  );
}

/** The one coloured left border in the system. */
export function RedRail({ children, className = "" }: { children: ReactNode; className?: string }) {
  return <div className={`border-l-2 border-coral pl-5 ${className}`}>{children}</div>;
}

/**
 * Is this delta a MISS?
 *
 * `onTarget === false` is not the answer. The vocabulary carries "1s under",
 * "neg split", "steady" and "peak long" — all fine, all flagged false — so
 * colouring on `!onTarget` paints a faster-than-target session red. One red,
 * and it points at the thing asking for a decision; a red on every row points
 * at nothing.
 *
 * A miss is a delta that reads slow ("+11 s/mi") or short ("cut 1 rep").
 */
const MISS = /\b(cut|short|over|off|missed|dnf|abandoned)\b/i;
export function isMiss(delta: string | null | undefined): boolean {
  if (!delta) return false;
  if (delta.trim().startsWith("+")) return true;
  return MISS.test(delta);
}
