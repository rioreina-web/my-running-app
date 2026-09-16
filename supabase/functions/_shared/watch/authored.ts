/**
 * Authored watches — a saved row becomes a Watch.
 *
 * The three watches in this directory are hand-written TypeScript. That was
 * the right way to prove the shape and the wrong way to ship a product: a
 * coach can't write a `.ts` file, and every new thing to look for shouldn't
 * need a deploy.
 *
 * This turns the shipped ones into templates. A row — metric, comparison,
 * number, window, how many times — becomes a `Watch` with the same interface
 * as the hardcoded ones, which means it flows through `runWatches` and
 * `backtestWatch` for free. Nothing downstream knows or cares whether a watch
 * came from code or from a person typing a sentence.
 *
 * What stays closed: the metric list. A person picks what to measure from
 * `METRICS`; they never describe a new measurement in prose and have the
 * system try to compute it. That boundary is what keeps a watch checkable.
 */

import { METRICS, type MetricId, type MetricReading } from "./metrics.ts";
import {
  clear,
  finding,
  gap,
  type Watch,
  type WatchContext,
  type WatchResult,
  type WatchSeverity,
} from "./types.ts";
import type { AdjustmentAction } from "../cause.ts";

export type Comparison = "above" | "below";

/**
 * The saved row. Mirrors the `watches` table.
 *
 * `min_observations` is the "so one hill doesn't count" control: how many
 * readings in the window must breach before the watch says anything. It's the
 * difference between a watch that fires on a single warm Tuesday and one that
 * fires on a habit.
 */
export interface WatchRow {
  id: string;
  /** What the person called it. Shown in the list and on the fire. */
  label: string;
  metric: MetricId;
  comparison: Comparison;
  threshold: number;
  window_days: number;
  min_observations: number;
  /** Held by the dispatcher and the backtest, not by evaluate(). */
  cooldown_days: number;
  severity: WatchSeverity;
  /** The move to propose, or null when the watch is an observation. */
  suggested_action: AdjustmentAction | null;
  /** What the athlete or coach originally typed, kept as the record of intent. */
  source_sentence: string | null;
  enabled: boolean;
}

function breaches(r: MetricReading, cmp: Comparison, threshold: number): boolean {
  return cmp === "above" ? r.value > threshold : r.value < threshold;
}

/** "over 145 bpm" / "under 7:03/mi" */
export function describeCondition(row: WatchRow): string {
  const m = METRICS[row.metric];
  const word = row.comparison === "above" ? "over" : "under";
  return `${m.label.toLowerCase()} ${word} ${m.format(row.threshold)}`;
}

/**
 * Build a Watch from a saved row.
 *
 * The evaluator is deliberately dull — read, compare, count, speak. Every
 * judgment that could be argued with lives in the row, where a person put it
 * and where a person can change it.
 */
export function watchFromRow(row: WatchRow): Watch {
  const metric = METRICS[row.metric];

  return {
    id: row.id,
    domain: metric.domain,
    // The row's own words where there are any; otherwise a readable fallback.
    question: row.source_sentence?.trim()
      ? `${row.source_sentence.trim().replace(/\?*$/, "")}?`
      : `Is ${describeCondition(row)}?`,
    reads: metric.reads,

    evaluate(ctx: WatchContext): WatchResult {
      if (!row.enabled) return clear();

      const readings = metric.read(ctx, row.window_days);

      // Null = this athlete's data can't serve the metric at all. That is a
      // different sentence from "nothing has breached", and conflating them
      // would let a missing heart-rate monitor read as a clean bill of health.
      if (readings === null) {
        return gap(
          row.id,
          metric.domain,
          `Can't run "${row.label}" — no ${metric.label.toLowerCase()} recorded for this athlete.`,
        );
      }
      if (readings.length === 0) {
        return gap(
          row.id,
          metric.domain,
          `Nothing to measure for "${row.label}" in the last ${row.window_days} days.`,
        );
      }

      const hits = readings.filter((r) => breaches(r, row.comparison, row.threshold));
      if (hits.length < row.min_observations) return clear();

      const word = row.comparison === "above" ? "over" : "under";
      const worst = hits.reduce((a, b) =>
        row.comparison === "above" ? (b.value > a.value ? b : a) : (b.value < a.value ? b : a)
      );

      const evidence = [
        `watching: ${describeCondition(row)}`,
        `${hits.length} of ${readings.length} readings in the last ${row.window_days} days`,
        ...hits.slice(0, 3).map((h) =>
          `${h.date}: ${metric.format(h.value)} — ${h.detail}`
        ),
      ];

      return finding({
        watch_id: row.id,
        domain: metric.domain,
        severity: row.severity,
        headline: row.label,
        detail:
          `${hits.length} of the last ${readings.length} readings came in ${word} ` +
          `${metric.format(row.threshold)}, the furthest being ${metric.format(worst.value)} ` +
          `on ${worst.date}.` +
          (row.min_observations > 1
            ? ` This watch needs ${row.min_observations} before it speaks, so it's a pattern rather than one session.`
            : ""),
        evidence,
        suggested: row.suggested_action,
        confidence: readings.length >= 5 ? "high" : "medium",
        // An authored watch proposes; the person who wrote it decides.
        defer_to_human: row.suggested_action === null,
      });
    },
  };
}

/**
 * Starting points, matching the prototype's "or start from one of these" list.
 *
 * Thresholds here are placeholders on purpose — nobody should save one of
 * these without running it through the backtest first, which is exactly the
 * flow that makes the number theirs rather than mine.
 */
export const WATCH_TEMPLATES: ReadonlyArray<Omit<WatchRow, "id" | "enabled">> = [
  {
    label: "Heart rate ceiling on easy runs",
    metric: "easy_run_hr",
    comparison: "above",
    threshold: 145,
    window_days: 14,
    min_observations: 2,
    cooldown_days: 7,
    severity: "med",
    suggested_action: null,
    source_sentence: null,
  },
  {
    label: "Easy days run too quick",
    metric: "easy_run_pace",
    comparison: "below",
    threshold: 480,
    window_days: 14,
    min_observations: 2,
    cooldown_days: 7,
    severity: "low",
    suggested_action: null,
    source_sentence: null,
  },
  {
    label: "Not enough of the week is easy",
    metric: "easy_share",
    comparison: "below",
    threshold: 70,
    window_days: 7,
    min_observations: 1,
    cooldown_days: 7,
    severity: "low",
    suggested_action: null,
    source_sentence: null,
  },
  {
    label: "A run of low-energy logs",
    metric: "mood_level",
    comparison: "below",
    threshold: 0,
    window_days: 10,
    min_observations: 3,
    cooldown_days: 7,
    severity: "med",
    suggested_action: "reduce_volume",
    source_sentence: null,
  },
  {
    label: "Same niggle mentioned repeatedly",
    metric: "niggle_mentions",
    comparison: "above",
    threshold: 2,
    window_days: 42,
    min_observations: 1,
    cooldown_days: 10,
    severity: "high",
    suggested_action: "insert_rest",
    source_sentence: null,
  },
  {
    label: "Too long without a full rest day",
    metric: "days_without_rest",
    comparison: "above",
    threshold: 10,
    window_days: 28,
    min_observations: 1,
    cooldown_days: 14,
    severity: "low",
    suggested_action: "insert_rest",
    source_sentence: null,
  },
  {
    label: "Weekly mileage jumped hard",
    metric: "weekly_mileage_jump",
    comparison: "above",
    threshold: 12,
    window_days: 28,
    min_observations: 1,
    cooldown_days: 7,
    severity: "med",
    suggested_action: "cap_volume",
    source_sentence: null,
  },
];
