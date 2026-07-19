import Link from "next/link";
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
import { EmptyState } from "@/components/ui/empty-state";
import {
  NarrativeStat,
  StatValue,
  StatLabel,
  StatAccent,
} from "@/components/ui/narrative-stat";
import { MoodBadge } from "@/components/ui/mood-badge";
import {
  derivePaceTableFromGoal,
  nearestZoneKey,
  type AthletePaceTable,
  type ZoneMiles,
  type PaceZone,
} from "@/components/coach/workout-helpers";
import { AthleteWeekVolume, type WeekVolume } from "@/components/coach/athlete-week-volume";
import dynamic from "next/dynamic";
import type { TrainingLog, Injury, Goal } from "@/lib/types";
import { dedupeRuns, paceStrToSec } from "@/lib/run-metrics";

const Sparkline = dynamic(() =>
  import("@/components/charts/sparkline").then((m) => m.Sparkline)
);
const MileageChart = dynamic(() =>
  import("@/components/charts/mileage-chart").then((m) => m.MileageChart)
);
const MoodHeatmap = dynamic(() =>
  import("@/components/charts/mood-heatmap").then((m) => m.MoodHeatmap)
);

// Trends — the journey as analytics. The athlete's 5-second view: this
// week's shape, training load (ACWR), niggles, volume by pace zone, mood.
// Mirrors the iOS Trends tab (Log · Trends · Train · Coach IA).
// Run de-dup + pace parsing live in @/lib/run-metrics (shared with Train).

type BodyMention = {
  id: string;
  body_area: string;
  side: string | null;
  verbatim_quote: string;
  severity_hint: string;
  mentioned_at: string;
};

export default async function TrendsPage() {
  const supabase = await createClient();

  const now = new Date();
  const nowMs = now.getTime();
  // 9 weeks of history: 6 weeks of pace-volume bars + the 28-day chronic
  // window ACWR needs behind the earliest acute week.
  const historyStartISO = new Date(
    nowMs - 63 * 24 * 60 * 60 * 1000
  ).toISOString();
  const thirtyDaysAgoISO = new Date(nowMs - 30 * 24 * 60 * 60 * 1000)
    .toISOString()
    .split("T")[0];
  // Monday-start calendar weeks. getDay() is 0=Sun..6=Sat; (getDay()+6)%7 is
  // days since Monday. "This week" = Monday 00:00 → now.
  const weekStart = new Date(now);
  weekStart.setHours(0, 0, 0, 0);
  weekStart.setDate(weekStart.getDate() - ((weekStart.getDay() + 6) % 7));
  const prevWeekStart = new Date(weekStart);
  prevWeekStart.setDate(prevWeekStart.getDate() - 7);

  const [logsResult, injuriesResult, goalsResult, paceProfileResult, nigglesResult] =
    await Promise.all([
      supabase
        .from("training_logs")
        .select(
          "id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes, source"
        )
        .gte("created_at", historyStartISO)
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
      supabase
        .from("athlete_pace_profiles")
        .select("marathon_pace_seconds, goal_race_distance, goal_time_seconds, generated_at")
        .order("generated_at", { ascending: false })
        .limit(1)
        .maybeSingle(),
      supabase
        .from("body_mentions")
        .select("id, body_area, side, verbatim_quote, severity_hint, mentioned_at")
        .gte("mentioned_at", thirtyDaysAgoISO)
        .order("mentioned_at", { ascending: false }),
    ]);

  const logs = (logsResult.data || []) as Pick<
    TrainingLog,
    "id" | "created_at" | "workout_date" | "workout_distance_miles" | "workout_duration_minutes" | "workout_pace_per_mile" | "workout_type" | "mood" | "cleaned_notes" | "notes" | "source"
  >[];
  const injuries = (injuriesResult.data || []) as Pick<
    Injury,
    "id" | "body_area" | "side" | "severity" | "status" | "first_reported_at"
  >[];
  const goals = (goalsResult.data || []) as Pick<
    Goal,
    "id" | "goal_title" | "target_date" | "status"
  >[];
  const niggles = (nigglesResult.data || []) as BodyMention[];

  // Athlete pace table — anchors the volume-by-pace zone bucketing. MP from
  // the pace profile wins; goal time is the fallback. No anchor → no zone
  // chart (never bucket against a reference runner's paces).
  const paceProfile = paceProfileResult.data as {
    marathon_pace_seconds: number | null;
    goal_race_distance: string | null;
    goal_time_seconds: number | null;
  } | null;
  let athletePaces: AthletePaceTable | null = null;
  if (paceProfile?.marathon_pace_seconds && paceProfile.marathon_pace_seconds > 0) {
    athletePaces = derivePaceTableFromGoal(paceProfile.marathon_pace_seconds, "marathon");
  } else if (
    paceProfile?.goal_time_seconds &&
    paceProfile.goal_race_distance
  ) {
    const RACE_MILES: Record<string, number> = {
      marathon: 26.2188,
      half_marathon: 13.1094,
      "10k": 6.2137,
      "5k": 3.1069,
      mile: 1,
    };
    const mi = RACE_MILES[paceProfile.goal_race_distance];
    if (mi) {
      athletePaces = derivePaceTableFromGoal(
        paceProfile.goal_time_seconds / mi,
        paceProfile.goal_race_distance
      );
    }
  }

  // This week vs previous week (Monday-start calendar weeks)
  const weekLogs = logs.filter((l) => {
    const d = new Date(l.workout_date || l.created_at);
    return d >= weekStart;
  });
  const prevWeekLogs = logs.filter((l) => {
    const d = new Date(l.workout_date || l.created_at);
    return d >= prevWeekStart && d < weekStart;
  });

  const weekRunLogs = dedupeRuns(weekLogs);
  const prevWeekRunLogs = dedupeRuns(prevWeekLogs);

  const weekMiles = weekRunLogs.reduce(
    (sum, l) => sum + (l.workout_distance_miles || 0),
    0
  );
  const prevWeekMiles = prevWeekRunLogs.reduce(
    (sum, l) => sum + (l.workout_distance_miles || 0),
    0
  );
  const weekRuns = weekRunLogs.length;
  const avgDist = weekRuns > 0 ? weekMiles / weekRuns : 0;

  // Avg pace
  const weekPaces = weekRunLogs
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

  const prevPaces = prevWeekRunLogs
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

  // ACWR — acute (trailing 7d miles) over chronic (trailing 28d weekly avg).
  // A load-ratio observation, not a prescription: the label states the zone,
  // never a directive (AI advises, never acts).
  const dedupedAll = dedupeRuns(logs);
  const milesInWindow = (days: number) => {
    const start = nowMs - days * 24 * 60 * 60 * 1000;
    return dedupedAll
      .filter((l) => new Date(l.workout_date || l.created_at).getTime() >= start)
      .reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
  };
  const acute7 = milesInWindow(7);
  const chronicWeekly = milesInWindow(28) / 4;
  const acwr = chronicWeekly >= 5 ? acute7 / chronicWeekly : null;
  const acwrLabel =
    acwr == null
      ? "acwr · needs 4 wks"
      : acwr > 1.5
        ? "acwr · high"
        : acwr > 1.3
          ? "acwr · elevated"
          : acwr < 0.8
            ? "acwr · light"
            : "acwr · in range";

  // Sparkline: daily mileage for last 7 days
  const dailyMiles: { value: number }[] = [];
  for (let i = 6; i >= 0; i--) {
    const dayStart = new Date();
    dayStart.setHours(0, 0, 0, 0);
    dayStart.setDate(dayStart.getDate() - i);
    const dayEnd = new Date(dayStart);
    dayEnd.setDate(dayEnd.getDate() + 1);
    const dayMiles = dedupeRuns(
      logs.filter((l) => {
        const d = new Date(l.workout_date || l.created_at);
        return d >= dayStart && d < dayEnd;
      })
    ).reduce((sum, l) => sum + (l.workout_distance_miles || 0), 0);
    dailyMiles.push({ value: dayMiles });
  }

  // Weekly mileage chart (6 Monday-aligned weeks; last bar = this week so far)
  const weeklyMileage: { label: string; miles: number }[] = [];
  for (let i = 5; i >= 0; i--) {
    const wStart = new Date(weekStart);
    wStart.setDate(wStart.getDate() - i * 7);
    const wEnd = new Date(wStart);
    wEnd.setDate(wEnd.getDate() + 7);
    const wLogs = dedupeRuns(
      logs.filter((l) => {
        const d = new Date(l.workout_date || l.created_at);
        return d >= wStart && d < wEnd;
      })
    );
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

  // Volume by pace zone — last 6 weeks, one stacked bar per day. Each run's
  // actual pace lands in its nearest zone on the athlete's table. Runs
  // without a usable pace sit at the aerobic base (easy).
  const DAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const paceWeeks: WeekVolume[] = [];
  if (athletePaces) {
    for (let i = 5; i >= 0; i--) {
      const wStart = new Date(weekStart);
      wStart.setDate(wStart.getDate() - i * 7);
      const days = DAY_LABELS.map((label, dayIdx) => {
        const dStart = new Date(wStart);
        dStart.setDate(dStart.getDate() + dayIdx);
        const dEnd = new Date(dStart);
        dEnd.setDate(dEnd.getDate() + 1);
        const dayRuns = dedupeRuns(
          logs.filter((l) => {
            const d = new Date(l.workout_date || l.created_at);
            return d >= dStart && d < dEnd;
          })
        );
        const zoneMiles: ZoneMiles = {};
        for (const run of dayRuns) {
          const miles = run.workout_distance_miles || 0;
          if (miles <= 0) continue;
          const paceSec =
            paceStrToSec(run.workout_pace_per_mile) ??
            (run.workout_duration_minutes && run.workout_distance_miles
              ? (run.workout_duration_minutes * 60) / run.workout_distance_miles
              : null);
          const zone: PaceZone = paceSec
            ? nearestZoneKey(paceSec, athletePaces)
            : "easy";
          zoneMiles[zone] = (zoneMiles[zone] ?? 0) + miles;
        }
        return { label, zoneMiles };
      });
      paceWeeks.push({
        weekNumber: 6 - i,
        label: wStart.toLocaleDateString("en-US", { month: "short", day: "numeric" }),
        days,
      });
    }
  }

  // Niggles — group the last 30 days of body mentions by area. Surface,
  // never interpret: counts, the athlete's words, no assessment.
  const niggleGroups = new Map<
    string,
    { count: number; latest: BodyMention }
  >();
  for (const n of niggles) {
    const key = n.side && n.side !== "unknown" ? `${n.side} ${n.body_area}` : n.body_area;
    const g = niggleGroups.get(key);
    if (g) g.count += 1;
    else niggleGroups.set(key, { count: 1, latest: n });
  }
  const niggleList = [...niggleGroups.entries()].slice(0, 4);

  // Mood heatmap data
  const moodData = logs.map((l) => ({
    date: l.workout_date || l.created_at.split("T")[0],
    mood: l.mood,
  }));

  // Recent workouts — last 14 days, up to 10 rows
  const fourteenDaysAgo = nowMs - 14 * 24 * 60 * 60 * 1000;
  const recentLogs = logs
    .filter((l) => new Date(l.workout_date || l.created_at).getTime() >= fourteenDaysAgo)
    .slice(0, 10);

  const weekStartLabel = weekStart.toLocaleDateString("en-US", {
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
        <h1 className="font-display text-3xl text-text-primary">Trends</h1>
        <p className="mt-1 font-body text-sm text-text-tertiary">
          This week · {weekStartLabel} – {weekEndLabel}
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

      {/* Stats grid — the 5-second view */}
      <div className="grid grid-cols-2 gap-4 md:grid-cols-3">
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
          value={acwr != null ? acwr.toFixed(2) : "--"}
          label={acwrLabel}
        />
        <StatCard
          value={niggles.length > 0 ? niggles.length.toString() : "0"}
          label="niggles · 30 days"
        />
        <StatCard
          value={topMood ? MOOD_CONFIG[topMood]?.label || "—" : "—"}
          label={topMood ? "top mood" : "avg mood"}
        />
      </div>

      <EditorialDivider />

      {/* Volume */}
      <div>
        <SectionHeader title="Volume" />
        <div className="mt-4">
          <MileageChart data={weeklyMileage} height={160} />
        </div>
        <div className="mt-6">
          {athletePaces && paceWeeks.length > 0 ? (
            <AthleteWeekVolume weeks={paceWeeks} initialWeekNumber={6} />
          ) : (
            <EmptyState
              variant="data-pending"
              eyebrow="Volume by pace"
              title="Set a goal race and time to see your daily volume split by pace zone."
              cta={{ label: "Open pace chart", href: "/pace-chart" }}
            />
          )}
        </div>
      </div>

      {/* Niggles */}
      <EditorialDivider />
      <div>
        <SectionHeader
          title="Niggles"
          actionHref="/injuries"
          actionLabel="View all →"
        />
        {niggleList.length === 0 ? (
          <EmptyState
            variant="optional-empty"
            title="No body mentions in the last 30 days."
            className="mt-2"
          />
        ) : (
          <Card className="mt-4 space-y-4" padding="md">
            {niggleList.map(([area, g]) => (
              <div key={area} className="flex items-baseline gap-3">
                <span className="font-mono text-[10px] tracking-widest uppercase text-coral-dark shrink-0">
                  {area} ×{g.count}
                </span>
                <span className="font-mono text-[10px] uppercase tracking-wider text-text-tertiary shrink-0">
                  {g.latest.severity_hint} ·{" "}
                  {new Date(g.latest.mentioned_at + "T00:00:00").toLocaleDateString("en-US", {
                    month: "short",
                    day: "numeric",
                  })}
                </span>
                <span className="font-body text-sm italic text-text-secondary truncate">
                  &ldquo;{g.latest.verbatim_quote}&rdquo;
                </span>
              </div>
            ))}
          </Card>
        )}
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

      {/* Upcoming */}
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

      {/* Recent Workouts */}
      <EditorialDivider />
      <div>
        <SectionHeader
          title="Recent Workouts"
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

      <p className="font-body text-xs text-text-tertiary">
        Looking for your plan?{" "}
        <Link href="/train" className="text-coral hover:text-coral-dark">
          It lives in Train now →
        </Link>
      </p>
    </div>
  );
}

function LogRow({
  log,
}: {
  log: Pick<
    TrainingLog,
    | "workout_date"
    | "created_at"
    | "workout_type"
    | "workout_distance_miles"
    | "workout_pace_per_mile"
    | "workout_duration_minutes"
    | "mood"
    | "cleaned_notes"
    | "notes"
  >;
}) {
  const dateStr = formatDate(log.workout_date || log.created_at);
  const type = log.workout_type || "other";
  const typeConfig = WORKOUT_TYPE_CONFIG[type] || WORKOUT_TYPE_CONFIG.other;
  const distance = log.workout_distance_miles;
  const pace = log.workout_pace_per_mile;
  const duration = log.workout_duration_minutes;
  const note = log.cleaned_notes || log.notes;

  return (
    <div className="px-4 py-3 text-sm">
      <div className="flex items-center gap-4">
        <span className="w-24 font-mono text-xs text-text-tertiary">
          {dateStr}
        </span>
        <span
          className={`rounded-md px-2 py-0.5 text-xs font-medium ${typeConfig.colorClass}`}
        >
          {typeConfig.label}
        </span>
        <span className="font-mono text-text-primary">
          {distance ? `${distance.toFixed(1)} mi` : ""}
        </span>
        <span className="font-mono text-text-secondary">{pace || ""}</span>
        {log.mood && <MoodBadge mood={log.mood} />}
        <span className="ml-auto font-mono text-xs text-text-tertiary">
          {duration ? formatDuration(duration) : ""}
        </span>
      </div>
      {note && (
        <p className="mt-1.5 pl-28 font-body text-xs italic leading-relaxed text-text-tertiary line-clamp-1">
          &ldquo;{note}&rdquo;
        </p>
      )}
    </div>
  );
}

function capitalize(s: string): string {
  return s.charAt(0).toUpperCase() + s.slice(1);
}
