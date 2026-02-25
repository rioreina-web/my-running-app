import { createClient } from "@/lib/supabase/server";
import { MOOD_CONFIG, WORKOUT_TYPE_CONFIG } from "@/lib/utils";

interface TrainingLog {
  workout_date: string | null;
  created_at: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_type: string | null;
  mood: string | null;
}

export default async function AnalysisPage() {
  const supabase = await createClient();

  const thirtyDaysAgo = new Date(
    Date.now() - 30 * 24 * 60 * 60 * 1000
  ).toISOString();

  const { data } = await supabase
    .from("training_logs")
    .select(
      "workout_date, created_at, workout_distance_miles, workout_duration_minutes, workout_type, mood"
    )
    .gte("created_at", thirtyDaysAgo)
    .order("created_at", { ascending: true });

  const logs: TrainingLog[] = data || [];

  // Stats
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

  // Workout type breakdown
  const typeCounts: Record<string, number> = {};
  logs.forEach((l) => {
    const t = l.workout_type || "other";
    typeCounts[t] = (typeCounts[t] || 0) + 1;
  });

  // Mood breakdown
  const moodCounts: Record<string, number> = {};
  logs.forEach((l) => {
    if (l.mood) moodCounts[l.mood] = (moodCounts[l.mood] || 0) + 1;
  });

  // Weekly mileage (last 4 weeks)
  const weeklyMileage: { label: string; miles: number }[] = [];
  for (let i = 3; i >= 0; i--) {
    const weekStart = new Date(
      Date.now() - (i + 1) * 7 * 24 * 60 * 60 * 1000
    );
    const weekEnd = new Date(Date.now() - i * 7 * 24 * 60 * 60 * 1000);
    const weekLogs = logs.filter((l) => {
      const d = new Date(l.workout_date || l.created_at);
      return d >= weekStart && d < weekEnd;
    });
    const miles = weekLogs.reduce(
      (sum, l) => sum + (l.workout_distance_miles || 0),
      0
    );
    weeklyMileage.push({
      label: weekStart.toLocaleDateString("en-US", {
        month: "short",
        day: "numeric",
      }),
      miles,
    });
  }

  const maxWeekMiles = Math.max(...weeklyMileage.map((w) => w.miles), 1);

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        ANALYSIS
      </h1>

      <p className="font-mono text-xs text-text-tertiary">Last 30 days</p>

      {/* Summary stats */}
      <div className="grid grid-cols-4 gap-4">
        <StatCard value={totalMiles.toFixed(1)} label="total miles" />
        <StatCard value={totalRuns.toString()} label="runs" />
        <StatCard value={avgPaceFormatted} label="avg pace" />
        <StatCard
          value={totalMinutes > 0 ? `${Math.round(totalMinutes / 60)}h` : "--"}
          label="total time"
        />
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        {/* Weekly mileage bar chart */}
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-4">
          <h2 className="mb-4 font-mono text-xs tracking-widest text-text-tertiary">
            WEEKLY MILEAGE
          </h2>
          <div className="flex items-end gap-3 h-32">
            {weeklyMileage.map((week, i) => (
              <div key={i} className="flex flex-1 flex-col items-center gap-1">
                <span className="font-mono text-[10px] text-text-secondary">
                  {week.miles > 0 ? week.miles.toFixed(1) : ""}
                </span>
                <div
                  className="w-full rounded-t bg-coral"
                  style={{
                    height: `${Math.max(
                      (week.miles / maxWeekMiles) * 100,
                      2
                    )}%`,
                  }}
                />
                <span className="font-mono text-[10px] text-text-tertiary">
                  {week.label}
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Workout type breakdown */}
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-4">
          <h2 className="mb-4 font-mono text-xs tracking-widest text-text-tertiary">
            WORKOUT TYPES
          </h2>
          <div className="space-y-2">
            {Object.entries(typeCounts)
              .sort((a, b) => b[1] - a[1])
              .map(([type, count]) => {
                const config =
                  WORKOUT_TYPE_CONFIG[type] || WORKOUT_TYPE_CONFIG.other;
                return (
                  <div key={type} className="flex items-center gap-3">
                    <span
                      className={`w-16 rounded-md px-2 py-0.5 text-center text-xs font-medium ${config.colorClass}`}
                    >
                      {config.label}
                    </span>
                    <div className="flex-1">
                      <div
                        className="h-2 rounded-full bg-coral/60"
                        style={{
                          width: `${
                            (count / Math.max(...Object.values(typeCounts))) *
                            100
                          }%`,
                        }}
                      />
                    </div>
                    <span className="w-6 text-right font-mono text-xs text-text-secondary">
                      {count}
                    </span>
                  </div>
                );
              })}
          </div>
        </div>

        {/* Mood breakdown */}
        <div className="rounded-xl border border-bg-elevated bg-bg-card p-4 md:col-span-2">
          <h2 className="mb-4 font-mono text-xs tracking-widest text-text-tertiary">
            MOOD DISTRIBUTION
          </h2>
          <div className="flex flex-wrap gap-4">
            {Object.entries(moodCounts)
              .sort((a, b) => b[1] - a[1])
              .map(([mood, count]) => {
                const config = MOOD_CONFIG[mood];
                if (!config) return null;
                return (
                  <div
                    key={mood}
                    className="flex items-center gap-2 rounded-lg bg-bg-elevated px-3 py-2"
                  >
                    <span className={config.colorClass}>{config.emoji}</span>
                    <span className="text-sm text-text-secondary">
                      {config.label}
                    </span>
                    <span className="font-mono text-xs text-text-tertiary">
                      {count}
                    </span>
                  </div>
                );
              })}
          </div>
        </div>
      </div>
    </div>
  );
}

function StatCard({ value, label }: { value: string; label: string }) {
  return (
    <div className="rounded-xl border border-bg-elevated bg-bg-card p-4 text-center">
      <div className="font-mono text-2xl font-bold text-text-primary">
        {value}
      </div>
      <div className="mt-1 text-xs text-text-tertiary">{label}</div>
    </div>
  );
}
