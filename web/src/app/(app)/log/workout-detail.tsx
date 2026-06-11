"use client";

import { useState, useEffect, useRef } from "react";
import type { TrainingLog } from "@/lib/types";
import type { WorkoutStreamData, TimelinePoint } from "@/lib/vital";

// ─── Main Detail Panel ───────────────────────────────────────

export function WorkoutDetail({
  log,
}: {
  log: TrainingLog;
  onClose?: () => void;
}) {
  const [data, setData] = useState<WorkoutStreamData | null>(null);
  const [loading, setLoading] = useState(false);
  const [activeTab, setActiveTab] = useState<"splits" | "hr" | "effort">("splits");

  useEffect(() => {
    const id = log.vital_workout_id;
    if (!id) return;
    let cancelled = false;
    // Kick off the request, then flip loading on inside the promise chain so
    // we never call setState synchronously in the effect body (which would
    // trigger cascading renders). Cancellation guards against late responses
    // resolving after the workout has changed/unmounted.
    Promise.resolve()
      .then(() => {
        if (!cancelled) setLoading(true);
        return fetch(`/api/vital-stream?id=${id}`);
      })
      .then((r) => r.json())
      .then((d) => {
        if (!cancelled) setData(d);
      })
      .catch(() => {})
      .finally(() => {
        if (!cancelled) setLoading(false);
      });
    return () => {
      cancelled = true;
    };
  }, [log.vital_workout_id]);

  const summary = data?.summary;

  return (
    <div className="space-y-5" onClick={(e) => e.stopPropagation()}>
      {/* Summary stat cards */}
      {summary && (
        <div className="grid grid-cols-4 gap-2">
          {summary.averageHr && <MiniStat label="Avg HR" value={`${summary.averageHr}`} unit="bpm" />}
          {summary.maxHr && <MiniStat label="Max HR" value={`${summary.maxHr}`} unit="bpm" accent />}
          {summary.elevationGainFt && <MiniStat label="Gain" value={`${summary.elevationGainFt}`} unit="ft" />}
          {summary.cadenceAvg && <MiniStat label="Cadence" value={`${summary.cadenceAvg}`} unit="spm" />}
        </div>
      )}

      {/* Auto-generated coaching insights */}
      {data?.insights && data.insights.length > 0 && (
        <div className="rounded-lg border-l-2 border-coral bg-bg-elevated px-4 py-3 space-y-1.5">
          {data.insights.map((insight, i) => (
            <p key={i} className="text-sm leading-relaxed text-text-secondary">
              {insight}
            </p>
          ))}
        </div>
      )}

      {/* Tab bar */}
      {data && (
        <>
          <div className="flex gap-0 border-b border-divider">
            {(["splits", "hr", "effort"] as const).map((tab) => (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={`px-4 py-2 font-mono text-[10px] tracking-[0.2em] uppercase transition-colors border-b-2 -mb-px ${
                  activeTab === tab
                    ? "text-coral border-coral"
                    : "text-text-tertiary border-transparent hover:text-text-secondary"
                }`}
              >
                {tab === "splits" ? "Mile Splits" : tab === "hr" ? "Heart Rate" : "Effort"}
              </button>
            ))}
          </div>

          {/* Tab content */}
          <div className="min-h-[200px]">
            {activeTab === "splits" && <SplitsTab data={data} />}
            {activeTab === "hr" && <HRTab data={data} />}
            {activeTab === "effort" && <EffortTab data={data} />}
          </div>
        </>
      )}

      {/* Pace / HR overlay chart */}
      {data?.timeline && data.timeline.length > 5 && (
        <div>
          <h4 className="mb-2 font-mono text-[10px] tracking-[0.2em] text-text-tertiary uppercase">
            Pace & Heart Rate
          </h4>
          <OverlayChart timeline={data.timeline} />
        </div>
      )}

      {/* Elevation */}
      {data?.elevationProfile && data.elevationProfile.length > 5 && (
        <div>
          <h4 className="mb-2 font-mono text-[10px] tracking-[0.2em] text-text-tertiary uppercase">
            Elevation
          </h4>
          <ElevationChart data={data.elevationProfile} />
        </div>
      )}

      {loading && (
        <div className="flex items-center gap-2 py-4">
          <div className="h-3 w-3 rounded-full border-2 border-coral border-t-transparent animate-spin" />
          <span className="font-mono text-xs text-text-tertiary">Loading Garmin data...</span>
        </div>
      )}
    </div>
  );
}

// ─── Mile Splits Tab ─────────────────────────────────────────

function SplitsTab({ data }: { data: WorkoutStreamData }) {
  const splits = data.mileSplits;
  if (!splits.length) return <EmptyTab message="No split data available" />;

  const fullSplits = splits.filter((s) => !s.isPartial);
  const fastest = Math.min(...fullSplits.map((s) => s.paceSeconds));
  const slowest = Math.max(...fullSplits.map((s) => s.paceSeconds));
  const range = slowest - fastest || 1;
  const avg = fullSplits.reduce((s, sp) => s + sp.paceSeconds, 0) / fullSplits.length;

  return (
    <div className="space-y-1">
      {splits.map((split) => {
        const delta = split.paceSeconds - avg;
        const pct = 1 - (split.paceSeconds - fastest) / range;
        const barWidth = Math.max(25, Math.min(100, 25 + pct * 75));
        const isFast = delta < -3;
        const isSlow = delta > 3;

        return (
          <div key={split.mile} className="group flex items-center gap-2 py-0.5">
            <span className="font-mono text-xs text-text-tertiary w-5 text-right">
              {split.isPartial ? `${(split.partialDistance || 0).toFixed(1)}` : split.mile}
            </span>

            <div className="flex-1 h-7 bg-bg-elevated rounded overflow-hidden relative">
              <div
                className={`h-full rounded flex items-center px-2 transition-all ${
                  isFast ? "bg-mood-energized/60" : isSlow ? "bg-mood-tired/50" : "bg-coral/50"
                }`}
                style={{ width: `${barWidth}%` }}
              >
                <span className="font-mono text-[11px] font-medium text-text-primary">
                  {split.pace}
                </span>
              </div>

              {/* Delta label */}
              <span
                className={`absolute right-2 top-1/2 -translate-y-1/2 font-mono text-[9px] ${
                  isFast ? "text-mood-energized" : isSlow ? "text-mood-tired" : "text-text-tertiary"
                }`}
              >
                {delta > 0 ? "+" : ""}{Math.round(delta)}s
              </span>
            </div>

            {/* HR for this mile */}
            {split.heartRate && (
              <span className="font-mono text-[10px] text-text-tertiary w-10 text-right">
                {split.heartRate}
              </span>
            )}

            {/* Elevation for this mile */}
            {split.elevation !== null && split.elevation !== 0 && (
              <span className={`font-mono text-[10px] w-8 text-right ${split.elevation > 0 ? "text-mood-tired" : "text-mood-positive"}`}>
                {split.elevation > 0 ? "+" : ""}{split.elevation}
              </span>
            )}
          </div>
        );
      })}

      {/* Legend */}
      <div className="flex items-center gap-4 pt-2 border-t border-divider mt-2">
        <span className="font-mono text-[9px] text-text-tertiary">
          Avg: {formatPace(avg)}/mi
        </span>
        <span className="font-mono text-[9px] text-mood-energized">
          Fastest: {formatPace(fastest)}/mi
        </span>
        <span className="font-mono text-[9px] text-mood-tired">
          Slowest: {formatPace(slowest)}/mi
        </span>
      </div>
    </div>
  );
}

// ─── Heart Rate Tab ──────────────────────────────────────────

function HRTab({ data }: { data: WorkoutStreamData }) {
  const { hrZones } = data;
  if (!hrZones.zones.length) return <EmptyTab message="No heart rate data" />;

  const activeZones = hrZones.zones.filter((z) => z.seconds > 0);

  return (
    <div className="space-y-4">
      {/* Zone bar — stacked horizontal */}
      <div className="rounded-lg overflow-hidden flex h-8">
        {activeZones.map((zone) => (
          <div
            key={zone.name}
            className="flex items-center justify-center text-white font-mono text-[9px] font-medium transition-all"
            style={{
              width: `${zone.pct}%`,
              backgroundColor: zone.color,
              minWidth: zone.pct > 3 ? "auto" : "0",
            }}
          >
            {zone.pct > 8 ? `${zone.pct}%` : ""}
          </div>
        ))}
      </div>

      {/* Zone detail rows */}
      <div className="space-y-1.5">
        {hrZones.zones.map((zone) => (
          <div key={zone.name} className="flex items-center gap-3">
            <div className="w-2 h-2 rounded-full" style={{ backgroundColor: zone.color }} />
            <span className="font-mono text-xs text-text-secondary w-28">{zone.name}</span>
            <span className="font-mono text-xs text-text-tertiary w-16">
              {zone.min}-{zone.max === 999 ? `${hrZones.maxHr}+` : zone.max}
            </span>
            <div className="flex-1 h-3 bg-bg-elevated rounded-sm overflow-hidden">
              <div
                className="h-full rounded-sm"
                style={{ width: `${zone.pct}%`, backgroundColor: zone.color }}
              />
            </div>
            <span className="font-mono text-xs text-text-primary w-12 text-right">
              {formatTime(zone.seconds)}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Effort Tab ──────────────────────────────────────────────

function EffortTab({ data }: { data: WorkoutStreamData }) {
  const blocks = data.effortDistribution;
  if (!blocks.length) return <EmptyTab message="No effort data" />;

  const effortTypes: { key: string; label: string; color: string }[] = [
    { key: "easy", label: "Easy", color: "#4A9E6B" },
    { key: "recovery", label: "Recovery", color: "#9B9590" },
    { key: "moderate", label: "Moderate", color: "#C4873A" },
    { key: "hard", label: "Hard", color: "#D4592A" },
  ];

  // Aggregate blocks by type
  const totals = effortTypes.map(({ key, label, color }) => {
    const matching = blocks.filter((b) => b.type === key);
    const miles = matching.reduce((s, b) => s + b.distanceMiles, 0);
    const seconds = matching.reduce((s, b) => s + (b.endMin - b.startMin) * 60, 0);
    const hrSum = matching.reduce((s, b) => s + b.avgHr * (b.endMin - b.startMin), 0);
    const durSum = matching.reduce((s, b) => s + (b.endMin - b.startMin), 0);
    const avgHr = durSum > 0 ? Math.round(hrSum / durSum) : 0;
    const avgPace = matching.length > 0
      ? matching.reduce((s, b) => s + b.avgPace * b.distanceMiles, 0) / Math.max(miles, 0.01)
      : 0;
    return { key, label, color, miles, seconds, avgHr, avgPace };
  }).filter((t) => t.miles > 0);

  const totalMiles = totals.reduce((s, t) => s + t.miles, 0);

  return (
    <div className="space-y-4">
      {/* Proportion bar */}
      <div className="rounded-lg overflow-hidden flex h-6">
        {totals.map((t) => {
          const pct = (t.miles / totalMiles) * 100;
          return (
            <div
              key={t.key}
              className="h-full flex items-center justify-center"
              style={{ width: `${pct}%`, backgroundColor: t.color }}
            >
              {pct > 12 && (
                <span className="font-mono text-[9px] font-medium text-white">
                  {Math.round(pct)}%
                </span>
              )}
            </div>
          );
        })}
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 gap-2">
        {totals.map((t) => (
          <div key={t.key} className="rounded-lg bg-bg-elevated px-3 py-2.5">
            <div className="flex items-center gap-2 mb-1.5">
              <div className="w-2 h-2 rounded-full" style={{ backgroundColor: t.color }} />
              <span className="font-mono text-[10px] tracking-wide uppercase text-text-secondary">
                {t.label}
              </span>
            </div>
            <div className="flex items-baseline gap-2">
              <span className="font-mono text-base font-medium text-text-primary">
                {t.miles.toFixed(1)} mi
              </span>
              <span className="font-mono text-[10px] text-text-tertiary">
                {Math.round((t.miles / totalMiles) * 100)}%
              </span>
            </div>
            <div className="flex gap-3 mt-1">
              {t.avgPace > 0 && (
                <span className="font-mono text-[10px] text-text-tertiary">
                  {formatPace(t.avgPace)}/mi
                </span>
              )}
              {t.avgHr > 0 && (
                <span className="font-mono text-[10px] text-text-tertiary">
                  {t.avgHr} bpm
                </span>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Pace / HR Overlay Chart ─────────────────────────────────

function OverlayChart({ timeline }: { timeline: TimelinePoint[] }) {
  const [hoverIdx, setHoverIdx] = useState<number | null>(null);
  const svgRef = useRef<SVGSVGElement>(null);

  // Filter out stopped points for cleaner chart
  const filtered = timeline.filter((t) => t.pace > 0 && t.pace < 900);
  if (filtered.length < 3) return null;

  const height = 100;
  const width = 400;

  // Pace range (inverted — lower pace = higher on chart)
  const paces = filtered.map((t) => t.pace);
  const paceMin = Math.min(...paces) - 10;
  const paceMax = Math.max(...paces) + 10;

  // HR range
  const hrs = filtered.map((t) => t.hr).filter((h) => h > 0);
  const hrMin = Math.min(...hrs) - 5;
  const hrMax = Math.max(...hrs) + 5;

  const pacePoints = filtered.map((t, i) => {
    const x = (i / (filtered.length - 1)) * width;
    const y = ((t.pace - paceMin) / (paceMax - paceMin)) * height; // NOT inverted — faster pace is lower on chart (lower number = faster)
    return `${x},${y}`;
  }).join(" ");

  const hrPoints = filtered.map((t, i) => {
    const x = (i / (filtered.length - 1)) * width;
    const y = height - ((t.hr - hrMin) / (hrMax - hrMin)) * height;
    return `${x},${y}`;
  }).join(" ");

  const handleMouseMove = (e: React.MouseEvent) => {
    if (!svgRef.current) return;
    const rect = svgRef.current.getBoundingClientRect();
    const x = (e.clientX - rect.left) / rect.width;
    const idx = Math.round(x * (filtered.length - 1));
    setHoverIdx(Math.max(0, Math.min(filtered.length - 1, idx)));
  };

  const hovered = hoverIdx !== null ? filtered[hoverIdx] : null;

  return (
    <div className="rounded-lg bg-bg-elevated p-3">
      {/* Hover tooltip */}
      {hovered && (
        <div className="flex items-center gap-4 mb-2 font-mono text-xs">
          <span className="text-text-tertiary">{hovered.minute}min</span>
          <span className="text-coral">{formatPace(hovered.pace)}/mi</span>
          <span className="text-mood-struggling">{hovered.hr} bpm</span>
          <span className="text-text-tertiary">{hovered.distance}mi</span>
          <span className="text-mood-positive">{hovered.altitude}ft</span>
        </div>
      )}

      <svg
        ref={svgRef}
        viewBox={`0 0 ${width} ${height}`}
        className="w-full h-24 cursor-crosshair"
        preserveAspectRatio="none"
        onMouseMove={handleMouseMove}
        onMouseLeave={() => setHoverIdx(null)}
      >
        {/* Pace line */}
        <polyline points={pacePoints} fill="none" stroke="#D4592A" strokeWidth="2" vectorEffect="non-scaling-stroke" />
        {/* HR line */}
        <polyline points={hrPoints} fill="none" stroke="#C45A3A" strokeWidth="1.5" strokeOpacity="0.5" vectorEffect="non-scaling-stroke" strokeDasharray="3,2" />

        {/* Hover line */}
        {hoverIdx !== null && (
          <line
            x1={(hoverIdx / (filtered.length - 1)) * width}
            y1="0"
            x2={(hoverIdx / (filtered.length - 1)) * width}
            y2={height}
            stroke="#9B9590"
            strokeWidth="1"
            vectorEffect="non-scaling-stroke"
          />
        )}
      </svg>

      <div className="flex justify-between mt-1">
        <div className="flex gap-3">
          <span className="flex items-center gap-1 font-mono text-[9px] text-coral">
            <span className="w-3 h-0.5 bg-coral inline-block" /> pace
          </span>
          <span className="flex items-center gap-1 font-mono text-[9px] text-mood-struggling">
            <span className="w-3 h-0.5 bg-mood-struggling/50 inline-block border-t border-dashed border-mood-struggling" /> hr
          </span>
        </div>
        <span className="font-mono text-[9px] text-text-tertiary">hover for details</span>
      </div>
    </div>
  );
}

// ─── Elevation Chart ─────────────────────────────────────────

function ElevationChart({ data }: { data: { distance: number; altitude: number }[] }) {
  const min = Math.min(...data.map((d) => d.altitude)) - 5;
  const max = Math.max(...data.map((d) => d.altitude)) + 5;
  const range = max - min;
  const height = 60;
  const width = 400;

  const points = data.map((d, i) => {
    const x = (i / (data.length - 1)) * width;
    const y = height - ((d.altitude - min) / range) * height;
    return `${x},${y}`;
  }).join(" ");

  const fillPoints = `0,${height} ${points} ${width},${height}`;

  return (
    <div className="rounded-lg bg-bg-elevated p-3">
      <svg viewBox={`0 0 ${width} ${height}`} className="w-full h-14" preserveAspectRatio="none">
        <polygon points={fillPoints} fill="#2D8A4E" fillOpacity="0.12" />
        <polyline points={points} fill="none" stroke="#2D8A4E" strokeWidth="1.5" vectorEffect="non-scaling-stroke" />
      </svg>
      <div className="mt-1 flex justify-between font-mono text-[9px] text-text-tertiary">
        <span>{Math.round(min)} ft</span>
        <span>{data[data.length - 1]?.distance.toFixed(1)} mi</span>
        <span>{Math.round(max)} ft</span>
      </div>
    </div>
  );
}

// ─── Small Components ────────────────────────────────────────

function MiniStat({ label, value, accent }: { label: string; value: string; unit?: string; accent?: boolean }) {
  return (
    <div className="rounded-lg bg-bg-elevated px-2.5 py-2 text-center">
      <div className={`font-mono text-base font-medium leading-tight ${accent ? "text-coral" : "text-text-primary"}`}>{value}</div>
      <div className="font-mono text-[8px] text-text-tertiary uppercase tracking-wider mt-0.5">{label}</div>
    </div>
  );
}

function EmptyTab({ message }: { message: string }) {
  return (
    <div className="flex items-center justify-center h-32 text-sm text-text-tertiary italic">
      {message}
    </div>
  );
}

// ─── Helpers ─────────────────────────────────────────────────

function formatPace(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function formatTime(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = seconds % 60;
  if (m > 0) return `${m}m`;
  return `${s}s`;
}
