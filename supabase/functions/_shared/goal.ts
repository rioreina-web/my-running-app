/**
 * `resolveGoal` — ONE answer to "what is this athlete training for?"
 *
 * WHY THIS FILE EXISTS. Before it, five separate ladders resolved the goal and
 * disagreed with each other:
 *
 *   1. `athlete-state.ts` (~1905) — selects only `goal_title` + `target_date`
 *      and re-derives distance and time BY REGEX, ignoring the structured
 *      columns `interpret-goal` already wrote to the same row.
 *   2. `analyzers/raceProjection.ts` (~137) — 2 tiers, no date.
 *   3. `analyzers/racePaceSpecificity.ts` (~98) — 4 tiers, no date.
 *   4. `trends-timeline.ts` (~503) — 3 tiers, no date; its own comment claims
 *      to mirror #3, which it does not (it drops the title tier).
 *   5. `trends-timeline.ts` (~607) — the ONLY one that reads `target_date`,
 *      and it feeds a chart axis rather than any prompt.
 *
 * The practical consequence was that the AI surfaces knew the goal TIME and
 * almost never the goal DATE. "Sub 2:20" reached the model; "in 13 weeks"
 * did not, except through one hand-rolled line in the athlete-state block.
 * A coach reads those two facts together or not at all.
 *
 * WHAT IS NEW HERE, versus the best of the five:
 *   - the DATE is carried at every tier, not just the structured one;
 *   - `daysToRace` / `weeksToRace` are computed once, in one place;
 *   - goal pace per mile is computed, so no caller divides by hand;
 *   - a past-due goal never wins over a live one;
 *   - `source` is reported, so a surface can say how much it trusts the answer.
 *
 * WHAT IT DELIBERATELY DOES NOT DO. It does not guess a distance from the
 * magnitude of a time. "Sub 2:20" with no distance word is left unresolved and
 * reported via `unparsedTitle`, because inferring marathon from 2:20 is right
 * most of the time and silently, badly wrong the rest — and a wrong goal pace
 * mis-scores every mile without ever looking broken. That reasoning is
 * inherited from `racePaceSpecificity.ts` and is load-bearing; do not "fix" it.
 */

/** Canonical keys, matching what `user_goals` / `athlete_state` actually store. */
export const GOAL_DISTANCE_MI: Record<string, number> = {
  mile: 1.0,
  "1500m": 0.9321,
  "3k": 1.8641,
  "5k": 3.1069,
  "10k": 6.2137,
  "10mi": 10.0,
  half: 13.1094,
  marathon: 26.2188,
};

/**
 * Normalize every spelling this codebase has ever stored into one key.
 * Two mapping systems already exist and disagree on casing: `paces.ts` uses
 * camelCase (`fiveK`, `tenK`) while `athlete_state` and `user_goals` use
 * lowercase (`5k`, `10k`). Both are accepted here so callers stop caring.
 */
export function normalizeRaceKey(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const k = raw.toLowerCase().trim().replace(/[\s-]+/g, "_");
  switch (k) {
    case "marathon": case "full": case "full_marathon": case "m":
      return "marathon";
    case "half": case "half_marathon": case "halfmarathon": case "hm":
      return "half";
    case "10k": case "tenk": case "10_k":
      return "10k";
    case "10mi": case "10_mi": case "tenmi": case "ten_mile": case "10_mile":
      return "10mi";
    case "5k": case "fivek": case "5_k":
      return "5k";
    case "3k": case "threek": case "3_k":
      return "3k";
    case "1500m": case "1500":
      return "1500m";
    case "mile": case "1mi": case "one_mile": case "1_mile":
      return "mile";
    default:
      return GOAL_DISTANCE_MI[k] != null ? k : null;
  }
}

/** Human label for prose. */
export function raceLabelFor(raceKey: string): string {
  switch (raceKey) {
    case "marathon": return "marathon";
    case "half": return "half marathon";
    case "10k": return "10K";
    case "5k": return "5K";
    case "3k": return "3K";
    case "10mi": return "10 mile";
    case "mile": return "mile";
    default: return raceKey;
  }
}

/** Distance words as an athlete writes them in a goal title. Half before marathon. */
const TITLE_DISTANCES: Array<[RegExp, string]> = [
  [/\bhalf(\s*marathon)?\b|\bhm\b/i, "half"],
  [/\bmarathon\b/i, "marathon"],
  [/\b10\s*-?\s*mi(le)?s?\b/i, "10mi"],
  [/\b10\s*-?\s*k\b/i, "10k"],
  [/\b5\s*-?\s*k\b/i, "5k"],
  [/\b3\s*-?\s*k\b/i, "3k"],
  [/\b1500\s*m?\b/i, "1500m"],
  [/\bmile\b/i, "mile"],
];

export type GoalSource =
  | "structured"    // user_goals.target_race_distance + target_time_seconds
  | "active_goal"   // athlete_state.active_goals[]
  | "plan"          // training_plans
  | "athlete_state" // athlete_state flat columns
  | "title";        // parsed from the goal's own wording

export interface ResolvedGoal {
  raceKey: string;
  raceLabel: string;
  distanceMiles: number | null;
  timeSeconds: number;
  /** Goal race pace. Null only when the distance is unknown, which cannot happen today. */
  pacePerMileSeconds: number | null;
  /** YYYY-MM-DD, or null when no date is on file at any tier. */
  targetDate: string | null;
  /** Negative once the date has passed. Null when there is no date. */
  daysToRace: number | null;
  /** Rounded. Callers wanting a floor should use `daysToRace`. */
  weeksToRace: number | null;
  title: string | null;
  source: GoalSource;
  athleteConfirmed: boolean;
}

export interface GoalRow {
  goal_title?: string | null;
  target_race_distance?: string | null;
  target_time_seconds?: number | null;
  target_date?: string | null;
  athlete_confirmed?: boolean | null;
  created_at?: string | null;
}

export interface ActiveGoalRow {
  title?: string | null;
  target_distance_key?: string | null;
  target_time_seconds?: number | null;
  target_date?: string | null;
}

export interface PlanRow {
  target_race_distance?: string | null;
  target_time_seconds?: number | null;
  end_date?: string | null;
  name?: string | null;
}

export interface GoalInputs {
  userGoals: GoalRow[];
  activeGoals: ActiveGoalRow[];
  plan: PlanRow | null;
  stateGoalRace: string | null;
  stateGoalTimeSeconds: number | null;
}

export interface GoalResolution {
  goal: ResolvedGoal | null;
  /** Set when a goal exists but names no distance we can resolve. Ask, never guess. */
  unparsedTitle: string | null;
}

const MIN_GOAL_SECONDS = 120;
const MAX_GOAL_SECONDS = 86400;

function toDateOnly(raw: string | null | undefined): string | null {
  if (!raw) return null;
  const m = String(raw).match(/^(\d{4}-\d{2}-\d{2})/);
  return m ? m[1] : null;
}

/**
 * Whole days between two calendar dates, computed at UTC midnight on both
 * sides so a timezone offset can never shift the answer by a day. This is the
 * same class of bug that once made Ask call a same-day run "yesterday".
 */
function daysBetween(fromISO: string, toISO: string): number {
  const a = Date.parse(`${fromISO}T00:00:00Z`);
  const b = Date.parse(`${toISO}T00:00:00Z`);
  return Math.round((b - a) / 86_400_000);
}

/** H:MM:SS, H:MM or MM:SS. The distance decides how two parts read. */
export function parseGoalTime(title: string, raceKey: string): number | null {
  const m = title.match(/(\d{1,2}):(\d{2})(?::(\d{2}))?/);
  if (!m) return null;
  const a = Number(m[1]), b = Number(m[2]);
  const c = m[3] != null ? Number(m[3]) : null;
  const longRace = raceKey === "marathon" || raceKey === "half" || raceKey === "10mi";
  const seconds = c != null ? a * 3600 + b * 60 + c : longRace ? a * 3600 + b * 60 : a * 60 + b;
  return seconds >= MIN_GOAL_SECONDS && seconds <= MAX_GOAL_SECONDS ? seconds : null;
}

export function parseGoalTitle(title: string): { raceKey: string; seconds: number } | null {
  const raceKey = TITLE_DISTANCES.find(([re]) => re.test(title))?.[1] ?? null;
  if (!raceKey) return null;
  const seconds = parseGoalTime(title, raceKey);
  return seconds == null ? null : { raceKey, seconds };
}

function build(
  raceKeyRaw: string,
  timeSeconds: number,
  targetDateRaw: string | null,
  title: string | null,
  source: GoalSource,
  todayISO: string,
  athleteConfirmed: boolean,
): ResolvedGoal | null {
  const raceKey = normalizeRaceKey(raceKeyRaw);
  if (!raceKey) return null;
  if (!(timeSeconds >= MIN_GOAL_SECONDS && timeSeconds <= MAX_GOAL_SECONDS)) return null;

  const distanceMiles = GOAL_DISTANCE_MI[raceKey] ?? null;
  const targetDate = toDateOnly(targetDateRaw);
  const daysToRace = targetDate ? daysBetween(todayISO, targetDate) : null;

  return {
    raceKey,
    raceLabel: raceLabelFor(raceKey),
    distanceMiles,
    timeSeconds,
    pacePerMileSeconds: distanceMiles ? timeSeconds / distanceMiles : null,
    targetDate,
    daysToRace,
    weeksToRace: daysToRace == null ? null : Math.round(daysToRace / 7),
    title,
    source,
    athleteConfirmed,
  };
}

/**
 * Prefer the soonest goal still ahead of us. Only if every dated goal has
 * passed do we fall back to the most recently created one — a stale goal must
 * never outrank a live one just because it sorts first by date.
 */
function orderGoals<T extends { target_date?: string | null; created_at?: string | null }>(
  rows: T[],
  todayISO: string,
): T[] {
  const withDay = rows.map((r) => {
    const d = toDateOnly(r.target_date);
    return { r, days: d ? daysBetween(todayISO, d) : null };
  });
  const future = withDay.filter((x) => x.days != null && x.days >= 0);
  if (future.length > 0) {
    return future.sort((a, b) => (a.days as number) - (b.days as number)).map((x) => x.r);
  }
  return withDay
    .sort((a, b) => String(b.r.created_at ?? "").localeCompare(String(a.r.created_at ?? "")))
    .map((x) => x.r);
}

/**
 * The pure core. `todayISO` is injected so tests are deterministic and so a
 * caller with the athlete's timezone can pass THEIR today rather than the
 * server's.
 */
export function resolveGoalFrom(inputs: GoalInputs, todayISO: string): GoalResolution {
  const userGoals = inputs.userGoals ?? [];
  const activeGoals = inputs.activeGoals ?? [];

  // Any date we know about, best-first. Used to date a goal resolved at a tier
  // that carries no date of its own — the flat athlete_state columns and the
  // title parse both name a race without ever saying when it is.
  const fallbackDate =
    toDateOnly(orderGoals(userGoals, todayISO)[0]?.target_date) ??
    toDateOnly(activeGoals.find((g) => toDateOnly(g.target_date))?.target_date) ??
    toDateOnly(inputs.plan?.end_date) ??
    null;

  // Tier 1 — the structured record, where interpret-goal is supposed to write.
  for (const g of orderGoals(userGoals, todayISO)) {
    const secs = Number(g.target_time_seconds ?? 0);
    if (secs > 0 && g.target_race_distance) {
      const built = build(
        g.target_race_distance, secs, g.target_date ?? fallbackDate,
        g.goal_title ?? null, "structured", todayISO, g.athlete_confirmed === true,
      );
      if (built) return { goal: built, unparsedTitle: null };
    }
  }

  // Tier 2 — where interpret-goal's answer actually lands today.
  for (const g of activeGoals) {
    const secs = Number(g.target_time_seconds ?? 0);
    if (secs > 0 && g.target_distance_key) {
      const built = build(
        g.target_distance_key, secs, g.target_date ?? fallbackDate,
        g.title ?? null, "active_goal", todayISO, false,
      );
      if (built) return { goal: built, unparsedTitle: null };
    }
  }

  // Tier 3 — the plan. Its `end_date` is the race date for plan-driven athletes.
  const plan = inputs.plan;
  if (plan?.target_race_distance && Number(plan.target_time_seconds ?? 0) > 0) {
    const built = build(
      plan.target_race_distance, Number(plan.target_time_seconds), plan.end_date ?? fallbackDate,
      plan.name ?? null, "plan", todayISO, false,
    );
    if (built) return { goal: built, unparsedTitle: null };
  }

  // Tier 4 — athlete_state's flat copy. Carries no date of its own.
  if (inputs.stateGoalRace && Number(inputs.stateGoalTimeSeconds ?? 0) > 0) {
    const built = build(
      inputs.stateGoalRace, Number(inputs.stateGoalTimeSeconds), fallbackDate,
      null, "athlete_state", todayISO, false,
    );
    if (built) return { goal: built, unparsedTitle: null };
  }

  // Tier 5 — the wording, but only when it names a distance.
  const titles = [
    ...orderGoals(userGoals, todayISO).map((g) => ({ t: g.goal_title, d: g.target_date })),
    ...activeGoals.map((g) => ({ t: g.title, d: g.target_date })),
  ].filter((x): x is { t: string; d: string | null } => !!x.t);

  for (const { t, d } of titles) {
    const parsed = parseGoalTitle(t);
    if (!parsed) continue;
    const built = build(parsed.raceKey, parsed.seconds, d ?? fallbackDate, t, "title", todayISO, false);
    if (built) return { goal: built, unparsedTitle: null };
  }

  return { goal: null, unparsedTitle: titles[0]?.t ?? null };
}

/** Minimal shape of the Supabase client this needs. Keeps the module testable. */
interface QueryClient {
  // deno-lint-ignore no-explicit-any
  from: (table: string) => any;
}

/**
 * Fetch + resolve. Three reads, run in parallel.
 *
 * NOTE the `user_id` filters. A goal row with a NULL `user_id` belongs to
 * nobody and must never resolve for anybody — one such orphan row sat active
 * in production until 2026-09-08 and was picked up by the two resolvers that
 * filtered on status alone.
 */
export async function resolveGoal(
  supabase: QueryClient,
  userId: string,
  opts?: { todayISO?: string },
): Promise<GoalResolution> {
  const todayISO = opts?.todayISO ?? new Date().toISOString().slice(0, 10);

  const [goalsRes, planRes, stateRes] = await Promise.all([
    supabase
      .from("user_goals")
      .select("goal_title, target_race_distance, target_time_seconds, target_date, athlete_confirmed, created_at")
      .eq("user_id", userId)
      .not("user_id", "is", null)
      .eq("status", "active")
      .order("target_date", { ascending: true })
      .limit(10),
    supabase
      .from("training_plans")
      .select("name, target_race_distance, target_time_seconds, end_date")
      .eq("user_id", userId)
      .eq("status", "active")
      .order("updated_at", { ascending: false })
      .limit(1),
    supabase
      .from("athlete_state")
      .select("goal_race, goal_time_seconds, active_goals")
      .eq("user_id", userId)
      .maybeSingle(),
  ]);

  const state = (stateRes?.data ?? null) as
    | { goal_race: string | null; goal_time_seconds: number | null; active_goals: ActiveGoalRow[] | null }
    | null;

  return resolveGoalFrom(
    {
      userGoals: (goalsRes?.data ?? []) as GoalRow[],
      activeGoals: (state?.active_goals ?? []) as ActiveGoalRow[],
      plan: ((planRes?.data ?? [])[0] ?? null) as PlanRow | null,
      stateGoalRace: state?.goal_race ?? null,
      stateGoalTimeSeconds: state?.goal_time_seconds ?? null,
    },
    todayISO,
  );
}

/** "5:20" from 320.4. Shared so no caller re-implements rounding. */
export function fmtPace(secPerMile: number | null | undefined): string | null {
  if (secPerMile == null || !Number.isFinite(secPerMile) || secPerMile <= 0) return null;
  const total = Math.round(secPerMile);
  return `${Math.floor(total / 60)}:${String(total % 60).padStart(2, "0")}`;
}

/** "13 weeks out" / "9 days out" / "past". The one place this phrasing lives. */
export function describeRunway(goal: ResolvedGoal): string | null {
  if (goal.daysToRace == null) return null;
  if (goal.daysToRace < 0) return "past";
  if (goal.daysToRace === 0) return "today";
  if (goal.daysToRace < 14) return `${goal.daysToRace} days out`;
  return `${Math.round(goal.daysToRace / 7)} weeks out`;
}
