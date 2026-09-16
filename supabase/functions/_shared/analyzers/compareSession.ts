/**
 * `compare_session` — "How does this session stack up against similar ones?"
 *
 * Principle XI (Comparison). Wraps `workoutComparison.compareWorkouts` +
 * `findBestComparison` — the engine `compare-workouts` already ships. This
 * analyzer adds nothing to the math; it adapts the engine's `factLines` and
 * `comparability` into the registry's `FactLine[]` + `Coverage` shape so the
 * comparison can be asked for conversationally rather than only from a
 * workout detail screen.
 *
 * Two front doors, unchanged from the comparison spec:
 *   • `{ workout_id }` — auto. Scans prior sessions, picks the fairest match.
 *   • `{ workout_id, compare_to_id }` — manual. Any two workouts, hedged by
 *     the comparability score rather than refused.
 * Plus a third the chip rail needs: **no params at all**, which resolves to
 * the athlete's most recent session with readable laps.
 *
 * The one refusal is an unreadable session — "couldn't read this session's
 * structure" — never a bad comparison dressed up as a good one.
 *
 * NOTE ON DUPLICATION: `compare-workouts/index.ts` remains the Trends entry
 * point and keeps its own handler. Both call the same engine, so the numbers
 * cannot drift; only the fetch plumbing is duplicated (see `data.ts`). Open
 * call in ASK-REGISTRY §10 is whether `ask` eventually absorbs it.
 */

import {
  compareWorkouts,
  findBestComparison,
  RECENCY_FLOOR_DAYS,
  type ComparisonResult,
} from "../workoutComparison.ts";
import {
  fetchFeaturesByLogIds,
  fetchLapsByWorkout,
  fetchLogById,
  fetchLogsSince,
  daysAgoISO,
  toComparisonWorkout,
  type LogRow,
} from "./data.ts";
import {
  factLinesToStrings,
  fmtDelta,
  fmtPaceSec,
  fmtSecDelta,
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerParams,
  type AnalyzerResult,
  type FactLine,
  type SeriesPoint,
} from "./types.ts";

export { factLinesToStrings };

/** Laps are the expensive fetch; cap the candidate pool the way auto mode does. */
const MAX_CANDIDATES = 12;

function emptyResult(
  eyebrow: string,
  nudge: string,
  sessionsUsed = 0,
): AnalyzerResult {
  return {
    facts: [],
    series: null,
    coverage: {
      sessionsUsed,
      windowDays: RECENCY_FLOOR_DAYS,
      missing: [],
      confidence: "low",
    },
    related: ["zone_trend", "load_balance"],
    empty: { eyebrow, nudge, cta: null },
  };
}

/**
 * "Aug 3 tempo · 7.2 mi" — enough identity for the athlete to know exactly
 * which run a fact line is talking about. The card was shipping deltas
 * against a ghost: "pace vs. the match" with no way to tell which session
 * was read or what it was matched against, which makes the whole comparison
 * unreadable from the chip rail (where no workout context exists).
 */
function fmtSession(log: LogRow): string {
  const d = new Date(log.workout_date);
  const date = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
  const type = typeof log.workout_type === "string" && log.workout_type.length > 0 &&
      log.workout_type.length <= 12
    ? ` ${log.workout_type.toLowerCase()}`
    : "";
  const mi = Number(log.workout_distance_miles ?? 0);
  return mi > 0 ? `${date}${type} · ${Math.round(mi * 10) / 10} mi` : `${date}${type}`;
}

/** The most recent log that has laps — the chip-rail default target. */
async function resolveDefaultTarget(ctx: AnalyzerCtx): Promise<LogRow | null> {
  const logs = await fetchLogsSince(
    ctx.supabase,
    ctx.userId,
    daysAgoISO(ctx.now, 60),
    60,
  );
  if (logs.length === 0) return null;
  const laps = await fetchLapsByWorkout(
    ctx.supabase,
    ctx.userId,
    logs.map((l) => l.id),
  );
  return logs.find((l) => (laps.get(l.id)?.length ?? 0) > 0) ?? null;
}

/**
 * Turn the engine's `ComparisonDiff` into registry fact lines.
 *
 * Only rows the diff actually computed become facts — a null pair is simply
 * absent, never rendered as zero. `diff.unavailable` becomes coverage
 * `missing[]`, so what couldn't be measured is stated rather than implied.
 */
function factsFromComparison(result: ComparisonResult): FactLine[] {
  const diff = result.diff!;
  const facts: FactLine[] = [];

  const repPace = diff.avgRepPaceAdjSec ?? diff.avgRepPaceRawSec ?? diff.avgPaceSec;
  if (repPace) {
    const adjusted = diff.avgRepPaceAdjSec != null;
    facts.push({
      key: "pace_delta",
      label: adjusted ? "Rep pace, conditions-adjusted" : "Pace vs. the match",
      value: fmtPaceSec(repPace.b),
      unit: "/mi",
      delta: fmtSecDelta(repPace.delta),
      tone: repPace.delta < -2 ? "good" : repPace.delta > 2 ? "watch" : "neutral",
    });
  }

  const hr = diff.avgWorkHr ?? diff.avgRunHr;
  if (hr) {
    facts.push({
      key: "hr_delta",
      label: diff.avgWorkHr ? "Average HR across the work" : "Average HR",
      value: String(Math.round(hr.b)),
      unit: " bpm",
      delta: fmtDelta(hr.delta),
      // Lower heart rate at the same work is the fitness signal.
      tone: hr.delta < -1 ? "good" : hr.delta > 3 ? "watch" : "neutral",
    });
  }

  if (diff.reps) {
    facts.push({
      key: "reps",
      label: "Reps at the work pace",
      value: String(Math.round(diff.reps.b)),
      delta: fmtDelta(diff.reps.delta),
      tone: "neutral",
    });
  }

  if (diff.tempF) {
    facts.push({
      key: "temp",
      label: "Temperature",
      value: String(Math.round(diff.tempF.b)),
      unit: "°F",
      delta: fmtDelta(diff.tempF.delta, { suffix: "°" }),
      tone: diff.tempF.delta > 8 ? "watch" : "neutral",
    });
  }

  if (diff.decouplingPct.a != null && diff.decouplingPct.b != null) {
    const d = diff.decouplingPct.b - diff.decouplingPct.a;
    facts.push({
      key: "decoupling",
      label: "Aerobic decoupling",
      value: (Math.round(diff.decouplingPct.b * 10) / 10).toFixed(1),
      unit: "%",
      delta: fmtDelta(d, { decimals: 1 }),
      tone: d < -0.5 ? "good" : d > 1 ? "watch" : "neutral",
    });
  }

  return facts;
}

export const compareSession: Analyzer = {
  id: "compare_session",
  label: "Compare this session to similar ones",
  group: "comparison",
  params: {
    workout_id: {
      type: "workout_id",
      optional: true,
      describe:
        "The session to read. Omit for the athlete's most recent session with lap data.",
    },
    compare_to_id: {
      type: "workout_id",
      optional: true,
      describe:
        "Compare against this specific session instead of the auto-picked fairest match.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const workoutId = typeof params.workout_id === "string" ? params.workout_id : null;
    const compareToId = typeof params.compare_to_id === "string"
      ? params.compare_to_id
      : null;

    const target = workoutId
      ? await fetchLogById(ctx.supabase, ctx.userId, workoutId)
      : await resolveDefaultTarget(ctx);

    if (!target) {
      return emptyResult(
        "No session to read yet",
        "The comparison needs a run with lap splits. Once one syncs, this can find its fairest match.",
      );
    }

    // Resolve the other side.
    let other: LogRow | null = null;
    let suggestionScore: number | null = null;

    if (compareToId) {
      if (compareToId === target.id) {
        return emptyResult("Same session on both sides", "Pick a different session to compare against.");
      }
      other = await fetchLogById(ctx.supabase, ctx.userId, compareToId);
      if (!other) {
        return emptyResult("Couldn't find that session", "The session to compare against isn't in your log.");
      }
    } else {
      const since = daysAgoISO(
        new Date(new Date(target.workout_date).getTime()),
        RECENCY_FLOOR_DAYS,
      );
      const pool = (await fetchLogsSince(ctx.supabase, ctx.userId, since, 300))
        .filter((l) =>
          l.id !== target.id &&
          new Date(l.workout_date).getTime() < new Date(target.workout_date).getTime()
        )
        .slice(0, MAX_CANDIDATES);

      if (pool.length === 0) {
        return emptyResult(
          "Nothing fair to compare against",
          "There's no earlier session close enough in shape to read this one against. It gets easier as the log fills in.",
        );
      }

      const laps = await fetchLapsByWorkout(
        ctx.supabase,
        ctx.userId,
        [target.id, ...pool.map((c) => c.id)],
      );
      const best = findBestComparison(
        toComparisonWorkout(target, laps.get(target.id)),
        pool.map((c) => toComparisonWorkout(c, laps.get(c.id))),
        ctx.zones,
      );
      if (!best) {
        return emptyResult(
          "Nothing fair to compare against",
          "Prior sessions exist, but none is close enough in kind for the comparison to mean anything. A hedged read would be worse than none.",
          pool.length,
        );
      }
      other = pool.find((c) => c.id === best.id) ?? null;
      suggestionScore = best.score;
    }

    if (!other) {
      return emptyResult("Nothing fair to compare against", "No earlier session qualified.");
    }

    const laps = await fetchLapsByWorkout(ctx.supabase, ctx.userId, [target.id, other.id]);
    const featureRows = await fetchFeaturesByLogIds(
      ctx.supabase,
      ctx.userId,
      [target.id, other.id],
    );

    const comparison = compareWorkouts(
      toComparisonWorkout(target, laps.get(target.id), featureRows.get(target.id)?.workout_structure),
      toComparisonWorkout(other, laps.get(other.id), featureRows.get(other.id)?.workout_structure),
      ctx.zones,
    );

    if (!comparison.ok || !comparison.diff || !comparison.comparability) {
      return emptyResult(
        "Couldn't read this session's structure",
        "The lap data doesn't resolve into readable work and recovery, so there's nothing honest to compare. Nothing is wrong with the run itself.",
        2,
      );
    }

    const { comparability, diff } = comparison;
    const facts = factsFromComparison(comparison);

    if (facts.length === 0) {
      return emptyResult(
        "Nothing measurable in common",
        "Both sessions read fine on their own, but they share no metric that survives the comparison. Try picking the other session by hand.",
        2,
      );
    }

    // The engine's own per-lap series (cumulative miles → lap pace), zipped by
    // lap index: y is the newer session (B), y2 the earlier match (A).
    const seriesPoints: SeriesPoint[] = [];
    const aSeries = comparison.a.series;
    const bSeries = comparison.b.series;
    const n = Math.max(aSeries.length, bSeries.length);
    for (let i = 0; i < n; i++) {
      const bp = bSeries[i];
      const ap = aSeries[i];
      if (!bp && !ap) continue;
      const primary = bp ?? ap!;
      seriesPoints.push({
        x: (Math.round(primary.mi * 10) / 10).toFixed(1),
        y: Math.round(primary.paceSec),
        y2: ap && bp ? Math.round(ap.paceSec) : null,
        label: null,
      });
    }

    // Name both sides of the comparison, first, so every delta below has a
    // referent. Without these two lines the card is deltas against a ghost.
    facts.unshift(
      {
        key: "target_session",
        label: "This session",
        value: fmtSession(target),
        tone: "neutral",
      },
      {
        key: "match_session",
        label: "Compared against",
        value: fmtSession(other),
        delta: comparability.daysApart != null
          ? `${comparability.daysApart} day${comparability.daysApart === 1 ? "" : "s"} earlier`
          : undefined,
        tone: "neutral",
      },
    );

    const missing = [...diff.unavailable];
    if (comparability.daysApart != null && comparability.daysApart > 120) {
      missing.push(`${comparability.daysApart} days apart`);
    }
    for (const note of comparability.notes) missing.push(note);

    return {
      facts,
      title: `How does ${fmtSession(target)} stack up?`,
      series: seriesPoints.length > 1
        ? {
          kind: "line",
          unit: "sec_per_mile",
          invertY: true,
          band: null,
          y2Label: "the match",
          points: seriesPoints,
        }
        : null,
      coverage: {
        sessionsUsed: 2,
        windowDays: comparability.daysApart ?? RECENCY_FLOOR_DAYS,
        missing,
        confidence: comparability.confidence,
      },
      related: suggestionScore != null
        ? ["zone_trend", "heat_normalize", "best_sessions"]
        : ["zone_trend", "load_balance", "heat_normalize"],
    };
  },
};
