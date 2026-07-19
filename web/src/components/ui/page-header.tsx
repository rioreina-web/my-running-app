import { ReactNode } from "react";
import { Eyebrow } from "./eyebrow";

/**
 * PageHeader — the editorial header block that opens every Post Run Drip
 * surface. Mirrors the iOS "section--first" frame (TodayScreen, TrainingScreen,
 * WorkoutDetailScreen): a coral eyebrow, a large Crimson Pro display headline,
 * an optional italic PT Serif subtitle, and an optional right-aligned action.
 *
 * Use this instead of <SectionHeader> for the top-of-page title. SectionHeader
 * is for the small mono labels that lead sections *within* a page.
 */
export function PageHeader({
  eyebrow,
  eyebrowRight,
  title,
  subtitle,
  action,
  className = "",
}: {
  /** Coral eyebrow, e.g. "WORKOUT LIBRARY · COACH PORTAL". */
  eyebrow?: string;
  /** Quiet right-aligned eyebrow, e.g. a count or date. */
  eyebrowRight?: string;
  /** The display headline, e.g. "Workout library." */
  title: string;
  /** Italic PT Serif subtitle, e.g. "Reusable workouts to build plans from." */
  subtitle?: string;
  /** Right-aligned action slot (a button or an editorial link). */
  action?: ReactNode;
  className?: string;
}) {
  return (
    <header className={className}>
      {(eyebrow || eyebrowRight) && (
        <div className="flex items-baseline justify-between gap-4">
          {eyebrow ? <Eyebrow coral>{eyebrow}</Eyebrow> : <span />}
          {eyebrowRight ? <Eyebrow>{eyebrowRight}</Eyebrow> : null}
        </div>
      )}
      <div className="mt-2 flex items-end justify-between gap-4">
        <h1 className="font-display text-[28px] font-bold leading-[1.05] tracking-[-0.01em] text-text-primary md:text-[34px]">
          {title}
        </h1>
        {action ? <div className="shrink-0 pb-1">{action}</div> : null}
      </div>
      {subtitle ? (
        <p className="mt-2 font-body text-[14px] italic text-text-secondary">
          {subtitle}
        </p>
      ) : null}
    </header>
  );
}
