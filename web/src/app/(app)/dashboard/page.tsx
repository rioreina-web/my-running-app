import { createClient } from "@/lib/supabase/server";
import {
  formatDuration,
  formatDate,
  daysUntil,
  MOOD_CONFIG,
  WORKOUT_TYPE_CONFIG,
} from "@/lib/utils";
import { StatCard } from "@/components/ui/stat-card";
import { Card } from "@/components/ui/card";
import { SectionHeader } from "@/components/ui/section-header";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import {
  NarrativeStat,
  StatValue,
  StatLabel,
  StatAccent,
} from "@/components/ui/narrative-stat";
import { MoodBadge } from "@/components/ui/mood-badge";
import dynamic from "next/dynamic";
import type { TrainingLog, Injury, Goal } from "@/lib/types";

const Sparkline = dynamic(() =>
  import("@/components/charts/sparkline").then((m) => m.Sparkline)
);
const MileageChart = dynamic(() =>
  import("@/components/charts/mileage-chart").then((m) => m.MileageChart)
);
const MoodHeatmap = dynamic(() =>
  import("@/components/charts/mood-heatmap").then((m) => m.MoodHeatmap)
);

export default async function DashboardPage() {
  const supabase = await createClient();

  const now = new Date();
  const nowMs = now.getTime();
  const fourWeeksAgoISO = new Date(
    nowMs - 28 * 24 * 60 * 60 * 1000
  ).toISOString();
  const twoWeeksAgoDate = new Date(nowMs - 14 * 24 * 60 * 60 * 1000);
  const weekAgoDate = new Date(nowMs - 7 * 24 * 60 * 60 * 1000);

  const [logsResult, injuriesResult, goalsResult] = await Promise.all([
    supabase
      .from("training_logs")
      .select(
        "id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes"
      )
      .gte("created_at", fourWeeksAgoISO)
      .order("created_at", { ascending: false }),
    supabase
      .from("injuries")
      .select("id, body_area, side, severity, status, first_reported_at")
      .in("status", ["active", "monitoring"])
      .order("severity", { ascending: false }),
    supabase
      .from("user_goals")
      .select("id, goal_title, target_date, status")
      .eq("status", "active")
      .order("target_date", { ascending: true }),
  ]);

  const logs = (logsResult.data || []) as Pick<
    TrainingLog,
    "id" | "created_at" | "workout_date" | "workout_distance_miles" | "workout_duration_minutes" | "workout_pace_per_mile" | "workout_type" | "mood" | "cleaned_notes" | "notes"
  >[];
  const injuries = (injuriesResult.data || []) as Pick<
    Injury,
    "id" | "body_area" | "side" | "severity" | "status" | "first_reported_at"
  >[];
  const goals = (goalsResult.data || []) as Pick<
    Goal,
    "id" | "goal_title" | "target_date" | "status"
  >[];

  // This week vs previous week
  const weekLogs = logs.filter((l) => {
    const d = new Date(l.workout_date || l.created_at);
    return d >= weekAgoDate;
  });
  const prevWeekLogs = logs.filter((l) => {
    const d = new Date(l.workout_date || l.created_at);
    return d >= twoWeeksAgoDate && d < weekAgoDate;
  });

  const weekMiles = weekLogs.reduce(
    (sum, l) => sum + (l.workout_distance_miles || 0),
    0
  );
  const prevWeekMiles = prevWeekLogs.reduce(
    (sum, l) => sum + (l.workout_distance_miles || 0),
    0
  );
  const weekRuns = weekLogs.filter(
    (l) => l.workout_distance_miles && l.workout_distance_miles > 0
  ).length;
  const avgDist = weekRuns > 0 ? weekMiles / weekRuns : 0;

  // Avg pace
  const weekPaces = weekLogs
    .filter((l) => l.workout_distance_miles && l.workout_duration_minutes)
    .map((l) => l.workout_duration_minutes! / l.workout_distance_miles!);
  const avgPace =
    weekPaces.length > 0
      ? weekPaces.reduce((a, b) => a + b, 0) / weekPaces.length
      : 0;
  const avgPaceFormatted = avgPace
    ? `${Math.floor(avgPace)}:${Math.round((avgPace % 1) * 60)
        .toString()
        .padStart(2, "0")}`
    : "--";

  const prevPaces = prevWeekLogs
    .filter((l) => l.workout_distance_miles && l.workout_duration_minutes)
    .map((l) => l.workout_duration_minutes! / l.workout_distance_miles!);
  const prevAvgPace =
    prevPaces.length > 0
      ? prevPaces.reduce((a, b) => a + b, 0) / prevPaces.length
      : 0;

  // Trends
  const milesTrend: "up" | "down" | "flat" =
    weekMiles > prevWeekMiles * 1.05
      ? "up"
      : weekMiles < prevWeekMiles * 0.95
        ? "down"
        : "flat";
  const paceTrend: "up" | "down" | "flat" =
    avgPace && prevAvgPace
      ? avgPace < prevAvgPace * 0.98
        ? "up"
        : avgPace > prevAvgPace * 1.02
          ? "down"
          : "flat"
      : "flat";

  // Most common mood
  const moodCounts: Record<string, number> = {};
  weekLogs.forEach((l) => {
    if (l.mood) moodCounts[l.mood] = (moodCounts[l.mood] || 0) + 1;
  });
  const topMood =
    Object.entries(moodCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || null;

  // Sparkline: daily mileage for last 7 days
  const dailyMiles: { value: number }[] = [];
  for (let i = 6; i >= 0; i--) {
    const dayStart = new Date();
    dayStart.setHours(0, 0, 0, 0);
    dayStart.setDate(dayStart.getDate() - i);
    const dayEnd = new Date(dayStart);
    dayEnd.setDate(dayEnd.getDate() + 1);
    const dayMiles = logs
      .filter((l) => {
        const d = new Date(l.workout_date || l.created_at);
        return d >= dayStart && d < dayEnd;
      })
      .reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
    dailyMiles.push({ value: dayMiles });
  }

  // Weekly mileage for mini chart (4 weeks)
  const weeklyMileage: { label: string; miles: number }[] = [];
  for (let i = 3; i >= 0; i--) {
    const wStart = new Date(nowMs - (i + 1) * 7 * 24 * 60 * 60 * 1000);
    const wEnd = new Date(nowMs - i * 7 * 24 * 60 * 60 * 1000);
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

  // Mood heatmap data
  const moodData = logs.map((l) => ({
    date: l.workout_date || l.created_at.split("T")[0],
    mood: l.mood,
  }));

  const recentLogs = logs.slice(0, 5);

  const weekStartLabel = weekAgoDate.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });
  const weekEndLabel = now.toLocaleDateString("en-US", {
    month: "short",
    day: "numeric",
  });

  return (
    <div className="mx-auto max-w-5xl space-y-8">
      {/* Header */}
      <div>
        <h1 className="font-display text-3xl text-text-primary">This Week</h1>
        <p className="mt-1 font-body text-sm text-text-tertiary">
          {weekStartLabel} – {weekEndLabel}
        </p>
      </div>

      {/* Narrative lede */}
      {weekRuns > 0 && (
        <NarrativeStat>
          <StatValue>{weekMiles.toFixed(1)}</StatValue>{" "}
          <StatLabel>miles across </StatLabel>
          <StatAccent size="sm">{weekRuns}</StatAccent>{" "}
          <StatLabel>
            run{weekRuns !== 1 ? "s" : ""} — averaging{" "}
          </StatLabel>
          <StatAccent size="sm">{avgDist.toFixed(1)}</StatAccent>{" "}
          <StatLabel>mi at </StatLabel>
          <StatAccent size="sm">{avgPaceFormatted}</StatAccent>
          <StatLabel>/mi.</StatLabel>
        </NarrativeStat>
      )}

      {/* Stats grid */}
      <div className="grid grid-cols-2 gap-4 md:grid-cols-4">
        <StatCard
          value={weekMiles > 0 ? weekMiles.toFixed(1) : "--"}
          label="miles"
          trend={milesTrend}
          sparkline={
            dailyMiles.some((d) => d.value > 0) ? (
              <Sparkline data={dailyMiles} />
            ) : undefined
          }
        />
        <StatCard
          value={weekRuns > 0 ? weekRuns.toString() : "--"}
          label="runs"
        />
        <StatCard
          value={avgPaceFormatted}
          label="per mile"
          trend={paceTrend}
        />
        <StatCard
          value={topMood ? MOOD_CONFIG[topMood]?.emoji || "—" : "—"}
          label={topMood ? MOOD_CONFIG[topMood]?.label || "mood" : "avg mood"}
        />
      </div>

      <EditorialDivider />

      {/* Weekly Mileage Chart */}
      <div>
        <SectionHeader title="Weekly Mileage" />
        <div className="mt-4">
          <MileageChart data={weeklyMileage} height={160} />
        </div>
      </div>

      {/* Mood Heatmap */}
      {moodData.length > 0 && (
        <>
          <EditorialDivider />
          <div>
            <SectionHeader title="Mood" />
            <div className="mt-4">
              <MoodHeatmap data={moodData} weeks={4} />
            </div>
          </div>
        </>
      )}

      {/* Highlights */}
      {(goals.length > 0 || injuries.length > 0) && (
        <>
          <EditorialDivider />
          <div>
            <SectionHeader title="Upcoming" />
            <Card className="mt-4 space-y-3">
              {goals.map((goal) => {
                const days = daysUntil(goal.target_date);
                return (
                  <div
                    key={goal.id}
                    className="flex items-center gap-3 text-sm"
                  >
                    <span className="w-1 h-4 rounded-full bg-coral" />
                    <span className="font-body text-text-primary">
                      {goal.goal_title}
                    </span>
                    <span className="ml-auto font-mono text-xs text-text-tertiary">
                      {days > 0 ? `${days}d` : "Today"}
                    </span>
                    <span className="font-mono text-xs text-text-tertiary">
                      {new Date(goal.target_date).toLocaleDateString("en-US", {
                        month: "short",
                        day: "numeric",
                      })}
                    </span>
                  </div>
                );
              })}
              {injuries.map((injury) => (
                <div
                  key={injury.id}
                  className="flex items-center gap-3 text-sm"
                >
                  <span className="w-1 h-4 rounded-full bg-mood-injured" />
                  <span className="font-body text-text-primary">
                    {injury.side !== "unknown"
                      ? `${capitalize(injury.side)} `
                      : ""}
                    {capitalize(injury.body_area)}
                  </span>
                  <span className="ml-auto font-mono text-xs text-text-tertiary">
                    {injury.severity}/10
                  </span>
                  <MoodBadge
                    mood={injury.status === "active" ? "injured" : "tired"}
                  />
                </div>
              ))}
            </Card>
          </div>
        </>
      )}

      {/* Recent Runs */}
      <EditorialDivider />
      <div>
        <SectionHeader
          title="Recent Runs"
          actionHref="/log"
          actionLabel="View all →"
        />
        <Card className="mt-4" padding="sm">
          {recentLogs.length === 0 ? (
            <div className="p-8 text-center text-sm italic text-text-tertiary">
              No training logs yet. Log a run from the iOS app to see it here.
            </div>
          ) : (
            <div className="divide-y divide-divider">
              {recentLogs.map((log) => (
                <LogRow key={log.id} log={log} />
              ))}
            </div>
          )}
        </Card>
      </div>
    </div>
  );
}

function LogRow({ log }: { log: Pick<TrainingLog, "workout_date" | "created_at" | "workout_type" | "workout_distance_miles" | "workout_pace_per_mile" | "workout_duration_minutes" | "mood"> }) {
  const dateStr = formatDate(log.workout_date || log.created_at);
  const type = log.workout_type || "other";
  const typeConfig = WORKOUT_TYPE_CONFIG[type] || WORKOUT_TYPE_CONFIG.other;
  const distance = log.workout_distance_miles;
  const pace = log.workout_pace_per_mile;
  const duration = log.workout_duration_minutes;

  return (
    <div className="flex items-center gap-4 px-4 py-3 text-sm">
      <span className="w-24 font-mono text-xs text-text-tertiary">
        {dateStr}
      </span>
      <span
        className={`rounded-md px-2 py-0.5 text-xs font-medium ${typeConfig.colorClass}`}
      >
        {typeConfig.label}
      </span>
      <span className="font-mono text-text-primary">
        {distance ? `${distance.toFixed(1)} mi` : "—"}
      </span>
      <span className="font-mono text-text-secondary">{pace || "—"}</span>
      {log.mood && <MoodBadge mood={log.mood} />}
      <span className="ml-auto font-mono text-xs text-text-tertiary">
        {duration ? formatDuration(duration) : ""}
      </span>
    </div>
  );
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
