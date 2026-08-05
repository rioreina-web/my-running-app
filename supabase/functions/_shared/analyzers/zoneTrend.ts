/**
 * `zone_trend` — "Is my LT / MP / 5K pace improving?"
 *
 * Principle V (Adaptation). Wraps `fast-segment-trends.analyzeFastSegmentTrends`,
 * which already does the hard part: bin every fast rep to its pace SYSTEM
 * (MP / HMP / LT / 10K / 5K / 3K / Mile), neutralize for heat and grade, and
 * emit a chronological per-system trend. This analyzer adds no math — it picks
 * the system, splits the points into an early and a late window, and turns the
 * difference into fact lines.
 *
 * Why early-vs-late rather than a regression: a linear fit over 6–10 noisy
 * sessions reads as more precise than it is, and the athlete-facing claim we
 * want to license is "the recent ones are faster than the early ones", which is
 * exactly what the two windows say. `conditionsPaceSecPerMile` (heat AND grade
 * removed) is the honest cross-day fitness pace, so it leads the comparison
 * whenever both windows have it.
 */

import {
  analyzeFastSegmentTrends,
  type KeySessionInput,
  type PaceSystem,
  type SystemTrend,
  type SystemTrendPoint,
} from "../fast-segment-trends.ts";
import {
  fetchFeaturesByLogIds,
  fetchLapsByWorkout,
  fetchLogsSince,
  daysAgoISO,
  weatherFromLog,
  type LogRow,
} from "./data.ts";
import {
  confidenceFromSamples,
  factLinesToStrings,
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

const DEFAULT_WINDOW_DAYS = 120;
/** Below this the two windows overlap and the comparison is meaningless. */
const MIN_POINTS = 4;
/** Points per comparison window. Three is enough to damp one bad day. */
const WINDOW_N = 3;

const SYSTEMS: PaceSystem[] = ["MP", "HMP", "LT", "10K", "5K", "3K", "Mile"];

/** Mean of a numeric field over a slice, ignoring nulls. */
function meanOf(
  points: SystemTrendPoint[],
  pick: (p: SystemTrendPoint) => number | null,
): number | null {
  const vals = points.map(pick).filter((v): v is number => typeof v === "number" && v > 0);
  if (vals.length === 0) return null;
  return vals.reduce((s, v) => s + v, 0) / vals.length;
}

/**
 * Which system to trend when the athlete didn't name one: the system with the
 * most sessions, breaking ties toward the faster (more specific) one, because
 * a runner with equal LT and MP volume is more likely asking about the sharper
 * end. Deterministic — no model input.
 */
function pickSystem(systems: SystemTrend[]): SystemTrend | null {
  if (systems.length === 0) return null;
  const ranked = [...systems].sort((a, b) => {
    if (b.points.length !== a.points.length) return b.points.length - a.points.length;
    return SYSTEMS.indexOf(b.system) - SYSTEMS.indexOf(a.system);
  });
  return ranked[0];
}

function buildInputs(
  logs: LogRow[],
  lapsByWorkout: Awaited<ReturnType<typeof fetchLapsByWorkout>>,
  labels: Map<string, string>,
): KeySessionInput[] {
  const inputs: KeySessionInput[] = [];
  for (const log of logs) {
    const laps = lapsByWorkout.get(log.id);
    if (!laps || laps.length === 0) continue;
    inputs.push({
      id: log.id,
      date: String(log.workout_date).slice(0, 10),
      name: labels.get(log.id) || undefined,
      totalMiles: log.workout_distance_miles ?? null,
      weather: weatherFromLog(log),
      laps: laps.map((l) => ({
        distance_meters: Number(l.distance_meters ?? 0),
        moving_time_seconds: Number(l.moving_time_seconds ?? 0),
        avg_pace_sec_per_mile: l.avg_pace_sec_per_mile != null
          ? Number(l.avg_pace_sec_per_mile)
          : null,
        avg_heart_rate: l.avg_heart_rate != null ? Number(l.avg_heart_rate) : null,
        total_elevation_gain: l.total_elevation_gain != null
          ? Number(l.total_elevation_gain)
          : null,
      })),
    });
  }
  return inputs;
}

function emptyResult(
  windowDays: number,
  sessionsUsed: number,
  eyebrow: string,
  nudge: string,
): AnalyzerResult {
  return {
    facts: [],
    series: null,
    coverage: { sessionsUsed, windowDays, missing: [], confidence: "low" },
    related: ["compare_session", "quality_share", "load_balance"],
    empty: { eyebrow, nudge, cta: null },
  };
}

export const zoneTrend: Analyzer = {
  id: "zone_trend",
  label: "Is my LT pace improving?",
  group: "adaptation",
  params: {
    system: {
      type: "string",
      enum: SYSTEMS,
      optional: true,
      describe:
        "Which pace system to trend. Omit to use the one the athlete has run most.",
    },
    window_days: {
      type: "number",
      min: 28,
      max: 365,
      optional: true,
      describe: "How far back to look. Defaults to 120 days.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const windowDays = Number(params.window_days ?? DEFAULT_WINDOW_DAYS);
    const requested = typeof params.system === "string"
      ? (params.system as PaceSystem)
      : null;

    if (!ctx.zoneTable.mp) {
      return emptyResult(
        windowDays,
        0,
        "No pace anchor yet",
        "Pace systems are derived from a race anchor. Confirm a race result and the whole trend becomes readable.",
      );
    }

    const logs = await fetchLogsSince(
      ctx.supabase,
      ctx.userId,
      daysAgoISO(ctx.now, windowDays),
    );
    if (logs.length === 0) {
      return emptyResult(windowDays, 0, "Nothing logged in this window", "Runs sync from HealthKit automatically. Once a few land, the trend draws itself.");
    }

    const lapsByWorkout = await fetchLapsByWorkout(
      ctx.supabase,
      ctx.userId,
      logs.map((l) => l.id),
    );
    const featureRows = await fetchFeaturesByLogIds(
      ctx.supabase,
      ctx.userId,
      logs.map((l) => l.id),
    );
    const labels = new Map<string, string>();
    for (const [id, row] of featureRows) {
      if (row.workout_structure?.trim()) labels.set(id, row.workout_structure.trim());
    }

    const trends = analyzeFastSegmentTrends(
      buildInputs(logs, lapsByWorkout, labels),
      ctx.zoneTable,
    );

    const trend = requested
      ? trends.systems.find((s) => s.system === requested) ?? null
      : pickSystem(trends.systems);

    if (!trend) {
      return emptyResult(
        windowDays,
        trends.sessions.length,
        requested ? `No ${requested} work on file` : "No fast work on file yet",
        requested
          ? `Nothing in the last ${windowDays} days registered as a real ${requested} session. The trend needs sessions that actually hit that band.`
          : "The trend reads sessions with sustained work at marathon pace or faster. Once a couple land, this fills in.",
      );
    }

    const points = trend.points;
    if (points.length < MIN_POINTS) {
      return emptyResult(
        windowDays,
        points.length,
        `${points.length} ${trend.system} ${points.length === 1 ? "session" : "sessions"} on file`,
        `The trend gets honest at ${MIN_POINTS}. Two more ${trend.system} sessions and this starts saying something.`,
      );
    }

    const n = Math.min(WINDOW_N, Math.floor(points.length / 2));
    const early = points.slice(0, n);
    const late = points.slice(-n);

    const earlyRaw = meanOf(early, (p) => p.avgPaceSecPerMile)!;
    const lateRaw = meanOf(late, (p) => p.avgPaceSecPerMile)!;
    const earlyAdj = meanOf(early, (p) => p.conditionsPaceSecPerMile);
    const lateAdj = meanOf(late, (p) => p.conditionsPaceSecPerMile);
    const bothAdjusted = earlyAdj != null && lateAdj != null;

    // Faster = negative delta.
    const rawDelta = lateRaw - earlyRaw;
    const adjDelta = bothAdjusted ? lateAdj! - earlyAdj! : null;
    const headlineDelta = adjDelta ?? rawDelta;

    const facts: FactLine[] = [
      {
        key: "recent_pace",
        label: `${trend.system} pace · last ${n} sessions`,
        value: fmtPaceSec(lateRaw),
        unit: "/mi",
        delta: fmtSecDelta(rawDelta),
        tone: rawDelta < -2 ? "good" : rawDelta > 2 ? "watch" : "neutral",
      },
      {
        key: "early_pace",
        label: `${trend.system} pace · first ${n} sessions`,
        value: fmtPaceSec(earlyRaw),
        unit: "/mi",
        tone: "neutral",
      },
    ];

    if (bothAdjusted) {
      facts.push({
        key: "recent_pace_neutral",
        label: "Conditions-neutral equivalent",
        value: fmtPaceSec(lateAdj!),
        unit: "/mi",
        delta: fmtSecDelta(adjDelta!),
        tone: adjDelta! < -2 ? "good" : adjDelta! > 2 ? "watch" : "neutral",
      });
    }

    const avgWorkMiles = late.reduce((s, p) => s + p.workMiles, 0) / late.length;
    const [lo, hi] = trend.expectedMiles;
    const inRange = avgWorkMiles >= lo && avgWorkMiles <= hi;
    facts.push({
      key: "work_volume",
      label: `${trend.system} volume · recent average`,
      value: (Math.round(avgWorkMiles * 10) / 10).toFixed(1),
      unit: " mi",
      delta: inRange ? "in range" : avgWorkMiles < lo ? "below range" : "above range",
      tone: inRange ? "good" : "watch",
    });

    const withoutHR = points.filter((p) => p.avgHeartRate == null).length;
    const withoutConditions = points.filter((p) => p.conditionsPaceSecPerMile == null).length;
    const missing: string[] = [];
    if (withoutHR > 0) missing.push(`no HR on ${withoutHR} of ${points.length} sessions`);
    if (withoutConditions > 0) {
      missing.push(`no weather on ${withoutConditions} of ${points.length} sessions`);
    }

    const seriesPoints: SeriesPoint[] = points.map((p) => ({
      x: p.date,
      y: Math.round(p.avgPaceSecPerMile),
      y2: p.conditionsPaceSecPerMile != null
        ? Math.round(p.conditionsPaceSecPerMile)
        : null,
      label: p.sessionName,
    }));

    return {
      facts,
      series: {
        kind: "line",
        unit: "sec_per_mile",
        invertY: true,
        band: null,
        y2Label: "conditions-neutral",
        points: seriesPoints,
      },
      coverage: {
        sessionsUsed: points.length,
        windowDays,
        missing,
        confidence: confidenceFromSamples(points.length, { high: 6, moderate: 4 }),
      },
      related: headlineDelta < 0
        ? ["compare_session", "system_volume", "race_projection"]
        : ["heat_normalize", "load_balance", "compare_session"],
    };
  },
};
