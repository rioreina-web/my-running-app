"use client";

interface TrainingLoadGaugeProps {
  acwr: number;
  size?: number;
}

export function TrainingLoadGauge({ acwr, size = 160 }: TrainingLoadGaugeProps) {
  // ACWR zones: <0.8 under-training, 0.8-1.3 optimal, 1.3-1.5 caution, >1.5 danger
  const clampedAcwr = Math.min(Math.max(acwr, 0), 2);
  const angle = (clampedAcwr / 2) * 180; // 0-2 maps to 0-180 degrees

  const cx = size / 2;
  const cy = size * 0.7;
  const r = size * 0.4;

  // Zone arcs
  const zones = [
    { start: 0, end: 0.8, color: "#C4873A" },    // under-training (tired/amber)
    { start: 0.8, end: 1.3, color: "#2D8A4E" },   // optimal (energized/green)
    { start: 1.3, end: 1.5, color: "#C4873A" },   // caution (amber)
    { start: 1.5, end: 2.0, color: "#C45A3A" },   // danger (struggling/red)
  ];

  function arcPath(startVal: number, endVal: number): string {
    const startAngle = (startVal / 2) * Math.PI;
    const endAngle = (endVal / 2) * Math.PI;
    const x1 = cx - r * Math.cos(startAngle);
    const y1 = cy - r * Math.sin(startAngle);
    const x2 = cx - r * Math.cos(endAngle);
    const y2 = cy - r * Math.sin(endAngle);
    const largeArc = endAngle - startAngle > Math.PI ? 1 : 0;
    return `M ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2}`;
  }

  // Needle
  const needleAngle = (clampedAcwr / 2) * Math.PI;
  const needleLen = r * 0.85;
  const nx = cx - needleLen * Math.cos(needleAngle);
  const ny = cy - needleLen * Math.sin(needleAngle);

  const zoneLabel =
    acwr < 0.8 ? "Under" : acwr <= 1.3 ? "Optimal" : acwr <= 1.5 ? "Caution" : "High";

  return (
    <div className="flex flex-col items-center">
      <svg width={size} height={size * 0.55} viewBox={`0 0 ${size} ${size * 0.75}`}>
        {/* Zone arcs */}
        {zones.map((zone, i) => (
          <path
            key={i}
            d={arcPath(zone.start, zone.end)}
            fill="none"
            stroke={zone.color}
            strokeWidth={8}
            strokeLinecap="round"
            opacity={0.3}
          />
        ))}
        {/* Needle */}
        <line x1={cx} y1={cy} x2={nx} y2={ny} stroke="#1A1815" strokeWidth={2} strokeLinecap="round" />
        <circle cx={cx} cy={cy} r={3} fill="#1A1815" />
      </svg>
      <div className="text-center -mt-1">
        <span className="font-mono text-xl font-semibold text-text-primary">{acwr.toFixed(2)}</span>
        <span className="block text-[10px] font-medium tracking-wider uppercase text-text-tertiary">{zoneLabel}</span>
      </div>
    </div>
  );
}
