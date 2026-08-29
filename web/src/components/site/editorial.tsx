import { ReactNode } from "react";

/* ──────────────────────────────────────────────────────────────────────
   POST RUN DRIP — editorial primitives for the public site.

   Web counterparts to design-system/ui_kits/ios_app/Primitives.jsx.
   Everything the marketing site draws should come from here so the site
   and the app read as one system: monospaced tracked eyebrows, the
   line·dot·line rule, the plate strip, coral used like punctuation.
   ────────────────────────────────────────────────────────────────────── */

/** Monospaced, tracked, uppercase label. The system's most-used mark. */
export function Eyebrow({
  children,
  coral,
  className = "",
}: {
  children: ReactNode;
  coral?: boolean;
  className?: string;
}) {
  return (
    <span
      className={`font-mono text-[10px] font-medium tracking-[0.14em] uppercase ${
        coral ? "text-coral" : "text-text-tertiary"
      } ${className}`}
    >
      {children}
    </span>
  );
}

/**
 * The plate strip — the single most identifiable gesture in the system.
 * Sits at the top of an editorial surface: publication mark on the left,
 * figure number + dateline on the right.
 */
export function PlateStrip({
  surface,
  fig,
  right,
}: {
  surface: string;
  fig?: string;
  right?: string;
}) {
  return (
    <div className="flex items-start justify-between border-b border-divider px-6 py-3 md:px-10">
      <div className="flex flex-col gap-0.5">
        <Eyebrow className="!text-text-primary">Running log</Eyebrow>
        <Eyebrow>— {surface}</Eyebrow>
      </div>
      {(fig || right) && (
        <div className="flex flex-col items-end gap-0.5 text-right">
          {fig && <Eyebrow className="!text-text-primary">{fig}</Eyebrow>}
          {right && <Eyebrow>{right}</Eyebrow>}
        </div>
      )}
    </div>
  );
}

/** thin line · 3px dot · thin line — the canonical section break. */
export function EditorialRule({ className = "" }: { className?: string }) {
  return (
    <div className={`flex items-center gap-2 ${className}`} aria-hidden>
      <div className="h-px flex-1 bg-divider" />
      <div className="h-[3px] w-[3px] rounded-full bg-divider" />
      <div className="h-px flex-1 bg-divider" />
    </div>
  );
}

/** The one place a coral left-bar appears. Coach voice, quoted. */
export function CoachQuote({
  children,
  className = "",
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <p
      className={`border-l-2 border-coral/50 pl-3 font-body text-[15px] italic leading-[1.6] text-text-secondary ${className}`}
    >
      {children}
    </p>
  );
}

/** Stat tile — label over a big mono numeral, optional delta caption. */
export function StatTile({
  label,
  value,
  unit,
  caption,
  captionTone = "neutral",
  size = "md",
}: {
  label: string;
  value: string;
  unit?: string;
  caption?: string;
  captionTone?: "neutral" | "good" | "watch" | "coral";
  /** "sm" for long values (a prediction range) that would wrap at full size. */
  size?: "md" | "sm";
}) {
  const tone = {
    neutral: "text-text-tertiary",
    good: "text-mood-energized",
    watch: "text-mood-tired",
    coral: "text-coral",
  }[captionTone];

  return (
    <div className="rounded-xl bg-bg-card p-4 shadow-[0_2px_8px_rgba(0,0,0,0.06)]">
      <Eyebrow>{label}</Eyebrow>
      <div
        className={`mt-2 font-mono font-semibold tabular-nums leading-none text-text-primary ${
          size === "sm" ? "text-[17px] tracking-[-0.02em]" : "text-[22px]"
        }`}
      >
        {value}
        {unit && (
          <span className="ml-1.5 font-mono text-[10px] font-medium tracking-[0.12em] uppercase text-text-tertiary">
            {unit}
          </span>
        )}
      </div>
      {caption && (
        <div
          className={`mt-2 font-mono text-[9px] font-medium tracking-[0.10em] uppercase ${tone}`}
        >
          {caption}
        </div>
      )}
    </div>
  );
}

/** Mood pill — tracked uppercase at a 12% wash. Never a face, never a fill. */
const MOOD_STYLES: Record<string, string> = {
  energized: "text-mood-energized bg-mood-energized/12",
  positive: "text-mood-positive bg-mood-positive/12",
  neutral: "text-text-secondary bg-mood-neutral/18",
  tired: "text-mood-tired bg-mood-tired/12",
  struggling: "text-mood-struggling bg-mood-struggling/12",
  injured: "text-mood-injured bg-mood-injured/12",
};

export function MoodPill({ mood }: { mood: string }) {
  const style = MOOD_STYLES[mood.toLowerCase()] ?? MOOD_STYLES.neutral;
  return (
    <span
      className={`inline-flex rounded-full px-2 py-[3px] font-mono text-[9px] font-medium tracking-[0.10em] uppercase ${style}`}
    >
      {mood}
    </span>
  );
}

/**
 * Section shell for long-form public pages: eyebrow left, optional
 * eyebrow right, then the section body on the paper background.
 */
export function Section({
  eyebrow,
  eyebrowRight,
  eyebrowCoral,
  children,
  className = "",
  id,
}: {
  eyebrow?: string;
  eyebrowRight?: string;
  eyebrowCoral?: boolean;
  children: ReactNode;
  className?: string;
  id?: string;
}) {
  return (
    <section id={id} className={className}>
      {(eyebrow || eyebrowRight) && (
        <div className="flex items-baseline justify-between gap-4 border-b border-divider pb-3">
          {eyebrow && <Eyebrow coral={eyebrowCoral}>{eyebrow}</Eyebrow>}
          {eyebrowRight && <Eyebrow>{eyebrowRight}</Eyebrow>}
        </div>
      )}
      {children}
    </section>
  );
}

/** Editorial link — verb + arrow, coral, underline on hover. */
export function ActionLink({
  children,
  href,
  className = "",
}: {
  children: ReactNode;
  href: string;
  className?: string;
}) {
  return (
    <a
      href={href}
      className={`font-display text-[15px] font-semibold text-coral underline-offset-4 transition-colors hover:text-coral-dark hover:underline ${className}`}
    >
      {children} ↗
    </a>
  );
}
