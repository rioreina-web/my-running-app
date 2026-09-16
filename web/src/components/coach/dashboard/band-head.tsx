/**
 * BandHead — the numbered section rule that opens each dashboard band
 * ("01 · SIGNAL ————"). Mono figure + display label + hairline, mirroring the
 * prototype's editorial band dividers.
 */
export function BandHead({ n, title }: { n: string; title: string }) {
  return (
    <div className="mt-8 mb-3 flex items-baseline gap-3 px-0.5">
      <span className="font-mono text-[11px] tracking-[0.14em] text-text-tertiary">
        {n}
      </span>
      <span className="font-display text-[15px] font-bold uppercase tracking-[0.02em] text-text-secondary">
        {title}
      </span>
      <span className="h-px flex-1 self-center bg-divider" />
    </div>
  );
}
