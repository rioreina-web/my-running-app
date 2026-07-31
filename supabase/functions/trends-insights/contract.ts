/**
 * trends-insights — card contract + detector context.
 *
 * The narrative-trend surface ("What the chart shows", v2 / "Trends 2").
 * Every detector is a PURE function `(ctx: DetectCtx) => TrendCard` — no IO,
 * no LLM, no `Date.now()`. `index.ts` assembles `ctx` once and hands the
 * same object to every detector; `detect.ts` filters + sorts the result.
 *
 * Contract is straight from `docs/specs/trends-insights-plan-2026-07-23.md`:
 *   { id, group, status, headline, body, evidence, confidence }
 *
 * House rules encoded here (see the plan §3 / §7):
 *   • Range + confidence, never false precision → `confidence` is required.
 *   • Absence is honest → `quiet` is a first-class status with real copy.
 *   • Detection, not diagnosis → detectors emit observation only; the
 *     BANNED_TERMS lint (detectorsA.test.ts) fails the build on prose drift.
 *   • Verbatim niggles → any body mention in copy is the athlete's own words.
 */

import type { TrendsWeekOut, TrendsDayOut, TimelineMention } from "../trends-timeline/timeline.ts";
import type { StreamRun } from "./streams.ts";

// ─── Card shape ────────────────────────────────────────────────────────

export type TrendGroup = "A" | "B" | "C";

/**
 * hidden → below the data gate; never leaves the server.
 * quiet  → gate met, no pattern → the honest "no-pattern" sentence.
 * active → a pattern fired.
 */
export type TrendStatus = "hidden" | "quiet" | "active";

export type Confidence = "low" | "medium" | "high";

export interface Evidence {
  /** Week label the point belongs to ("May 26"). */
  week: string;
  /** The plotted number (miles, sec/mi, …). */
  value: number;
  /** Optional short tag ("mi", "key pace", the body-area label). */
  label?: string;
}

/**
 * The FULL ordered series behind a card, so the client can draw a real
 * mini-chart (the mockup's 12-week line) instead of a 2-point stub from
 * `evidence`. Optional and additive: a card without a series still renders
 * (prose + evidence chips); the chart just doesn't draw.
 *
 * `polarity` tells the UI which direction is the win, so the line can be
 * oriented/labelled honestly (HR-at-pace and pace are `down_good`; recovery
 * is `up_good`; miles are `neutral`). `markerIdx` rings specific points
 * (e.g. the niggle weeks for A1). `band` is an optional reference zone
 * (e.g. decoupling under 5%).
 */
export interface TrendSeries {
  /** Ordered values, oldest → newest. Length ≥ 2 when present. */
  points: number[];
  /** X labels aligned 1:1 to `points` (week/month tags). */
  labels?: string[];
  /** Unit of the values: "mi" | "sec" | "bpm" | "%" | "bpm/60s" | "spm". */
  unit?: string;
  /** Which direction reads as improvement. */
  polarity?: "up_good" | "down_good" | "neutral";
  /** Indices in `points` to emphasize (rings) — e.g. niggle weeks. */
  markerIdx?: number[];
  /** Optional reference band drawn behind the line. */
  band?: { lo: number; hi: number };
}

export interface TrendCard {
  id: string; // "A1", "B3", "C0" …
  group: TrendGroup;
  status: TrendStatus;
  headline: string; // one line, editorial voice
  body: string; // 1–2 sentences, feeling-before-math
  evidence: Evidence[]; // chart-pluckable points; may be []
  confidence: Confidence;
  /** Full series for the in-card mini-chart. Absent → prose-only card. */
  series?: TrendSeries;
}

// ─── Detector context ──────────────────────────────────────────────────

/**
 * Everything the detectors read, gathered once in `index.ts`.
 *
 * `weeks` is the SAME `TrendsWeekOut[]` the chart renders (built by the
 * shared `buildTrendsTimeline`), so a card never disagrees with the bars.
 * `mentions` are the raw body-mention rows (weeks carry only distinct
 * labels; A1 needs per-mention `body_area` + date to group and count).
 */
export interface DetectCtx {
  weeks: TrendsWeekOut[];
  mentions: TimelineMention[];
  /** Per-second stream runs for Group B. Empty when no streams are wired. */
  streamRuns: StreamRun[];
  /**
   * The daily substrate (same `buildDailyTimeline` the calendar renders on).
   * Only the weekday-rhythm detector (A4) needs it — a weekly series can't
   * see day-of-week. Empty/absent → A4 stays hidden.
   */
  days?: TrendsDayOut[];
}

// ─── Helpers ───────────────────────────────────────────────────────────

/**
 * A hidden card — the gate wasn't met. `index.ts`/`detect.ts` drops these
 * before responding, so an unmet gate renders as nothing, never a stub.
 */
export function hiddenCard(id: string, group: TrendGroup): TrendCard {
  return {
    id,
    group,
    status: "hidden",
    headline: "",
    body: "",
    evidence: [],
    confidence: "low",
  };
}

/**
 * Detection-not-diagnosis guard vocabulary. Any of these appearing in a
 * card's `headline`/`body` is a bug — a detector crossed from observation
 * into prescription or a cause claim. Enforced by a unit test, not at
 * runtime, so the check is free in prod. Whole-word matched (\b…\b),
 * case-insensitive.
 *
 * Deliberately NOT banned: "diagnosed"/"interpreted" (brand copy says
 * "never diagnosed", the opposite of a diagnosis) and the "niggle"
 * vocabulary. The list targets prescription ("rest", "ice"), obligation
 * ("should", "must"), and causal assertion ("because", "caused") — the
 * things a detector must never say.
 */
export const BANNED_TERMS: readonly string[] = [
  "rest",
  "ice",
  "should",
  "must",
  "because",
  "caused",
  "stop running",
];

/** Least-squares slope of `ys` over index 0..n-1. Null for < 2 points. */
export function slope(ys: number[]): number | null {
  const n = ys.length;
  if (n < 2) return null;
  const meanX = (n - 1) / 2;
  const meanY = ys.reduce((a, b) => a + b, 0) / n;
  let num = 0;
  let den = 0;
  for (let i = 0; i < n; i++) {
    num += (i - meanX) * (ys[i] - meanY);
    den += (i - meanX) * (i - meanX);
  }
  return den === 0 ? 0 : num / den;
}

/** Median of a numeric list (0 for empty). */
export function median(xs: number[]): number {
  if (xs.length === 0) return 0;
  const s = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(s.length / 2);
  return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2;
}

/** UTC-midnight epoch ms for a "YYYY-MM-DD" (or ISO datetime) string. */
export function dayMs(dateStr: string): number {
  const d = new Date(dateStr);
  return Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
}

/** "6:41" from 401 sec/mi. */
export function fmtPace(sec: number): string {
  const s = Math.round(sec);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}
