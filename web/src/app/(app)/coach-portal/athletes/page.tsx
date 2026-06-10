import { createClient } from "@/lib/supabase/server";
import { SectionHeader } from "@/components/ui/section-header";
import { Card } from "@/components/ui/card";
import { CoachPortalNav } from "@/components/coach/coach-portal-nav";
import { CoachSetupPrompt } from "@/components/coach/coach-setup-prompt";
import { AthleteRosterCard, type RosterAthlete } from "@/components/coach/athlete-roster-card";

// Daily-scan dashboard for the coach: card grid of subscribed athletes
// with mileage trend, pace adherence, and wellness flags.
//
// Signals on each card:
//   - Mileage trend ← training_logs (last 6 weeks, weekly buckets)
//   - Pace adherence ← workout_reconciliations.adjusted_pace_delta_seconds
//                      rolled up over the last 7 days, quality workouts only
//   - Wellness flags ← athlete_state (mood, ACWR, injury risk)

export default async function CoachAthletesPage() {
  const supabase = await createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: coachProfile } = await supabase
    .from("coach_profiles")
    .select("*")
    .eq("user_id", user.id)
    .maybeSingle();

  if (!coachProfile) {
    return <CoachSetupPrompt />;
  }

  // Pull every active subscription against any plan this coach owns.
  // The join shape mirrors the SELECT in plans/page.tsx.
  // Schema note: the FK column is athlete_user_id (text), not athlete_id.
  const { data: subs } = await supabase
    .from("athlete_plan_subscriptions")
    .select(`
      id,
      athlete_user_id,
      created_at,
      status,
      plan_template:plan_templates!inner (
        id,
        name,
        coach_id,
        duration_weeks
      )
    `)
    .eq("plan_template.coach_id", coachProfile.id)
    .eq("status", "active")
    .order("created_at", { ascending: false });

  const subscriptions = (subs ?? []) as Array<{
    id: string;
    athlete_user_id: string;
    created_at: string;
    status: string;
    plan_template: { id: string; name: string; coach_id: string; duration_weeks: number };
  }>;

  // Display name resolution: there's no user_profiles table on this DB, so
  // the source of truth is auth.users.email. Server-side render only — the
  // service-role admin API gives us the email; we fall back to the bare
  // user_id when a row isn't found (e.g., synthetic test users).
  const athleteIds = Array.from(new Set(subscriptions.map((s) => s.athlete_user_id)));
  const profilesById = new Map<string, { name: string | null; email: string | null }>();
  if (athleteIds.length > 0) {
    const { data: authRows } = await supabase
      .schema("auth")
      .from("users")
      .select("id, email")
      .in("id", athleteIds);
    for (const row of (authRows ?? []) as Array<{ id: string; email: string | null }>) {
      profilesById.set(row.id, { name: null, email: row.email });
    }
  }

  // Bulk-fetch the last 6 weeks of training_logs miles per athlete to
  // power the sparkline. Schema columns are workout_date (timestamptz)
  // and workout_distance_miles — not date / distance_miles.
  const sixWeeksAgo = new Date();
  sixWeeksAgo.setDate(sixWeeksAgo.getDate() - 7 * 6);
  const { data: logs } = await supabase
    .from("training_logs")
    .select("user_id, workout_date, workout_distance_miles")
    .in("user_id", athleteIds)
    .gte("workout_date", sixWeeksAgo.toISOString())
    .order("workout_date", { ascending: true });

  // Group miles into 6 weekly buckets per athlete (oldest → newest).
  const milesByAthleteByWeek = new Map<string, number[]>();
  for (const id of athleteIds) milesByAthleteByWeek.set(id, [0, 0, 0, 0, 0, 0]);
  for (const row of (logs ?? []) as Array<{ user_id: string; workout_date: string; workout_distance_miles: number | null }>) {
    const d = new Date(row.workout_date);
    const weeksAgo = Math.min(5, Math.max(0, Math.floor((Date.now() - d.getTime()) / (1000 * 60 * 60 * 24 * 7))));
    const bucketIdx = 5 - weeksAgo; // 0 = oldest, 5 = current week
    const bucket = milesByAthleteByWeek.get(row.user_id);
    if (bucket && row.workout_distance_miles != null) bucket[bucketIdx] += row.workout_distance_miles;
  }

  // ── Real signal #1: pace adherence ─────────────────────────────────
  // Pull workout_reconciliations from the last 7 days for each athlete
  // and roll up adjusted_pace_delta_seconds. Heat-adjusted delta is the
  // honest read — an athlete who ran 10s/mi slow in 80°F dew isn't
  // slipping; that's expected. Non-quality reconciliations (no
  // scheduled_workout_id) get filtered out — recovery runs don't have
  // a pace target to miss.
  const sevenDaysAgo = new Date();
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
  const { data: recsRaw } = await supabase
    .from("workout_reconciliations")
    .select("user_id, scheduled_workout_id, adjusted_pace_delta_seconds, hit_target, created_at")
    .in("user_id", athleteIds)
    .gte("created_at", sevenDaysAgo.toISOString());

  const paceByAthlete = new Map<string, RosterAthlete["paceAdherence"]>();
  const recsForAthlete = new Map<string, number[]>();
  for (const r of (recsRaw ?? []) as Array<{
    user_id: string;
    scheduled_workout_id: string | null;
    adjusted_pace_delta_seconds: number | null;
  }>) {
    if (!r.scheduled_workout_id) continue;        // skip unplanned runs
    if (r.adjusted_pace_delta_seconds == null) continue;
    const arr = recsForAthlete.get(r.user_id) ?? [];
    arr.push(Math.abs(Number(r.adjusted_pace_delta_seconds)));
    recsForAthlete.set(r.user_id, arr);
  }
  for (const id of athleteIds) {
    const deltas = recsForAthlete.get(id) ?? [];
    if (deltas.length === 0) {
      paceByAthlete.set(id, "unknown");
      continue;
    }
    const avg = deltas.reduce((a, b) => a + b, 0) / deltas.length;
    paceByAthlete.set(
      id,
      avg <= 5 ? "on_track" : avg <= 15 ? "slipping" : "way_off"
    );
  }

  // ── Real signal #2: wellness flags from athlete_state ──────────────
  // Map athlete_state columns to the WellnessFlag enum the card knows
  // how to render. The card already supports `fatigue` and `soreness`;
  // we extend the surface with `injury_risk` and `overreaching` because
  // those are the highest-signal coaching flags athlete_state actually
  // computes today. hr_drift / sleep stay reserved for when Vital data
  // gets wired in.
  const { data: statesRaw } = await supabase
    .from("athlete_state")
    .select("user_id, last_mood, mood_trend, acwr, injury_risk_score, active_injuries")
    .in("user_id", athleteIds);

  const wellnessByAthlete = new Map<string, RosterAthlete["wellnessFlags"]>();
  for (const s of (statesRaw ?? []) as Array<{
    user_id: string;
    last_mood: string | null;
    mood_trend: string | null;
    acwr: number | null;
    injury_risk_score: number | null;
    active_injuries: unknown;
  }>) {
    const flags: RosterAthlete["wellnessFlags"] = [];

    const m = (s.last_mood ?? "").toLowerCase();
    const mt = (s.mood_trend ?? "").toLowerCase();
    if (m === "tired" || m === "struggling" || mt.includes("declin")) {
      flags.push("fatigue");
    }

    const activeInjuries = Array.isArray(s.active_injuries) ? s.active_injuries : [];
    if ((s.injury_risk_score ?? 0) >= 5 || activeInjuries.length > 0) {
      flags.push("injury_risk");
    }

    if ((s.acwr ?? 0) > 1.5) {
      flags.push("overreaching");
    }

    wellnessByAthlete.set(s.user_id, flags);
  }

  // Shape data for the card component. Pace adherence + wellness flags
  // are stubbed deterministically off the athlete id so the prototype
  // shows variety; the eventual queries will replace these.
  const roster: RosterAthlete[] = subscriptions.map((s, idx) => {
    const profile = profilesById.get(s.athlete_user_id);
    const displayName = profile?.name?.trim()
      || profile?.email?.split("@")[0]
      || `Athlete ${s.athlete_user_id.slice(0, 6)}`;
    const trend = milesByAthleteByWeek.get(s.athlete_user_id) ?? [0, 0, 0, 0, 0, 0];
    const planStart = new Date(s.created_at);
    const weeksIn = Math.max(
      1,
      Math.min(s.plan_template.duration_weeks, Math.ceil((Date.now() - planStart.getTime()) / (1000 * 60 * 60 * 24 * 7)))
    );

    const paceAdherence: RosterAthlete["paceAdherence"] =
      paceByAthlete.get(s.athlete_user_id) ?? "unknown";
    const wellnessFlags: RosterAthlete["wellnessFlags"] =
      wellnessByAthlete.get(s.athlete_user_id) ?? [];

    return {
      subscriptionId: s.id,
      athleteId: s.athlete_user_id,
      displayName,
      planName: s.plan_template.name,
      weeksIn,
      totalWeeks: s.plan_template.duration_weeks,
      mileageTrend: trend,
      paceAdherence,
      wellnessFlags,
    };
  });

  return (
    <div className="max-w-6xl mx-auto space-y-6">
      <CoachPortalNav />

      <SectionHeader
        title="Athletes"
        subtitle={`${roster.length} active ${roster.length === 1 ? "subscription" : "subscriptions"}`}
      />

      {roster.length === 0 ? (
        <Card className="p-8 text-center">
          <p className="text-[var(--color-text-secondary)]">
            No athletes are subscribed to your plans yet.
          </p>
          <p className="mt-2 text-xs text-[var(--color-text-tertiary)]">
            Share a plan&rsquo;s join code to onboard your first athlete.
          </p>
        </Card>
      ) : (
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {roster.map((athlete) => (
            <AthleteRosterCard key={athlete.subscriptionId} athlete={athlete} />
          ))}
        </div>
      )}

    </div>
  );
}
