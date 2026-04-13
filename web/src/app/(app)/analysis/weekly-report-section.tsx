"use client";

import { useState } from "react";

interface WeeklyReport {
  week_start: string;
  week_end: string;
  coaching_narrative: string;
  alerts: { severity: string; title: string; message: string }[];
  adjustments: { action: string; target_workout_type: string; rationale: string; priority: string }[];
  focus_areas: string[];
  metrics: {
    totalMiles?: number;
    runCount?: number;
    acwr?: number;
    complianceScore?: number;
    longRunMiles?: number;
    volumeChangePct?: number;
    avgPaceSeconds?: number;
    easyPaceAvg?: number;
  } | null;
}

function formatPace(seconds: number): string {
  const m = Math.floor(seconds / 60);
  const s = Math.round(seconds % 60);
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function formatWeekDate(dateStr: string): string {
  const d = new Date(dateStr + "T00:00:00");
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

const severityColor: Record<string, string> = {
  red: "text-red-600 bg-red-50",
  orange: "text-orange-600 bg-orange-50",
  yellow: "text-yellow-700 bg-yellow-50",
  green: "text-green-600 bg-green-50",
};

const priorityColor: Record<string, string> = {
  high: "text-red-600 bg-red-50",
  medium: "text-amber-600 bg-amber-50",
  low: "text-green-600 bg-green-50",
};

export function WeeklyReportSection() {
  const [report, setReport] = useState<WeeklyReport | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function generate() {
    setLoading(true);
    setError(null);
    try {
      const res = await fetch("/api/weekly-report", { method: "POST" });
      const data = await res.json();
      if (data.report) {
        // Fix narrative if it's a nested object
        const r = data.report;
        if (typeof r.coaching_narrative === "object" && r.coaching_narrative?.narrative) {
          r.coaching_narrative = r.coaching_narrative.narrative;
        }
        setReport(r);
      } else {
        setError(data.error || "Failed to generate report");
      }
    } catch {
      setError("Network error");
    }
    setLoading(false);
  }

  if (!report && !loading) {
    return (
      <div className="rounded-xl border border-divider bg-bg-card p-6 text-center">
        <h3 className="font-display text-xl text-text-primary">Weekly Coaching Analysis</h3>
        <p className="mt-2 text-sm text-text-tertiary">AI-generated training review based on your Garmin data, voice memos, and training plan.</p>
        <button
          onClick={generate}
          className="mt-4 rounded-lg bg-coral px-5 py-2.5 font-mono text-xs font-medium text-white transition-colors hover:bg-coral-light"
        >
          Generate Report
        </button>
      </div>
    );
  }

  if (loading) {
    return (
      <div className="rounded-xl border border-divider bg-bg-card p-8 text-center">
        <div className="mx-auto h-6 w-6 rounded-full border-2 border-coral border-t-transparent animate-spin" />
        <p className="mt-3 text-sm text-text-tertiary">Analyzing your training...</p>
        <p className="mt-1 text-xs text-text-tertiary">This takes 15-30 seconds</p>
      </div>
    );
  }

  if (error) {
    return (
      <div className="rounded-xl border border-divider bg-bg-card p-6 text-center">
        <p className="text-sm text-red-600">{error}</p>
        <button
          onClick={generate}
          className="mt-3 rounded-lg bg-bg-elevated px-4 py-2 font-mono text-xs text-text-secondary hover:text-coral"
        >
          Retry
        </button>
      </div>
    );
  }

  if (!report) return null;

  const narrative = report.coaching_narrative || "";
  const paragraphs = narrative.split(/\n\n|\n/).filter((p: string) => p.trim());
  const metrics = report.metrics;

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h3 className="font-display text-xl text-text-primary">Weekly Analysis</h3>
          <p className="text-xs text-text-tertiary">
            {formatWeekDate(report.week_start)} — {formatWeekDate(report.week_end)}
          </p>
        </div>
        <button
          onClick={generate}
          className="font-mono text-[10px] text-text-tertiary hover:text-coral transition-colors"
        >
          regenerate
        </button>
      </div>

      {/* Metrics bar */}
      {metrics && (
        <div className="grid grid-cols-3 md:grid-cols-6 gap-2">
          {metrics.totalMiles != null && <MetricPill label="Miles" value={metrics.totalMiles.toFixed(1)} />}
          {metrics.runCount != null && <MetricPill label="Runs" value={String(metrics.runCount)} />}
          {metrics.acwr != null && (
            <MetricPill
              label="ACWR"
              value={metrics.acwr.toFixed(2)}
              alert={metrics.acwr > 1.3 ? "red" : metrics.acwr > 1.2 ? "orange" : undefined}
            />
          )}
          {metrics.avgPaceSeconds != null && <MetricPill label="Avg Pace" value={`${formatPace(metrics.avgPaceSeconds)}/mi`} />}
          {metrics.longRunMiles != null && <MetricPill label="Long Run" value={`${metrics.longRunMiles}mi`} />}
          {metrics.volumeChangePct != null && (
            <MetricPill
              label="Vol Change"
              value={`${metrics.volumeChangePct > 0 ? "+" : ""}${Math.round(metrics.volumeChangePct)}%`}
              alert={Math.abs(metrics.volumeChangePct) > 20 ? "orange" : undefined}
            />
          )}
        </div>
      )}

      {/* Narrative */}
      <div className="rounded-xl border-l-2 border-coral bg-bg-card p-5 space-y-3">
        {paragraphs.map((p: string, i: number) => (
          <p key={i} className="text-sm leading-relaxed text-text-primary">
            {p.trim()}
          </p>
        ))}
      </div>

      {/* Alerts */}
      {report.alerts.length > 0 && (
        <div className="space-y-2">
          {report.alerts.map((alert, i) => (
            <div key={i} className={`rounded-lg px-4 py-3 ${severityColor[alert.severity] || severityColor.green}`}>
              <span className="font-mono text-xs font-medium">{alert.title}</span>
              <span className="ml-2 text-xs opacity-80">{alert.message}</span>
            </div>
          ))}
        </div>
      )}

      {/* Adjustments */}
      {report.adjustments.length > 0 && (
        <div className="space-y-2">
          <h4 className="font-mono text-[10px] tracking-[0.2em] text-text-tertiary uppercase">Recommended Adjustments</h4>
          {report.adjustments.map((adj, i) => (
            <div key={i} className="flex items-start gap-3 rounded-lg bg-bg-card border border-divider px-4 py-3">
              <span className={`mt-0.5 rounded-full px-2 py-0.5 font-mono text-[9px] font-medium ${priorityColor[adj.priority] || ""}`}>
                {adj.priority}
              </span>
              <div>
                <span className="font-mono text-xs text-text-primary">
                  {adj.action.replace(/_/g, " ")} — {adj.target_workout_type.replace(/_/g, " ")}
                </span>
                <p className="mt-1 text-xs text-text-secondary">{adj.rationale}</p>
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Focus areas */}
      {report.focus_areas.length > 0 && (
        <div className="flex items-center gap-2">
          <span className="font-mono text-[10px] text-text-tertiary uppercase tracking-wide">Focus:</span>
          {report.focus_areas.map((area, i) => (
            <span key={i} className="rounded-full bg-coral/10 px-3 py-1 font-mono text-[10px] text-coral">
              {area}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

function MetricPill({ label, value, alert }: { label: string; value: string; alert?: string }) {
  return (
    <div className={`rounded-lg px-3 py-2 text-center ${alert ? (alert === "red" ? "bg-red-50" : "bg-amber-50") : "bg-bg-elevated"}`}>
      <div className={`font-mono text-sm font-medium ${alert === "red" ? "text-red-600" : alert === "orange" ? "text-amber-600" : "text-text-primary"}`}>
        {value}
      </div>
      <div className="font-mono text-[8px] text-text-tertiary uppercase tracking-wider mt-0.5">{label}</div>
    </div>
  );
}
