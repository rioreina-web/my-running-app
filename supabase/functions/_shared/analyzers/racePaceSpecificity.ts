/**
 * `race_pace_specificity` — "How much of my work is actually at goal pace?"
 *
 * Principle III (Specificity), and the analyzer the registry audit called the
 * most load-bearing missing question a goal-chasing runner has.
 *
 * THIS IS THE JOIN NOBODY EVER WROTE. The product has known the goal
 * (`athlete_state.goal_race` + `goal_time_seconds`) and known the training
 * (`running_workout_laps.avg_pace_sec_per_mile`) for months, and has never
 * once put them in the same sentence. Both operands were persisted; the line
 * that divides them didn't exist. That's the whole analyzer.
 *
 * WHAT IT COUNTS. Miles run within a tolerance band of goal pace, over a
 * window, as a share of total running. Not "quality miles" — those are
 * MP-anchored and answer a different question. This is specifically *the pace
 * you are trying to hold on race day*, which for a marathoner is a pace that
 * barely registers as quality at all.
 *
 * WHY A BAND AND NOT AN EXACT MATCH. Nobody runs a mile at exactly 5:20. The
 * band is ±2% of goal pace by default — about ±7 seconds on a 6:00 mile —
 * which is the range a coach would call "at pace" without hedging.
 *
 * WHAT IT DOES NOT DO. It does not say whether the share is enough. There is
 * no universal right answer (a base block and a peak block should look
 * completely different), so it reports the share, the trend against the first
 * half of the window, and the goal pace itself — and lets the athlete and
 * their coach read it. Hard rule #2: observation, not prescription.
 */

import { daysAgoISO, fetchLogsSince, fetchLapsByWorkout } from "./data.ts";
import { fetchAthleteState, raceDistanceMiles, raceLabel } from "./athleteState.ts";
import {
  fmtPaceSec,
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerParams,
  type AnalyzerResult,
  type FactLine,
  type SeriesPoint,
} from "./types.ts";

const DEFAULT_WINDOW_DAYS = 56;
const METERS_PER_MILE = 1609.34;
/** ±2% of goal pace reads as "at pace" without hedging. */
const DEFAULT_TOLERANCE_PCT = 2;

/** Distance words as an athlete writes them, in a goal title. */
const TITLE_DISTANCES: Array<[RegExp, string]> = [
  [/\bmarathon\b/i, "marathon"],
  [/\bhalf(\s*marathon)?\b/i, "half"],
  [/\b10\s*-?\s*k\b/i, "10k"],
  [/\b5\s*-?\s*k\b/i, "5k"],
  [/\bmile\b/i, "mile"],
];

type GoalSource = "structured" | "athlete_state" | "title";

interface ResolvedGoal {
  raceKey: string;
  seconds: number;
  from: GoalSource;
  title: string | null;
}

/**
 * The goal, from wherever it actually lives, in order of trustworthiness.
 *
 *   1. `user_goals.target_race_distance` + `target_time_seconds` — the proper
 *      structured home, populated by `interpret-goal`.
 *   2. `athlete_state.goal_race` + `goal_time_seconds`.
 *   3. A narrow parse of the goal's own wording.
 *
 * A NOTE ON WHY TIER 3 EXISTS AND WHY IT IS NOT ENOUGH. In practice tiers 1
 * and 2 are often empty while a goal is plainly visible in the app as free
 * text — "Run sub 2:20 at CIM". That gap is almost certainly why this join was
 * never written: there was nothing structured to join against.
 *
 * But the parse can only resolve a goal that names its distance. "Run sub 2:20
 * at CIM" does not — knowing CIM is a marathon takes world knowledge, which is
 * exactly what `interpret-goal` is for. So tier 3 catches "sub 1:10 at Austin
 * Half Marathon" and misses "sub 2:20 at CIM", and the honest response to a
 * miss is an empty state asking the athlete to confirm the goal, NOT a guess.
 * Inferring the distance from the magnitude of the time would work most of the
 * time and be silently, badly wrong the rest — and a wrong goal pace
 * mis-scores every mile in the window without ever looking broken.
 */
async function resolveGoal(
  ctx: AnalyzerCtx,
  state: {
    goal_race: string | null;
    goal_time_seconds: number | null;
    active_goals: Array<{ title?: string | null }> | null;
  } | null,
): Promise<{ goal: ResolvedGoal | null; sawUnparsedGoal: string | null }> {
  // Tier 1 — the structured record.
  const { data } = await ctx.supabase
    .from("user_goals")
    .select("goal_title, target_race_distance, target_time_seconds, status")
    .eq("user_id", ctx.userId)
    .eq("status", "active")
    .order("created_at", { ascending: false });

  const goals = (data ?? []) as Array<{
    goal_title: string | null;
    target_race_distance: string | null;
    target_time_seconds: number | null;
  }>;

  for (const g of goals) {
    const secs = Number(g.target_time_seconds ?? 0);
    if (secs > 0 && g.target_race_distance) {
      return {
        goal: {
          raceKey: g.target_race_distance,
          seconds: secs,
          from: "structured",
          title: g.goal_title,
        },
        sawUnparsedGoal: null,
      };
    }
  }

  // Tier 2 — athlete_state's copy.
  const stateSeconds = Number(state?.goal_time_seconds ?? 0);
  if (stateSeconds > 0 && state?.goal_race) {
    return {
      goal: { raceKey: state.goal_race, seconds: stateSeconds, from: "athlete_state", title: null },
      sawUnparsedGoal: null,
    };
  }

  // Tier 3 — the wording, when it names a distance.
  const titles = [
    ...goals.map((g) => g.goal_title),
    ...(state?.active_goals ?? []).map((g) => g?.title ?? null),
  ].filter((t): t is string => !!t);

  for (const title of titles) {
    const distance = TITLE_DISTANCES.find(([re]) => re.test(title))?.[1] ?? null;
    if (!distance) continue;

    // H:MM:SS, H:MM, or MM:SS. The distance decides how a two-part time reads:
    // "2:20" is two hours twenty for a marathon, two-twenty for a mile.
    const m = title.match(/(\d{1,2}):(\d{2})(?::(\d{2}))?/);
    if (!m) continue;
    const a = Number(m[1]), b = Number(m[2]), c = m[3] != null ? Number(m[3]) : null;
    const seconds = c != null
      ? a * 3600 + b * 60 + c
      : distance === "marathon" || distance === "half"
      ? a * 3600 + b * 60
      : a * 60 + b;

    if (seconds >= 120 && seconds <= 86400) {
      return { goal: { raceKey: distance, seconds, from: "title", title }, sawUnparsedGoal: null };
    }
  }

  return { goal: null, sawUnparsedGoal: titles[0] ?? null };
}

export const racePaceSpecificity: Analyzer = {
  id: "race_pace_specificity",
  label: "How much work is at goal pace?",
  group: "specificity",
  params: {
    window_days: {
      type: "number",
      min: 14,
      max: 180,
      optional: true,
      describe: "How far back to count. Defaults to 56 days.",
    },
    tolerance_pct: {
      type: "number",
      min: 1,
      max: 5,
      optional: true,
      describe: "How wide the at-pace band is, as a percent. Defaults to 2.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const windowDays = Number(params.window_days ?? DEFAULT_WINDOW_DAYS);
    const tolerancePct = Number(params.tolerance_pct ?? DEFAULT_TOLERANCE_PCT);

    const state = await fetchAthleteState(ctx.supabase, ctx.userId);
    const { goal: resolved, sawUnparsedGoal } = await resolveGoal(ctx, state);
    const goalSeconds = resolved?.seconds ?? 0;
    const distanceMiles = resolved ? raceDistanceMiles(resolved.raceKey) : null;

    if (!(goalSeconds > 0) || !distanceMiles) {
      // Two different empty states, because they need two different actions.
      // A goal that exists but hasn't been pinned to a distance and a time is
      // a confirmation away; no goal at all is a different ask.
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays, missing: [], confidence: "low" },
        related: ["race_projection", "zone_trend", "quality_share"],
        empty: sawUnparsedGoal
          ? {
            eyebrow: "Goal needs a distance and a time",
            nudge:
              `Your goal reads "${sawUnparsedGoal}". To measure your training against it, the app needs to know the distance and the target time behind those words. Confirm them and this reads straight away.`,
            cta: { label: "Confirm goal", action: "confirm_goal" },
          }
          : {
            eyebrow: "No goal to measure against",
            nudge:
              "This compares your running against the pace you're chasing, so it needs a goal race and a goal time. Set one and it reads immediately.",
            cta: { label: "Set a goal", action: "open_goal" },
          },
      };
    }

    const goalPaceSec = goalSeconds / distanceMiles;
    const lo = goalPaceSec * (1 - tolerancePct / 100);
    const hi = goalPaceSec * (1 + tolerancePct / 100);

    const logs = await fetchLogsSince(
      ctx.supabase,
      ctx.userId,
      daysAgoISO(ctx.now, windowDays),
      400,
    );
    if (logs.length === 0) {
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays, missing: [], confidence: "low" },
        related: ["race_projection", "zone_trend"],
        empty: {
          eyebrow: "Nothing logged in this window",
          nudge: "Once a few runs land, this shows how much of them sat at goal pace.",
          cta: null,
        },
      };
    }

    const lapsByWorkout = await fetchLapsByWorkout(
      ctx.supabase,
      ctx.userId,
      logs.map((l) => l.id),
    );

    // Split the window in half so the share has something to move against.
    const midpoint = ctx.now.getTime() - (windowDays / 2) * 86400000;

    let atPaceMiles = 0;
    let totalMiles = 0;
    let atPaceMilesRecent = 0;
    let totalMilesRecent = 0;
    let sessionsWithAtPace = 0;
    let logsWithLaps = 0;

    for (const log of logs) {
      const laps = lapsByWorkout.get(log.id);
      if (!laps || laps.length === 0) continue;
      logsWithLaps++;
      const isRecent = new Date(log.workout_date).getTime() >= midpoint;
      let sessionAtPace = 0;

      for (const lap of laps) {
        // A recovery float is not training at goal pace, no matter its clock.
        if ((lap as { is_rest?: boolean | null }).is_rest === true) continue;
        const meters = Number(lap.distance_meters ?? 0);
        if (!(meters > 0)) continue;
        const miles = meters / METERS_PER_MILE;

        const pace = Number(lap.avg_pace_sec_per_mile ?? 0);
        totalMiles += miles;
        if (isRecent) totalMilesRecent += miles;
        if (!(pace > 0)) continue;

        if (pace >= lo && pace <= hi) {
          atPaceMiles += miles;
          sessionAtPace += miles;
          if (isRecent) atPaceMilesRecent += miles;
        }
      }
      if (sessionAtPace >= 0.5) sessionsWithAtPace++;
    }

    if (totalMiles <= 0) {
      return {
        facts: [],
        coverage: { sessionsUsed: logs.length, windowDays, missing: [], confidence: "low" },
        related: ["race_projection", "zone_trend"],
        empty: {
          eyebrow: "No lap data in this window",
          nudge:
            "This reads lap splits to see which miles sat at goal pace. Runs without splits can't be counted.",
          cta: null,
        },
      };
    }

    const sharePct = (atPaceMiles / totalMiles) * 100;
    const earlyMiles = totalMiles - totalMilesRecent;
    const earlyAtPace = atPaceMiles - atPaceMilesRecent;
    const earlyPct = earlyMiles > 0 ? (earlyAtPace / earlyMiles) * 100 : null;
    const recentPct = totalMilesRecent > 0
      ? (atPaceMilesRecent / totalMilesRecent) * 100
      : null;
    const shift = earlyPct != null && recentPct != null ? recentPct - earlyPct : null;

    const label = raceLabel(resolved!.raceKey);

    const facts: FactLine[] = [
      {
        key: "goal_pace",
        label: `Goal pace · ${label}`,
        value: fmtPaceSec(goalPaceSec),
        unit: "/mi",
        tone: "neutral",
      },
      {
        key: "at_pace_miles",
        label: `Miles at goal pace · ${windowDays} days`,
        value: (Math.round(atPaceMiles * 10) / 10).toFixed(1),
        unit: " mi",
        tone: "neutral",
      },
      {
        key: "share",
        label: "Share of running at goal pace",
        value: sharePct.toFixed(1),
        unit: "%",
        delta: shift != null
          ? `${shift < 0 ? "−" : "+"}${Math.abs(shift).toFixed(1)} vs. first half`
          : undefined,
        // Direction, not judgement — there is no correct share in the abstract.
        tone: "neutral",
      },
      {
        key: "sessions",
        label: "Sessions with real work at it",
        value: String(sessionsWithAtPace),
        delta: `of ${logsWithLaps}`,
        tone: "neutral",
      },
    ];

    const points: SeriesPoint[] = [];
    if (earlyPct != null) {
      points.push({ x: "first half", y: Math.round(earlyPct * 10) / 10, y2: null, label: null });
    }
    if (recentPct != null) {
      points.push({ x: "recent", y: Math.round(recentPct * 10) / 10, y2: null, label: null });
    }

    const missing: string[] = [
      `counted within ${tolerancePct}% of goal pace (${fmtPaceSec(lo)} to ${fmtPaceSec(hi)})`,
    ];
    if (resolved!.from === "title") {
      // Be explicit that the goal was read off free text. If the parse is
      // wrong, this line is how the athlete notices.
      missing.push("goal pace read from your goal's wording, not a confirmed goal time");
    }
    const withoutLaps = logs.length - logsWithLaps;
    if (withoutLaps > 0) {
      missing.push(`${withoutLaps} of ${logs.length} runs had no lap splits to read`);
    }

    return {
      title: `How much of my work is at ${label.toLowerCase()} goal pace?`,
      facts,
      series: points.length > 1
        ? { kind: "bar", unit: "percent", invertY: false, band: null, points }
        : null,
      coverage: {
        sessionsUsed: logsWithLaps,
        windowDays,
        missing,
        confidence: logsWithLaps >= 20 ? "high" : logsWithLaps >= 8 ? "moderate" : "low",
      },
      related: ["race_projection", "zone_trend", "load_balance"],
    };
  },
};
