/* Athlete-site mockup · shared primitives.
   Port of design-system/ui_kits/ios_app/Primitives.jsx. Server-safe
   (no hooks) so every page can stay a server component. */

import Link from "next/link";
import type { ReactNode } from "react";
import type { Mood } from "./data";

export function Eyebrow({
  children,
  coral,
  faint,
  sm,
  className = "",
}: {
  children: ReactNode;
  coral?: boolean;
  faint?: boolean;
  sm?: boolean;
  className?: string;
}) {
  const cls = [
    "m-eyebrow",
    coral ? "m-eyebrow--coral" : "",
    faint ? "m-eyebrow--faint" : "",
    sm ? "m-eyebrow--sm" : "",
    className,
  ]
    .filter(Boolean)
    .join(" ");
  return <div className={cls}>{children}</div>;
}

export function EditorialRule() {
  return (
    <div className="m-rule" aria-hidden="true">
      <span className="m-dot" />
    </div>
  );
}

export function Hairline({ className = "" }: { className?: string }) {
  return <div className={`m-hairline ${className}`} />;
}

export function Spacer({ h = 16 }: { h?: 8 | 12 | 16 | 20 | 24 | 32 | 40 }) {
  return <div className={`m-sp-${h}`} aria-hidden="true" />;
}

/** Plate strip · the top mono header of every editorial surface.
 *  `RUNNING LOG — LOG · v1 VOICE LOG` on the left, figure + date right. */
export function PlateStrip({
  surface,
  fig,
  right = "MAYA · 09.2026",
}: {
  surface: string;
  fig?: string;
  right?: string;
}) {
  return (
    <div className="m-platewrap">
      <div className="m-plate">
        <div className="m-plate__col">
          <span className="is-ink">RUNNING LOG</span>
          <span>· {surface}</span>
        </div>
        <div className="m-plate__col is-right">
          {fig ? <span className="is-ink">{fig}</span> : null}
          <span>{right}</span>
        </div>
      </div>
    </div>
  );
}

export function Section({
  eyebrow,
  eyebrowRight,
  eyebrowCoral,
  first,
  children,
}: {
  eyebrow?: ReactNode;
  eyebrowRight?: ReactNode;
  eyebrowCoral?: boolean;
  first?: boolean;
  children: ReactNode;
}) {
  return (
    <div className={`m-section${first ? " m-section--first" : ""}`}>
      {eyebrow || eyebrowRight ? (
        <div className="m-section__head">
          {eyebrow ? <Eyebrow coral={eyebrowCoral}>{eyebrow}</Eyebrow> : <span />}
          {eyebrowRight ? <Eyebrow faint>{eyebrowRight}</Eyebrow> : null}
        </div>
      ) : null}
      {children}
    </div>
  );
}

export function MoodPill({ mood }: { mood: Mood }) {
  return (
    <span className="m-mood" data-mood={mood}>
      {mood}
    </span>
  );
}

export function StatTile({
  label,
  value,
  unit,
  delta,
  tone = "neutral",
  href,
}: {
  label: string;
  value: string;
  unit?: string;
  delta?: string;
  tone?: "neutral" | "pos" | "coral" | "watch";
  href?: string;
}) {
  const inner = (
    <>
      <div className="m-tile__label">{label}</div>
      <div className="m-tile__value">
        {value}
        {unit ? <span className="m-tile__unit">{unit}</span> : null}
      </div>
      {delta ? <div className={`m-tile__delta${tone !== "neutral" ? ` is-${tone}` : ""}`}>{delta}</div> : null}
    </>
  );
  return href ? (
    <Link href={href} className="m-tile">
      {inner}
    </Link>
  ) : (
    <div className="m-tile">{inner}</div>
  );
}

/** Coach quote · italic blockquote with the 2px coral-at-50% left bar.
 *  The one place a coloured left border appears in the system. */
export function CoachQuote({ children }: { children: ReactNode }) {
  return <p className="m-coachquote">{children}</p>;
}

/** Empty state · eyebrow + plain-prose nudge + optional CTA.
 *  Hard rule #8: never an em-dash placeholder. */
export function EmptyState({
  eyebrow,
  nudge,
  cta,
  quiet,
}: {
  eyebrow?: string;
  nudge: string;
  cta?: { label: string; href: string };
  quiet?: boolean;
}) {
  return (
    <div className={`m-empty${quiet ? " m-empty--quiet" : ""}`}>
      {eyebrow ? <Eyebrow faint>{eyebrow}</Eyebrow> : null}
      <p className="m-empty__nudge">{nudge}</p>
      {cta ? (
        <Link href={cta.href} className="m-link m-link--sm">
          {cta.label} ↗
        </Link>
      ) : null}
    </div>
  );
}

/** Sheet chrome · back link + centred surface label + figure. Used at the
 *  top of every non-tab surface so the athlete always has a way back. */
export function SheetChrome({
  back,
  backLabel = "Back",
  surface,
  fig,
  action,
}: {
  back: string;
  backLabel?: string;
  surface: string;
  fig?: string;
  action?: { label: string; href: string };
}) {
  return (
    <div className="m-row m-row--center">
      <Link href={back} className="m-link m-link--sm">
        ← {backLabel}
      </Link>
      <span className="m-caption m-caption--faint">{surface}</span>
      {action ? (
        <Link href={action.href} className="m-link m-link--sm">
          {action.label}
        </Link>
      ) : (
        <span className="m-caption m-caption--faint">{fig ?? ""}</span>
      )}
    </div>
  );
}

/** A stat strip cell · label / value+unit / sub. */
export function StripCell({
  l,
  v,
  u,
  s,
  center,
  small,
}: {
  l: string;
  v: string;
  u?: string;
  s?: string;
  center?: boolean;
  small?: boolean;
}) {
  return (
    <div className={`m-strip__cell${center ? " is-center" : ""}`}>
      <span className="m-strip__l">{l}</span>
      <span className={`m-strip__v${small ? " m-strip__v--sm" : ""}`}>
        {v}
        {u ? <span>{u}</span> : null}
      </span>
      {s ? <span className="m-strip__s">{s}</span> : null}
    </div>
  );
}

/** Curly-quoted body copy. Keeps the diary voice in quotes. */
export function Quoted({ children }: { children: ReactNode }) {
  return (
    <>
      {"“"}
      {children}
      {"”"}
    </>
  );
}
