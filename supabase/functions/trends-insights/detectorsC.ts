/**
 * Group C detectors — recovery-side trends (daily Garmin biometrics).
 *
 * SCAFFOLD ONLY. Group C needs a new capture path: the `daily_biometrics`
 * table + a `vital-webhook` branch for daily events (sleep / HRV / RHR /
 * stress), then 3–4 weeks of baseline before anything unhides. Until then
 * every C detector returns `hidden`.
 *
 * The convergence rule is non-negotiable for this group (plan §6c): NO
 * single biometric ever generates a card. A recovery observation surfaces
 * only when 2+ independent signals agree — including the qualitative mood
 * stream — and is emitted as ONE synthesized card (`C0`), with the
 * constituents demoted to its evidence. `applyConvergence` is where that
 * gate will live; it's a documented no-op while C is dark.
 */

import { type DetectCtx, type TrendCard, hiddenCard } from "./contract.ts";

// C0 = the synthesized convergence card; C1–C4 = the individual signals
// (kept as evidence once C0 fires — see the plan's resolved decision #1).
const C_IDS = ["C0", "C1", "C2", "C3", "C4"] as const;

export function scaffoldC(_ctx: DetectCtx): TrendCard[] {
  // No daily_biometrics yet → all hidden.
  return C_IDS.map((id) => hiddenCard(id, "C"));
}

/**
 * The convergence gate. Once Group C has data, this will:
 *   • force any lone C-signal to `quiet` (renders in the chart, says nothing);
 *   • require ≥2 agreeing signals (C1–C4 + heavy mood) to reach `active`;
 *   • collapse the agreeing set into a single `C0` card, demoting the
 *     constituents to its `evidence`.
 * No-op today — C detectors are all hidden, so there's nothing to converge.
 */
export function applyConvergence(cards: TrendCard[], _ctx: DetectCtx): TrendCard[] {
  return cards;
}
