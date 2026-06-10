import Link from "next/link";

/**
 * Empty-state component (eyebrow + nudge + optional CTA).
 *
 * Replace every em-dash placeholder in the UI with this. Variant drives tone:
 *   setup-needed   — the user must act for the surface to populate.
 *   data-pending   — needs more activity (runs, voice logs).
 *   optional-empty — legitimately empty; not a problem.
 *   error          — a fetch/computation failed.
 *
 * See docs/conventions/empty-states.md for the 6 copy rules.
 */
export type EmptyStateVariant =
  | "setup-needed"
  | "data-pending"
  | "optional-empty"
  | "error";

interface EmptyStateProps {
  variant: EmptyStateVariant;
  eyebrow?: string;
  title: string;
  cta?: { label: string; href?: string; onClick?: () => void };
  className?: string;
}

export function EmptyState({
  variant,
  eyebrow,
  title,
  cta,
  className = "",
}: EmptyStateProps) {
  const eyebrowTone =
    variant === "setup-needed" || variant === "error"
      ? "text-coral"
      : "text-text-tertiary";
  const verticalPad =
    variant === "optional-empty" ? "py-6" : "py-10";

  return (
    <div
      className={`flex flex-col items-center gap-3 text-center ${verticalPad} ${className}`}
      data-empty-state-variant={variant}
    >
      {eyebrow ? (
        <span
          className={`font-body text-[11px] font-medium tracking-[1.5px] uppercase ${eyebrowTone}`}
        >
          {eyebrow}
        </span>
      ) : null}
      <p className="font-body text-sm text-text-secondary max-w-[36ch]">
        {title}
      </p>
      {cta ? <EmptyStateCTA {...cta} /> : null}
    </div>
  );
}

function EmptyStateCTA({
  label,
  href,
  onClick,
}: {
  label: string;
  href?: string;
  onClick?: () => void;
}) {
  const className =
    "mt-1 text-[12px] italic text-coral hover:text-coral-dark transition-colors";
  if (href) {
    return (
      <Link href={href} className={className}>
        {label}
      </Link>
    );
  }
  return (
    <button type="button" onClick={onClick} className={className}>
      {label}
    </button>
  );
}
