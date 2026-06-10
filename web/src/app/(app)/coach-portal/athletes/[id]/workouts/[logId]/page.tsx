import Link from "next/link";
import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { CoachPortalNav } from "@/components/coach/coach-portal-nav";
import { EditorialDivider } from "@/components/ui/editorial-divider";
import { MoodBadge } from "@/components/ui/mood-badge";

// Coach-side single-workout deep-dive. Reached by clicking a row in
// the athlete's workout log. Currently shows what we have — distance,
// pace, duration, mood, full note. Splits + per-rep data will land here
// once the iOS log captures them.

export default async function CoachWorkoutDetailPage({
  params,
}: {
  params: Promise<{ id: string; logId: string }>;
}) {
  const { id: athleteId, logId } = await params;
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

  // Confirm the coach-athlete relationship (same gate as the athlete page).
  const { data: gateRow } = await supabase
    .from("athlete_plan_subscriptions")
    .select("id, plan_template:plan_templates!inner(coach_id)")
    .eq("athlete_user_id", athleteId)
    .eq("status", "active")
    .eq("plan_template.coach_id", coachProfile.id)
    .limit(1)
    .maybeSingle();
  if (!gateRow) notFound();

  const { data: log } = await supabase
    .from("training_logs")
    .select(
      "id, workout_date, workout_distance_miles, workout_duration_minutes, workout_pace_per_mile, workout_type, mood, cleaned_notes, notes, scheduled_workout_id"
    )
    .eq("id", logId)
    .eq("user_id", athleteId)
    .maybeSingle();
  if (!log) notFound();

  // Pull the prescribed workout if linked.
  type ScheduledLite = {
    id: string;
    date: string;
    workout_type: string;
    workout_data: Record<string, unknown> | null;
    notes: string | null;
  };
  let scheduled: ScheduledLite | null = null;
  if ((log as { scheduled_workout_id?: string }).scheduled_workout_id) {
    const { data } = await supabase
      .from("scheduled_workouts")
      .select("id, date, workout_type, workout_data, notes")
      .eq("id", (log as { scheduled_workout_id: string }).scheduled_workout_id)
      .maybeSingle();
    scheduled = (data as ScheduledLite | null) ?? null;
  }

  const date = new Date((log as { workout_date: string }).workout_date);
  const distance = (log as { workout_distance_miles: number | null }).workout_distance_miles;
  const duration = (log as { workout_duration_minutes: number | null }).workout_duration_minutes;
  const pace = (log as { workout_pace_per_mile: string | null }).workout_pace_per_mile;
  const mood = (log as { mood: string | null }).mood;
  const note =
    (log as { cleaned_notes: string | null; notes: string | null }).cleaned_notes ??
    (log as { notes: string | null }).notes ??
    null;
  const typeKey =
    scheduled?.workout_type ?? (log as { workout_type: string | null }).workout_type ?? null;
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
  const typeLabel = typeKey ? TYPE_LABEL[typeKey] ?? typeKey : "Workout";

  return (
    <div className="mx-auto max-w-3xl px-4 py-8 space-y-10">
      <CoachPortalNav />

      <Link
        href={`/coach-portal/athletes/${athleteId}`}
        className="inline-block text-xs text-text-tertiary hover:text-coral transition-colors"
      >
        ← Back to athlete
      </Link>

      <header className="space-y-3">
        <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
          {date.toLocaleDateString("en-US", {
            weekday: "long",
            month: "long",
            day: "numeric",
            year: "numeric",
          })}
        </p>
        <h1 className="font-display text-[44px] leading-[1.05] text-text-primary">
          {typeLabel}
        </h1>
        <div className="flex items-baseline gap-4 flex-wrap">
          {distance != null && (
            <span className="font-display text-2xl text-coral tabular-nums">
              {distance.toFixed(2)}
              <span className="font-body text-sm text-text-tertiary"> mi</span>
            </span>
          )}
          {pace && (
            <span className="font-display text-2xl text-text-primary tabular-nums">
              {pace}
              <span className="font-body text-sm text-text-tertiary">/mi</span>
            </span>
          )}
          {duration != null && (
            <span className="font-body text-sm text-text-secondary tabular-nums">
              {formatDuration(duration)}
            </span>
          )}
          {mood && <MoodBadge mood={mood} />}
        </div>
      </header>

      {note && (
        <>
          <EditorialDivider />
          <section>
            <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
              Athlete&rsquo;s notes
            </p>
            <blockquote className="mt-4 pl-4 border-l-2 border-coral/40 font-body text-[17px] leading-8 text-text-primary/90 italic">
              {note}
            </blockquote>
          </section>
        </>
      )}

      <EditorialDivider />
      <section>
        <p className="font-body text-[11px] tracking-[1.5px] uppercase text-text-tertiary">
          Splits &amp; intervals
        </p>
        <p className="mt-4 font-body text-sm text-text-tertiary">
          Per-rep splits aren&rsquo;t captured yet on the iOS log. When they
          are, the breakdown lands here — warmup, each interval, recovery,
          cooldown, with prescribed-vs-actual side by side.
        </p>
      </section>
    </div>
  );
}

function formatDuration(minutes: number): string {
  if (minutes <= 0) return "—";
  if (minutes < 60) {
    const m = Math.floor(minutes);
    const s = Math.round((minutes - m) * 60);
    return s > 0 ? `${m}m ${s}s` : `${m}m`;
  }
  const h = Math.floor(minutes / 60);
  const m = Math.round(minutes - h * 60);
  return m > 0 ? `${h}h ${m}m` : `${h}h`;
}
