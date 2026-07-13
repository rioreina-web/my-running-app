import "server-only";
import type { createClient } from "@/lib/supabase/server";
import type { PreviewAthlete } from "@/components/coach/athlete-preview-rail";

/** The RLS-scoped server client returned by `@/lib/supabase/server`. */
type Client = Awaited<ReturnType<typeof createClient>>;

/**
 * Server-side loader for the plan builder's athlete preview rail (Phase 5).
 *
 * Resolves the coach's linked athletes into `PreviewAthlete[]`: a display name,
 * a pace anchor (real race > goal), and their preferred quality/long/rest days.
 * All reads go through the caller's RLS-scoped Supabase client — the same
 * coach-scoped reads the athletes dashboard already performs
 * (coach-portal/athletes/page.tsx) — so no new policy or service-role access
 * is needed.
 *
 * Anchor precedence mirrors the materializer's `resolveAthletePaces`
 * (subscribe-to-plan): a real, confirmed race outranks a goal time; the pace
 * math itself is shared via `derivePaceTableFromGoal` on the client rail.
 */

// Race miles by the distance labels stored in athlete_state.confirmed_races
// ('5K' | '10K' | 'half' | 'marathon' | 'mile') and athlete_pace_profiles
// (goal_race_distance uses the same set). Standard IAAF/road distances.
const RACE_MILES: Record<string, number> = {
  mile: 1,
  "5k": 3.106856,
  "10k": 6.213712,
  half: 13.109375,
  marathon: 26.21875,
};

// Normalize a stored distance label to the `derivePaceTableFromGoal` input
// vocabulary. Returns null for 'other'/unknown so we skip it as an anchor.
function normalizeDistance(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const d = raw.toLowerCase();
  if (d === "mile") return "mile";
  if (d === "5k") return "5k";
  if (d === "10k") return "10k";
  if (d === "half" || d === "half_marathon") return "half_marathon";
  if (d === "marathon") return "marathon";
  return null;
}

function milesForDistance(normalized: string): number {
  if (normalized === "half_marathon") return RACE_MILES.half;
  return RACE_MILES[normalized] ?? 0;
}

function formatClock(totalSeconds: number): string {
  const s = Math.round(totalSeconds);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  if (h > 0) return `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`;
  return `${m}:${String(sec).padStart(2, "0")}`;
}

const DISTANCE_LABEL: Record<string, string> = {
  mile: "mile",
  "5k": "5K",
  "10k": "10K",
  half_marathon: "half",
  marathon: "marathon",
};

interface ConfirmedRace {
  date?: string;
  distance?: string;
  finish_time_seconds?: number;
}

interface ResolvedAnchor {
  secPerMile: number;
  distance: string; // derive-helper input form
  label: string;
  isReal: boolean;
}

// Pick the strongest anchor for an athlete: a confirmed race (most recent)
// beats a goal. Returns null when neither resolves to a usable distance/time.
function resolveAnchor(
  confirmedRaces: ConfirmedRace[],
  goalDistance: string | null,
  goalSeconds: number | null,
): ResolvedAnchor | null {
  // 1. Real race — most recent valid entry wins.
  const races = confirmedRaces
    .map((r) => ({
      norm: normalizeDistance(r.distance),
      seconds: typeof r.finish_time_seconds === "number" ? r.finish_time_seconds : null,
      date: r.date ?? "",
    }))
    .filter((r): r is { norm: string; seconds: number; date: string } =>
      r.norm !== null && r.seconds !== null && r.seconds > 0,
    )
    .sort((a, b) => (a.date < b.date ? 1 : -1));
  if (races.length > 0) {
    const r = races[0];
    const miles = milesForDistance(r.norm);
    if (miles > 0) {
      return {
        secPerMile: r.seconds / miles,
        distance: r.norm,
        label: `${formatClock(r.seconds)} ${DISTANCE_LABEL[r.norm]}`,
        isReal: true,
      };
    }
  }

  // 2. Goal time.
  const gNorm = normalizeDistance(goalDistance);
  if (gNorm && goalSeconds && goalSeconds > 0) {
    const miles = milesForDistance(gNorm);
    if (miles > 0) {
      return {
        secPerMile: goalSeconds / miles,
        distance: gNorm,
        label: `goal · ${formatClock(goalSeconds)} ${DISTANCE_LABEL[gNorm]}`,
        isReal: false,
      };
    }
  }

  return null;
}

export async function fetchPreviewAthletes(
  supabase: Client,
  coachProfileId: string,
): Promise<PreviewAthlete[]> {
  // Active subscriptions against any plan this coach owns — mirrors the join
  // in coach-portal/athletes/page.tsx and plans/page.tsx.
  const { data: subs } = await supabase
    .from("athlete_plan_subscriptions")
    .select(
      `id, athlete_user_id, created_at, status,
       preferred_quality_dows, long_run_dow, rest_dows,
       plan_template:plan_templates!inner ( coach_id )`,
    )
    .eq("plan_template.coach_id", coachProfileId)
    .eq("status", "active")
    .order("created_at", { ascending: false });

  const subscriptions = (subs ?? []) as unknown as Array<{
    athlete_user_id: string;
    preferred_quality_dows: number[] | null;
    long_run_dow: number | null;
    rest_dows: number[] | null;
  }>;

  // Most-recent active subscription per athlete carries their day prefs.
  const prefsByAthlete = new Map<
    string,
    { preferred_quality_dows: number[] | null; long_run_dow: number | null; rest_dows: number[] }
  >();
  for (const s of subscriptions) {
    if (prefsByAthlete.has(s.athlete_user_id)) continue; // ordered newest-first
    prefsByAthlete.set(s.athlete_user_id, {
      preferred_quality_dows: s.preferred_quality_dows,
      long_run_dow: s.long_run_dow,
      rest_dows: Array.isArray(s.rest_dows) ? s.rest_dows : [],
    });
  }

  const athleteIds = Array.from(prefsByAthlete.keys());
  if (athleteIds.length === 0) return [];

  // Names (auth.users.email — no user_profiles table on this DB), anchors
  // (athlete_state.confirmed_races + goal), and goal fallback
  // (athlete_pace_profiles). All coach-readable under existing RLS.
  const [authRes, stateRes, profileRes] = await Promise.all([
    supabase.schema("auth").from("users").select("id, email").in("id", athleteIds),
    supabase
      .from("athlete_state")
      .select("user_id, confirmed_races, goal_race, goal_time_seconds")
      .in("user_id", athleteIds),
    supabase
      .from("athlete_pace_profiles")
      .select("user_id, goal_race_distance, goal_time_seconds, manual_anchor_distance, manual_anchor_time_seconds")
      .in("user_id", athleteIds),
  ]);

  const emailById = new Map<string, string | null>();
  for (const row of (authRes.data ?? []) as Array<{ id: string; email: string | null }>) {
    emailById.set(row.id, row.email);
  }
  const stateById = new Map<
    string,
    { confirmed_races: ConfirmedRace[]; goal_time_seconds: number | null }
  >();
  for (const row of (stateRes.data ?? []) as Array<{
    user_id: string;
    confirmed_races: ConfirmedRace[] | null;
    goal_time_seconds: number | null;
  }>) {
    stateById.set(row.user_id, {
      confirmed_races: Array.isArray(row.confirmed_races) ? row.confirmed_races : [],
      goal_time_seconds: row.goal_time_seconds,
    });
  }
  const profileById = new Map<
    string,
    {
      goal_race_distance: string | null;
      goal_time_seconds: number | null;
      manual_anchor_distance: string | null;
      manual_anchor_time_seconds: number | null;
    }
  >();
  for (const row of (profileRes.data ?? []) as Array<{
    user_id: string;
    goal_race_distance: string | null;
    goal_time_seconds: number | null;
    manual_anchor_distance: string | null;
    manual_anchor_time_seconds: number | null;
  }>) {
    profileById.set(row.user_id, row);
  }

  return athleteIds.map((id) => {
    const prefs = prefsByAthlete.get(id)!;
    const state = stateById.get(id);
    const profile = profileById.get(id);
    const email = emailById.get(id);
    const name = email?.split("@")[0] || `Athlete ${id.slice(0, 6)}`;

    // A manual anchor (explicit, user-set) is treated as a confirmed race so
    // it outranks the goal; otherwise fall through to real races then goal.
    const races: ConfirmedRace[] = [...(state?.confirmed_races ?? [])];
    if (profile?.manual_anchor_distance && profile.manual_anchor_time_seconds) {
      races.unshift({
        distance: profile.manual_anchor_distance,
        finish_time_seconds: profile.manual_anchor_time_seconds,
        date: "9999-12-31", // sort to front as the authoritative anchor
      });
    }

    const goalDistance = profile?.goal_race_distance ?? null;
    const goalSeconds = profile?.goal_time_seconds ?? state?.goal_time_seconds ?? null;
    const anchor = resolveAnchor(races, goalDistance, goalSeconds);

    return {
      id,
      name,
      anchorLabel: anchor?.label ?? "no anchor yet",
      anchorIsReal: anchor?.isReal ?? false,
      anchorSecPerMile: anchor?.secPerMile ?? null,
      anchorDistance: anchor?.distance ?? null,
      preferredQualityDows: prefs.preferred_quality_dows,
      longRunDow: prefs.long_run_dow,
      restDows: prefs.rest_dows,
    } satisfies PreviewAthlete;
  });
}
