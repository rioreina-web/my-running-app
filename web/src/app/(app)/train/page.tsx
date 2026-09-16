import { createClient } from "@/lib/supabase/server";
import { Check } from "lucide-react";
import type { ScheduledWorkout, TrainingPlan } from "@/lib/types";
import { MoveDayButton } from "@/components/plan/move-day-button";
import { TrainTabs } from "@/components/train/train-tabs";
import {
  TrainCalendar,
  type CalendarEntry,
} from "@/components/train/train-calendar";
import { PaceVolumeDistribution } from "@/components/train/pace-volume-distribution";
import { MileageChart } from "@/components/charts/mileage-chart";
import { StatCard } from "@/components/ui/stat-card";
import { SectionHeader } from "@/components/ui/section-header";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { EmptyState } from "@/components/ui/empty-state";
import {
  derivePaceTableFromGoal,
  nearestZoneKey,
  type AthletePaceTable,
  type ZoneMiles,
  type PaceZone,
} from "@/components/coach/workout-helpers";
import { dedupeRuns, runPaceSec, localDateStr } from "@/lib/run-metrics";

// ---------------------------------------------------------------------------
// Train — the journey as plan and history. Three modes via segmenter,
// mirroring the iOS Train tab (Log · Trends · Train · Coach IA):
//
//   CURRENT  — this week + today ("This week" shape, docs/athlete-plan-ux.md §2A)
//   CALENDAR — month view with past runs + planned workouts layered together
//   HISTORY  — longer-arc analytics: pace × volume distribution, 26-week volume
//
// `activePlan == nil` is a first-class state, not a failure mode: Calendar
// and History render from training_logs regardless; only Current needs a
// plan to have something to say.
//
// Key invariants:
//   - Timezone-safe date parsing (see parseLocalDate). `new Date("YYYY-MM-DD")`
//     gives UTC midnight which renders as the previous day in negative-offset
//     timezones.
//   - Monday-first week indexing. JS's getDay() is Sun=0..Sat=6; we map to
//     Mon=0..Sun=6 so the week grid aligns with how the coach authored it.
// ---------------------------------------------------------------------------

function parseLocalDate(s: string): Date {
  const [y, m, d] = s.split("-").map(Number);
  return new Date(y, m - 1, d);
}

function mondayIndex(date: Date): number {
  return (date.getDay() + 6) % 7;
}

const DAY_LABELS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

// Workout types the athlete can't casually move — require the "Why?" /
// "Move day" quality affordance rather than the generic `⋯` menu.
const QUALITY_TYPES = new Set<string>([
  "tempo",
  "intervals",
  "long_run",
  "race",
  "threshold",
  "hill_repeats",
  "fartlek",
  "progression",
  "time_trial",
]);

function isQualityType(t: string | null | undefined): boolean {
  return !!t && QUALITY_TYPES.has(t.toLowerCase());
}

function formatWorkoutType(t: string | null | undefined): string {
  if (!t) return "Rest";
  return t
    .split("_")
    .map((p) => (p ? p.charAt(0).toUpperCase() + p.slice(1) : ""))
    .join(" ");
}

// Workout-type accent — a stop on the single-hue blue pace ramp (three-
// palette rule: blue = pace; green stays mood-only, coral stays alert-only).
// Rest gets no accent.
function typeAccent(t: string | null | undefined): string | null {
  const s = (t || "").toLowerCase();
  if (!s || s === "rest") return null;
  if (s === "easy" || s === "recovery") return "var(--color-pace-easy)";
  if (s === "long_run" || s === "progression" || s === "medium")
    return "var(--color-pace-moderate)";
  if (s === "tempo" || s === "threshold") return "var(--color-pace-lt)";
  if (s === "intervals" || s === "hill_repeats" || s === "fartlek")
    return "var(--color-pace-5k)";
  if (s === "race" || s === "time_trial") return "var(--color-pace-mile)";
  return "var(--color-pace-easy)";
}

// Fallback for days with no rationale_short backfilled yet. Generic,
// workout-type-based. `generate-day-rationale` (Phase 4) replaces these.
function placeholderRationale(
  type: string | null | undefined,
  isToday: boolean,
): string {
  const t = (type || "").toLowerCase();
  if (t === "tempo" || t === "threshold")
    return "Threshold work — sustained effort to raise your sustainable pace.";
  if (t === "intervals" || t === "hill_repeats" || t === "fartlek")
    return "Sharp reps to build speed. Recovery between is the point.";
  if (t === "long_run")
    return "Longest run of the week. Steady effort, build durability.";
  if (t === "progression")
    return "Start easy, finish strong. Teach the legs to close.";
  if (t === "race" || t === "time_trial")
    return "Race day. Trust the taper.";
  if (t === "recovery")
    return "Recovery pace only — tomorrow needs fresh legs.";
  if (t === "easy")
    return isToday
      ? "Easy miles. Conversational pace — save the work for quality days."
      : "Easy, conversational.";
  if (t === "medium")
    return "Steady aerobic — firmer than easy, softer than tempo.";
  if (t === "rest" || !t) return "Rest day. Let the work consolidate.";
  return "";
}

function formatMonthDay(d: Date): string {
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
}

type TrainingLogLite = {
  id: string;
  created_at: string;
  workout_date: string | null;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  source: string | null;
};

export default async function TrainPage() {
  const supabase = await createClient();

  const now = new Date();
  const nowMs = now.getTime();
  const todayStr = localDateStr(now);

  // Current week — Monday through Sunday, Monday-anchored.
  const weekStart = new Date(now);
  weekStart.setDate(now.getDate() - mondayIndex(now));
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekStart.getDate() + 6);

  // Windows: calendar reaches 12 weeks back / 12 forward; history reads 26
  // weeks of logs.
  const schedFrom = new Date(weekStart);
  schedFrom.setDate(schedFrom.getDate() - 84);
  const schedTo = new Date(weekEnd);
  schedTo.setDate(schedTo.getDate() + 84);
  const logsFromISO = new Date(
    nowMs - 26 * 7 * 24 * 60 * 60 * 1000
  ).toISOString();

  const [planRes, schedRes, logsRes, paceProfileRes] = await Promise.all([
    supabase
      .from("training_plans")
      .select("id, name, start_date, end_date, status")
      .eq("status", "active")
      .limit(1)
      .single(),
    supabase
      .from("scheduled_workouts")
      .select(
        "id, scheduled_date, workout_type, description, target_distance_miles, target_pace, completed, rationale_short",
      )
      .gte("scheduled_date", localDateStr(schedFrom))
      .lte("scheduled_date", localDateStr(schedTo))
      .order("scheduled_date", { ascending: true }),
    supabase
      .from("training_logs")
      .select(
        "id, created_at, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, source",
      )
      .gte("created_at", logsFromISO)
      .order("created_at", { ascending: false }),
    supabase
      .from("athlete_pace_profiles")
      .select("marathon_pace_seconds, goal_race_distance, goal_time_seconds, generated_at")
      .order("generated_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
  ]);

  const plan: TrainingPlan | null = planRes.data;
  const allScheduled: ScheduledWorkout[] = schedRes.data || [];
  const logs = (logsRes.data || []) as TrainingLogLite[];

  // Athlete pace table — anchors zone colors in Calendar and the History
  // distribution. No anchor → neutral dots + an honest nudge, never a
  // reference runner's zones.
  const paceProfile = paceProfileRes.data as {
    marathon_pace_seconds: number | null;
    goal_race_distance: string | null;
    goal_time_seconds: number | null;
  } | null;
  let athletePaces: AthletePaceTable | null = null;
  if (paceProfile?.marathon_pace_seconds && paceProfile.marathon_pace_seconds > 0) {
    athletePaces = derivePaceTableFromGoal(paceProfile.marathon_pace_seconds, "marathon");
  } else if (paceProfile?.goal_time_seconds && paceProfile.goal_race_distance) {
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

  // ── CURRENT — this week ─────────────────────────────────────────────
  const weekStartStr = localDateStr(weekStart);
  const weekEndStr = localDateStr(weekEnd);
  const workouts = allScheduled.filter(
    (w) => w.scheduled_date >= weekStartStr && w.scheduled_date <= weekEndStr,
  );

  const weekDays = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(weekStart);
    d.setDate(weekStart.getDate() + i);
    const ds = localDateStr(d);
    const workout = workouts.find((x) => x.scheduled_date === ds);
    return {
      dayIndex: i,
      date: d,
      dateStr: ds,
      label: DAY_LABELS[i],
      workout,
      isToday: ds === todayStr,
      isPast: ds < todayStr,
    };
  });

  const todayDay = weekDays.find((d) => d.isToday) ?? null;
  const restOfWeek = weekDays.filter((d) => !d.isToday);

  const totalMiles = workouts.reduce(
    (sum, w) => sum + (w.target_distance_miles || 0),
    0,
  );
  const qualityCount = workouts.filter((w) => isQualityType(w.workout_type))
    .length;
  const restCount = weekDays.filter(
    (d) => !d.workout || (d.workout.workout_type || "").toLowerCase() === "rest",
  ).length;

  // Plan progress ("week 9 of 16")
  let weekOfPlan: string | null = null;
  if (plan) {
    const planStart = parseLocalDate(plan.start_date);
    const planEnd = parseLocalDate(plan.end_date);
    const totalWeeks = Math.max(
      1,
      Math.ceil(
        (planEnd.getTime() - planStart.getTime()) / (7 * 24 * 60 * 60 * 1000),
      ),
    );
    const currentWeek = Math.max(
      1,
      Math.ceil(
        (now.getTime() - planStart.getTime()) / (7 * 24 * 60 * 60 * 1000),
      ),
    );
    if (currentWeek >= 1 && currentWeek <= totalWeeks) {
      weekOfPlan = `week ${currentWeek} of ${totalWeeks}`;
    }
  }

  const nextQuality = weekDays.find(
    (d) =>
      !d.isPast &&
      d.workout &&
      isQualityType(d.workout.workout_type) &&
      !d.workout.completed,
  );

  // ── CALENDAR — logged + planned, merged by day ──────────────────────
  const dedupedLogs = dedupeRuns(logs);
  const logsByDate = new Map<
    string,
    { miles: number; bestMiles: number; zone: PaceZone | null }
  >();
  for (const l of dedupedLogs) {
    const ds = localDateStr(new Date(l.workout_date || l.created_at));
    const miles = l.workout_distance_miles || 0;
    if (miles <= 0) continue;
    const paceSec = runPaceSec(l);
    const zone: PaceZone | null = athletePaces
      ? paceSec
        ? nearestZoneKey(paceSec, athletePaces)
        : "easy"
      : null;
    const cur = logsByDate.get(ds);
    if (!cur) {
      logsByDate.set(ds, { miles, bestMiles: miles, zone });
    } else {
      cur.miles += miles;
      if (miles > cur.bestMiles) {
        cur.bestMiles = miles;
        cur.zone = zone;
      }
    }
  }
  const schedByDate = new Map<string, ScheduledWorkout>();
  for (const w of allScheduled) {
    const existing = schedByDate.get(w.scheduled_date);
    // Prefer a non-rest workout when a day somehow has two rows.
    if (!existing || (existing.workout_type || "").toLowerCase() === "rest") {
      schedByDate.set(w.scheduled_date, w);
    }
  }
  const calendarDates = new Set<string>([
    ...logsByDate.keys(),
    ...schedByDate.keys(),
  ]);
  const calendarEntries: CalendarEntry[] = [...calendarDates].sort().map((ds) => {
    const log = logsByDate.get(ds);
    const sched = schedByDate.get(ds);
    return {
      date: ds,
      loggedMiles: log ? Math.round(log.miles * 100) / 100 : 0,
      zone: log?.zone ?? null,
      plannedType: sched?.workout_type ?? null,
      plannedMiles: sched?.target_distance_miles ?? null,
      plannedCompleted: sched?.completed ?? false,
    };
  });

  // ── HISTORY — longer-arc analytics ──────────────────────────────────
  const twelveWeeksAgoMs = nowMs - 12 * 7 * 24 * 60 * 60 * 1000;
  const logs12 = dedupedLogs.filter(
    (l) => new Date(l.workout_date || l.created_at).getTime() >= twelveWeeksAgoMs,
  );
  const miles12 = logs12.reduce((s, l) => s + (l.workout_distance_miles || 0), 0);
  const longest12 = logs12.reduce(
    (m, l) => Math.max(m, l.workout_distance_miles || 0),
    0,
  );
  let zoneMiles12: ZoneMiles | null = null;
  if (athletePaces) {
    zoneMiles12 = {};
    for (const l of logs12) {
      const miles = l.workout_distance_miles || 0;
      if (miles <= 0) continue;
      const paceSec = runPaceSec(l);
      const zone: PaceZone = paceSec
        ? nearestZoneKey(paceSec, athletePaces)
        : "easy";
      zoneMiles12[zone] = (zoneMiles12[zone] ?? 0) + miles;
    }
  }

  // 26 Monday-aligned weeks of volume (last bar = this week so far).
  const weeklyVolume: { label: string; miles: number }[] = [];
  for (let i = 25; i >= 0; i--) {
    const wStart = new Date(weekStart);
    wStart.setDate(wStart.getDate() - i * 7);
    const wEnd = new Date(wStart);
    wEnd.setDate(wEnd.getDate() + 7);
    const miles = dedupedLogs
      .filter((l) => {
        const d = new Date(l.workout_date || l.created_at);
        return d >= wStart && d < wEnd;
      })
      .reduce((s, l) => s + (l.workout_distance_miles || 0), 0);
    weeklyVolume.push({
      label: wStart.toLocaleDateString("en-US", { month: "short", day: "numeric" }),
      miles,
    });
  }

  // ── Panels ──────────────────────────────────────────────────────────

  const currentPanel = plan ? (
    <div className="space-y-7">
      {/* Plan header — chapter spread for the week. */}
      <div className="flex items-start justify-between gap-6 flex-wrap">
        <div className="min-w-0">
          <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
            {plan.name}
            {weekOfPlan ? ` · ${weekOfPlan}` : ""}
          </p>
          <h2 className="mt-1 font-display text-3xl text-text-primary leading-[1.05]">
            This week
          </h2>
          <p className="mt-1.5 font-mono text-xs text-text-secondary tabular-nums">
            {formatMonthDay(weekStart)}&nbsp;–&nbsp;{formatMonthDay(weekEnd)}
          </p>
        </div>
        {nextQuality && nextQuality.workout ? (
          <div className="text-right border-l border-divider pl-5 self-stretch flex flex-col justify-center">
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
              Next quality
            </p>
            <p className="mt-1 font-display text-lg text-text-primary leading-tight">
              {nextQuality.label}&apos;s{" "}
              {formatWorkoutType(nextQuality.workout.workout_type).toLowerCase()}
            </p>
          </div>
        ) : null}
      </div>

      {/* Today pinned — the one card that matters most right now */}
      {todayDay ? (
        <TodayBand
          day={todayDay}
          weekStartDate={weekStartStr}
          todayDate={todayStr}
        />
      ) : null}

      {/* Rest of the week — Monday first, today skipped */}
      <div className="space-y-1.5">
        {restOfWeek.map((d) => (
          <DayRow
            key={d.dayIndex}
            day={d}
            weekStartDate={weekStartStr}
            todayDate={todayStr}
          />
        ))}
      </div>

      {/* Week stats + reshape — editorial summary footer. */}
      <div className="rounded-xl bg-bg-card px-5 py-4 flex items-center justify-between gap-4 shadow-[0_2px_8px_rgba(0,0,0,0.04)]">
        <div className="flex items-baseline gap-5">
          <div>
            <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
              This week
            </p>
            <p className="mt-0.5 leading-none">
              <span className="font-display text-2xl text-text-primary tabular-nums">
                {Math.round(totalMiles)}
              </span>
              <span className="ml-1.5 font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                mi
              </span>
            </p>
          </div>
          <div className="text-xs text-text-secondary leading-relaxed">
            <span className="tabular-nums">{qualityCount}</span>{" "}
            {qualityCount === 1 ? "quality" : "qualities"} ·{" "}
            <span className="tabular-nums">{restCount}</span>{" "}
            {restCount === 1 ? "rest" : "rest days"}
          </div>
        </div>
        <button
          type="button"
          disabled
          aria-disabled="true"
          title="Coming soon — move the long run or pull volume when life shifts"
          className="rounded-lg border border-divider bg-transparent px-3 py-1.5 text-sm text-text-secondary opacity-60 transition hover:bg-bg-elevated disabled:cursor-not-allowed"
        >
          Reshape this week
        </button>
      </div>
    </div>
  ) : (
    <div className="rounded-xl bg-bg-card p-6 space-y-4 shadow-[0_2px_8px_rgba(0,0,0,0.04)]">
      <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
        No active plan
      </p>
      <p className="text-base text-text-primary leading-relaxed">
        Nothing on the schedule this week — your Calendar and History still
        track every run. The first plan comes from your coach, or set up a
        goal race in the iOS app and we&apos;ll draft the opening weeks.
      </p>
      <div className="flex flex-wrap gap-2 pt-1">
        <a
          href="/settings"
          className="inline-flex items-center rounded-lg border border-divider px-4 py-2 text-sm text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors"
        >
          Set a goal race
        </a>
      </div>
    </div>
  );

  const calendarPanel =
    calendarEntries.length > 0 ? (
      <TrainCalendar entries={calendarEntries} today={todayStr} />
    ) : (
      <EmptyState
        variant="data-pending"
        eyebrow="Calendar"
        title="Runs and planned workouts land here as they happen — log a run from the iOS app to start the grid."
      />
    );

  const historyPanel = (
    <div className="space-y-8">
      <div className="grid grid-cols-3 gap-4">
        <StatCard
          value={miles12 > 0 ? miles12.toFixed(0) : "--"}
          label="miles · 12 wks"
        />
        <StatCard
          value={logs12.length > 0 ? logs12.length.toString() : "--"}
          label="runs"
        />
        <StatCard
          value={longest12 > 0 ? longest12.toFixed(1) : "--"}
          label="longest run"
        />
      </div>

      {zoneMiles12 ? (
        <PaceVolumeDistribution zoneMiles={zoneMiles12} windowLabel="12 wks" />
      ) : (
        <EmptyState
          variant="data-pending"
          eyebrow="Pace × volume"
          title="Set a goal race and time to see where your miles land across pace zones."
          cta={{ label: "Open pace chart", href: "/pace-chart" }}
        />
      )}

      <EditorialDivider />

      <div>
        <SectionHeader title="Weekly volume · 26 wks" />
        <div className="mt-4">
          <MileageChart data={weeklyVolume} height={180} />
        </div>
      </div>
    </div>
  );

  return (
    <div className="mx-auto max-w-3xl py-2">
      <div className="mb-5">
        <h1 className="font-display text-4xl text-text-primary leading-[1.05]">
          Train
        </h1>
      </div>
      <TrainTabs
        current={currentPanel}
        calendar={calendarPanel}
        history={historyPanel}
      />
    </div>
  );
}

// --- components -------------------------------------------------------------

interface DayVM {
  dayIndex: number;
  date: Date;
  dateStr: string;
  label: string;
  workout?: ScheduledWorkout;
  isToday: boolean;
  isPast: boolean;
}

function TodayBand({
  day,
  weekStartDate,
  todayDate,
}: {
  day: DayVM;
  weekStartDate: string;
  todayDate: string;
}) {
  const w = day.workout;
  const type = w?.workout_type || "rest";
  const distance = w?.target_distance_miles ?? null;
  const pace = w?.target_pace ?? null;
  const rationale = w?.rationale_short || placeholderRationale(type, true);
  const isQuality = isQualityType(type);

  // Left-edge accent rides the blue pace ramp (rest stays neutral).
  const accentColor = typeAccent(type) ?? "var(--color-text-tertiary)";

  return (
    <div className="relative overflow-hidden rounded-2xl bg-bg-card shadow-[0_2px_12px_rgba(0,0,0,0.06)]">
      {/* Left-edge color rule — at-a-glance read of what kind of day this is */}
      <span
        aria-hidden="true"
        className="absolute left-0 top-0 bottom-0 w-1"
        style={{ backgroundColor: accentColor }}
      />
      <div className="px-6 py-5">
        <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
          Today · {day.label}
        </p>

        <div className="mt-1.5 flex items-baseline justify-between gap-4">
          <h2 className="font-display text-3xl text-text-primary leading-[1.05] tracking-tight">
            {formatWorkoutType(type)}
          </h2>
          {distance != null ? (
            <p className="font-mono text-base text-text-secondary tabular-nums flex-shrink-0">
              <span className="text-text-primary">{distance}</span>{" "}
              <span className="text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
                mi
              </span>
            </p>
          ) : null}
        </div>

        {w && (w.description || pace) ? (
          <p className="mt-3 text-sm text-text-primary leading-relaxed">
            {w.description ? <span>{w.description}</span> : null}
            {w.description && pace ? (
              <span className="text-text-tertiary"> · </span>
            ) : null}
            {pace ? (
              <span className="font-mono tabular-nums">
                {pace}
                {/mi/i.test(pace) ? "" : "/mi"}
              </span>
            ) : null}
          </p>
        ) : null}

        {/* Rationale renders as a coach note — serif italic with left rule,
            visually marked as quoted material rather than UI chrome. */}
        {rationale ? (
          <p className="coach-note text-[15px] mt-4">{rationale}</p>
        ) : null}

        <div className="mt-5 flex flex-wrap items-center gap-2">
          {/* Why? still disabled until Phase 4 lands the rationale drawer. */}
          {isQuality ? (
            <button
              type="button"
              disabled
              aria-disabled="true"
              title="Coming soon — the why behind today's workout"
              className="rounded-lg border border-divider px-3 py-1.5 text-xs text-text-secondary opacity-60 disabled:cursor-not-allowed"
            >
              Why this?
            </button>
          ) : null}
          {w ? (
            <MoveDayButton
              workout={{
                id: w.id,
                scheduled_date: w.scheduled_date,
                workout_type: w.workout_type,
                description: w.description,
                target_distance_miles: w.target_distance_miles,
                target_pace: w.target_pace,
              }}
              weekStartDate={weekStartDate}
              todayDate={todayDate}
              isQuality={isQuality}
              variant="primary"
              label="Move day"
            />
          ) : null}
          {w && w.completed ? (
            <span className="ml-auto inline-flex items-center gap-1.5 rounded-full bg-bg-calendar px-3 py-1 text-xs font-medium text-text-secondary">
              <Check size={13} strokeWidth={2.5} aria-hidden /> Done
            </span>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function DayRow({
  day,
  weekStartDate,
  todayDate,
}: {
  day: DayVM;
  weekStartDate: string;
  todayDate: string;
}) {
  const w = day.workout;
  const type = w?.workout_type || "rest";
  const isRest = (type || "").toLowerCase() === "rest";
  const isQuality = isQualityType(type);
  const rationale = w?.rationale_short || placeholderRationale(type, false);

  // Same pace-ramp accent mapping as TodayBand — the eye learns one code.
  const accentColor = typeAccent(type);

  const rowClasses = [
    "relative overflow-hidden flex items-center gap-3 rounded-lg pr-2 transition-colors",
    isQuality ? "bg-bg-card py-3 pl-4 shadow-[0_1px_4px_rgba(0,0,0,0.04)]" : "py-2.5 pl-3",
    !isQuality && !isRest ? "bg-bg-elevated" : "",
    isRest ? "bg-transparent" : "",
    day.isPast && w?.completed ? "opacity-70" : "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <div className={rowClasses}>
      {/* Color rule — only on actual workouts. Thicker on quality days. */}
      {accentColor ? (
        <span
          aria-hidden="true"
          className={`absolute left-0 top-0 bottom-0 ${
            isQuality ? "w-1" : "w-0.5"
          }`}
          style={{ backgroundColor: accentColor }}
        />
      ) : null}

      <div className="w-10 shrink-0 font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
        {day.label}
      </div>

      <div className="min-w-0 flex-1">
        <div className="flex items-baseline gap-2">
          {isRest ? (
            <span className="text-sm italic text-text-tertiary">Rest</span>
          ) : (
            <span
              className={
                isQuality
                  ? "font-display text-lg text-text-primary leading-tight"
                  : "text-sm text-text-primary"
              }
            >
              {formatWorkoutType(type)}
              {w?.target_distance_miles != null
                ? (
                  <span className="font-mono text-text-tertiary tabular-nums">
                    {" "}
                    · {w.target_distance_miles} mi
                  </span>
                )
                : ""}
            </span>
          )}
          {w?.completed ? (
            <span
              className="inline-flex text-text-tertiary"
              aria-label="completed"
            >
              <Check size={12} strokeWidth={2.5} aria-hidden />
            </span>
          ) : null}
        </div>

        {(w?.description || rationale) && !isRest ? (
          <p className="mt-1 truncate text-[12px] text-text-secondary leading-snug">
            {w?.target_pace ? (
              <span className="font-mono tabular-nums text-text-tertiary">
                @ {w.target_pace}
                {/mi/i.test(w.target_pace) ? "" : "/mi"} ·{" "}
              </span>
            ) : null}
            <span className="italic">{rationale}</span>
          </p>
        ) : null}
      </div>

      {w && !isRest && !day.isPast ? (
        <MoveDayButton
          workout={{
            id: w.id,
            scheduled_date: w.scheduled_date,
            workout_type: w.workout_type,
            description: w.description,
            target_distance_miles: w.target_distance_miles,
            target_pace: w.target_pace,
          }}
          weekStartDate={weekStartDate}
          todayDate={todayDate}
          isQuality={isQuality}
          variant="icon"
        />
      ) : null}
    </div>
  );
}
