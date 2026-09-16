import { ReactNode } from "react";

/**
 * Eyebrow — the mono, tracked, uppercase micro-label that leads every section
 * in the Post Run Drip app (TUESDAY, FROM YOUR COACH, WEEKLY MILEAGE). Mirrors
 * the iOS `.eyebrow` primitive (design-system/ui_kits/ios_app/Primitives.jsx).
 *
 * Monospaced + tracked is the single most identifiable brand gesture — the
 * column of uppercase labels is what gives the product its editorial rhythm.
 * The `coral` variant marks the one active / live section per cluster; coral
 * is punctuation, so use it once, not everywhere.
 */
export function Eyebrow({
  children,
  coral = false,
  className = "",
}: {
  children: ReactNode;
  coral?: boolean;
  className?: string;
}) {
  return (
    <span
      className={`font-mono text-[10px] font-medium uppercase tracking-[0.12em] ${
        coral ? "text-coral" : "text-text-secondary"
      } ${className}`}
    >
      {children}
    </span>
  );
}
