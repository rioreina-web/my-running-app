/* global React */
/* ════════════════════════════════════════════════════════════════════
   PLAN PAGE — chart primitives
   - BlockMileageBars: 16-week bar chart with current week marked + phases
   - LoadPreview: 7-day load barcode
   - PaceZonesTable: today's pace targets
   ════════════════════════════════════════════════════════════════════ */

const INK = "#1A1815";
const INK2 = "#6B6560";
const INK3 = "#9B9590";
const HAIRLINE = "#E8E4E0";
const SAGE = "#6B8068";
const CORAL = "#D4592A";

/* ════════════════════════════════════════════════════════════════════
   BLOCK MILEAGE BARS — 16 weeks. Phases as ranges. Current week marked.
   ════════════════════════════════════════════════════════════════════ */
window.BlockMileageBars = function BlockMileageBars({
  weeks,            // [{ idx, miles, phase, isCurrent, isDone }]
  height = 200,
  accent = CORAL,
}) {
  const W = 720;
  const H = height;
  const padL = 40;
  const padR = 16;
  const padT = 14;
  const padB = 42;

  const max = Math.max(...weeks.map((w) => w.miles)) * 1.05;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const slot = innerW / weeks.length;
  const barW = slot * 0.62;

  const colorFor = (w) => {
    if (w.isCurrent) return accent;
    if (w.isDone) return INK;
    return INK3;
  };
  const opacityFor = (w) => {
    if (w.isCurrent) return 1;
    if (w.isDone) return 0.7;
    return 0.35;
  };

  const yTicks = [0, 20, 40, 60];

  // Phase spans
  const phases = [];
  let cur = null;
  weeks.forEach((w, i) => {
    if (!cur || cur.phase !== w.phase) {
      if (cur) phases.push(cur);
      cur = { phase: w.phase, start: i, end: i };
    } else {
      cur.end = i;
    }
  });
  if (cur) phases.push(cur);

  const xFor = (i) => padL + i * slot + slot / 2;

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {/* y-axis grid */}
      {yTicks.map((t) => {
        const y = padT + ((max - t) / max) * innerH;
        return (
          <g key={t}>
            <line
              x1={padL}
              x2={W - padR}
              y1={y}
              y2={y}
              stroke={HAIRLINE}
              strokeWidth="1"
              strokeDasharray={t === 0 ? "0" : "2 3"}
            />
            <text
              x={padL - 8}
              y={y + 3}
              textAnchor="end"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="9"
              letterSpacing="1.2"
              fill={INK3}
            >
              {t}
            </text>
          </g>
        );
      })}

      {/* phase bars + labels */}
      {phases.map((p) => {
        const x0 = padL + p.start * slot;
        const x1 = padL + (p.end + 1) * slot;
        return (
          <g key={`${p.phase}-${p.start}`}>
            <line
              x1={x0 + 2}
              x2={x1 - 2}
              y1={H - padB + 10}
              y2={H - padB + 10}
              stroke={HAIRLINE}
              strokeWidth="1"
            />
            <text
              x={(x0 + x1) / 2}
              y={H - padB + 22}
              textAnchor="middle"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="9"
              letterSpacing="1.4"
              fill={INK3}
            >
              {p.phase.toUpperCase()}
            </text>
          </g>
        );
      })}

      {/* bars */}
      {weeks.map((w, i) => {
        const h = (w.miles / max) * innerH;
        const x = padL + i * slot + (slot - barW) / 2;
        const y = padT + (innerH - h);
        return (
          <g key={i}>
            <rect
              x={x}
              y={y}
              width={barW}
              height={h}
              fill={colorFor(w)}
              opacity={opacityFor(w)}
              rx="1"
            />
            {/* week number */}
            <text
              x={xFor(i)}
              y={H - padB - 4}
              textAnchor="middle"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="8.5"
              letterSpacing="1.2"
              fill={w.isCurrent ? accent : INK3}
            >
              {String(w.idx).padStart(2, "0")}
            </text>
          </g>
        );
      })}

      {/* current week callout */}
      {(() => {
        const curIdx = weeks.findIndex((w) => w.isCurrent);
        if (curIdx < 0) return null;
        const w = weeks[curIdx];
        const h = (w.miles / max) * innerH;
        const x = xFor(curIdx);
        const y = padT + (innerH - h);
        return (
          <g>
            <line x1={x} x2={x} y1={y - 6} y2={y - 22} stroke={accent} strokeWidth="1" />
            <text
              x={x}
              y={y - 26}
              textAnchor="middle"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="9.5"
              letterSpacing="1.4"
              fill={accent}
            >
              YOU · {w.miles} MI
            </text>
          </g>
        );
      })()}
    </svg>
  );
};

/* ════════════════════════════════════════════════════════════════════
   LOAD PREVIEW — 7-day load barcode. Mon-first.
   ════════════════════════════════════════════════════════════════════ */
window.LoadPreview = function LoadPreview({
  days,        // [{ label, load (0-100), type, isToday }]
  accent = CORAL,
  height = 88,
}) {
  const W = 360;
  const H = height;
  const padL = 8;
  const padR = 8;
  const padT = 8;
  const padB = 26;
  const innerW = W - padL - padR;
  const innerH = H - padT - padB;
  const slot = innerW / days.length;
  const barW = slot * 0.74;

  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {/* baseline */}
      <line
        x1={padL}
        x2={W - padR}
        y1={H - padB}
        y2={H - padB}
        stroke={HAIRLINE}
        strokeWidth="1"
      />
      {days.map((d, i) => {
        const h = (d.load / 100) * innerH;
        const x = padL + i * slot + (slot - barW) / 2;
        const y = padT + (innerH - h);
        const color =
          d.type === "quality" ? accent :
          d.type === "long" ? SAGE :
          d.type === "rest" ? HAIRLINE :
          INK2;
        return (
          <g key={i}>
            {d.load > 0 ? (
              <rect
                x={x}
                y={y}
                width={barW}
                height={h}
                fill={color}
                opacity={d.isToday ? 1 : 0.7}
                rx="1"
              />
            ) : (
              <line
                x1={x}
                x2={x + barW}
                y1={H - padB - 1}
                y2={H - padB - 1}
                stroke={HAIRLINE}
                strokeWidth="2"
              />
            )}
            {/* day label */}
            <text
              x={x + barW / 2}
              y={H - 12}
              textAnchor="middle"
              fontFamily="ui-monospace, Menlo, monospace"
              fontSize="9"
              letterSpacing="1.4"
              fill={d.isToday ? accent : INK3}
              fontWeight={d.isToday ? "700" : "500"}
            >
              {d.label}
            </text>
            {/* today marker */}
            {d.isToday ? (
              <circle cx={x + barW / 2} cy={H - 3} r="1.6" fill={accent} />
            ) : null}
          </g>
        );
      })}
    </svg>
  );
};

/* ════════════════════════════════════════════════════════════════════
   PACE ZONES TABLE — canonical 7 zones from CLAUDE.md
   `highlight` is the zone the workout uses today.
   ════════════════════════════════════════════════════════════════════ */
window.PaceZonesTable = function PaceZonesTable({
  zones,       // [{ key, label, pace, range, note }]
  highlight,   // key to highlight
  accent = CORAL,
}) {
  return (
    <div className="border border-divider-soft rounded-md overflow-hidden">
      {zones.map((z, i) => {
        const isOn = z.key === highlight;
        return (
          <div
            key={z.key}
            className={`grid grid-cols-[88px_1fr_auto] items-baseline gap-3 px-3.5 py-2 ${
              i < zones.length - 1 ? "border-b border-divider-soft" : ""
            }`}
            style={{
              background: isOn ? "rgba(212, 89, 42, 0.06)" : "transparent",
            }}
          >
            <span
              className="font-mono text-[10px] tracking-[1.4px] uppercase"
              style={{ color: isOn ? accent : INK3 }}
            >
              {z.label}
            </span>
            <span
              className="font-mono text-[13px] tabular-nums"
              style={{ color: isOn ? INK : INK2, fontWeight: isOn ? 700 : 500 }}
            >
              {z.range || z.pace}
              <span className="ml-1 text-[10px] tracking-[1.2px] uppercase text-text-tertiary">
                / mi
              </span>
            </span>
            {z.note ? (
              <span className="font-body italic text-[12px] text-text-tertiary text-right">
                {z.note}
              </span>
            ) : (
              <span />
            )}
          </div>
        );
      })}
    </div>
  );
};

/* ════════════════════════════════════════════════════════════════════
   TAPER READINESS — small horizontal indicator. 0–100.
   ════════════════════════════════════════════════════════════════════ */
window.TaperReadiness = function TaperReadiness({ value = 62, accent = CORAL }) {
  const W = 220;
  const H = 14;
  return (
    <svg viewBox={`0 0 ${W} ${H}`} className="w-full h-auto block">
      {/* track */}
      <rect x="0" y="6" width={W} height="3" fill={HAIRLINE} rx="1.5" />
      {/* tick marks at 25/50/75 */}
      {[25, 50, 75].map((t) => (
        <line
          key={t}
          x1={(W * t) / 100}
          x2={(W * t) / 100}
          y1="3"
          y2="12"
          stroke={INK3}
          strokeWidth="1"
          opacity="0.4"
        />
      ))}
      {/* progress */}
      <rect
        x="0"
        y="6"
        width={(W * value) / 100}
        height="3"
        fill={INK}
        rx="1.5"
      />
      {/* current marker */}
      <circle
        cx={(W * value) / 100}
        cy="7.5"
        r="3.5"
        fill={accent}
        stroke="#FFFFFF"
        strokeWidth="1.5"
      />
    </svg>
  );
};
