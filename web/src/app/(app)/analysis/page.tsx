import { createClient, getUserId } from "@/lib/supabase/server";
import { WORKOUT_TYPE_CONFIG } from "@/lib/utils";
import { Card } from "@/components/ui/card";
import { SectionHeader } from "@/components/ui/section-header";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import {
  NarrativeStat,
  StatValue,
  StatLabel,
  StatAccent,
} from "@/components/ui/narrative-stat";
import dynamic from "next/dynamic";
import type { TrainingLog } from "@/lib/types";
import { WeeklyReportSection } from "./weekly-report-section";

const MileageChart = dynamic(() =>
  import("@/components/charts/mileage-chart").then((m) => m.MileageChart)
);
const PaceTrendChart = dynamic(() =>
  import("@/components/charts/pace-trend-chart").then((m) => m.PaceTrendChart)
);
const WorkoutTypeDonut = dynamic(() =>
  import("@/components/charts/workout-type-donut").then((m) => m.WorkoutTypeDonut)
);
const MoodHeatmap = dynamic(() =>
  import("@/components/charts/mood-heatmap").then((m) => m.MoodHeatmap)
);
const MoodDistributionChart = dynamic(() =>
  import("@/components/charts/mood-distribution-chart").then((m) => m.MoodDistributionChart)
);
const TrainingLoadGauge = dynamic(() =>
  import("@/components/charts/training-load-gauge").then((m) => m.TrainingLoadGauge)
);
const RunFrequencyChart = dynamic(() =>
  import("@/components/charts/run-frequency-chart").then((m) => m.RunFrequencyChart)
);

export default async function AnalysisPage() {
  const supabase = await createClient();

  const ninetyDaysAgo = new Date(
    Date.now() - 90 * 24 * 60 * 60 * 1000
  ).toISOString();

  const userId = await getUserId();
  const { data } = await supabase
    .from("training_logs")
    .select(
      "workout_date, created_at, workout_distance_miles, workout_duration_minutes, workout_type, mood"
    )
    .eq("user_id", userId || "")
    .gte("created_at", ninetyDaysAgo)
    .order("created_at", { ascending: true });

  const logs = (data || []) as Pick<
    TrainingLog,
    "workout_date" | "created_at" | "workout_distance_miles" | "workout_duration_minutes" | "workout_type" | "mood"
  >[];

  // Totals
  const totalMiles = logs.reduce(
    (sum, l) => sum + (l.workout_distance_miles || 0),
    0
  );
  const totalRuns = logs.filter(
    (l) => l.workout_distance_miles && l.workout_distance_miles > 0
  ).length;
  const totalMinutes = logs.reduce(
    (sum, l) => sum + (l.workout_duration_minutes || 0),
    0
  );
  const avgDist = totalRuns > 0 ? totalMiles / totalRuns : 0;

  // Avg pace
  const paceLogs = logs.filter(
    (l) => l.workout_distance_miles && l.workout_duration_minutes
  );
  const avgPace =
    paceLogs.length > 0
      ? paceLogs.reduce(
          (sum, l) =>
            sum + l.workout_duration_minutes! / l.workout_distance_miles!,
          0
        ) / paceLogs.length
      : 0;
  const avgPaceFormatted = avgPace
    ? `${Math.floor(avgPace)}:${Math.round((avgPace % 1) * 60)
        .toString()
        .padStart(2, "0")}`
    : "--";

  // Weekly mileage (12 weeks) → MileageChart
  const weeklyMileage: { label: string; miles: number }[] = [];
  for (let i = 11; i >= 0; i--) {
    const wStart = new Date(Date.now() - (i + 1) * 7 * 24 * 60 * 60 * 1000);
    const wEnd = new Date(Date.now() - i * 7 * 24 * 60 * 60 * 1000);
    const wLogs = logs.filter((l) => {
      const d = new Date(l.workout_date || l.created_at);
      return d >= wStart && d < wEnd;
    });
    weeklyMileage.push({
      label: wStart.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      }),
      miles: wLogs.reduce(
        (sum, l) => sum + (l.workout_distance_miles || 0),
        0
      ),
    });
  }

  // Pace trend → PaceTrendChart
  const paceData = paceLogs.map((l) => {
    const d = new Date(l.workout_date || l.created_at);
    return {
      label: d.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      }),
      pace: l.workout_duration_minutes! / l.workout_distance_miles!,
    };
  });

  // Workout type breakdown → WorkoutTypeDonut
  const typeCounts: Record<string, number> = {};
  logs.forEach((l) => {
    const t = l.workout_type || "other";
    typeCounts[t] = (typeCounts[t] || 0) + 1;
  });
  const workoutTypeData = Object.entries(typeCounts)
    .sort((a, b) => b[1] - a[1])
    .map(([type, count]) => ({
      type,
      count,
      label: (WORKOUT_TYPE_CONFIG[type] || WORKOUT_TYPE_CONFIG.other).label,
    }));

  // Run frequency by day of week → RunFrequencyChart
  const dayOfWeekCounts = [0, 0, 0, 0, 0, 0, 0];
  logs.forEach((l) => {
    if (l.workout_distance_miles && l.workout_distance_miles > 0) {
      const d = new Date(l.workout_date || l.created_at);
      dayOfWeekCounts[d.getDay()]++;
    }
  });
  const DAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const runFrequencyData = DAY_LABELS.map((label, i) => ({
    label,
    runs: dayOfWeekCounts[i],
  }));

  // Mood heatmap → MoodHeatmap
  const moodData = logs.map((l) => ({
    date: l.workout_date || l.created_at.split("T")[0],
    mood: l.mood,
  }));

  // Mood distribution by week → MoodDistributionChart
  const moodWeeklyData: {
    label: string;
    energized: number;
    positive: number;
    neutral: number;
    tired: number;
    struggling: number;
    injured: number;
  }[] = [];
  for (let i = 11; i >= 0; i--) {
    const wStart = new Date(Date.now() - (i + 1) * 7 * 24 * 60 * 60 * 1000);
    const wEnd = new Date(Date.now() - i * 7 * 24 * 60 * 60 * 1000);
    const wLogs = logs.filter((l) => {
      const d = new Date(l.workout_date || l.created_at);
      return d >= wStart && d < wEnd;
    });
    const week = {
      label: wStart.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      }),
      energized: 0,
      positive: 0,
      neutral: 0,
      tired: 0,
      struggling: 0,
      injured: 0,
    };
    wLogs.forEach((l) => {
      if (l.mood && l.mood in week) {
        (week as unknown as Record<string, number>)[l.mood]++;
      }
    });
    moodWeeklyData.push(week);
  }

  // ACWR → TrainingLoadGauge
  const weekAgoDate = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000);
  const acuteMiles = logs
    .filter((l) => new Date(l.workout_date || l.created_at) >= weekAgoDate)
    .reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
  const chronicWeeks = [0, 1, 2, 3].map((i) => {
    const wStart = new Date(Date.now() - (i + 1) * 7 * 24 * 60 * 60 * 1000);
    const wEnd = new Date(Date.now() - i * 7 * 24 * 60 * 60 * 1000);
    return logs
      .filter((l) => {
        const d = new Date(l.workout_date || l.created_at);
        return d >= wStart && d < wEnd;
      })
      .reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
  });
  const chronicAvg = chronicWeeks.reduce((a, b) => a + b, 0) / 4;
  const acwr = chronicAvg > 0 ? acuteMiles / chronicAvg : 1;

  return (
    <div className="mx-auto max-w-5xl space-y-8">
      <div>
        <h1 className="font-display text-3xl text-text-primary">
          Training Analysis
        </h1>
        <p className="mt-1 font-body text-sm text-text-tertiary">
          Last 90 days
        </p>
      </div>

      {/* AI Weekly Coaching Report */}
      <WeeklyReportSection />

      <EditorialDivider />

      {/* Narrative lede */}
      {totalRuns > 0 && (
        <NarrativeStat>
          <StatValue>{totalMiles.toFixed(1)}</StatValue>{" "}
          <StatLabel>miles across </StatLabel>
          <StatAccent size="sm">{totalRuns}</StatAccent>{" "}
          <StatLabel>
            run{totalRuns !== 1 ? "s" : ""} — averaging{" "}
          </StatLabel>
          <StatAccent size="sm">{avgDist.toFixed(1)}</StatAccent>{" "}
          <StatLabel>mi at </StatLabel>
          <StatAccent size="sm">{avgPaceFormatted}</StatAccent>
          <StatLabel>/mi.</StatLabel>
        </NarrativeStat>
      )}

      <EditorialDivider />

      {/* Mileage Chart */}
      <div>
        <SectionHeader title="Weekly Mileage" />
        <Card className="mt-4">
          <MileageChart data={weeklyMileage} height={200} />
        </Card>
      </div>

      <EditorialDivider />

      {/* Pace + Run Frequency */}
      <div className="grid gap-6 md:grid-cols-2">
        <div>
          <SectionHeader title="Pace Trend" />
          <Card className="mt-4">
            <PaceTrendChart data={paceData} height={200} />
          </Card>
        </div>
        <div>
          <SectionHeader title="Run Frequency" />
          <Card className="mt-4">
            <RunFrequencyChart data={runFrequencyData} height={200} />
          </Card>
        </div>
      </div>

      <EditorialDivider />

      {/* Workout Types + Training Load */}
      <div className="grid gap-6 md:grid-cols-2">
        <div>
          <SectionHeader title="Workout Types" />
          <Card className="mt-4">
            <WorkoutTypeDonut data={workoutTypeData} height={200} />
          </Card>
        </div>
        <div>
          <SectionHeader title="Training Load" />
          <Card className="mt-4 flex items-center justify-center">
            <TrainingLoadGauge acwr={acwr} />
          </Card>
        </div>
      </div>

      <EditorialDivider />

      {/* Mood */}
      <div>
        <SectionHeader title="Mood" />
        <div className="mt-4 grid gap-6 md:grid-cols-2">
          <Card>
            <h3 className="mb-3 font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
              Heatmap
            </h3>
            <MoodHeatmap data={moodData} weeks={12} />
          </Card>
          <Card>
            <h3 className="mb-3 font-body text-[11px] font-medium tracking-[1.5px] uppercase text-text-secondary">
              Distribution
            </h3>
            <MoodDistributionChart data={moodWeeklyData} height={180} />
          </Card>
        </div>
      </div>
    </div>
  );
}
