/**
 * The analyzer registry.
 *
 * Registration convention mirrors `_shared/rules/index.ts`: one import, one
 * map entry. Adding a question to Ask is a two-line change here plus one new
 * file — no prompt surgery, no endpoint change, no client release.
 *
 * The registry is also the router's closed enum: Layer 0 may only ever return
 * an id present in `ANALYZER_IDS`, and may only fill params declared in that
 * analyzer's `params`. It cannot invent a question and it cannot write a query.
 *
 * ── Coverage ──
 *
 * Phase A shipped three: a session comparison, a multi-session trend, and a
 * whole-block aggregate — chosen to exercise every part of the contract.
 *
 * Phase B (2026-08-07) adds six more, and they are cheap for a specific
 * reason: `athlete_state` is already the app's computed layer, so most of
 * these read a field the state builders maintain rather than recomputing it.
 * That keeps Ask from ever disagreeing with the Trends tile — a second
 * implementation of `fitness_prediction` would drift from the first within a
 * month. The two that go to raw laps (`race_pace_specificity`, `heat_effect`)
 * do so because state carries no per-lap detail.
 *
 * `race_pace_specificity` is the exception in kind: it is not a wrapper. Both
 * of its operands — the goal pace and the training paces — have been persisted
 * for months, and nothing ever divided one by the other. See its header.
 *
 * The remaining registry (50 analyzers across 11 training principles) with a
 * build-status audit against this repo is in `ASK-REGISTRY.md`.
 */

import type { Analyzer } from "./types.ts";
import { compareSession } from "./compareSession.ts";
import { currentFitness } from "./currentFitness.ts";
import { loadBalance } from "./loadBalance.ts";
import { zoneTrend } from "./zoneTrend.ts";
import { decoupling, efficiency } from "./efficiency.ts";
import { heatEffect } from "./heatEffect.ts";
import { moodTrend } from "./moodTrend.ts";
import { niggleTimeline } from "./niggleTimeline.ts";
import { racePaceSpecificity } from "./racePaceSpecificity.ts";
import { raceProjection } from "./raceProjection.ts";

export * from "./types.ts";
export {
  compareSession,
  currentFitness,
  decoupling,
  efficiency,
  heatEffect,
  loadBalance,
  moodTrend,
  niggleTimeline,
  racePaceSpecificity,
  raceProjection,
  zoneTrend,
};

export const ANALYZERS: Record<string, Analyzer> = {
  // Load
  [loadBalance.id]: loadBalance,
  // Adaptation
  [currentFitness.id]: currentFitness,
  [zoneTrend.id]: zoneTrend,
  [efficiency.id]: efficiency,
  [raceProjection.id]: raceProjection,
  // Durability
  [decoupling.id]: decoupling,
  // Specificity
  [racePaceSpecificity.id]: racePaceSpecificity,
  // Conditions
  [heatEffect.id]: heatEffect,
  // The body
  [moodTrend.id]: moodTrend,
  [niggleTimeline.id]: niggleTimeline,
  // Comparison
  [compareSession.id]: compareSession,
};

export const ANALYZER_IDS: string[] = Object.keys(ANALYZERS);

export function getAnalyzer(id: unknown): Analyzer | null {
  if (typeof id !== "string") return null;
  return ANALYZERS[id] ?? null;
}

/**
 * The chip rail, in display order. Contextual chips are derived client-side
 * from athlete state; these are the standing ones.
 */
export function analyzerCatalog(): Array<{
  id: string;
  label: string;
  group: string;
}> {
  return ANALYZER_IDS.map((id) => {
    const a = ANALYZERS[id];
    return { id: a.id, label: a.label, group: a.group };
  });
}

/**
 * Coerce and validate router-supplied params against an analyzer's closed
 * schema. Unknown keys are DROPPED, not rejected — a router that hallucinates
 * a parameter degrades to the analyzer's defaults rather than 400-ing at the
 * athlete. Values outside an `enum` or numeric range are dropped the same way.
 */
export function coerceParams(
  analyzer: Analyzer,
  raw: unknown,
): Record<string, string | number> {
  const out: Record<string, string | number> = {};
  if (!raw || typeof raw !== "object") return out;
  const input = raw as Record<string, unknown>;

  for (const [key, spec] of Object.entries(analyzer.params)) {
    const v = input[key];
    if (v == null) continue;

    if (spec.type === "number") {
      const n = typeof v === "number" ? v : Number(v);
      if (!isFinite(n)) continue;
      if (spec.min != null && n < spec.min) continue;
      if (spec.max != null && n > spec.max) continue;
      out[key] = n;
      continue;
    }

    if (typeof v !== "string" || v.length === 0) continue;
    if (spec.type === "string" && spec.enum && !spec.enum.includes(v)) continue;
    // workout_id: a UUID from the athlete's own log. Ownership is enforced by
    // the `.eq("user_id")` on every fetch, not by shape — but reject anything
    // that obviously isn't an id so we don't spend a round trip on it.
    if (spec.type === "workout_id" && !/^[0-9a-fA-F-]{16,64}$/.test(v)) continue;
    out[key] = v;
  }

  return out;
}
