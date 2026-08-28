import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";
import { Card } from "@/components/ui/card";
import { CoachSetupPrompt } from "@/components/coach/coach-setup-prompt";
import {
  RosterLedger,
  RosterAllClear,
  type RosterRow,
} from "@/components/coach/roster-ledger";

// The Desk — the coach's daily scan, and the portal's landing surface.
//
// Signals on each row:
//   - Mileage trend  ← training_logs (last 6 weeks, weekly buckets)
//   - Pace adherence ← workout_reconciliations.adjusted_pace_delta_seconds
//                      rolled up over the last 7 days, quality workouts only
//   - Mood + flags   ← athlete_state (mood, ACWR, injury risk)
//   - Last run       ← most recent training_logs.workout_date
//
// Rows sort attention-first: anyone with a reason to be looked at rises to
// the top, and the quiet ones collapse to a one-line tail. Every reason is
// a fact drawn from a column above — the ledger never diagnoses.

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

  // Supabase types a to-one embed (`plan_templates!inner`) as an array, but at
  // runtime it returns a single object. Bridge via `unknown` per TS guidance.
  const subscriptions = (subs ?? []) as unknown as Array<{
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

    // Coach-set display names live on athlete_settings (owner + service-role
    // RLS), so read them through the admin client for these already-gated
    // athletes. A saved name takes priority over the email/id fallback below.
    const admin = createAdminClient();
    const { data: settingsRows } = await admin
      .from("athlete_settings")
      .select("user_id, display_name")
      .in("user_id", athleteIds);
    for (const row of (settingsRows ?? []) as Array<{ user_id: string; display_name: string | null }>) {
      const existing = profilesById.get(row.user_id) ?? { name: null, email: null };
      profilesById.set(row.user_id, { ...existing, name: row.display_name });
    }
  }

  // Bulk-fetch the last 6 weeks of training_logs miles per athlete to
  // power the volume bars. Schema columns are workout_date (timestamptz)
  // and workout_distance_miles — not date / distance_miles.
  const nowMs = new Date().getTime();
  const sixWeeksAgo = new Date();
  sixWeeksAgo.setDate(sixWeeksAgo.getDate() - 7 * 6);
  const { data: logs } = await supabase
    .from("training_logs")
    .select("user_id, workout_date, workout_distance_miles")
    .in("user_id", athleteIds)
    .gte("workout_date", sixWeeksAgo.toISOString())
    .order("workout_date", { ascending: true });

  // Group miles into 6 weekly buckets per athlete (oldest → newest), and
  // track the most recent logged run while we're walking the same rows.
  const milesByAthleteByWeek = new Map<string, number[]>();
  const lastRunMsByAthlete = new Map<string, number>();
  for (const id of athleteIds) milesByAthleteByWeek.set(id, [0, 0, 0, 0, 0, 0]);
  for (const row of (logs ?? []) as Array<{ user_id: string; workout_date: string; workout_distance_miles: number | null }>) {
    const d = new Date(row.workout_date);
    const weeksAgo = Math.min(5, Math.max(0, Math.floor((nowMs - d.getTime()) / (1000 * 60 * 60 * 24 * 7))));
    const bucketIdx = 5 - weeksAgo; // 0 = oldest, 5 = current week
    const bucket = milesByAthleteByWeek.get(row.user_id);
    if (bucket && row.workout_distance_miles != null) bucket[bucketIdx] += row.workout_distance_miles;

    const prev = lastRunMsByAthlete.get(row.user_id) ?? 0;
    if (d.getTime() > prev) lastRunMsByAthlete.set(row.user_id, d.getTime());
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

  const paceByAthlete = new Map<string, RosterRow["paceAdherence"]>();
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

  // ── Real signal #2: mood + load flags from athlete_state ───────────
  // Each attention line names the column it came from and the number in
  // it. No inference, no diagnosis — the coach reads the fact and makes
  // the call. `last_mood` additionally drives the mood rule under the
  // athlete's name; it is the only place the mood ramp appears.
  const { data: statesRaw } = await supabase
    .from("athlete_state")
    .select("user_id, last_mood, mood_trend, acwr, injury_risk_score, active_injuries")
    .in("user_id", athleteIds);

  const moodByAthlete = new Map<string, string | null>();
  const attentionByAthlete = new Map<string, string[]>();
  for (const s of (statesRaw ?? []) as Array<{
    user_id: string;
    last_mood: string | null;
    mood_trend: string | null;
    acwr: number | null;
    injury_risk_score: number | null;
    active_injuries: unknown;
  }>) {
    const reasons: string[] = [];

    const mood = (s.last_mood ?? "").toLowerCase() || null;
    moodByAthlete.set(s.user_id, mood);

    const trend = (s.mood_trend ?? "").toLowerCase();
    if (mood === "tired" || mood === "struggling" || trend.includes("declin")) {
      reasons.push(mood === "struggling" ? "Mood · struggling" : "Mood · declining");
    }

    const activeInjuries = Array.isArray(s.active_injuries) ? s.active_injuries : [];
    if (activeInjuries.length > 0) {
      reasons.push(
        `Active injury · ${activeInjuries.length}`
      );
    } else if ((s.injury_risk_score ?? 0) >= 5) {
      reasons.push(`Injury risk · ${s.injury_risk_score}`);
    }

    if ((s.acwr ?? 0) > 1.5) {
      reasons.push(`ACWR ${Number(s.acwr).toFixed(2)}`);
    }

    attentionByAthlete.set(s.user_id, reasons);
  }

  // Shape rows, then add the two signals that come from the log timeline
  // rather than athlete_state: a quiet athlete and an off-target one both
  // need the coach, and neither shows up in the columns above.
  const rows: RosterRow[] = subscriptions.map((s) => {
    const profile = profilesById.get(s.athlete_user_id);
    const displayName = profile?.name?.trim()
      || profile?.email?.split("@")[0]
      || `Athlete ${s.athlete_user_id.slice(0, 6)}`;
    const trend = milesByAthleteByWeek.get(s.athlete_user_id) ?? [0, 0, 0, 0, 0, 0];
    const planStart = new Date(s.created_at);
    const weeksIn = Math.max(
      1,
      Math.min(s.plan_template.duration_weeks, Math.ceil((nowMs - planStart.getTime()) / (1000 * 60 * 60 * 24 * 7)))
    );

    const paceAdherence = paceByAthlete.get(s.athlete_user_id) ?? "unknown";

    const lastRunMs = lastRunMsByAthlete.get(s.athlete_user_id);
    const daysSinceLastRun =
      lastRunMs === undefined
        ? null
        : Math.max(0, Math.floor((nowMs - lastRunMs) / (1000 * 60 * 60 * 24)));

    const attention = [...(attentionByAthlete.get(s.athlete_user_id) ?? [])];
    if (daysSinceLastRun === null) {
      attention.unshift("No runs logged");
    } else if (daysSinceLastRun >= 7) {
      attention.unshift(`${daysSinceLastRun} days quiet`);
    }
    if (paceAdherence === "way_off") {
      attention.push("Pace off target");
    }

    return {
      subscriptionId: s.id,
      athleteId: s.athlete_user_id,
      displayName,
      planName: s.plan_template.name,
      weeksIn,
      totalWeeks: s.plan_template.duration_weeks,
      mileageTrend: trend,
      thisWeekMiles: trend[5] ?? 0,
      paceAdherence,
      daysSinceLastRun,
      mood: moodByAthlete.get(s.athlete_user_id) ?? null,
      attention,
      // The athlete's own words belong here, but cleaned_notes is usually
      // the provider's title ("Morning Run") rather than anything they
      // said — printing that as a quote would put words in their mouth.
      // Wire this to the voice-memo transcript, not to notes.
      lastVoice: null,
    };
  });

  // Attention first, then most reasons, then quietest.
  const flagged = rows
    .filter((r) => r.attention.length > 0)
    .sort((a, b) => b.attention.length - a.attention.length);
  const steady = rows.filter((r) => r.attention.length === 0 && r.thisWeekMiles > 0);
  const clear = rows.filter((r) => r.attention.length === 0 && r.thisWeekMiles === 0);

  const totalMiles = rows.reduce((sum, r) => sum + r.thisWeekMiles, 0);
  const ledgerRows = [...flagged, ...steady];

  if (rows.length === 0) {
    return (
      <>
        <Masthead flaggedCount={0} activeCount={0} totalMiles={0} />
        <Card className="p-8 text-center">
          <p style={{ color: "var(--color-text-secondary)" }}>
            No athletes are subscribed to your plans yet.
          </p>
          <p className="drip-eyebrow mt-2" style={{ color: "var(--color-text-tertiary)" }}>
            Share a plan&rsquo;s join code to onboard your first athlete.
          </p>
        </Card>
      </>
    );
  }

  return (
    <>
      <Masthead
        flaggedCount={flagged.length}
        activeCount={rows.length}
        totalMiles={totalMiles}
      />

      <section className="mt-11">
        <SectionHead
          eyebrow={`Roster · ${flagged.length > 0 ? "attention first" : "all steady"}`}
          note="6-week volume, this week's miles, pace against plan."
        />
        <RosterLedger rows={ledgerRows} />
      </section>

      {clear.length > 0 && (
        <section className="mt-11">
          <SectionHead
            eyebrow={`Nothing logged this week · ${clear.length}`}
            note="No signals, and no runs in the current week."
          />
          <RosterAllClear rows={clear} />
        </section>
      )}
    </>
  );
}

function Masthead({
  flaggedCount,
  activeCount,
  totalMiles,
}: {
  flaggedCount: number;
  activeCount: number;
  totalMiles: number;
}) {
  // The dek states the count and nothing else. A headline names the surface;
  // it does not editorialise it.
  const dek =
    flaggedCount === 0
      ? "No athlete is flagged for a decision."
      : `${flaggedCount} ${flaggedCount === 1 ? "athlete needs" : "athletes need"} a decision.`;

  return (
    <header className="flex flex-wrap items-end justify-between gap-8 pb-[6px] pt-[34px]">
      <div>
        <h1 className="drip-display text-[46px]">The desk</h1>
        <p
          className="mt-[9px] text-[15px] italic"
          style={{ fontFamily: "var(--font-accent)", color: "var(--color-text-secondary)" }}
        >
          {dek}
        </p>
      </div>
      <div className="flex gap-[30px]">
        <Tally n={flaggedCount} label="Flagged" red={flaggedCount > 0} />
        <Tally n={activeCount} label="Active" />
        <Tally n={Math.round(totalMiles)} label="Miles this wk" />
      </div>
    </header>
  );
}

function Tally({ n, label, red = false }: { n: number; label: string; red?: boolean }) {
  return (
    <div>
      <span
        className="drip-stat block text-[27px] leading-none"
        style={red ? { color: "var(--red-text)" } : undefined}
      >
        {n}
      </span>
      <span className="drip-eyebrow mt-[6px] block">{label}</span>
    </div>
  );
}

function SectionHead({ eyebrow, note }: { eyebrow: string; note: string }) {
  return (
    <div
      className="flex items-baseline justify-between gap-3 pb-2"
      style={{ borderBottom: "2px solid var(--rule-strong)" }}
    >
      <span className="drip-eyebrow">{eyebrow}</span>
      <span
        className="hidden text-[12.5px] italic sm:block"
        style={{ fontFamily: "var(--font-accent)", color: "var(--color-text-tertiary)" }}
      >
        {note}
      </span>
    </div>
  );
}
