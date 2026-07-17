import type { Acwr } from "@/lib/coach-dashboard/types";

/**
 * AcwrCard — acute:chronic workload as a banded gauge. Bands are neutral grays
 * except the spike band, which is the only coral (three-palette rule — never
 * green for "safe"). Monotony / strain shown as secondary stats.
 */
export function AcwrCard({ acwr }: { acwr: Acwr }) {
  const cx = 120;
  const cy = 130;
  const r = 100;
  const vMax = 2.0;
  const ang = (f: number) => Math.PI * (1 - f);
  const pt = (f: number, rr: number) =>
    [cx + rr * Math.cos(ang(f)), cy - rr * Math.sin(ang(f))] as const;
  const arc = (f0: number, f1: number, color: string, key: string) => {
    const [x0, y0] = pt(f0, r);
    const [x1, y1] = pt(f1, r);
    const large = f1 - f0 > 0.5 ? 1 : 0;
    return (
      <path
        key={key}
        d={`M ${x0} ${y0} A ${r} ${r} 0 ${large} 1 ${x1} ${y1}`}
        fill="none"
        stroke={color}
        strokeWidth="13"
      />
    );
  };
  const [nx, ny] = pt(acwr.value / vMax, r - 18);
  const [t08x, t08y] = pt(0.8 / vMax, r + 13);
  const [t13x, t13y] = pt(1.3 / vMax, r + 13);

  return (
    <div className="flex flex-col items-center rounded-xl border border-divider bg-bg-card p-5">
      <div className="self-start font-mono text-[10px] uppercase tracking-[0.12em] text-text-tertiary">
        Acute : chronic load
      </div>

      <svg viewBox="0 0 240 150" className="mt-1.5 h-auto w-[220px]">
        {arc(0, 0.6 / vMax, "#D8D3CC", "b1")}
        {arc(0.6 / vMax, 0.8 / vMax, "#C3BCB2", "b2")}
        {arc(0.8 / vMax, 1.3 / vMax, "#6B6560", "b3")}
        {arc(1.3 / vMax, 1.5 / vMax, "#C3BCB2", "b4")}
        {arc(1.5 / vMax, 2.0 / vMax, "#D4592A", "b5")}
        <line x1={cx} y1={cy} x2={nx} y2={ny} stroke="#1A1815" strokeWidth="2.5" strokeLinecap="round" />
        <circle cx={cx} cy={cy} r="5" fill="#1A1815" />
        <text x={t08x} y={t08y} textAnchor="middle" className="font-mono" fontSize="8.5" fill="#9B9590">0.8</text>
        <text x={t13x} y={t13y} textAnchor="middle" className="font-mono" fontSize="8.5" fill="#9B9590">1.3</text>
      </svg>

      <div className="font-mono text-[40px] font-semibold leading-none tabular-nums text-text-primary">
        {acwr.value.toFixed(2)}
      </div>
      <div className="mt-1 font-mono text-[10px] uppercase tracking-[0.12em] text-text-secondary">
        {acwr.bandLabel}
      </div>
      <div className="mt-3.5 flex w-full justify-between font-mono text-[9px] uppercase text-text-tertiary">
        <span>0.6 detrain</span>
        <span>1.3</span>
        <span>1.5 spike</span>
      </div>

      <div className="mt-4 flex w-full justify-center gap-6 border-t border-divider pt-3.5">
        <div className="text-center">
          <div className="font-mono text-[9px] uppercase tracking-[0.1em] text-text-tertiary">Monotony 7d</div>
          <div className="mt-1 font-mono text-[18px] font-semibold tabular-nums text-text-primary">
            {acwr.monotony7d.toFixed(1)}
          </div>
        </div>
        <div className="text-center">
          <div className="font-mono text-[9px] uppercase tracking-[0.1em] text-text-tertiary">Strain 7d</div>
          <div className="mt-1 font-mono text-[18px] font-semibold tabular-nums text-text-primary">
            {acwr.strain7d}
          </div>
        </div>
      </div>
    </div>
  );
}
