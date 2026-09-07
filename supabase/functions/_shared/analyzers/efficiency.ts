/**
 * `efficiency` — "Metres per heartbeat. Is the same work costing less?"
 *
 * Principle V (Adaptation). Reads `athlete_state.fitness_signal.efficiency`,
 * computed by `fitnessSignal.ts` — one entry per effort bucket (easy /
 * threshold / interval), each with a recent window against a baseline window.
 *
 * The metric is efficiency factor: speed per heartbeat. Same pace at a lower
 * heart rate, or a faster pace at the same heart rate, both read as fitter.
 * It is the cleanest fitness signal available without a lab, and it is the one
 * that survives a hot summer — which is exactly why it deserves its own chip
 * rather than living inside a pace trend.
 *
 * TWO HONESTY CONSTRAINTS, both inherited from the module:
 *
 *  1. **It needs heart rate on both windows.** An athlete who ran without a
 *     strap for a month has no signal, and the analyzer must say so rather
 *     than compare a thin recent window to a thick baseline.
 *  2. **A small delta is not a trend.** Efficiency moves a couple of percent
 *     on noise alone, so anything inside ±2% is reported as flat regardless
 *     of sign. The stored `direction` already applies this; we surface it
 *     rather than re-deriving a verdict from the number.
 */

import { fetchAthleteState, type EfficiencyBucket } from "./athleteState.ts";
import {
  fmtPaceSec,
  fmtPctDelta,
  fmtSecDelta,
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerParams,
  type AnalyzerResult,
  type Confidence,
  type FactLine,
} from "./types.ts";

const BUCKETS = ["easy", "threshold", "interval"];

const BUCKET_LABEL: Record<string, string> = {
  easy: "Easy running",
  threshold: "Threshold work",
  interval: "Interval work",
};

function tierToConfidence(tier: string | null | undefined): Confidence {
  switch ((tier ?? "").toLowerCase()) {
    case "high": return "high";
    case "medium":
    case "moderate": return "moderate";
    default: return "low";
  }
}

/** Direction → tone. "declining" efficiency is a watch, never a "bad". */
function directionTone(direction: string | null | undefined): "good" | "watch" | "neutral" {
  switch ((direction ?? "").toLowerCase()) {
    case "improving": return "good";
    case "declining": return "watch";
    default: return "neutral";
  }
}

/** The bucket with the most recent samples — the one there's most to say about. */
function pickBucket(
  buckets: EfficiencyBucket[],
  requested: string | null,
): EfficiencyBucket | null {
  if (requested) {
    return buckets.find((b) => (b.bucket ?? "").toLowerCase() === requested) ?? null;
  }
  const ranked = [...buckets].sort(
    (a, b) => Number(b.recent_samples ?? 0) - Number(a.recent_samples ?? 0),
  );
  return ranked[0] ?? null;
}

export const efficiency: Analyzer = {
  id: "efficiency",
  label: "Metres per heartbeat",
  group: "adaptation",
  params: {
    effort: {
      type: "string",
      enum: BUCKETS,
      optional: true,
      describe:
        "Which effort band to read. Omit to use the one with the most recent sessions.",
    },
  },

  async run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const state = await fetchAthleteState(ctx.supabase, ctx.userId);
    const signal = state?.fitness_signal;
    const buckets = (signal?.efficiency ?? []).filter(
      (b): b is EfficiencyBucket => b != null && b.ef_recent != null,
    );

    if (buckets.length === 0) {
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays: 0, missing: [], confidence: "low" },
        related: ["zone_trend", "decoupling", "load_balance"],
        empty: {
          eyebrow: "No heart-rate signal yet",
          nudge:
            "Metres per heartbeat needs heart rate on both a recent stretch and a baseline before it means anything. Runs recorded with a strap fill this in.",
          cta: null,
        },
      };
    }

    const requested = typeof params.effort === "string" ? params.effort : null;
    const b = pickBucket(buckets, requested);

    if (!b) {
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays: 0, missing: [], confidence: "low" },
        related: ["efficiency", "zone_trend"],
        empty: {
          eyebrow: `No ${requested ?? "matching"} sessions with heart rate`,
          nudge:
            "That effort band has no sessions with heart rate in the window. The other bands may still read.",
          cta: null,
        },
      };
    }

    const label = BUCKET_LABEL[(b.bucket ?? "").toLowerCase()] ?? (b.bucket ?? "Running");
    const deltaPct = Number(b.ef_delta_pct ?? 0);
    const tone = directionTone(b.direction);

    const facts: FactLine[] = [
      {
        key: "ef_recent",
        label: `Efficiency · ${label}, recent`,
        value: Number(b.ef_recent).toFixed(2),
        delta: isFinite(deltaPct) && deltaPct !== 0 ? fmtPctDelta(deltaPct) : "flat",
        tone,
      },
      {
        key: "ef_baseline",
        label: `Efficiency · baseline${b.baseline_days ? `, ${b.baseline_days} days` : ""}`,
        value: Number(b.ef_baseline ?? 0).toFixed(2),
        tone: "neutral",
      },
    ];

    // Pace and HR are what the efficiency number is made of. Showing them
    // separately is what lets the athlete see WHICH side moved — a slower pace
    // at the same heart rate reads very differently from the same pace at a
    // higher one, and the ratio alone hides that.
    if (b.pace_recent_sec != null && b.pace_baseline_sec != null) {
      const paceDelta = Number(b.pace_recent_sec) - Number(b.pace_baseline_sec);
      facts.push({
        key: "pace",
        label: "Pace at that effort",
        value: fmtPaceSec(Number(b.pace_recent_sec)),
        unit: "/mi",
        delta: fmtSecDelta(paceDelta),
        tone: paceDelta < -2 ? "good" : paceDelta > 2 ? "watch" : "neutral",
      });
    }

    if (b.hr_recent != null && b.hr_baseline != null) {
      const hrDelta = Number(b.hr_recent) - Number(b.hr_baseline);
      facts.push({
        key: "hr",
        label: "Heart rate at that effort",
        value: String(Math.round(Number(b.hr_recent))),
        unit: " bpm",
        delta: hrDelta === 0
          ? "same"
          : `${hrDelta < 0 ? "−" : "+"}${Math.abs(Math.round(hrDelta))}`,
        tone: hrDelta < -1 ? "good" : hrDelta > 2 ? "watch" : "neutral",
      });
    }

    const recentN = Number(b.recent_samples ?? 0);
    const baselineN = Number(b.baseline_samples ?? 0);
    const missing: string[] = [];
    if (recentN > 0 && recentN < 4) {
      missing.push(`only ${recentN} recent ${recentN === 1 ? "session" : "sessions"} with heart rate`);
    }
    if (baselineN > 0 && recentN > 0 && baselineN < recentN) {
      missing.push("baseline is thinner than the recent window");
    }

    return {
      title: `Metres per heartbeat · ${label.toLowerCase()}`,
      facts,
      series: null,
      coverage: {
        sessionsUsed: recentN + baselineN,
        windowDays: Number(signal?.window_days ?? b.baseline_days ?? 0),
        missing,
        confidence: tierToConfidence(b.confidence),
      },
      related: tone === "watch"
        ? ["decoupling", "heat_effect", "load_balance"]
        : ["decoupling", "zone_trend", "race_projection"],
    };
  },
};

/**
 * `decoupling` — "Is my heart rate drifting less than it used to?"
 *
 * Same source block, different question. Decoupling is the percentage of
 * efficiency lost from the first half of a run to the second: the durability
 * signal. Falling decoupling means the aerobic engine is holding together
 * later into the effort, which is the thing a marathoner is actually buying
 * with all those long runs.
 *
 * Lives in this file because it reads the same `fitness_signal` block and
 * splitting it would mean two fetches of one row.
 */
export const decoupling: Analyzer = {
  id: "decoupling",
  label: "Am I decoupling less?",
  group: "durability",
  params: {},

  async run(_params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const state = await fetchAthleteState(ctx.supabase, ctx.userId);
    const d = state?.fitness_signal?.decoupling;

    if (!d || d.recent_pct == null || d.baseline_pct == null) {
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays: 0, missing: [], confidence: "low" },
        related: ["efficiency", "zone_trend"],
        empty: {
          eyebrow: "No drift signal yet",
          nudge:
            "Decoupling compares the first half of a run against the second, so it needs heart rate across a few longer efforts before it reads.",
          cta: null,
        },
      };
    }

    const recent = Number(d.recent_pct);
    const baseline = Number(d.baseline_pct);
    const delta = recent - baseline;
    const recentN = Number(d.recent_samples ?? 0);
    const baselineN = Number(d.baseline_samples ?? 0);

    const facts: FactLine[] = [
      {
        key: "decoupling_recent",
        label: "Decoupling · recent",
        value: recent.toFixed(1),
        unit: "%",
        // Less drift is the good direction.
        delta: `${delta < 0 ? "−" : "+"}${Math.abs(delta).toFixed(1)}`,
        tone: delta < -0.5 ? "good" : delta > 1 ? "watch" : "neutral",
      },
      {
        key: "decoupling_baseline",
        label: "Decoupling · baseline",
        value: baseline.toFixed(1),
        unit: "%",
        tone: "neutral",
      },
    ];

    const missing: string[] = [];
    if (recentN > 0 && recentN < 3) {
      missing.push(`only ${recentN} recent ${recentN === 1 ? "run" : "runs"} readable for drift`);
    }

    return {
      facts,
      series: null,
      coverage: {
        sessionsUsed: recentN + baselineN,
        windowDays: Number(state?.fitness_signal?.window_days ?? 0),
        missing,
        confidence: recentN >= 4 ? "high" : recentN >= 2 ? "moderate" : "low",
      },
      related: ["efficiency", "heat_effect", "zone_trend"],
    };
  },
};
