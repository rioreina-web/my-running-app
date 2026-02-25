import { createClient } from "@/lib/supabase/server";
import {
  formatDuration,
  formatDate,
  daysUntil,
  daysSince,
  MOOD_CONFIG,
  WORKOUT_TYPE_CONFIG,
} from "@/lib/utils";

interface TrainingLog {
  id: string;
  created_at: string;
  workout_date: string | null;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  workout_type: string | null;
  mood: string | null;
  cleaned_notes: string | null;
  notes: string | null;
}

interface Injury {
  id: string;
  body_area: string;
  side: string;
  severity: number;
  status: string;
  first_reported_at: string;
}

interface Goal {
  id: string;
  goal_title: string;
  target_date: string;
  status: string;
}

export default async function DashboardPage() {
  const supabase = await createClient();

  // Fetch data in parallel
  const weekAgo = new Date(
    Date.now() - 7 * 24 * 60 * 60 * 1000
  ).toISOString();

  const [logsResult, injuriesResult, goalsResult] = await Promise.all([
    supabase
      .from("training_logs")
      .select(
        "id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes"
      )
      .order("created_at", { ascending: false })
      .limit(20),
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

  const logs: TrainingLog[] = logsResult.data || [];
  const injuries: Injury[] = injuriesResult.data || [];
  const goals: Goal[] = goalsResult.data || [];

  // Calculate weekly stats
  const weekLogs = logs.filter((log) => {
    const logDate = log.workout_date || log.created_at;
    return new Date(logDate) >= new Date(weekAgo);
  });

  const weekMiles = weekLogs.reduce(
    (sum, log) => sum + (log.workout_distance_miles || 0),
    0
  );
  const weekRuns = weekLogs.filter(
    (log) => log.workout_distance_miles && log.workout_distance_miles > 0
  ).length;

  const weekPaces = weekLogs
    .filter((log) => log.workout_distance_miles && log.workout_duration_minutes)
    .map(
      (log) => log.workout_duration_minutes! / log.workout_distance_miles!
    );
  const avgPaceMinPerMile =
    weekPaces.length > 0
      ? weekPaces.reduce((a, b) => a + b, 0) / weekPaces.length
      : 0;
  const avgPaceFormatted = avgPaceMinPerMile
    ? `${Math.floor(avgPaceMinPerMile)}:${Math.round((avgPaceMinPerMile % 1) * 60)
        .toString()
        .padStart(2, "0")}`
    : "--";

  // Most common mood
  const moodCounts: Record<string, number> = {};
  weekLogs.forEach((log) => {
    if (log.mood) moodCounts[log.mood] = (moodCounts[log.mood] || 0) + 1;
  });
  const topMood =
    Object.entries(moodCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || null;

  const recentLogs = logs.slice(0, 5);

  return (
    <div className="mx-auto max-w-5xl space-y-6">
      {/* Header */}
      <h1 className="font-display text-3xl tracking-wider text-text-primary">
        DASHBOARD
      </h1>

      {/* Weekly stats */}
      <div>
        <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
          THIS WEEK
        </h2>
        <div className="grid grid-cols-4 gap-4">
          <StatCard
            value={weekMiles > 0 ? weekMiles.toFixed(1) : "--"}
            label="miles"
          />
          <StatCard value={weekRuns > 0 ? weekRuns.toString() : "--"} label="runs" />
          <StatCard value={avgPaceFormatted} label="/mile" />
          <StatCard
            value={topMood ? MOOD_CONFIG[topMood]?.emoji || "—" : "—"}
            label={topMood ? MOOD_CONFIG[topMood]?.label || "mood" : "avg mood"}
          />
        </div>
      </div>

      {/* Highlights */}
      {(goals.length > 0 || injuries.length > 0) && (
        <div>
          <h2 className="mb-3 font-mono text-xs tracking-widest text-text-tertiary">
            HIGHLIGHTS
          </h2>
          <div className="rounded-xl border border-bg-elevated bg-bg-card p-4 space-y-3">
            {goals.map((goal) => {
              const days = daysUntil(goal.target_date);
              return (
                <div key={goal.id} className="flex items-center gap-3 text-sm">
                  <span className="text-coral">🏁</span>
                  <span className="font-medium text-text-primary">Race</span>
                  <span className="text-text-secondary">{goal.goal_title}</span>
                  <span className="ml-auto font-mono text-xs text-text-tertiary">
                    {days > 0 ? `${days} days` : "Today"}
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
              <div key={injury.id} className="flex items-center gap-3 text-sm">
                <span className="text-mood-injured">🩹</span>
                <span className="font-medium text-text-primary">Injury</span>
                <span className="text-text-secondary">
                  {injury.side !== "unknown" ? `${capitalize(injury.side)} ` : ""}
                  {capitalize(injury.body_area)}
                </span>
                <span className="ml-auto font-mono text-xs text-text-tertiary">
                  {injury.severity}/10
                </span>
                <span className="font-mono text-xs text-mood-injured">
                  {capitalize(injury.status)}
                </span>
              </div>
            ))}
            {weekRuns > 0 && (
              <div className="flex items-center gap-3 text-sm">
                <span className="text-mood-energized">📈</span>
                <span className="font-medium text-text-primary">Streak</span>
                <span className="text-text-secondary">
                  {weekRuns} run{weekRuns !== 1 ? "s" : ""} this week
                </span>
              </div>
            )}
          </div>
        </div>
      )}

      {/* Recent logs */}
      <div>
        <div className="mb-3 flex items-center justify-between">
          <h2 className="font-mono text-xs tracking-widest text-text-tertiary">
            RECENT LOGS
          </h2>
          <a
            href="/log"
            className="font-mono text-xs text-coral hover:text-coral-light"
          >
            View all →
          </a>
        </div>
        <div className="rounded-xl border border-bg-elevated bg-bg-card">
          {recentLogs.length === 0 ? (
            <div className="p-8 text-center text-sm text-text-tertiary">
              No training logs yet. Log a run from the iOS app to see it here.
            </div>
          ) : (
            <div className="divide-y divide-bg-elevated">
              {recentLogs.map((log) => (
                <LogRow key={log.id} log={log} />
              ))}
            </div>
          )}
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

function LogRow({ log }: { log: TrainingLog }) {
  const dateStr = formatDate(log.workout_date || log.created_at);
  const type = log.workout_type || "other";
  const typeConfig = WORKOUT_TYPE_CONFIG[type] || WORKOUT_TYPE_CONFIG.other;
  const mood = log.mood ? MOOD_CONFIG[log.mood] : null;
  const distance = log.workout_distance_miles;
  const duration = log.workout_duration_minutes;
  const pace = log.workout_pace_per_mile;

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
      <span className="font-mono text-text-secondary">
        {pace || "—"}
      </span>
      {mood && (
        <span className={mood.colorClass} title={mood.label}>
          {mood.emoji}
        </span>
      )}
      <span className="ml-auto font-mono text-xs text-text-tertiary">
        {duration ? formatDuration(duration) : ""}
      </span>
    </div>
  );
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
