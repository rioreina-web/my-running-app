/**
 * `current_fitness` — "How fit am I right now?"
 *
 * Principle V (Adaptation). THE SYNTHESIS CHIP: one card that answers the
 * question every other analyzer answers a slice of. Capacity (what could I
 * race today) + trajectory (building or eroding) + the confidence that makes
 * either claim honest. Assembled per CURRENT-FITNESS-APPLY.md — the three
 * questions are answered SEPARATELY and never blended into one score.
 *
 * WHAT IT READS, AND WHY ONLY THESE:
 *   • `athlete_state.fitness_prediction` — capacity. State, not a recompute:
 *     Ask must never disagree with the Trends tile.
 *   • `athlete_state.fitness_signal`     — trajectory (EF trend, decoupling).
 *     Only threshold + easy buckets: interval was retired from EF 2026-08-15
 *     (short reps never reach an HR plateau — measured; see fitnessSignal.ts).
 *   • `workout_features.rep_signal`      — the latest rep-shape read, the one
 *     per-session signal state doesn't carry. Reads the PERSISTED row; never
 *     touches `external_streams` (the app's #1 cost).
 *
 * WHAT IT REFUSES TO DO:
 *   • No blended score. Capacity is a time; trajectory is a direction; they
 *     are separate facts on one card.
 *   • No readiness. Push/pull is the v1.5 Recovery pillar — a chip that hints
 *     "you should/shouldn't train today" violates hard rule #2.
 *   • Load and mood never touch capacity. TLS shades believability at most;
 *     that logic lives in the state builders, not here.
 *   • A rep-signal verdict withheld at LOW confidence stays withheld here.
 *     This analyzer surfaces the withholding as a fact (`tone: "watch"`),
 *     it does not second-guess the gate.
 */

import { fetchAthleteState } from "./athleteState.ts";
import {
  fmtPaceSec,
  fmtPctDelta,
  type Analyzer,
  type AnalyzerCtx,
  type AnalyzerParams,
  type AnalyzerResult,
  type Confidence,
  type FactLine,
} from "./types.ts";

// ── Local shapes ─────────────────────────────────────────────────────────

/** The persisted repSignal payload (workout_features.rep_signal, v1). */
interface RepSignalRow {
  training_log_id?: string | null;
  rep_signal?: {
    v?: number;
    score?: {
      scored?: boolean;
      reason?: string | null;
      repsUsable?: number;
      level?: number | null;
      recovery?: { total?: number; direction?: string } | null;
      carryover?: { total?: number; direction?: string } | null;
      pace?: { total?: number; direction?: string } | null;
      hrCost?: { total?: number; direction?: string } | null;
      finalRep?: { paceSecPerMile?: number; close?: string } | null;
      flags?: string[];
      confidence?: string;
      hrSource?: string;
      verdict?: { key?: string; label?: string } | null;
    } | null;
  } | null;
  workout_date?: string | null;
}

function fmtRaceSeconds(total: number): string {
  const s = Math.round(total);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(sec).padStart(2, "0")}`
    : `${m}:${String(sec).padStart(2, "0")}`;
}

function tierToConfidence(tier: string | null | undefined): Confidence {
  switch ((tier ?? "").toLowerCase()) {
    case "high": return "high";
    case "medium":
    case "moderate": return "moderate";
    default: return "low";
  }
}

const worse = (a: Confidence, b: Confidence): Confidence => {
  const rank: Record<Confidence, number> = { high: 3, moderate: 2, low: 1 };
  return rank[a] <= rank[b] ? a : b;
};

// ── The analyzer ─────────────────────────────────────────────────────────

export const currentFitness: Analyzer = {
  id: "current_fitness",
  label: "How fit am I right now?",
  group: "adaptation",
  params: {},

  async run(_params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult> {
    const state = await fetchAthleteState(ctx.supabase, ctx.userId);
    const prediction = state?.fitness_prediction ?? null;
    const signal = state?.fitness_signal ?? null;

    // Latest persisted rep-shape read — one narrow select, newest first.
    let repRow: RepSignalRow | null = null;
    try {
      const { data } = await ctx.supabase
        .from("workout_features")
        .select("training_log_id, workout_date, rep_signal")
        .eq("user_id", ctx.userId)
        .not("rep_signal", "is", null)
        .order("workout_date", { ascending: false })
        .limit(1);
      repRow = (data?.[0] as RepSignalRow | undefined) ?? null;
    } catch (_) {
      repRow = null; // additive signal — absence is a coverage note, not an error
    }

    const facts: FactLine[] = [];
    const missing: string[] = [];

    // ── Capacity — a time + a tier, never blended with the rest ──
    // "10K", not "10k" — the stored key is uppercase (athlete-state.ts writes
    // mile / 5K / 10K / half / marathon). `RaceRangeKey` now makes a typo a
    // compile error rather than a silently blank capacity line.
    const tenK = prediction?.ranges?.["10K"]?.point ?? null;
    const tier = prediction?.confidence_tier ?? null;
    if (tenK != null && tenK > 0) {
      facts.push({
        key: "capacity_10k",
        label: "Capacity · 10K today",
        value: fmtRaceSeconds(tenK),
        tone: "neutral",
      });
      facts.push({
        key: "capacity_tier",
        label: "Capacity confidence",
        value: (tier ?? "low").toUpperCase(),
        tone: tierToConfidence(tier) === "high" ? "good" : "neutral",
      });
    } else {
      missing.push("no fitness prediction on file yet");
    }

    // ── Trajectory — EF direction from the surviving buckets ──
    const efBuckets = (signal?.efficiency ?? []).filter((b) =>
      b != null && b.ef_recent != null &&
      (b.bucket === "threshold" || b.bucket === "easy")
    );
    const lead = efBuckets.find((b) => b.bucket === "threshold") ?? efBuckets[0] ?? null;
    if (lead && lead.ef_delta_pct != null) {
      const dir = (lead.direction ?? "flat").toLowerCase();
      facts.push({
        key: "trajectory_ef",
        label: lead.bucket === "threshold"
          ? "Trajectory · threshold efficiency"
          : "Trajectory · easy-run efficiency",
        value: dir,
        delta: fmtPctDelta(lead.ef_delta_pct),
        tone: dir === "improving" ? "good" : dir === "declining" ? "watch" : "neutral",
      });
    } else {
      missing.push("no efficiency trend (needs HR on both windows)");
    }

    // ── Latest rep-shape read — the newest instrument ──
    const score = repRow?.rep_signal?.score ?? null;
    if (score?.scored) {
      if (score.verdict?.label) {
        facts.push({
          key: "rep_read",
          label: `Last rep session${repRow?.workout_date ? ` · ${repRow.workout_date}` : ""}`,
          value: score.verdict.label,
          tone: score.verdict.key === "inside_capacity" ? "good"
            : score.verdict.key === "over_the_edge" ? "watch" : "neutral",
        });
      } else {
        // Verdict withheld at LOW — surface the withholding, honestly, and
        // name the sensor when the metadata can: wrist optical lags exactly
        // where hrr60 measures (post-effort recovery).
        facts.push({
          key: "rep_read_withheld",
          label: "Last rep session",
          value: score.hrSource === "optical"
            ? "read withheld — wrist HR lags on recovery; a chest strap would make this readable"
            : "read withheld — sensor confidence low",
          tone: "watch",
        });
      }
      if (score.level != null) {
        facts.push({
          key: "rep_recovery_level",
          label: "Recovery, first rep (hrr60)",
          value: String(score.level),
          unit: "bpm",
          tone: "neutral",
        });
      }
      if (score.finalRep?.close === "fast" && score.finalRep.paceSecPerMile) {
        facts.push({
          key: "rep_close",
          label: "Closed the session",
          value: fmtPaceSec(score.finalRep.paceSecPerMile),
          unit: "/mi",
          delta: "faster than the set",
          tone: "good",
        });
      }
    } else if (score?.reason) {
      missing.push(`latest rep session not scoreable: ${score.reason}`);
    } else {
      missing.push("no rep-shape read persisted yet");
    }

    // ── Coverage — worst of the parts, never better than capacity's tier ──
    const confidence = worse(
      tierToConfidence(tier),
      lead ? tierToConfidence(lead.confidence) : "low",
    );

    if (facts.length === 0) {
      return {
        facts: [],
        coverage: { sessionsUsed: 0, windowDays: 84, missing, confidence: "low" },
        related: ["efficiency", "race_projection"],
        empty: {
          eyebrow: "Not enough signal yet",
          nudge:
            "A fitness read needs a few weeks of runs with heart rate — and " +
            "a race or hard session to anchor it. Keep logging; this fills in on its own.",
        },
      };
    }

    return {
      title: null,
      facts,
      series: null,
      coverage: {
        sessionsUsed: (prediction?.workout_count ?? 0),
        windowDays: 84,
        missing,
        confidence,
      },
      related: ["efficiency", "race_projection", "decoupling"],
    };
  },
};
