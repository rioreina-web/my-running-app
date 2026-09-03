/* Athlete-site mockup · tiny SVG chart primitives.
   Everything is drawn with SVG attributes (not CSS `style`) so the
   charts render under the app's nonce-only CSP. Colours reference the
   scoped tokens via `currentColor` and explicit hex from the design
   system. */

const INK = "#1A1815";
const INK2 = "#6B6560";
const INK3 = "#9B9590";
const CORAL = "#D4592A";
const RULE = "#E8E4E0";

function scale(values: number[], h: number, pad = 8, invert = false) {
  const min = Math.min(...values);
  const max = Math.max(...values);
  const span = max - min || 1;
  return (v: number) => {
    const t = (v - min) / span;
    const y = h - pad - t * (h - pad * 2);
    return invert ? h - y : y;
  };
}

function pathFrom(xs: number[], ys: number[]) {
  return xs.map((x, i) => `${i === 0 ? "M" : "L"} ${x.toFixed(1)} ${ys[i].toFixed(1)}`).join(" ");
}

/** Fitness arc · 26 weeks, lower = fitter, races as vertical markers,
 *  goal line along the bottom. */
export function FitnessArc({
  data,
  markers,
  goal,
  height = 120,
}: {
  data: number[];
  markers: { index: number; short: string }[];
  goal: number;
  height?: number;
}) {
  const w = 320;
  const h = height;
  const all = [...data, goal];
  const y = scale(all, h, 12, true); // invert: lower time = higher on chart
  const xs = data.map((_, i) => 24 + (i / (data.length - 1)) * (w - 36));
  const ys = data.map((v) => y(v));
  const goalY = y(goal);
  const last = data.length - 1;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} className="m-chart" role="img" aria-label="Twenty-six week fitness arc with race anchors and goal line">
      {/* goal line */}
      <line x1={24} x2={w - 12} y1={goalY} y2={goalY} stroke={INK3} strokeWidth={1} strokeDasharray="3 4" />
      <text x={w - 12} y={goalY - 4} fontSize={8} fill={INK3} textAnchor="end" fontFamily="ui-monospace, monospace" letterSpacing="1">
        GOAL 3:16
      </text>
      {/* race markers */}
      {markers.map((m) => (
        <g key={m.short}>
          <line x1={xs[m.index]} x2={xs[m.index]} y1={10} y2={h - 10} stroke={RULE} strokeWidth={1} />
          <circle cx={xs[m.index]} cy={ys[m.index]} r={3} fill="#fff" stroke={INK} strokeWidth={1.5} />
          <text x={xs[m.index]} y={h - 1} fontSize={7.5} fill={INK2} textAnchor="middle" fontFamily="ui-monospace, monospace" letterSpacing="1">
            {m.short}
          </text>
        </g>
      ))}
      {/* arc */}
      <path d={pathFrom(xs, ys)} fill="none" stroke={INK} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={xs[last]} cy={ys[last]} r={3.5} fill={CORAL} />
      {/* anchor label sits under the start of the arc */}
      <circle cx={xs[0]} cy={ys[0]} r={3} fill="#fff" stroke={INK} strokeWidth={1.5} />
      <text x={xs[0] - 2} y={ys[0] - 8} fontSize={7.5} fill={INK3} fontFamily="ui-monospace, monospace" letterSpacing="1">
        HOUSTON 3:28
      </text>
    </svg>
  );
}

/** Simple line chart with a coral end dot. */
export function LineChart({ data, height = 70, coralLast = true }: { data: number[]; height?: number; coralLast?: boolean }) {
  const w = 280;
  const y = scale(data, height, 6);
  const xs = data.map((_, i) => (i / (data.length - 1)) * w);
  const ys = data.map(y);
  return (
    <svg viewBox={`0 0 ${w} ${height}`} preserveAspectRatio="none" className="m-chart" aria-hidden="true">
      <path d={pathFrom(xs, ys)} fill="none" stroke={INK} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
      {coralLast ? <circle cx={xs[xs.length - 1]} cy={ys[ys.length - 1]} r={3.5} fill={CORAL} /> : null}
    </svg>
  );
}

/** Weekly volume bars · last bar in ink, the rest in ink-3. */
export function VolumeBars({ data, height = 64, highlightLast = true }: { data: number[]; height?: number; highlightLast?: boolean }) {
  const w = 280;
  const gap = 4;
  const bw = (w - gap * (data.length - 1)) / data.length;
  const max = Math.max(...data);
  return (
    <svg viewBox={`0 0 ${w} ${height}`} preserveAspectRatio="none" className="m-chart" aria-hidden="true">
      {data.map((v, i) => {
        const bh = (v / max) * (height - 4);
        const isLast = i === data.length - 1;
        return (
          <rect
            key={i}
            x={i * (bw + gap)}
            y={height - bh}
            width={bw}
            height={bh}
            fill={isLast && highlightLast ? INK : INK3}
            opacity={isLast && highlightLast ? 1 : 0.6}
            rx={1}
          />
        );
      })}
    </svg>
  );
}

/** Two-series overlay · this build vs. the last one. */
export function CycleOverlay({ current, prior, height = 90 }: { current: number[]; prior: number[]; height?: number }) {
  const w = 300;
  const n = Math.max(current.length, prior.length);
  const y = scale([...current, ...prior], height, 8);
  const x = (i: number) => (i / (n - 1)) * w;
  const cx = current.map((_, i) => x(i));
  const px = prior.map((_, i) => x(i));
  return (
    <svg viewBox={`0 0 ${w} ${height}`} preserveAspectRatio="none" className="m-chart" aria-hidden="true">
      <path d={pathFrom(px, prior.map(y))} fill="none" stroke={INK3} strokeWidth={1.5} strokeDasharray="3 4" strokeLinecap="round" />
      <path d={pathFrom(cx, current.map(y))} fill="none" stroke={INK} strokeWidth={1.5} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={cx[cx.length - 1]} cy={y(current[current.length - 1])} r={3.5} fill={CORAL} />
    </svg>
  );
}

/** Horizontal share bar · pace × volume distribution. */
export function ShareBar({ pct, coral }: { pct: number; coral?: boolean }) {
  return (
    <svg viewBox="0 0 100 6" preserveAspectRatio="none" className="m-chart" height={6} aria-hidden="true">
      <rect x={0} y={0} width={100} height={6} rx={3} fill="#E8E4DF" />
      <rect x={0} y={0} width={Math.max(pct, 1)} height={6} rx={3} fill={coral ? CORAL : INK2} />
    </svg>
  );
}

/** Workout telemetry · pace (ink), HR (coral), elevation (paper-deep area). */
export function Telemetry({ pace, hr, elev, height = 120 }: { pace: number[]; hr: number[]; elev: number[]; height?: number }) {
  const w = 320;
  const n = pace.length;
  const x = (i: number) => (i / (n - 1)) * w;
  const paceY = scale(pace, height, 14, true);
  const hrY = scale(hr, height, 14);
  const elevY = scale(elev, height, 40);
  const xs = pace.map((_, i) => x(i));
  const elevPath = `${pathFrom(xs, elev.map(elevY))} L ${w} ${height} L 0 ${height} Z`;
  return (
    <svg viewBox={`0 0 ${w} ${height}`} preserveAspectRatio="none" className="m-chart" role="img" aria-label="Pace, heart rate and elevation over the run">
      <path d={elevPath} fill="#E8E4DF" opacity={0.9} />
      <path d={pathFrom(xs, hr.map(hrY))} fill="none" stroke={CORAL} strokeWidth={1.2} strokeLinecap="round" opacity={0.9} />
      <path d={pathFrom(xs, pace.map(paceY))} fill="none" stroke={INK} strokeWidth={1.6} strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Prescribed pace shape · warm-up / main / cool-down blocks. */
export function PaceShape({ shape }: { shape: { kind: "wu" | "main" | "cd" | "rest"; flex: number; h: number; label?: string }[] }) {
  const w = 320;
  const h = 56;
  const gap = 3;
  const total = shape.reduce((s, b) => s + b.flex, 0);
  const widths = shape.map((b) => (b.flex / total) * (w - gap * (shape.length - 1)));
  const starts = widths.map((_, i) => widths.slice(0, i).reduce((s, bw) => s + bw + gap, 0));
  return (
    <div>
      <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" className="m-chart" aria-hidden="true">
        {shape.map((b, i) => {
          const bw = widths[i];
          const bx = starts[i];
          const bh = (b.h / 100) * h;
          const fill = b.kind === "main" ? CORAL : INK3;
          const op = b.kind === "main" ? 1 : b.kind === "rest" ? 0.25 : 0.4;
          return <rect key={i} x={bx} y={h - bh} width={bw} height={bh} rx={2} fill={fill} opacity={op} />;
        })}
      </svg>
      <div className="m-chart__axis">
        {shape
          .filter((b) => b.label)
          .map((b, i) => (
            <span key={i} className="m-caption m-caption--faint m-eyebrow--sm">
              {b.label}
            </span>
          ))}
      </div>
    </div>
  );
}

/** Race split bars · relative to the slowest split. */
export function SplitBar({ sec, max, min, key: _k }: { sec: number; max: number; min: number; key?: string }) {
  void _k;
  const pct = 30 + ((max - sec) / (max - min || 1)) * 70;
  return (
    <svg viewBox="0 0 100 6" preserveAspectRatio="none" className="m-chart" height={6} aria-hidden="true">
      <rect x={0} y={0} width={100} height={6} rx={3} fill="#E8E4DF" />
      <rect x={0} y={0} width={pct} height={6} rx={3} fill={INK2} />
    </svg>
  );
}
