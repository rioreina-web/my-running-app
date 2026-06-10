import { createClient } from "@/lib/supabase/server";
import type { ScheduledWorkout, TrainingPlan } from "@/lib/types";
import { Card } from "@/components/ui/card";
import { MoveDayButton } from "@/components/plan/move-day-button";

// ---------------------------------------------------------------------------
// Athlete's plan view — "This week" shape.
//
// Design source of truth: docs/athlete-plan-ux.md §2A.
// Mockup: docs/athlete-plan-ux-mockup.html.
//
// Phase 1 (this file) renders the new shape using only existing data plus
// the rationale_short column added in migration 20260424100000. Interactive
// verbs (Move, Why?, Reshape) are visual placeholders — they render to show
// where action will live but are disabled until Phase 2.
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

function formatLocalDate(d: Date): string {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
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

export default async function PlanPage() {
  const supabase = await createClient();

  const now = new Date();
  const todayStr = formatLocalDate(now);

  // Current week — Monday through Sunday, Monday-anchored.
  const weekStart = new Date(now);
  weekStart.setDate(now.getDate() - mondayIndex(now));
  const weekEnd = new Date(weekStart);
  weekEnd.setDate(weekStart.getDate() + 6);

  const [planRes, workoutsRes] = await Promise.all([
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
      .gte("scheduled_date", formatLocalDate(weekStart))
      .lte("scheduled_date", formatLocalDate(weekEnd))
      .order("scheduled_date", { ascending: true }),
  ]);

  const plan: TrainingPlan | null = planRes.data;
  const workouts: ScheduledWorkout[] = workoutsRes.data || [];

  // Weekly layout — one entry per day of the current week, Monday-first.
  const weekDays = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(weekStart);
    d.setDate(weekStart.getDate() + i);
    const ds = formatLocalDate(d);
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

  // Week stats — total miles, quality count, rest days
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

  // Next upcoming quality session — powers the "Next quality" forecast line
  const nextQuality = weekDays.find(
    (d) =>
      !d.isPast &&
      d.workout &&
      isQualityType(d.workout.workout_type) &&
      !d.workout.completed,
  );

  // Empty state — athlete has no active plan. Empty-state component
  // pattern per CLAUDE.md: kicker + plain-prose nudge + optional CTA.
  // Voice: coach-first, no AI-speak, peer energy.
  if (!plan) {
    return (
      <div className="mx-auto max-w-3xl py-2">
        <div className="space-y-2 mb-8">
          <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
            Your plan
          </p>
          <h1 className="font-display text-4xl text-text-primary leading-[1.05]">
            Nothing on the schedule yet
          </h1>
        </div>
        <div className="rounded-xl bg-bg-card p-6 space-y-4 shadow-[0_2px_8px_rgba(0,0,0,0.04)]">
          <p className="text-base text-text-primary leading-relaxed">
            The first plan comes from your coach. Invite them in, or set up a
            goal race in the iOS app and we&apos;ll draft the opening weeks.
          </p>
          <div className="flex flex-wrap gap-2 pt-1">
            <a
              href="/coach"
              className="inline-flex items-center rounded-lg bg-coral px-4 py-2 text-sm font-medium text-white hover:bg-coral-dark transition-colors"
            >
              Invite your coach
            </a>
            <a
              href="/settings"
              className="inline-flex items-center rounded-lg border border-divider px-4 py-2 text-sm text-text-secondary hover:text-text-primary hover:border-text-tertiary transition-colors"
            >
              Set a goal race
            </a>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="mx-auto max-w-3xl space-y-7 py-2">
      {/* Plan header — chapter spread for the week. Editorial kicker names
          the plan + position; display title names the chunk of time; the
          subhead carries the date range. Right-side "Next quality" reads
          as a footnote pointing forward. */}
      <div className="flex items-start justify-between gap-6 flex-wrap">
        <div className="min-w-0">
          <p className="font-mono text-[10px] uppercase tracking-[0.18em] text-text-tertiary">
            {plan.name}
            {weekOfPlan ? ` · ${weekOfPlan}` : ""}
          </p>
          <h1 className="mt-1 font-display text-4xl text-text-primary leading-[1.05]">
            This week
          </h1>
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
          weekStartDate={formatLocalDate(weekStart)}
          todayDate={todayStr}
        />
      ) : null}

      {/* Rest of the week — Monday first, today skipped */}
      <div className="space-y-1.5">
        {restOfWeek.map((d) => (
          <DayRow
            key={d.dayIndex}
            day={d}
            weekStartDate={formatLocalDate(weekStart)}
            todayDate={todayStr}
          />
        ))}
      </div>

      {/* Week stats + reshape — editorial summary footer. The total miles
          is the headline number in Playfair; the kicker labels carry it.
          Reshape stays disabled until Phase 3 lands the rationale logic. */}
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
  const isRest = (type || "").toLowerCase() === "rest";

  // Workout-type accent rule — coral for race-pace quality, green for
  // aerobic quality, mood-neutral for everything else. Picks up the same
  // semantic mapping the coach builder uses.
  const accentColor = isRest
    ? "var(--color-text-tertiary)"
    : type === "long_run" || type === "progression"
      ? "var(--color-mood-energized)"
      : isQuality
        ? "var(--color-coral)"
        : "var(--color-mood-positive)";

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
            <span className="ml-auto inline-flex items-center gap-1.5 rounded-full bg-mood-positive/10 px-3 py-1 text-xs font-medium text-mood-positive">
              <span aria-hidden="true">✓</span> Done
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

  // Same accent mapping as TodayBand — keeps the eye trained on what a
  // given color means as it scans down the week.
  const accentColor = isRest
    ? null
    : type === "long_run" || type === "progression"
      ? "var(--color-mood-energized)"
      : isQuality
        ? "var(--color-coral)"
        : "var(--color-mood-positive)";

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
              className="font-mono text-[10px] text-mood-positive"
              aria-label="completed"
            >
              ✓
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
