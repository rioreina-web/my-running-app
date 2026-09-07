/**
 * Watches — the standing questions a coach keeps asking about the training.
 *
 * This is a different shape from `_shared/rules/`. A rule reacts to an event
 * ("2 sessions skipped this week"). A watch is surveillance: it asks the same
 * question of every athlete, continuously, and speaks up when the answer
 * turns. "How's she feeling over the last few weeks." "Is she running her
 * easy days easy." "Is that calf still talking."
 *
 * The domains below are Rio's, in his words, and explicitly not exhaustive —
 * the registry is meant to grow. Adding a watch is writing one pure function
 * and appending it to ALL_WATCHES.
 *
 * Three properties every watch holds to:
 *
 *   1. It reads from `athlete_state`, the assembled brain — never raw tables.
 *      If the signal isn't in state, the watch declares the gap rather than
 *      guessing (see `reads` and `WatchGap`).
 *   2. It computes in code. A watch never asks a model whether something is
 *      off; it decides, and the model only narrates the finding.
 *   3. It proposes from the closed five-move vocabulary and applies nothing.
 *      AI advises, never acts.
 */

import type { AdjustmentAction } from "../cause.ts";

// ─── Domains ─────────────────────────────────────────────────────────────────

/**
 * What a watch is about. Rio's framing: recovery, pace, niggles — "these
 * aren't the only ones, but these are stuff to look for in an athlete's
 * training." Extend deliberately; a domain is a category of coaching
 * attention, not a bucket for a stray metric.
 */
export const WATCH_DOMAINS = [
  "recovery", // how they're feeling, across days and weeks
  "pace", // discipline against their own zones
  "niggles", // body mentions and flare-ups
  "load", // volume and its rate of change
  "consistency", // whether the plan is actually being run
] as const;

export type WatchDomain = typeof WATCH_DOMAINS[number];

export type WatchSeverity = "info" | "low" | "med" | "high";
export type WatchConfidence = "low" | "medium" | "high";

// ─── Findings ────────────────────────────────────────────────────────────────

export interface WatchFinding {
  watch_id: string;
  domain: WatchDomain;
  severity: WatchSeverity;
  /** One line, the way a coach would open. No hedging, no metric-speak. */
  headline: string;
  /** The reasoning, in prose. Cites the numbers it used. */
  detail: string;
  /**
   * The specific numbers behind the call. Every claim in `detail` should be
   * traceable to one of these — the same discipline the daily read uses to
   * keep the model from inventing arithmetic.
   */
  evidence: string[];
  /** The move, from the closed vocabulary. Null when the finding is an
   *  observation rather than an ask. */
  suggested: AdjustmentAction | null;
  confidence: WatchConfidence;
  /** True when the right next step is a person's judgment, not a plan edit. */
  defer_to_human: boolean;
}

/**
 * What a watch says when it can't see. Distinct from "nothing's wrong" —
 * conflating the two is how a blind spot reads as an all-clear.
 */
export interface WatchGap {
  watch_id: string;
  domain: WatchDomain;
  /** What's missing, in plain terms the athlete or coach can act on. */
  gap: string;
}

export type WatchResult =
  | { kind: "finding"; finding: WatchFinding }
  | { kind: "gap"; gap: WatchGap }
  | { kind: "clear" };

// ─── Context ─────────────────────────────────────────────────────────────────

/**
 * The slice of `athlete_state` watches read.
 *
 * Deliberately structural rather than importing AthleteState wholesale: it
 * keeps every watch unit-testable from a small literal instead of a
 * 2,600-line state object, and it documents exactly which fields this layer
 * depends on.
 */
export interface WatchContext {
  athleteUserId: string;
  /** Reference "now" — pure tests pass a fixed date. */
  now: Date;

  /** Mood labels with dates, newest-first. From training_logs / check-ins. */
  moodHistory: Array<{ date: string; mood: string | null }>;

  /** athlete_state.load_distribution.zone_pct_7d — time-in-zone, last 7 days. */
  zonePct7d?: {
    easy: number;
    moderate: number;
    threshold: number;
    hard: number;
  } | null;
  /** athlete_state.load_distribution.zone_pct_28d equivalent, when available. */
  zonePct28d?: {
    easy: number;
    moderate: number;
    threshold: number;
    hard: number;
  } | null;

  /**
   * PaceEngine's easy band, seconds per mile. Never a hardcoded default —
   * paces come from the athlete's own data or the watch declares a gap.
   */
  easyBand?: { paceFast: number; paceSlow: number } | null;

  /**
   * The moderate band, same source. Used to tell drift from mislabelling:
   * a run typed easy that lands at steady pace or quicker isn't a drifting
   * easy day, it's a different session. Deriving that boundary from the
   * athlete's own zones beats any fixed seconds-per-mile margin.
   */
  moderateBand?: { paceFast: number; paceSlow: number } | null;

  /** Easy-labelled runs with their actual pace, newest-first. */
  easyRuns?: Array<{
    date: string;
    paceSecPerMile: number | null;
    workoutType: string;
    /** Needed to tell an easy day from a warmup fragment. */
    distanceMiles?: number | null;
  }> | null;

  /** athlete_state.niggle_recurrence. */
  niggles?: Array<{
    body_area: string;
    side: "left" | "right" | null;
    occurrences: number;
    first_seen: string;
    last_seen: string;
    worst_severity: string;
    status: "active" | "resolved";
    resolved_at: string | null;
  }> | null;

  /** Whether a quality session is on the calendar in the next few days. */
  upcomingQualityWithinDays?: number | null;
}

// ─── The watch ───────────────────────────────────────────────────────────────

export interface Watch {
  id: string;
  domain: WatchDomain;
  /** The coach's standing question, in plain English. This is the thing the
   *  coach reads when deciding whether the watch is worth having on. */
  question: string;
  /** Which context fields it depends on — surfaced in the portal so a dark
   *  watch is visibly dark rather than silently idle. */
  reads: readonly string[];
  evaluate: (ctx: WatchContext) => WatchResult;
}

/** Convenience constructors so evaluators read as prose. */
export const clear = (): WatchResult => ({ kind: "clear" });

export const gap = (
  watch_id: string,
  domain: WatchDomain,
  text: string,
): WatchResult => ({ kind: "gap", gap: { watch_id, domain, gap: text } });

export const finding = (f: WatchFinding): WatchResult => ({
  kind: "finding",
  finding: f,
});

// ─── Shared helpers ──────────────────────────────────────────────────────────

/**
 * Mood labels as a signed scale, for trend work only.
 *
 * The labels are the product's vocabulary (process-training-memo writes
 * them); this mapping exists so "how are they feeling over days or weeks"
 * can have a direction. `injured` and `struggling` share a floor on purpose —
 * the distinction matters for routing, not for the trend line.
 */
export const MOOD_SCORE: Readonly<Record<string, number>> = {
  energized: 2,
  positive: 1,
  neutral: 0,
  tired: -1,
  struggling: -2,
  injured: -2,
};

export function moodScore(label: string | null | undefined): number | null {
  if (!label) return null;
  const v = MOOD_SCORE[label.toLowerCase().trim()];
  return v === undefined ? null : v;
}

/** Whole days between two ISO dates. */
export function daysBetween(fromIso: string, to: Date): number {
  const from = new Date(fromIso + (fromIso.length === 10 ? "T00:00:00Z" : ""));
  return Math.floor((to.getTime() - from.getTime()) / 86_400_000);
}

/** M:SS per mile, for evidence strings. */
export function fmtPace(secPerMile: number): string {
  const s = Math.round(secPerMile);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
