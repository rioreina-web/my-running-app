"use client";

import { useState } from "react";
import { createBrowserClient } from "@supabase/ssr";

export default function ExportPage() {
  const [loading, setLoading] = useState(false);
  const [dateRange, setDateRange] = useState<"30" | "90" | "365" | "all">(
    "all"
  );

  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  async function exportCSV() {
    setLoading(true);
    try {
      let query = supabase
        .from("training_logs")
        .select(
          "created_at, workout_date, workout_type, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, mood, cleaned_notes, coach_insight"
        )
        .order("workout_date", { ascending: false, nullsFirst: false });

      if (dateRange !== "all") {
        const daysBack = parseInt(dateRange);
        const since = new Date(
          Date.now() - daysBack * 24 * 60 * 60 * 1000
        ).toISOString();
        query = query.gte("created_at", since);
      }

      const { data, error } = await query;
      if (error) throw error;

      if (!data || data.length === 0) {
        alert("No data to export.");
        return;
      }

      // Build CSV
      const headers = [
        "Date",
        "Type",
        "Distance (mi)",
        "Duration (min)",
        "Pace (/mi)",
        "Mood",
        "Notes",
        "Coach Insight",
      ];
      const rows = data.map((log) => [
        log.workout_date || log.created_at,
        log.workout_type || "",
        log.workout_distance_miles?.toString() || "",
        log.workout_duration_minutes?.toString() || "",
        log.workout_pace_per_mile || "",
        log.mood || "",
        csvEscape(log.cleaned_notes || ""),
        csvEscape(log.coach_insight || ""),
      ]);

      const csv = [headers.join(","), ...rows.map((r) => r.join(","))].join(
        "\n"
      );

      // Download
      const blob = new Blob([csv], { type: "text/csv;charset=utf-8;" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `training-logs-${new Date().toISOString().split("T")[0]}.csv`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error("Export failed:", err);
      alert("Export failed. Check console for details.");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        EXPORT
      </h1>

      <p className="text-sm text-text-secondary">
        Download your training data as CSV for analysis in Excel, Google Sheets,
        or any other tool.
      </p>

      {/* Date range selector */}
      <div>
        <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
          DATE RANGE
        </h2>
        <div className="flex gap-2">
          {(
            [
              { key: "30", label: "30 days" },
              { key: "90", label: "90 days" },
              { key: "365", label: "1 year" },
              { key: "all", label: "All time" },
            ] as const
          ).map((opt) => (
            <button
              key={opt.key}
              onClick={() => setDateRange(opt.key)}
              className={`rounded-full px-4 py-1.5 font-mono text-xs transition-colors ${
                dateRange === opt.key
                  ? "bg-coral text-white"
                  : "bg-bg-elevated text-text-secondary hover:text-text-primary"
              }`}
            >
              {opt.label}
            </button>
          ))}
        </div>
      </div>

      {/* Export options */}
      <div>
        <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
          FORMAT
        </h2>
        <div className="space-y-3">
          <button
            onClick={exportCSV}
            disabled={loading}
            className="flex w-full items-center gap-4 rounded-xl border border-bg-elevated bg-bg-card p-4 transition-colors hover:border-coral/30 disabled:opacity-50"
          >
            <span className="text-2xl">📊</span>
            <div className="text-left">
              <div className="font-medium text-text-primary">CSV Export</div>
              <div className="text-xs text-text-tertiary">
                Training logs with dates, distances, paces, moods, and notes
              </div>
            </div>
            <span className="ml-auto font-mono text-xs text-coral">
              {loading ? "Exporting..." : "Download →"}
            </span>
          </button>
        </div>
      </div>

      <div className="rounded-xl border border-bg-elevated bg-bg-card p-4 text-center text-xs text-text-tertiary">
        Excel and PDF exports coming soon.
      </div>
    </div>
  );
}

function csvEscape(s: string): string {
  if (s.includes(",") || s.includes('"') || s.includes("\n")) {
    return `"${s.replace(/"/g, '""')}"`;
  }
  return s;
}
