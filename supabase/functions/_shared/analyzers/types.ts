/**
 * The analyzer contract — Layer 1 of the Ask surface.
 *
 * An analyzer answers ONE athlete question by running real math over real rows
 * and emitting `FactLine[]`. The rule that makes the whole surface safe:
 *
 *   **If a number is not in `facts`, it does not exist.**
 *
 * The UI renders from `facts`. The Layer-2 model may speak only the numbers in
 * `facts` (enforced mechanically by `narration-guard.ts`). There is no third
 * source. An analyzer that wants to say something must say it as a fact.
 *
 * Analyzers are pure-ish: they read through `ctx.supabase` and compute, and
 * they never write. Nothing in this directory mutates state — no
 * `coachable_moments`, no `plan_adjustments`, no plan mutation. Ask reads.
 *
 * Hard rule #2 applies in full: no analyzer may emit a fact that diagnoses,
 * recommends rest, or assesses severity. `FactTone` deliberately has no "bad"
 * value — `watch` is the ceiling.
 */

import type { PaceZones } from "../workoutSegmentation.ts";
import type { ZoneTable } from "../quality-volume.ts";

// ── Facts ────────────────────────────────────────────────────────

/** Never "bad". Observation, not judgement. */
export type FactTone = "neutral" | "good" | "watch";

export interface FactLine {
  /** Stable machine key — `lt_pace_recent`. Clients key off this, not `label`. */
  key: string;
  /** Athlete-facing label — "LT pace · last 3 sessions". */
  label: string;
  /** Pre-formatted display value — "7:03", "1.06", "46.2". */
  value: string;
  /** Unit rendered small alongside the value — "/mi", "mi", "bpm". */
  unit?: string | null;
  /** Signed change, pre-formatted — "−9s", "+6%". Omit when not a delta. */
  delta?: string | null;
  tone?: FactTone;
}

// ── Coverage ─────────────────────────────────────────────────────

/** Same three tiers as `workoutComparison.Confidence` — one vocabulary. */
export type Confidence = "high" | "moderate" | "low";

/**
 * What the answer is built on. Rendered under EVERY answer, not just weak
 * ones — the difference between a product that feels analytical and one that
 * feels like it's guessing.
 */
export interface Coverage {
  sessionsUsed: number;
  windowDays: number;
  /** Honest holes — "no HR on 3 of 9 sessions". Never silently omitted. */
  missing: string[];
  confidence: Confidence;
}

// ── Series (chart spec) ──────────────────────────────────────────

export type SeriesUnit =
  | "sec_per_mile"
  | "miles"
  | "minutes"
  | "ratio"
  | "bpm"
  | "count"
  | "percent";

export interface SeriesPoint {
  /** ISO date (YYYY-MM-DD) or a bucket label ("W-3"). */
  x: string;
  y: number;
  /** Optional second series — the conditions-adjusted twin, typically. */
  y2?: number | null;
  label?: string | null;
}

export interface SeriesSpec {
  kind: "line" | "bar";
  unit: SeriesUnit;
  /** Lower is better (pace). The client inverts the axis. */
  invertY?: boolean;
  /** Reference band drawn behind the marks — an expected/target range. */
  band?: [number, number] | null;
  y2Label?: string | null;
  points: SeriesPoint[];
}

// ── Empty state ──────────────────────────────────────────────────

/**
 * Hard rule #8: never an em-dash placeholder. Every analyzer must return a
 * real empty state when coverage is insufficient, with a plain-prose nudge
 * that says what would make the answer possible.
 */
export interface EmptyState {
  eyebrow: string;
  nudge: string;
  cta?: { label: string; action: string } | null;
}

// ── Result ───────────────────────────────────────────────────────

export interface AnalyzerResult {
  facts: FactLine[];
  series?: SeriesSpec | null;
  coverage: Coverage;
  /** Analyzer ids → follow-up chips. Deterministic, so the surface can never
   *  suggest a question the product can't answer. */
  related: string[];
  /** When set, the client renders this instead of facts/series. */
  empty?: EmptyState | null;
}

// ── Params ───────────────────────────────────────────────────────

/**
 * A closed param schema. The Layer-0 router may fill these and nothing else —
 * it cannot invent a parameter, and it cannot pass a value outside `enum`.
 * Deliberately tiny: this is a routing contract, not JSON Schema.
 */
export type ParamSpec =
  | { type: "string"; enum?: string[]; optional?: boolean; describe: string }
  | { type: "number"; min?: number; max?: number; optional?: boolean; describe: string }
  | { type: "workout_id"; optional?: boolean; describe: string };

export type ParamsSchema = Record<string, ParamSpec>;

export type AnalyzerParams = Record<string, string | number | undefined>;

// ── Context ──────────────────────────────────────────────────────

/** Minimal shape of the Supabase client the analyzers use. Kept structural so
 *  tests can pass a stub without importing the SDK. */
export interface SupabaseLike {
  // deno-lint-ignore no-explicit-any
  from(table: string): any;
}

export interface AnalyzerCtx {
  userId: string;
  supabase: SupabaseLike;
  /** Segmentation-flavoured zones (workoutComparison, workoutSegmentation). */
  zones: PaceZones;
  /** Quality-volume-flavoured zones (fast-segment-trends). Same source blob. */
  zoneTable: ZoneTable;
  /** Injected so analyzer output is deterministic under test. */
  now: Date;
}

// ── The analyzer itself ──────────────────────────────────────────

export type AnalyzerGroup =
  | "load"
  | "mix"
  | "adaptation"
  | "durability"
  | "specificity"
  | "recovery"
  | "consistency"
  | "block"
  | "conditions"
  | "body"
  | "comparison";

export interface Analyzer {
  id: string;
  /** Chip text. Phrased as the athlete's question, not the metric's name. */
  label: string;
  group: AnalyzerGroup;
  params: ParamsSchema;
  run(params: AnalyzerParams, ctx: AnalyzerCtx): Promise<AnalyzerResult>;
}

// ── The Layer-1 → Layer-2 seam ───────────────────────────────────

/**
 * Serialize facts into the exact strings the number guard tokenizes.
 *
 * This function is the ONLY seam between the two layers. The same array is
 * both what the model is shown and what `allowedNumberTokens` is computed
 * from, so the guard can never disagree with the prompt about which numbers
 * were licensed. Do not build the prompt from `facts` directly anywhere else.
 */
export function factLinesToStrings(result: AnalyzerResult): string[] {
  const lines = result.facts.map((f) => {
    const value = `${f.value}${f.unit ?? ""}`;
    const delta = f.delta ? ` (${f.delta})` : "";
    return `${f.label}: ${value}${delta}`;
  });
  const missing = result.coverage.missing.length
    ? ` — ${result.coverage.missing.join("; ")}`
    : "";
  lines.push(
    `Coverage: ${result.coverage.sessionsUsed} sessions over ${result.coverage.windowDays} days (${result.coverage.confidence} confidence)${missing}`,
  );
  return lines;
}

// ── Small shared formatters ──────────────────────────────────────

/** "7:03" from 423. Mirrors `weeklyAnalytics.formatPace` minus the "/mi". */
export function fmtPaceSec(secondsPerMile: number): string {
  const total = Math.round(secondsPerMile);
  const m = Math.floor(total / 60);
  const s = total % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

/** Signed second-delta for a pace fact — "−9s" / "+4s". Faster is negative. */
export function fmtSecDelta(deltaSeconds: number): string {
  const r = Math.round(deltaSeconds);
  if (r === 0) return "0s";
  return `${r < 0 ? "−" : "+"}${Math.abs(r)}s`;
}

export function fmtPctDelta(pct: number): string {
  const r = Math.round(pct);
  if (r === 0) return "0%";
  return `${r < 0 ? "−" : "+"}${Math.abs(r)}%`;
}

/**
 * A signed delta for counts, bpm, degrees — anything that isn't a pace or a
 * percentage. Crucially, a delta that ROUNDS to zero renders as "same", never
 * as "+0": a signed zero reads as a real (tiny) change and invites the model
 * to narrate a difference that the rounding just erased.
 *
 * `decimals` lets a metric that lives below 1.0 (decoupling %) keep its
 * precision without every integer metric inheriting a ".0".
 */
export function fmtDelta(
  delta: number,
  opts: { decimals?: number; suffix?: string; zeroLabel?: string } = {},
): string {
  const { decimals = 0, suffix = "", zeroLabel = "same" } = opts;
  const factor = 10 ** decimals;
  const rounded = Math.round(delta * factor) / factor;
  if (rounded === 0) return zeroLabel;
  const magnitude = Math.abs(rounded).toFixed(decimals);
  return `${rounded < 0 ? "−" : "+"}${magnitude}${suffix}`;
}

/** Confidence from sample size, with an explicit floor the analyzers share. */
export function confidenceFromSamples(
  n: number,
  opts: { high: number; moderate: number } = { high: 6, moderate: 3 },
): Confidence {
  if (n >= opts.high) return "high";
  if (n >= opts.moderate) return "moderate";
  return "low";
}
