/**
 * The analyzer registry.
 *
 * Registration convention mirrors `_shared/rules/index.ts`: one import, one
 * map entry. Adding a question to Ask is a two-line change here plus one new
 * file — no prompt surgery, no endpoint change, no client release.
 *
 * PHASE A ships three analyzers, chosen because their underlying math is the
 * deepest and because between them they exercise every part of the contract:
 * a session-level comparison, a multi-session trend with a chart, and a
 * whole-block aggregate. The remaining 47 are enumerated in ASK-REGISTRY.md
 * with a build-status audit against this repo.
 *
 * The registry is also the router's closed enum: Layer 0 may only ever return
 * an id present in `ANALYZER_IDS`, and may only fill params declared in that
 * analyzer's `params`. It cannot invent a question and it cannot write a query.
 */

import type { Analyzer } from "./types.ts";
import { compareSession } from "./compareSession.ts";
import { loadBalance } from "./loadBalance.ts";
import { zoneTrend } from "./zoneTrend.ts";

export * from "./types.ts";
export { compareSession, loadBalance, zoneTrend };

export const ANALYZERS: Record<string, Analyzer> = {
  [compareSession.id]: compareSession,
  [loadBalance.id]: loadBalance,
  [zoneTrend.id]: zoneTrend,
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
