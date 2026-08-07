/**
 * `heat_effect` — "Was that pace real, or was it the heat?"
 *
 * Principle IX (Conditions). Reads the heat columns already persisted on
 * `running_workout_laps` by the heat pipeline — `heat_adjusted_pace_sec_per_mile`,
 * `heat_category`, `dew_point_f`. No model, no recomputation: the adjustment
 * was applied at ingest and this analyzer reports what it did.
 *
 * WHY THIS DESERVES ITS OWN CHIP. An athlete who trains through a summer
 * watches their paces go backwards and concludes they are losing fitness. Very
 * often they are not — the same effort simply costs more seconds in a 71°F dew
 * point. `zone_trend` already carries a conditions-neutral figure, but it's one
 * fact among four. Asked directly, this is the question that stops a good block
 * from reading as a bad one.
 *
 * HONESTY. The adjustment is a MODEL, not a measurement. It is applied above a
 * 68°F dew point, mentioned between 60 and 68, and ignored below — and the
 * coverage line says so, every time. We are not claiming to know what the
 * athlete would have run on a cool day; we are saying what the model says that
 * heat is worth, so they can discount it themselves.
 */

import { daysAgoISO, fetchLapsByWorkout, fetchLogsSince } from "./data.ts";
import {
  fmtPaceSec,
  fmtSecDelta,
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerParams,
  type AnalyzerResult,
  type FactLine,
  type SeriesPoint,
} from "./types.ts";

const DEFAULT_WINDOW_DAYS = 90;
const METERS_PER_MILE = 1609.34;
/** Mirrors `pace-heat-adjustment.ts` — above this dew point the model applies. */
const DEW_APPLY_F = 68;

interface HeatLap {
  distance_meters?: number | null;
  avg_pace_sec_per_mile?: number | null;
  heat_adjusted_pace_sec_per_mile?: number | null;
  heat_category?: string | null;
  is_rest?: boolean | null;
}

export const heatEffect: Analyzer = {
  id: "heat_effect",
  label: "Was that pace real, or was it the heat?",
  group: "conditions",
  params: {
    window_days: {
      type: "number",
      min: 14,
      max: 365,
      optional: true,
      describe: "How far back to look. Defaults to 90 days.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const windowDays = Number(params.window_days ?? DEFAULT_WINDOW_DAYS);

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
        related: ["zone_trend", "efficiency"],
        empty: {
          eyebrow: "Nothing logged in this window",
          nudge: "Once runs land with weather attached, this shows what the conditions were worth.",
          cta: null,
        },
      };
    }

    const lapsByWorkout = await fetchLapsByWorkout(
      ctx.supabase,
      ctx.userId,
      logs.map((l) => l.id),
    );

    // Distance-weight everything: a 6-mile tempo should not count the same as
    // a 400m float when we're averaging what the heat cost.
    let rawSum = 0;
    let adjSum = 0;
    let adjMiles = 0;
    let dewSum = 0;
    let dewCount = 0;
    let runsAboveApply = 0;
    let runsWithWeather = 0;
    const byMonth = new Map<string, { dew: number; n: number }>();

    for (const log of logs) {
      const wx = log.weather_actual as Record<string, unknown> | null;
      const dew = wx && typeof wx.dew_point_f === "number" ? wx.dew_point_f : null;
      if (dew != null) {
        runsWithWeather++;
        dewSum += dew;
        dewCount++;
        if (dew >= DEW_APPLY_F) runsAboveApply++;
        const month = String(log.workout_date).slice(0, 7);
        const bucket = byMonth.get(month) ?? { dew: 0, n: 0 };
        bucket.dew += dew;
        bucket.n++;
        byMonth.set(month, bucket);
      }

      const laps = (lapsByWorkout.get(log.id) ?? []) as unknown as HeatLap[];
      for (const lap of laps) {
        if (lap.is_rest === true) continue;
        const meters = Number(lap.distance_meters ?? 0);
        const raw = Number(lap.avg_pace_sec_per_mile ?? 0);
        const adj = Number(lap.heat_adjusted_pace_sec_per_mile ?? 0);
        if (!(meters > 0) || !(raw > 0) || !(adj > 0)) continue;
        const miles = meters / METERS_PER_MILE;
        rawSum += raw * miles;
        adjSum += adj * miles;
        adjMiles += miles;
      }
    }

    if (adjMiles <= 0) {
      return {
        facts: [],
        coverage: {
          sessionsUsed: logs.length,
          windowDays,
          missing: ["no runs in this window carried both weather and lap splits"],
          confidence: "low",
        },
        related: ["zone_trend", "efficiency"],
        empty: {
          eyebrow: "Nothing to adjust yet",
          nudge:
            "The heat read needs weather attached to runs that also have lap splits. It fills in as those sync.",
          cta: null,
        },
      };
    }

    const rawPace = rawSum / adjMiles;
    const adjPace = adjSum / adjMiles;
    // Heat-adjusted is the cool-equivalent, so it is FASTER. The cost is the gap.
    const costPerMile = rawPace - adjPace;
    const avgDew = dewCount > 0 ? dewSum / dewCount : null;

    const facts: FactLine[] = [
      {
        key: "raw_pace",
        label: `Actual pace · ${windowDays} days`,
        value: fmtPaceSec(rawPace),
        unit: "/mi",
        tone: "neutral",
      },
      {
        key: "neutral_pace",
        label: "Cool-weather equivalent",
        value: fmtPaceSec(adjPace),
        unit: "/mi",
        delta: fmtSecDelta(-costPerMile),
        tone: "good",
      },
      {
        key: "heat_cost",
        label: "What the conditions were worth",
        value: String(Math.round(costPerMile)),
        unit: " s/mi",
        tone: costPerMile >= 8 ? "watch" : "neutral",
      },
    ];

    if (avgDew != null) {
      facts.push({
        key: "dew_point",
        label: "Average dew point",
        value: String(Math.round(avgDew)),
        unit: "°F",
        delta: avgDew >= DEW_APPLY_F ? "adjustment applied" : "below threshold",
        tone: avgDew >= DEW_APPLY_F ? "watch" : "neutral",
      });
    }

    if (runsWithWeather > 0) {
      facts.push({
        key: "runs_in_heat",
        label: "Runs above the heat threshold",
        value: String(runsAboveApply),
        delta: `of ${runsWithWeather}`,
        tone: runsAboveApply > runsWithWeather / 2 ? "watch" : "neutral",
      });
    }

    const points: SeriesPoint[] = [...byMonth.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([month, v]) => ({
        x: month,
        y: Math.round((v.dew / v.n) * 10) / 10,
        y2: null,
        label: null,
      }));

    const missing: string[] = [
      "the heat adjustment is a model, not a measurement — it applies above a 68°F dew point",
    ];
    const withoutWeather = logs.length - runsWithWeather;
    if (withoutWeather > 0) {
      missing.push(`${withoutWeather} of ${logs.length} runs had no weather attached`);
    }

    return {
      facts,
      series: points.length > 1
        ? {
          kind: "line",
          unit: "percent",
          invertY: false,
          band: [DEW_APPLY_F, DEW_APPLY_F + 8],
          points,
        }
        : null,
      coverage: {
        sessionsUsed: runsWithWeather,
        windowDays,
        missing,
        confidence: runsWithWeather >= 20 ? "high" : runsWithWeather >= 8 ? "moderate" : "low",
      },
      related: ["zone_trend", "efficiency", "decoupling"],
    };
  },
};
