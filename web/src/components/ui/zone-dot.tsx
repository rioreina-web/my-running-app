/**
 * ZoneDot — a small filled dot that carries a pace/zone (or mood) color.
 *
 * Post Run Drip communicates category through a tracked uppercase label plus a
 * colored dot — never an emoji or a colored heading. This is the dot half of
 * that pattern (pair it with an <Eyebrow>). The only filled glyph in the
 * system is a dot, so this is the sanctioned way to add color to a label.
 */
export function ZoneDot({
  color,
  size = 6,
  className = "",
}: {
  color: string;
  size?: number;
  className?: string;
}) {
  return (
    <span
      aria-hidden
      className={`inline-block shrink-0 rounded-full ${className}`}
      style={{ width: size, height: size, backgroundColor: color }}
    />
  );
}
