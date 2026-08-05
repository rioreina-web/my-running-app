/**
 * `load_balance` — "Am I ramping too fast?"
 *
 * Principle I (Progressive overload). Wraps `weeklyAnalytics.aggregateWeeklyLoad`
 * + `calculateACWR` — the same intensity-weighted acute-to-chronic math that
 * already drives `athlete_state`, so the answer here can never disagree with
 * the Trends tile.
 *
 * Two things this analyzer is careful about:
 *
 *   1. **The current week is partial.** Asking on a Tuesday and comparing three
 *      days against four full prior weeks reads as "you've collapsed". The
 *      facts label the current week explicitly as days-elapsed, and the ACWR
 *      fact is computed on the last COMPLETE week when today is before
 *      midweek — otherwise the headline number is an artefact of the calendar.
 *   2. **Monotony and strain come from `workout_features`, not recomputed.**
 *      `monotony_7d` / `strain_7d` are persisted per workout by
 *      compute-workout-features; the latest row wins. Recomputing them here
 *      would be a second implementation of a number the athlete already sees.
 *
 * Hard rule #2: no fact here says "back off" or "you're overtrained". It says
 * what the ratio is and which band it sits in. `tone: "watch"` is the ceiling.
 */

import {
  aggregateWeeklyLoad,
  calculateACWR,
  type TrainingLogRow,
  type WorkoutFeaturesRow,
} from "../weeklyAnalytics.ts";
import {
  fetchFeaturesSince,
  fetchLogsSince,
  daysAgoISO,
  weekStart,
  type FeatureRow,
  type LogRow,
} from "./data.ts";
import {
  factLinesToStrings,
  fmtPctDelta,
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerParams,
  type AnalyzerResult,
  type FactLine,
  type SeriesPoint,
} from "./types.ts";

export { factLinesToStrings };

const DEFAULT_WEEKS = 6;
/** ACWR needs a chronic baseline; below this the ratio is noise. */
const MIN_WEEKS_FOR_ACWR = 3;
/** Before this many days into the week, lead on the last complete week. */
const PARTIAL_WEEK_CUTOFF_DAYS = 4;

/** The band the product treats as "holding" — mirrors `calculateACWR`'s bands. */
const ACWR_LOW = 0.8;
const ACWR_HIGH = 1.3;

interface Bucket {
  start: Date;
  label: string;
  logs: TrainingLogRow[];
  miles: number;
}

/** Map an analyzer LogRow onto the weeklyAnalytics input shape. */
function toTrainingLogRow(l: LogRow): TrainingLogRow {
  return {
    id: l.id,
    workout_date: l.workout_date,
    workout_distance_miles: l.workout_distance_miles,
    workout_duration_minutes: l.workout_duration_minutes,
    workout_type: l.workout_type,
    workout_pace_per_mile: null,
    pace_segments: null,
    mood: null,
    notes: null,
    cleaned_notes: null,
    coach_insight: null,
  };
}

function toFeaturesRow(f: FeatureRow): WorkoutFeaturesRow {
  return {
    training_log_id: f.training_log_id,
    intensity_score: f.intensity_score,
    total_duration_seconds: f.total_duration_seconds,
  };
}

/** Bucket logs into Mon–Sun weeks, newest last. */
function bucketWeeks(logs: LogRow[], now: Date, weeks: number): Bucket[] {
  const thisWeek = weekStart(now);
  const out: Bucket[] = [];
  for (let i = weeks - 1; i >= 0; i--) {
    const start = new Date(thisWeek.getTime() - i * 7 * 86400000);
    const end = new Date(start.getTime() + 7 * 86400000);
    const inWeek = logs.filter((l) => {
      const d = new Date(l.workout_date);
      return d >= start && d < end;
    });
    out.push({
      start,
      label: i === 0 ? "NOW" : `W-${i}`,
      logs: inWeek.map(toTrainingLogRow),
      miles: inWeek.reduce((s, l) => s + (l.workout_distance_miles ?? 0), 0),
    });
  }
  return out;
}

function acwrTone(acwr: number): "good" | "watch" {
  return acwr >= ACWR_LOW && acwr <= ACWR_HIGH ? "good" : "watch";
}

function acwrBand(acwr: number): string {
  if (acwr > ACWR_HIGH) return "above band";
  if (acwr < ACWR_LOW) return "below band";
  return "in band";
}

export const loadBalance: Analyzer = {
  id: "load_balance",
  label: "Am I ramping too fast?",
  group: "load",
  params: {
    weeks: {
      type: "number",
      min: 4,
      max: 26,
      optional: true,
      describe: "How many weeks of history to chart. Defaults to 6.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const weeks = Math.max(MIN_WEEKS_FOR_ACWR + 1, Number(params.weeks ?? DEFAULT_WEEKS));
    const windowDays = weeks * 7 + 7;

    const [logs, features] = await Promise.all([
      fetchLogsSince(ctx.supabase, ctx.userId, daysAgoISO(ctx.now, windowDays)),
      fetchFeaturesSince(ctx.supabase, ctx.userId, daysAgoISO(ctx.now, windowDays)),
    ]);

    const buckets = bucketWeeks(logs, ctx.now, weeks);
    const nonEmpty = buckets.filter((b) => b.logs.length > 0);

    if (nonEmpty.length < MIN_WEEKS_FOR_ACWR) {
      return {
        facts: [],
        series: null,
        coverage: {
          sessionsUsed: logs.length,
          windowDays,
          missing: [],
          confidence: "low",
        },
        related: ["volume_trend", "quality_share", "compare_session"],
        empty: {
          eyebrow: `${nonEmpty.length} ${nonEmpty.length === 1 ? "week" : "weeks"} of history`,
          nudge:
            `The acute-to-chronic ratio compares this week against the four before it. It needs ${MIN_WEEKS_FOR_ACWR} weeks on file before it means anything.`,
          cta: null,
        },
      };
    }

    const featuresByLogId = new Map<string, WorkoutFeaturesRow>();
    for (const f of features) {
      featuresByLogId.set(String(f.training_log_id), toFeaturesRow(f));
    }

    const loads = buckets.map((b) => aggregateWeeklyLoad(b.logs, featuresByLogId));

    // A partial current week makes the headline ratio lie. Lead on the last
    // complete week until enough of this one has happened.
    const daysIntoWeek = Math.floor(
      (ctx.now.getTime() - buckets[buckets.length - 1].start.getTime()) / 86400000,
    ) + 1;
    const usePartial = daysIntoWeek >= PARTIAL_WEEK_CUTOFF_DAYS;
    const headlineIdx = usePartial ? buckets.length - 1 : buckets.length - 2;

    const priorLoads = loads
      .slice(Math.max(0, headlineIdx - 4), headlineIdx)
      .reverse(); // calculateACWR expects most-recent-first
    const { acwr } = calculateACWR(loads[headlineIdx], priorLoads);

    const headlineWeek = buckets[headlineIdx];
    const chronicMiles = buckets
      .slice(Math.max(0, headlineIdx - 4), headlineIdx)
      .reduce((s, b) => s + b.miles, 0) /
      Math.max(1, Math.min(4, headlineIdx));
    const milesDeltaPct = chronicMiles > 0
      ? ((headlineWeek.miles - chronicMiles) / chronicMiles) * 100
      : 0;

    const facts: FactLine[] = [
      {
        key: "acwr",
        label: usePartial
          ? "Acute : chronic ratio"
          : "Acute : chronic ratio · last complete week",
        value: acwr.toFixed(2),
        delta: acwrBand(acwr),
        tone: acwrTone(acwr),
      },
      {
        key: "week_miles",
        label: usePartial
          ? `This week · ${daysIntoWeek} ${daysIntoWeek === 1 ? "day" : "days"} in`
          : "Last complete week",
        value: (Math.round(headlineWeek.miles * 10) / 10).toFixed(1),
        unit: " mi",
        tone: "neutral",
      },
      {
        key: "chronic_miles",
        label: "4-week average",
        value: (Math.round(chronicMiles * 10) / 10).toFixed(1),
        unit: " mi",
        delta: fmtPctDelta(milesDeltaPct),
        tone: Math.abs(milesDeltaPct) > 25 ? "watch" : "neutral",
      },
    ];

    // Monotony is persisted, not recomputed — the newest row inside the window.
    const latestMonotony = features
      .filter((f) => typeof f.monotony_7d === "number")
      .sort((a, b) => String(b.workout_date).localeCompare(String(a.workout_date)))[0];
    if (latestMonotony?.monotony_7d != null) {
      const m = Number(latestMonotony.monotony_7d);
      facts.push({
        key: "monotony",
        label: "Monotony · 7 day",
        value: (Math.round(m * 10) / 10).toFixed(1),
        tone: m >= 2.0 ? "watch" : "good",
      });
    }

    const missing: string[] = [];
    const withoutFeatures = logs.filter((l) => !featuresByLogId.has(l.id)).length;
    if (withoutFeatures > 0) {
      missing.push(
        `${withoutFeatures} of ${logs.length} runs used the fallback load estimate`,
      );
    }
    if (!usePartial) missing.push("current week too short to read; showing the last complete one");

    const seriesPoints: SeriesPoint[] = buckets.map((b) => ({
      x: b.label,
      y: Math.round(b.miles * 10) / 10,
      label: b.start.toISOString().slice(0, 10),
    }));

    return {
      facts,
      series: {
        kind: "bar",
        unit: "miles",
        invertY: false,
        band: null,
        points: seriesPoints,
      },
      coverage: {
        sessionsUsed: logs.length,
        windowDays,
        missing,
        confidence: nonEmpty.length >= 5 ? "high" : "moderate",
      },
      related: acwr > ACWR_HIGH
        ? ["quality_share", "hard_day_spacing", "niggle_timeline"]
        : ["quality_share", "volume_trend", "zone_trend"],
    };
  },
};
