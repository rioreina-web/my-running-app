/**
 * The metric registry — what a watch is allowed to measure.
 *
 * A watch is "a thing to look for in training." Once watches are authored by
 * people rather than shipped as code, the *measurable* half has to be a closed
 * list: a person picks a metric, a comparison and a number, and the app can
 * always check it. That's the same discipline as reschedule-plan's closed
 * workout library — the model can help someone phrase a watch, but it can
 * never invent something to measure.
 *
 * Each metric knows three things: what it means in English, how to pull the
 * numbers out of a WatchContext, and — critically — how to say "I can't see
 * this for this athlete." That last one is why `read()` returns null rather
 * than an empty array when the underlying data is absent: an athlete with no
 * heart-rate monitor must produce a gap, not a silent all-clear.
 */

import { daysBetween, fmtPace, type WatchContext, type WatchDomain } from "./types.ts";

export const METRIC_IDS = [
  "easy_run_hr",
  "easy_run_pace",
  "easy_share",
  "mood_level",
  "niggle_mentions",
  "days_without_rest",
  "weekly_mileage_jump",
] as const;

export type MetricId = typeof METRIC_IDS[number];

export type MetricUnit = "bpm" | "sec_per_mile" | "percent" | "count" | "days";

/** One observation the metric produced — a value with the day it came from. */
export interface MetricReading {
  date: string;
  value: number;
  /** Short human context for the evidence line, e.g. "8.0mi easy". */
  detail: string;
}

export interface Metric {
  id: MetricId;
  /** How it reads in the picker. */
  label: string;
  unit: MetricUnit;
  domain: WatchDomain;
  /** Context fields it depends on — surfaced so a dark metric is visible. */
  reads: readonly string[];
  /**
   * Whether a higher number is the concerning direction. Used to phrase the
   * default comparison sensibly when someone builds a watch from a template.
   */
  concernWhen: "above" | "below";
  /**
   * Readings inside the window, or null when this athlete's data can't serve
   * the metric at all. Null means gap; empty array means "nothing to measure
   * yet", which is also a gap but a different sentence.
   */
  read: (ctx: WatchContext, windowDays: number) => MetricReading[] | null;
  /** Render a threshold in this metric's units — "145 bpm", "7:03/mi". */
  format: (value: number) => string;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

function inWindow<T extends { date: string }>(
  rows: readonly T[] | null | undefined,
  ctx: WatchContext,
  windowDays: number,
): T[] {
  return (rows ?? []).filter((r) => {
    const age = daysBetween(r.date, ctx.now);
    return age >= 0 && age <= windowDays;
  });
}

/** Sum of distance per ISO week-start, newest week first. */
function weeklyMiles(
  runs: ReadonlyArray<{ date: string; distanceMiles: number | null }>,
): Array<{ weekStart: string; miles: number }> {
  const buckets = new Map<string, number>();
  for (const r of runs) {
    if (r.distanceMiles == null) continue;
    const d = new Date(`${r.date}T00:00:00Z`);
    // Monday-start weeks, matching the rest of the codebase.
    const dow = (d.getUTCDay() + 6) % 7;
    const start = new Date(d.getTime() - dow * 86_400_000).toISOString().slice(0, 10);
    buckets.set(start, (buckets.get(start) ?? 0) + r.distanceMiles);
  }
  return [...buckets.entries()]
    .map(([weekStart, miles]) => ({ weekStart, miles }))
    .sort((a, b) => (a.weekStart < b.weekStart ? 1 : -1));
}

/** Easy runs long enough to be easy days, not warmup fragments. */
const MIN_EASY_DISTANCE_MI = 3;

function realEasyRuns(ctx: WatchContext, windowDays: number) {
  return inWindow(ctx.easyRuns, ctx, windowDays).filter(
    (r) => r.distanceMiles == null || r.distanceMiles >= MIN_EASY_DISTANCE_MI,
  );
}

// ─── The registry ────────────────────────────────────────────────────────────

export const METRICS: Readonly<Record<MetricId, Metric>> = {
  easy_run_hr: {
    id: "easy_run_hr",
    label: "Average heart rate on easy runs",
    unit: "bpm",
    domain: "recovery",
    reads: ["easyRuns.avgHeartRate"],
    concernWhen: "above",
    format: (v) => `${Math.round(v)} bpm`,
    read: (ctx, windowDays) => {
      const runs = realEasyRuns(ctx, windowDays);
      const withHr = runs.filter((r) => typeof r.avgHeartRate === "number");
      // No HR anywhere = this athlete can't run this watch at all.
      if (withHr.length === 0) return null;
      return withHr.map((r) => ({
        date: r.date,
        value: r.avgHeartRate as number,
        detail: `${r.distanceMiles?.toFixed(1) ?? "?"}mi ${r.workoutType}`,
      }));
    },
  },

  easy_run_pace: {
    id: "easy_run_pace",
    label: "Pace on easy runs",
    unit: "sec_per_mile",
    domain: "pace",
    reads: ["easyRuns.paceSecPerMile", "easyBand"],
    // Faster than the ceiling is the concern, and faster = fewer seconds.
    concernWhen: "below",
    format: (v) => `${fmtPace(v)}/mi`,
    read: (ctx, windowDays) => {
      const runs = realEasyRuns(ctx, windowDays).filter(
        (r) => r.paceSecPerMile !== null,
      );
      if (runs.length === 0) return null;
      return runs.map((r) => ({
        date: r.date,
        value: r.paceSecPerMile as number,
        detail: `${r.distanceMiles?.toFixed(1) ?? "?"}mi ${r.workoutType}`,
      }));
    },
  },

  easy_share: {
    id: "easy_share",
    label: "Share of the week's time spent easy",
    unit: "percent",
    domain: "load",
    reads: ["zonePct7d.easy"],
    concernWhen: "below",
    format: (v) => `${Math.round(v)}%`,
    read: (ctx) => {
      const share = ctx.zonePct7d?.easy;
      if (typeof share !== "number") return null;
      // A single current-week reading — this one is a snapshot, not a series.
      return [{
        date: ctx.now.toISOString().slice(0, 10),
        value: share,
        detail: "last 7 days",
      }];
    },
  },

  mood_level: {
    id: "mood_level",
    label: "How they've been feeling",
    unit: "count",
    domain: "recovery",
    reads: ["moodHistory"],
    concernWhen: "below",
    format: (v) => `${v.toFixed(1)} on a −2…+2 scale`,
    read: (ctx, windowDays) => {
      const scored = inWindow(ctx.moodHistory, ctx, windowDays)
        .map((m) => ({ date: m.date, mood: m.mood }))
        .filter((m) => m.mood);
      if (scored.length === 0) return null;
      const SCORE: Record<string, number> = {
        energized: 2, positive: 1, neutral: 0, tired: -1, struggling: -2, injured: -2,
      };
      return scored
        .map((m) => ({
          date: m.date,
          value: SCORE[(m.mood as string).toLowerCase()] ?? 0,
          detail: m.mood as string,
        }))
        .filter((r) => r.value !== undefined);
    },
  },

  niggle_mentions: {
    id: "niggle_mentions",
    label: "Times the same body area has come up",
    unit: "count",
    domain: "niggles",
    reads: ["niggles"],
    concernWhen: "above",
    format: (v) => `${Math.round(v)} mention${Math.round(v) === 1 ? "" : "s"}`,
    read: (ctx, windowDays) => {
      if (ctx.niggles == null) return null;
      const active = ctx.niggles.filter(
        (n) => n.status === "active" && daysBetween(n.first_seen, ctx.now) <= windowDays,
      );
      return active.map((n) => ({
        date: n.last_seen,
        value: n.occurrences,
        detail: n.side ? `${n.side} ${n.body_area}` : n.body_area,
      }));
    },
  },

  days_without_rest: {
    id: "days_without_rest",
    label: "Longest stretch without a full day off",
    unit: "days",
    domain: "load",
    reads: ["allRuns"],
    concernWhen: "above",
    format: (v) => `${Math.round(v)} day${Math.round(v) === 1 ? "" : "s"}`,
    read: (ctx, windowDays) => {
      const runs = inWindow(ctx.allRuns, ctx, windowDays);
      if (runs.length === 0) return null;
      // Distinct days with any running in them.
      const ranDays = new Set(runs.map((r) => r.date));
      let streak = 0;
      const readings: MetricReading[] = [];
      for (let i = windowDays; i >= 0; i--) {
        const day = new Date(ctx.now.getTime() - i * 86_400_000)
          .toISOString().slice(0, 10);
        if (ranDays.has(day)) {
          streak++;
          readings.push({ date: day, value: streak, detail: `${streak} straight` });
        } else {
          streak = 0;
        }
      }
      return readings;
    },
  },

  weekly_mileage_jump: {
    id: "weekly_mileage_jump",
    label: "Week-over-week mileage increase",
    unit: "percent",
    domain: "load",
    reads: ["allRuns"],
    concernWhen: "above",
    format: (v) => `${v > 0 ? "+" : ""}${Math.round(v)}%`,
    read: (ctx, windowDays) => {
      const weeks = weeklyMiles(inWindow(ctx.allRuns, ctx, windowDays + 7));
      if (weeks.length < 2) return null;
      const out: MetricReading[] = [];
      for (let i = 0; i < weeks.length - 1; i++) {
        const cur = weeks[i], prev = weeks[i + 1];
        if (prev.miles <= 0) continue;
        out.push({
          date: cur.weekStart,
          value: ((cur.miles - prev.miles) / prev.miles) * 100,
          detail: `${cur.miles.toFixed(0)}mi vs ${prev.miles.toFixed(0)}mi`,
        });
      }
      return out;
    },
  },
};

export function isMetricId(v: unknown): v is MetricId {
  return typeof v === "string" && (METRIC_IDS as readonly string[]).includes(v);
}
