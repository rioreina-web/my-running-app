import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { CoachPortalNav } from "@/components/coach/coach-portal-nav";
import { CoachNoteComposer } from "@/components/coach/coach-note-composer";
import {
  CoachableMomentCard,
  type CoachableMomentRow,
} from "@/components/coach/coachable-moment-card";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { MoodBadge } from "@/components/ui/mood-badge";
import {
  NarrativeStat,
  StatValue,
  StatAccent,
  StatLabel,
} from "@/components/ui/narrative-stat";

// Athlete deep-dive — what the coach actually opens to read.
//
// Five sections on one page:
//   1. Header        — name, plan, week N of M, goal time + race date
//   2. This Week     — 7-day calendar strip (status pills + miles)
//   3. Recent        — last 14 days of training_logs, prescribed-vs-actual
//   4. Training Load — compliance %, ACWR, rolling miles, fitness trend
//   5. Actions       — quick links to adjust, edit goal, send message
//
// All five are read-only for now; action buttons are stubs that will route
// into existing flows (or new ones) once the wiring lands.

// ── Types ─────────────────────────────────────────────────────────────

type WorkoutData = {
  name?: string;
  total_distance_km?: number;
  total_distance_mi?: number;
  target_pace?: string;
};

type ScheduledWorkout = {
  id: string;
  date: string;
  day_of_week: number;
  week_number: number;
  workout_type: string;
  status: "scheduled" | "completed" | "skipped" | "modified";
  workout_data: WorkoutData | null;
  notes: string | null;
  scheduled_hour: number | null;
  completed_workout_id: string | null;
};

type TrainingLog = {
  id: string;
  workout_date: string;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
  workout_pace_per_mile: string | null;
  workout_type: string | null;
  mood: string | null;
  cleaned_notes: string | null;
  notes: string | null;
};

type AthleteState = {
  experience_level: string | null;
  current_phase: string | null;
  week_compliance_pct: number | null;
  weekly_avg_miles: number | null;
  rolling_7d_miles: number | null;
  rolling_28d_miles: number | null;
  hard_sessions_7d: number | null;
  easy_sessions_7d: number | null;
  runs_last_7d: number | null;
  longest_run_14d: number | null;
  last_mood: string | null;
  mood_trend: string | null;
  fitness_trend: string | null;
  fitness_vs_6mo_ago_label: string | null;
  acwr: number | null;
};

// ── Display tables ────────────────────────────────────────────────────

const STATUS_META: Record<string, { label: string; bg: string; fg: string; symbol: string }> = {
  completed: { label: "Done",     bg: "bg-emerald-100", fg: "text-emerald-700", symbol: "✓" },
  scheduled: { label: "Upcoming", bg: "bg-slate-100",   fg: "text-slate-600",   symbol: "○" },
  skipped:   { label: "Skipped",  bg: "bg-rose-100",    fg: "text-rose-700",    symbol: "⊘" },
  modified:  { label: "Modified", bg: "bg-amber-100",   fg: "text-amber-700",   symbol: "✎" },
};

const TYPE_LABEL: Record<string, string> = {
  easy: "Easy",
  recovery: "Recovery",
  tempo: "Tempo",
  intervals: "Intervals",
  long_run: "Long run",
  race: "Race",
  progression: "Progression",
  strides: "Strides",
  rest: "Rest",
};

const MOOD_META: Record<string, { emoji: string; label: string; tone: string }> = {
  great: { emoji: "🔥", label: "Great", tone: "bg-emerald-50 text-emerald-700" },
  good:  { emoji: "🙂", label: "Good",  tone: "bg-emerald-50 text-emerald-700" },
  okay:  { emoji: "😐", label: "Okay",  tone: "bg-slate-50 text-slate-700" },
  tired: { emoji: "😪", label: "Tired", tone: "bg-amber-50 text-amber-700" },
  rough: { emoji: "😣", label: "Rough", tone: "bg-rose-50 text-rose-700" },
};

const DAY_SHORT = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

// ── Page ──────────────────────────────────────────────────────────────

export default async function CoachAthleteDetailPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("id")
    .eq("user_id", user.id)
    .maybeSingle();
  if (!coachProfile) return null;

  // Coach must own at least one active subscription with this athlete to
  // see the page. The roster page uses `athlete_plan_subscriptions` as
  // the source of truth, so the gate here must match — otherwise athletes
  // who appear in the roster (because a subscription exists) 404 on
  // click-through (because no row in the legacy relationships table).
  // The check joins through plan_templates to confirm the coach owns
  // the plan the athlete is subscribed to.
  const { data: gateRow } = await supabase
    .from("athlete_plan_subscriptions")
    .select("id, plan_template:plan_templates!inner(coach_id)")
    .eq("athlete_user_id", id)
    .eq("status", "active")
    .eq("plan_template.coach_id", coachProfile.id)
    .limit(1)
    .maybeSingle();
  if (!gateRow) notFound();

  // Best-effort email lookup. RLS on auth.users typically blocks reads of
  // other users' rows from the standard client, so fall back to a stable
  // "Athlete <prefix>" handle.
  const { data: authRow } = await supabase
    .schema("auth")
    .from("users")
    .select("email")
    .eq("id", id)
    .maybeSingle();
  const email = (authRow as { email?: string | null } | null)?.email ?? null;
  const displayName = email ? email.split("@")[0] : `Athlete ${id.slice(0, 6)}`;

  // Active plan + everything that hangs off it.
  const { data: plan } = await supabase
    .from("training_plans")
    .select(
      "id, name, start_date, end_date, target_race_distance, target_time_seconds, plan_type"
    )
    .eq("user_id", id)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const workouts: ScheduledWorkout[] = plan
    ? (((
        await supabase
          .from("scheduled_workouts")
          .select(
            "id, date, day_of_week, week_number, workout_type, status, workout_data, notes, scheduled_hour, completed_workout_id"
          )
          .eq("plan_id", plan.id)
          .order("date", { ascending: true })
      ).data ?? []) as ScheduledWorkout[])
    : [];

  // Pull 90 days so the volume chart and pace trends have enough history
  // to actually show a shape. Cap at 200 rows — even a high-mileage
  // marathoner won't push past that across 13 weeks.
  const ninetyDaysAgo = new Date();
  ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);
  const logs: TrainingLog[] = (
    (
      await supabase
        .from("training_logs")
        .select(
          "id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes"
        )
        .eq("user_id", id)
        .gte("workout_date", ninetyDaysAgo.toISOString())
        .order("workout_date", { ascending: false })
        .limit(200)
    ).data ?? []
  ) as TrainingLog[];

  const { data: state } = await supabase
    .from("athlete_state")
    .select(
      "experience_level, current_phase, week_compliance_pct, weekly_avg_miles, rolling_7d_miles, rolling_28d_miles, hard_sessions_7d, easy_sessions_7d, runs_last_7d, longest_run_14d, last_mood, mood_trend, fitness_trend, fitness_vs_6mo_ago_label, acwr"
    )
    .eq("user_id", id)
    .maybeSingle();
  const athleteState = state as AthleteState | null;

  // Open coachable_moments — the lifecycle-tracked attention surface.
  // RLS already gates on coach ownership; ordering by severity-first puts
  // "high" above same-day "low" so Take-Action triage isn't strictly
  // chronological. Spec: docs/specs/coachable_moment.md.
  const { data: openMoments } = await supabase
    .from("coachable_moments")
    .select("id, athlete_user_id, rule_id, severity, action_type, summary, source_log_ids, triggered_at")
    .eq("athlete_user_id", id)
    .eq("status", "open")
    .order("triggered_at", { ascending: false });
  const moments = ((openMoments ?? []) as CoachableMomentRow[]).slice().sort((a, b) => {
    const order: Record<CoachableMomentRow["severity"], number> = { high: 0, med: 1, low: 2 };
    return order[a.severity] - order[b.severity];
  });

  // Compute the Monday-anchored week containing today.
  const today = new Date();
  const todayDow = today.getDay(); // 0=Sun..6=Sat
  const daysBackToMonday = (todayDow + 6) % 7;
  const thisMonday = new Date(today);
  thisMonday.setDate(thisMonday.getDate() - daysBackToMonday);
  thisMonday.setHours(0, 0, 0, 0);
  const nextMonday = new Date(thisMonday);
  nextMonday.setDate(nextMonday.getDate() + 7);

  const thisWeekWorkouts = workouts.filter((w) => {
    const d = new Date(w.date);
    return d >= thisMonday && d < nextMonday;
  });

  // For "Recent workouts," join logs back to their scheduled_workouts via
  // completed_workout_id so the row can show prescribed-vs-actual.
  const scheduledByLogId = new Map<string, ScheduledWorkout>();
  for (const w of workouts) {
    if (w.completed_workout_id) scheduledByLogId.set(w.completed_workout_id, w);
  }

  // Plan progress (week N of M) — derived from start_date + duration.
  const planStart = plan ? new Date(plan.start_date) : null;
  const planEnd = plan ? new Date(plan.end_date) : null;
  const totalWeeks =
    planStart && planEnd
      ? Math.max(1, Math.round((planEnd.getTime() - planStart.getTime()) / (7 * 86400000)) + 1)
      : 0;
  const currentWeekNumber =
    planStart
      ? Math.max(1, Math.floor((today.getTime() - planStart.getTime()) / (7 * 86400000)) + 1)
      : 0;

  // ── Derived analytics for the new coach-facing sections ─────────────

  // Weekly volume buckets, oldest first, 12 weeks long. Each bucket holds
  // total miles + a rough quality count (any tempo/intervals/long_run).
  const weeklyVolumes: Array<{ weekStart: Date; miles: number; quality: number }> = [];
  for (let i = 11; i >= 0; i--) {
    const start = new Date(thisMonday);
    start.setDate(start.getDate() - i * 7);
    weeklyVolumes.push({ weekStart: start, miles: 0, quality: 0 });
  }
  for (const log of logs) {
    const d = new Date(log.workout_date);
    for (const bucket of weeklyVolumes) {
      const end = new Date(bucket.weekStart);
      end.setDate(end.getDate() + 7);
      if (d >= bucket.weekStart && d < end) {
        bucket.miles += log.workout_distance_miles ?? 0;
        if (log.workout_type && /tempo|interval|long_run|progression|race/i.test(log.workout_type)) {
          bucket.quality += 1;
        }
        break;
      }
    }
  }

  // Notes scan for injury / pain keywords. Coaches need to see "she
  // mentioned her hamstring twice this week" without scrolling logs.
  const INJURY_PATTERNS =
    /\b(pain|sore|sorenes+|hurt|injur(y|ed|ies)|tweak|tight|cramp|strain|achilles|hamstring|quad|calf|shin(s)?|knee|hip|IT band|plantar|foot|ankle|back|glute)\b/i;
  const injuryMentions = logs
    .map((log) => {
      const text = (log.cleaned_notes ?? log.notes ?? "").trim();
      if (!text) return null;
      const match = text.match(INJURY_PATTERNS);
      if (!match) return null;
      return {
        id: log.id,
        date: new Date(log.workout_date),
        match: match[0],
        excerpt: text.length > 160 ? `${text.slice(0, 160)}…` : text,
      };
    })
    .filter((x): x is NonNullable<typeof x> => x !== null);

  // Reverse-lookup: log id → matched keyword. Lets each WorkoutLogEntry
  // surface "🩹 sore quad" inline, so the coach scanning the log doesn't
  // have to cross-reference the separate Injury Mentions section.
  const injuryByLogId = new Map<string, string>(
    injuryMentions.map((m) => [m.id, m.match])
  );

  // Mood + notes stream for the new "What they're saying" section.
  // Most recent first; cap at 8 so the card stays scannable.
  const moodTimeline = logs
    .filter((log) => log.mood || (log.cleaned_notes ?? log.notes))
    .slice(0, 8)
    .map((log) => ({
      id: log.id,
      date: new Date(log.workout_date),
      mood: log.mood,
      type: log.workout_type,
      miles: log.workout_distance_miles,
      note: (log.cleaned_notes ?? log.notes ?? "").trim() || null,
    }));

  // Watch list — auto-derived signals the coach should react to TODAY.
  // Each entry is a tone + headline + optional detail. Prioritized by
  // severity (red → amber → emerald).
  const watchSignals: Array<{
    tone: "alert" | "warn" | "ok";
    icon: string;
    headline: string;
    detail?: string;
  }> = [];

  // 1. Injury mentions in last 14 days
  const recentInjuries = injuryMentions.filter(
    (m) => m.date.getTime() > Date.now() - 14 * 86400000
  );
  if (recentInjuries.length > 0) {
    const lastWord = recentInjuries[0].match.toLowerCase();
    watchSignals.push({
      tone: "alert",
      icon: "🩹",
      headline: `${recentInjuries.length} injury mention${recentInjuries.length === 1 ? "" : "s"} in 14 days`,
      detail: `Most recent: "${lastWord}"`,
    });
  }

  // 2. ACWR out of safe range
  if (athleteState?.acwr != null) {
    if (athleteState.acwr > 1.5) {
      watchSignals.push({
        tone: "alert",
        icon: "📈",
        headline: `ACWR ${athleteState.acwr.toFixed(2)} — overreaching risk`,
        detail: "Acute load >1.5× chronic. Consider a down week.",
      });
    } else if (athleteState.acwr < 0.7) {
      watchSignals.push({
        tone: "warn",
        icon: "📉",
        headline: `ACWR ${athleteState.acwr.toFixed(2)} — undertraining`,
        detail: "Athlete is well below their chronic load.",
      });
    }
  }

  // 3. Compliance trending down
  if (
    athleteState?.week_compliance_pct != null &&
    athleteState.week_compliance_pct < 60
  ) {
    watchSignals.push({
      tone: "warn",
      icon: "⚠️",
      headline: `Compliance ${Math.round(athleteState.week_compliance_pct)}% this week`,
      detail: "More than 2 sessions skipped or modified.",
    });
  }

  // 4. Mood trend negative
  if (athleteState?.mood_trend && /declin|worsen|down|drop/i.test(athleteState.mood_trend)) {
    watchSignals.push({
      tone: "warn",
      icon: "😪",
      headline: `Mood trending ${athleteState.mood_trend}`,
      detail: athleteState.last_mood ? `Last logged: ${athleteState.last_mood}` : undefined,
    });
  }

  // 5. Volume jump — this week vs prior week
  const thisWeekVol = weeklyVolumes[weeklyVolumes.length - 1]?.miles ?? 0;
  const lastWeekVol = weeklyVolumes[weeklyVolumes.length - 2]?.miles ?? 0;
  if (lastWeekVol > 5 && thisWeekVol > lastWeekVol * 1.3) {
    watchSignals.push({
      tone: "warn",
      icon: "🚀",
      headline: `+${(((thisWeekVol - lastWeekVol) / lastWeekVol) * 100).toFixed(0)}% volume vs last week`,
      detail: `${thisWeekVol.toFixed(0)} mi vs ${lastWeekVol.toFixed(0)} mi prior.`,
    });
  }

  // 6. All-clear when nothing else fired — keeps the section from looking
  // empty for healthy athletes.
  if (watchSignals.length === 0) {
    watchSignals.push({
      tone: "ok",
      icon: "✓",
      headline: "Nothing flagged",
      detail: "Athlete is on track across compliance, load, and mood.",
    });
  }

  // Roll-up stats for the narrative lede.
  const totalMiles = logs.reduce((s, l) => s + (l.workout_distance_miles ?? 0), 0);
  const totalRuns = logs.filter((l) => (l.workout_distance_miles ?? 0) > 0).length;
  const moodCounts: Record<string, number> = {};
  for (const l of logs) {
    if (l.mood) moodCounts[l.mood] = (moodCounts[l.mood] ?? 0) + 1;
  }
  const dominantMood =
    Object.entries(moodCounts).sort((a, b) => b[1] - a[1])[0]?.[0] ?? null;

  return (
    <div className="mx-auto max-w-3xl px-4 py-8 space-y-10">
      <CoachPortalNav />

      <Link
        href="/coach-portal/athletes"
        className="inline-block text-xs text-text-tertiary hover:text-coral transition-colors"
      >
        ← Back to roster
      </Link>

      {/* ── Coachable moments ──────────────────────────────────────────
          Top-of-page so the coach lands on attention work first. Renders
          0–N cards; severity-sorted so high-priority items don't sit
          below older low-priority ones. */}
      {moments.length > 0 && (
        <section className="space-y-3">
          <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
            Needs your read
          </p>
          {moments.map((m) => (
            <CoachableMomentCard key={m.id} moment={m} />
          ))}
        </section>
      )}

      {/* ── Header ─────────────────────────────────────────────────── */}
      <header className="space-y-3">
        <div>
          <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
            Athlete
          </p>
          <h1 className="mt-1 font-display text-[44px] leading-[1.05] text-text-primary">
            {displayName}
          </h1>
        </div>
        <p className="font-body text-sm text-text-secondary">
          {plan ? (
            <>
              {plan.name} · Week {Math.min(currentWeekNumber, totalWeeks)} of {totalWeeks}
              {plan.target_time_seconds ? (
                <>
                  {" · Goal "}
                  <span className="text-text-primary">
                    {formatHms(plan.target_time_seconds)} {raceLabel(plan.target_race_distance)}
                  </span>
                </>
              ) : null}
              {planEnd ? (
                <span className="text-text-tertiary"> · race in {weeksOut(planEnd)} weeks</span>
              ) : null}
            </>
          ) : (
            <>No active plan</>
          )}
        </p>
      </header>

      <EditorialDivider />

      {/* ── Narrative lede ─────────────────────────────────────────── */}
      {totalRuns > 0 ? (
        <NarrativeStat>
          <StatValue>{totalMiles.toFixed(0)}</StatValue>{" "}
          <StatLabel>miles across </StatLabel>
          <StatAccent size="sm">{totalRuns}</StatAccent>{" "}
          <StatLabel>runs in 90 days. Most days felt </StatLabel>
          <StatAccent size="sm">{dominantMood ?? "—"}</StatAccent>
          <StatLabel>
            {injuryMentions.length > 0
              ? `, with ${injuryMentions.length} note${injuryMentions.length === 1 ? "" : "s"} mentioning pain or soreness.`
              : "."}
          </StatLabel>
        </NarrativeStat>
      ) : (
        <p className="font-body text-base text-text-tertiary leading-relaxed">
          No logged runs in the last 90 days.
        </p>
      )}

      {/* ── Watch list — only when something's actually flagged ───── */}
      {watchSignals.some((s) => s.tone !== "ok") && (
        <>
          <EditorialDivider />
          <section>
            <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
              What to know
            </p>
            <div className="mt-4 space-y-2">
              {watchSignals
                .filter((s) => s.tone !== "ok")
                .map((s, i) => (
                  <WatchSignalRow key={i} signal={s} />
                ))}
            </div>
          </section>
        </>
      )}

      {/* ── Mood at a glance ───────────────────────────────────────── */}
      <EditorialDivider />
      <section>
        <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
          Mood
        </p>
        <MoodSummary
          dominantMood={dominantMood}
          counts={moodCounts}
          totalLogged={logs.filter((l) => l.mood).length}
        />
      </section>

      {/* ── Injury mentions ────────────────────────────────────────── */}
      {injuryMentions.length > 0 && (
        <>
          <EditorialDivider />
          <section>
            <div className="flex items-baseline justify-between">
              <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
                Injury mentions
              </p>
              <p className="font-body text-[11px] text-text-tertiary">
                {injuryMentions.length} in 90 days
              </p>
            </div>
            <div className="mt-4 space-y-4">
              {injuryMentions.slice(0, 5).map((m) => (
                <InjuryRow key={m.id} mention={m} />
              ))}
            </div>
          </section>
        </>
      )}

      {/* ── Volume ─────────────────────────────────────────────────── */}
      <EditorialDivider />
      <section>
        <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
          Weekly volume
        </p>
        <VolumeChart weekly={weeklyVolumes} />
      </section>

      {/* ── Workout log ────────────────────────────────────────────── */}
      <EditorialDivider />
      <section>
        <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
          Workout log
        </p>
        {logs.length === 0 ? (
          <p className="mt-4 font-body text-sm text-text-tertiary">
            No logged workouts in the last 90 days.
          </p>
        ) : (
          <div className="mt-6 space-y-2">
            {logs.slice(0, 14).map((log) => (
              <WorkoutLogEntry
                key={log.id}
                log={log}
                scheduled={scheduledByLogId.get(log.id)}
                athleteId={id}
                injuryMatch={injuryByLogId.get(log.id)}
              />
            ))}
          </div>
        )}
      </section>

      {/* ── Coach note composer ────────────────────────────────────── */}
      <EditorialDivider />
      <CoachNoteComposer
        athleteUserId={id}
        coachId={coachProfile.id}
        athleteFirstName={displayName.split(" ")[0]}
      />
    </div>
  );
}

// ── Subcomponents ─────────────────────────────────────────────────────

// Single workout entry in the editorial log. Each block:
//   1. Date in a left rail (whisper)
//   2. Type · distance · pace as the headline (numbers sing)
//   3. Splits (if prescribed steps exist) as a sub-line
//   4. Mood badge + injury pill (when flagged) inline with the headline
//   5. Note as a generously-leaded italic blockquote
//
// The whole entry is wrapped in a Link so the coach can drill into the
// individual workout. When a note matched an injury keyword, the
// blockquote rule shifts from coral/40 to rose-300 — the visual cue
// matches the separate "Injury mentions" section so a coach scanning
// the log can immediately see WHICH workout triggered each flag.
function WorkoutLogEntry({
  log,
  scheduled,
  athleteId,
  injuryMatch,
}: {
  log: TrainingLog;
  scheduled?: ScheduledWorkout;
  athleteId: string;
  injuryMatch?: string;
}) {
  const date = new Date(log.workout_date);
  const prescribedPace = scheduled?.workout_data?.target_pace ?? null;
  const actualPace = log.workout_pace_per_mile ?? null;
  const typeKey = scheduled?.workout_type ?? log.workout_type ?? null;
  const typeLabel = typeKey ? TYPE_LABEL[typeKey] ?? typeKey : "Workout";
  const note = log.cleaned_notes ?? log.notes ?? null;
  const distance = log.workout_distance_miles;
  const duration = log.workout_duration_minutes;
  const stepsRaw = (scheduled?.workout_data as Record<string, unknown> | null)?.["steps"];
  const splits = parseSplits(stepsRaw);

  return (
    <Link
      href={`/coach-portal/athletes/${athleteId}/workouts/${log.id}`}
      className="block -mx-3 px-3 py-3 rounded-md transition-colors hover:bg-[var(--color-bg-elevated,rgba(0,0,0,0.02))]"
    >
      <article className="grid grid-cols-[80px_1fr] gap-6">
        {/* Left rail — date in editorial caption style */}
        <div className="text-right">
          <div className="font-display text-2xl text-text-primary leading-none">
            {date.getDate()}
          </div>
          <div className="mt-1 font-body text-[10px] tracking-[1.2px] uppercase text-text-tertiary">
            {date.toLocaleDateString("en-US", { month: "short", weekday: "short" })}
          </div>
        </div>

        {/* Right column — headline + body */}
        <div className="min-w-0">
          <div className="flex items-baseline gap-3 flex-wrap">
            <span className="font-display text-xl text-text-primary">
              {typeLabel}
            </span>
            {distance != null && (
              <span className="font-display text-xl text-coral tabular-nums">
                {distance.toFixed(1)}
                <span className="font-body text-sm text-text-tertiary"> mi</span>
              </span>
            )}
            {actualPace && (
              <span className="font-body text-sm text-text-secondary tabular-nums">
                {actualPace}/mi
              </span>
            )}
            {duration != null && (
              <span className="font-body text-sm text-text-tertiary tabular-nums">
                {formatDuration(duration)}
              </span>
            )}
            {log.mood && <MoodBadge mood={log.mood} />}
            {injuryMatch && (
              <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-semibold text-rose-700 bg-rose-100">
                <span>🩹</span>
                <span className="lowercase">{injuryMatch}</span>
              </span>
            )}
          </div>

          {/* Coach-prescribed line — only when there's a target to compare to */}
          {prescribedPace && (
            <p className="mt-1 font-body text-xs text-text-tertiary tabular-nums">
              Coach prescribed{" "}
              <span className="text-text-secondary">{prescribedPace}/mi</span>
              {actualPace && (
                <>
                  {" · ran "}
                  <span className={paceColor(prescribedPace, actualPace)}>
                    {paceDeltaLabel(prescribedPace, actualPace)}
                  </span>
                </>
              )}
            </p>
          )}

          {/* Splits — when the prescribed plan gave us a structured workout */}
          {splits.length > 0 && (
            <div className="mt-3 grid grid-cols-1 sm:grid-cols-2 gap-x-6 gap-y-1">
              {splits.map((s, i) => (
                <div
                  key={i}
                  className="flex items-baseline justify-between font-body text-xs"
                >
                  <span className="text-text-secondary truncate pr-2">
                    {s.label}
                  </span>
                  <span className="text-text-primary tabular-nums">{s.value}</span>
                </div>
              ))}
            </div>
          )}

          {/* Athlete's note — italic, generously leaded, drop-quote feel.
              Rule shifts to rose when an injury keyword matched. */}
          {note && (
            <blockquote
              className={`mt-3 pl-4 border-l-2 font-body text-[15px] leading-7 text-text-primary/85 italic ${
                injuryMatch ? "border-rose-300" : "border-coral/40"
              }`}
            >
              {note}
            </blockquote>
          )}
        </div>
      </article>
    </Link>
  );
}

// Mood at-a-glance — dominant mood as a big number, distribution as small pills
function MoodSummary({
  dominantMood,
  counts,
  totalLogged,
}: {
  dominantMood: string | null;
  counts: Record<string, number>;
  totalLogged: number;
}) {
  if (!dominantMood || totalLogged === 0) {
    return (
      <p className="mt-4 font-body text-sm text-text-tertiary">
        No mood entries logged.
      </p>
    );
  }
  const sorted = Object.entries(counts).sort((a, b) => b[1] - a[1]);
  return (
    <div className="mt-4">
      <div className="flex items-baseline gap-3 flex-wrap">
        <MoodBadge mood={dominantMood} />
        <span className="font-body text-sm text-text-secondary">
          most-logged mood across {totalLogged} entries.
        </span>
      </div>
      <div className="mt-4 flex flex-wrap gap-2">
        {sorted.map(([mood, count]) => (
          <div
            key={mood}
            className="flex items-center gap-1.5 font-body text-xs text-text-secondary"
          >
            <MoodBadge mood={mood} />
            <span className="tabular-nums">×{count}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── Helpers ───────────────────────────────────────────────────────────

function formatHms(seconds: number): string {
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  const s = seconds % 60;
  if (h > 0) return `${h}:${m.toString().padStart(2, "0")}:${s.toString().padStart(2, "0")}`;
  return `${m}:${s.toString().padStart(2, "0")}`;
}

function raceLabel(distance: string): string {
  switch (distance) {
    case "5k": return "5K";
    case "10k": return "10K";
    case "half_marathon": return "Half";
    case "marathon": return "Marathon";
    case "mile": return "Mile";
    default: return distance;
  }
}

function formatDateLong(d: Date): string {
  return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
}

function formatDateShort(d: Date): string {
  return d.toLocaleDateString("en-US", { weekday: "short", month: "short", day: "numeric" });
}

function weekRangeLabel(start: Date, end: Date): string {
  const endInclusive = new Date(end);
  endInclusive.setDate(endInclusive.getDate() - 1);
  const startStr = start.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  const endStr = endInclusive.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  return `${startStr} – ${endStr}`;
}

function weeksOut(end: Date): number {
  const ms = end.getTime() - Date.now();
  return Math.max(0, Math.round(ms / (7 * 86400000)));
}

function sameDay(a: Date, b: Date): boolean {
  return (
    a.getFullYear() === b.getFullYear() &&
    a.getMonth() === b.getMonth() &&
    a.getDate() === b.getDate()
  );
}

function workoutMiles(
  workout: ScheduledWorkout | undefined,
  log: TrainingLog | undefined
): number | null {
  if (log?.workout_distance_miles != null) return log.workout_distance_miles;
  const data = workout?.workout_data;
  if (!data) return null;
  if (typeof data.total_distance_mi === "number") return data.total_distance_mi;
  if (typeof data.total_distance_km === "number") return data.total_distance_km / 1.609344;
  return null;
}

function acwrHint(acwr: number | null | undefined): string | undefined {
  if (acwr == null) return undefined;
  if (acwr < 0.8) return "undertraining";
  if (acwr <= 1.3) return "balanced";
  if (acwr <= 1.5) return "high load";
  return "spike risk";
}

/// Compare prescribed M:SS vs actual M:SS pace (per mile). Within 5
/// seconds either way is "on target," slower is amber, much slower is
/// rose. Faster than prescribed is emerald — over-delivery for now;
/// future versions can tag "ran too fast for an easy day."
function paceColor(prescribed: string | null, actual: string | null): string {
  if (!prescribed || !actual) return "text-[var(--color-text-primary)]";
  const p = paceToSeconds(prescribed);
  const a = paceToSeconds(actual);
  if (p == null || a == null) return "text-[var(--color-text-primary)]";
  const delta = a - p;
  if (delta <= -3) return "text-emerald-700";
  if (Math.abs(delta) <= 5) return "text-emerald-700";
  if (delta <= 15) return "text-amber-700";
  return "text-rose-700";
}

function paceToSeconds(s: string): number | null {
  const parts = s.split(":").map((x) => parseInt(x, 10));
  if (parts.length === 2 && parts.every((x) => !Number.isNaN(x))) {
    return parts[0] * 60 + parts[1];
  }
  return null;
}

// ── Watch-list signals ────────────────────────────────────────────────

function WatchSignalRow({
  signal,
}: {
  signal: { tone: "alert" | "warn" | "ok"; icon: string; headline: string; detail?: string };
}) {
  // Editorial signal — left coral rule for alerts, amber for warns. No
  // boxy backgrounds, just a thin colored rule and headline that sings.
  const ruleColor =
    signal.tone === "alert"
      ? "border-rose-400"
      : signal.tone === "warn"
        ? "border-amber-400"
        : "border-emerald-400";
  return (
    <div className={`pl-4 border-l-2 ${ruleColor}`}>
      <div className="flex items-baseline gap-2">
        <span className="text-base leading-none">{signal.icon}</span>
        <span className="font-display text-base text-text-primary">
          {signal.headline}
        </span>
      </div>
      {signal.detail && (
        <p className="mt-1 font-body text-xs text-text-secondary leading-relaxed">
          {signal.detail}
        </p>
      )}
    </div>
  );
}

// ── Volume bar chart ──────────────────────────────────────────────────

function VolumeChart({
  weekly,
}: {
  weekly: Array<{ weekStart: Date; miles: number; quality: number }>;
}) {
  const max = Math.max(1, ...weekly.map((w) => w.miles));
  const total = weekly.reduce((s, w) => s + w.miles, 0);
  const avg = total / Math.max(1, weekly.filter((w) => w.miles > 0).length);
  return (
    <div className="mt-4">
      <div className="flex items-end justify-between gap-1.5 h-32">
        {weekly.map((bucket, i) => {
          const isCurrent = i === weekly.length - 1;
          const heightPct = bucket.miles === 0 ? 4 : Math.max(8, (bucket.miles / max) * 100);
          return (
            <div
              key={i}
              className="flex-1 flex flex-col items-center justify-end gap-1"
              title={`${bucket.miles.toFixed(1)} mi · ${bucket.quality} quality session${
                bucket.quality === 1 ? "" : "s"
              }`}
            >
              <div
                className={`w-full rounded-t-sm relative ${
                  isCurrent ? "bg-[var(--color-coral)]" : "bg-[var(--color-coral)]/35"
                }`}
                style={{ height: `${heightPct}%` }}
              >
                {/* Quality marker — small dot at the top per quality session */}
                {bucket.quality > 0 && bucket.miles > 0 && (
                  <div className="absolute -top-1.5 left-1/2 -translate-x-1/2 flex gap-0.5">
                    {Array.from({ length: Math.min(3, bucket.quality) }).map((_, k) => (
                      <span
                        key={k}
                        className="w-1.5 h-1.5 rounded-full bg-[var(--color-text-primary)]"
                      />
                    ))}
                  </div>
                )}
              </div>
              <div className="text-[9px] text-[var(--color-text-tertiary)] tabular-nums">
                {bucket.weekStart.getMonth() + 1}/{bucket.weekStart.getDate()}
              </div>
            </div>
          );
        })}
      </div>
      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-1 text-xs text-[var(--color-text-secondary)]">
        <span>
          12-week total{" "}
          <span className="text-[var(--color-text-primary)] font-medium">
            {total.toFixed(0)} mi
          </span>
        </span>
        <span>
          weekly avg{" "}
          <span className="text-[var(--color-text-primary)] font-medium">
            {avg.toFixed(1)} mi
          </span>
        </span>
        <span>
          this week{" "}
          <span className="text-[var(--color-text-primary)] font-medium">
            {(weekly[weekly.length - 1]?.miles ?? 0).toFixed(1)} mi
          </span>
        </span>
        <span className="ml-auto flex items-center gap-1.5 text-[10px] text-[var(--color-text-tertiary)]">
          <span className="w-1.5 h-1.5 rounded-full bg-[var(--color-text-primary)]" />
          <span>quality session</span>
        </span>
      </div>
    </div>
  );
}

// ── Injury watch row ─────────────────────────────────────────────────

function InjuryRow({
  mention,
}: {
  mention: { id: string; date: Date; match: string; excerpt: string };
}) {
  // Editorial injury entry — left coral rule, date as label, blockquote
  // for the excerpt. No card chrome — just the paragraph.
  return (
    <div className="pl-4 border-l-2 border-rose-300">
      <div className="flex items-baseline justify-between gap-2">
        <span className="font-body text-[11px] tracking-[1.5px] uppercase text-rose-700">
          {mention.date.toLocaleDateString("en-US", { month: "short", day: "numeric" })}
          {" — "}
          {mention.match.toLowerCase()}
        </span>
      </div>
      <p className="mt-1 font-body text-[15px] leading-7 text-text-primary/85 italic">
        {mention.excerpt}
      </p>
    </div>
  );
}

// ── Workout-log helpers ─────────────────────────────────────────────

/// Decode the prescribed step array (whatever shape the plan stored
/// into workout_data.steps) into a clean list of "label · value" rows.
/// Returns [] when the field is missing or unrecognized.
function parseSplits(raw: unknown): Array<{ label: string; value: string }> {
  if (!Array.isArray(raw)) return [];
  const out: Array<{ label: string; value: string }> = [];
  for (const step of raw as Array<Record<string, unknown>>) {
    const stepType = String(step.stepType ?? step.step_type ?? "active");
    const repeats = typeof step.repeats === "number" && step.repeats > 1 ? step.repeats : null;
    const dur = step.durationValue ?? step.duration_value;
    const durType = String(step.durationType ?? step.duration_type ?? "");
    const valueParts: string[] = [];
    if (repeats) valueParts.push(`${repeats}×`);
    if (typeof dur === "number") {
      if (durType.includes("mile")) valueParts.push(`${dur} mi`);
      else if (durType.includes("meter")) valueParts.push(`${dur} m`);
      else if (durType.includes("km")) valueParts.push(`${dur} km`);
      else if (durType.includes("time") || durType.includes("second")) {
        valueParts.push(formatDuration(dur / 60));
      } else {
        valueParts.push(`${dur}`);
      }
    }
    const ref = step.paceReference ?? step.pace_reference;
    if (typeof ref === "string") valueParts.push(`@ ${ref}`);
    const labelKey = stepType === "warmup" ? "Warm-up"
      : stepType === "cooldown" ? "Cool-down"
      : stepType === "rest" || stepType === "recovery" ? "Recovery"
      : "Active";
    const label = (step.notes as string | undefined) ?? labelKey;
    out.push({ label, value: valueParts.join(" ") || "—" });
  }
  return out;
}

/// "1h 12m" / "47m" / "8m 32s" depending on magnitude.
function formatDuration(minutes: number | null | undefined): string {
  if (minutes == null || minutes <= 0) return "—";
  if (minutes < 1) {
    return `${Math.round(minutes * 60)}s`;
  }
  if (minutes < 60) {
    const m = Math.floor(minutes);
    const s = Math.round((minutes - m) * 60);
    return s > 0 ? `${m}m ${s}s` : `${m}m`;
  }
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes - h * 60);
  return m > 0 ? `${h}h ${m}m` : `${h}h`;
}

/// "+8s/mi" / "−3s/mi" / "0s/mi". Returns the actual pace string when
/// either side fails to parse so the caller can fall back gracefully.
function paceDeltaLabel(prescribed: string, actual: string): string {
  const p = paceToSeconds(prescribed);
  const a = paceToSeconds(actual);
  if (p == null || a == null) return actual;
  const delta = a - p;
  if (Math.abs(delta) < 1) return `on target`;
  return `${delta > 0 ? "+" : "−"}${Math.abs(Math.round(delta))}s/mi`;
}
