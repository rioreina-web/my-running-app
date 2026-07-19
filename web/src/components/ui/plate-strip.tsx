/**
 * Plate strip — the single most identifiable Post Run Drip gesture.
 *
 * Sits at the top of an editorial surface and frames the whole page as a
 * plate in the running log ("Plate 18 / 29 · restraint as foundation..."),
 * not a SaaS chrome bar. Monospaced, tracked, ink label + quiet caption, on
 * warm paper. Reuse this across the coach portal for a consistent frame.
 *
 * See design-system/README.md → "Fixed elements" and Primitives.jsx PlateStrip.
 */
export function PlateStrip({
  surface,
  figure,
  right,
  padded = true,
  rule = false,
  className = "",
}: {
  /** The surface name, e.g. "Plan Builder · Coach Portal". Rendered after the em-dash. */
  surface: string;
  /** Optional figure line (ink), e.g. "Fig. — new". */
  figure?: string;
  /** Optional right-hand caption (quiet), e.g. a date "07.2026". */
  right?: string;
  /** Apply built-in horizontal padding. Set false when the parent already pads
   *  (e.g. the app <main> content column) so the strip aligns with content. */
  padded?: boolean;
  /** Draw a hairline under the strip — the framed editorial look. */
  rule?: boolean;
  className?: string;
}) {
  return (
    <div
      className={`flex items-start justify-between gap-4 ${padded ? "px-6" : ""} py-2.5 font-mono text-[10px] uppercase tracking-[0.14em] text-text-tertiary ${
        rule ? "border-b border-divider" : ""
      } ${className}`}
    >
      <div className="flex flex-col gap-0.5 leading-tight">
        <span className="text-text-primary">Running Log</span>
        <span>— {surface}</span>
      </div>
      {(figure || right) && (
        <div className="flex flex-col gap-0.5 leading-tight text-right">
          {figure && <span className="text-text-primary">{figure}</span>}
          {right && <span>{right}</span>}
        </div>
      )}
    </div>
  );
}
