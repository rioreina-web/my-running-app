import type { Progression } from "@/lib/coach-dashboard/types";

/**
 * FitnessCurve — a 26-week relative-fitness line with confirmed races plotted
 * as vertical markers and a projection fan into the goal race (range, not a
 * point). Blue ink only; coral reserved for the goal marker. Static SVG.
 */
export function FitnessCurve({ progression }: { progression: Progression }) {
  const F = progression.fitnessSeries;
  const W = 720;
  const H = 300;
  const M = { l: 30, r: 96, t: 18, b: 34 };
  const pw = W - M.l - M.r;
  const ph = H - M.t - M.b;
  const n = F.length;
  const yMin = 40;
  const yMax = 80;
  const x = (i: number) => M.l + (i / (n - 1)) * pw;
  const y = (v: number) => M.t + ph - ((v - yMin) / (yMax - yMin)) * ph;

  const areaPath =
    `M ${x(0)} ${y(F[0])} ` +
    F.map((v, i) => `L ${x(i)} ${y(v)}`).join(" ") +
    ` L ${x(n - 1)} ${M.t + ph} L ${x(0)} ${M.t + ph} Z`;
  const linePath =
    `M ${x(0)} ${y(F[0])} ` +
    F.slice(1)
      .map((v, i) => `L ${x(i + 1)} ${y(v)}`)
      .join(" ");

  const gx = M.l + pw + 70;
  const gyHi = y(78);
  const gyLo = y(72);
  const nowx = x(n - 1);
  const nowy = y(F[n - 1]);

  return (
    <svg
      viewBox={`0 0 ${W} ${H}`}
      preserveAspectRatio="xMidYMid meet"
      className="block h-auto w-full overflow-visible"
    >
      {[40, 50, 60, 70, 80].map((v) => (
        <g key={v}>
          <line x1={M.l} y1={y(v)} x2={M.l + pw} y2={y(v)} stroke={v === 40 ? "#E0DAD3" : "#EFEBE6"} strokeWidth="1" />
          <text x={M.l - 6} y={y(v) + 3} textAnchor="end" className="font-mono" fontSize="9" fill="#9B9590">
            {v === 80 ? "80" : String(v)}
          </text>
        </g>
      ))}
      {progression.fitnessMonths.map((m) => (
        <text key={m.label} x={x(m.weekIndex)} y={M.t + ph + 18} textAnchor="middle" className="font-mono" fontSize="9.5" fill="#9B9590">
          {m.label.toUpperCase()}
        </text>
      ))}

      <path d={areaPath} fill="rgba(63,124,181,0.07)" />

      {progression.races.map((r) => (
        <g key={r.label}>
          <line x1={x(r.weekIndex)} y1={M.t} x2={x(r.weekIndex)} y2={M.t + ph} stroke="#9B9590" strokeWidth="1" strokeDasharray="2 3" opacity="0.7" />
          <circle cx={x(r.weekIndex)} cy={M.t - 2} r="2.6" fill="#6B6560" />
          <text
            x={x(r.weekIndex)}
            y={M.t + ph - 8}
            textAnchor="middle"
            transform={`rotate(-90 ${x(r.weekIndex)} ${M.t + ph - 8})`}
            className="font-display"
            fontWeight="700"
            fontSize="11"
            fill="#1A1815"
          >
            {r.label}
          </text>
        </g>
      ))}

      <path d={linePath} fill="none" stroke="#3F7CB5" strokeWidth="2.4" strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={nowx} cy={nowy} r="4" fill="#3F7CB5" stroke="#fff" strokeWidth="1.5" />

      {/* projection fan to the goal race */}
      <path d={`M ${nowx} ${nowy} L ${gx} ${gyHi} L ${gx} ${gyLo} Z`} fill="rgba(147,185,214,0.22)" />
      <line x1={nowx} y1={nowy} x2={gx} y2={(gyHi + gyLo) / 2} stroke="#93B9D6" strokeWidth="2" strokeDasharray="4 3" />
      <line x1={gx} y1={M.t} x2={gx} y2={M.t + ph} stroke="#D4592A" strokeWidth="1" strokeDasharray="2 3" opacity="0.5" />
      <text x={gx} y={M.t - 4} textAnchor="middle" className="font-mono" fontSize="9" fill="#B84420">
        {progression.projection.goalLabel}
      </text>
      <text x={gx} y={gyHi - 8} textAnchor="middle" className="font-display" fontWeight="700" fontSize="12" fill="#1A1815">
        {progression.projection.rangeLabel}
      </text>
      <text x={gx} y={M.t + ph + 18} textAnchor="middle" className="font-mono" fontSize="9" fill="#9B9590">
        {progression.projection.xLabel}
      </text>
    </svg>
  );
}
