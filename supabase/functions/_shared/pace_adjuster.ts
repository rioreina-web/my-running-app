/**
 * Slow-adjusting pace proposer.
 *
 * Watches workout_reconciliations and proposes pace zone adjustments only
 * when there's enough evidence to justify the change. NEVER applies a
 * change directly — it returns a proposal which the caller writes to
 * `plan_adjustments` with `auto_applied: false`. The athlete sees a card
 * and explicitly accepts.
 *
 * Design principles encoded here:
 *   1. Slow. Multiple confirming sessions over time, not single workouts.
 *   2. Outlier-robust. Rolling MEDIAN, not mean. One bad tempo from a
 *      sub-15 5K runner does not turn them into a 16:00 runner.
 *   3. Asymmetric. Faster paces are harder to earn (max +5s/mi per cycle).
 *      Slower paces are also conservative (max -3s/mi per cycle) so a
 *      bad block doesn't yank the athlete's perceived fitness down.
 *   4. Warm-up gated. Need both >= 14 days since plan start AND >= 4
 *      quality reconciliations before any adjustment fires.
 *   5. Athlete-decided. We only propose. Never write paces.
 *
 * See feedback memory `feedback_ai_advises_never_acts.md`.
 * See cowork doc `day-picking-prompts.md` § DP-B.1, B.2.
 */

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Types ────────────────────────────────────────────────

export type PaceZone =
  | "easy"
  | "marathon"
  | "half"
  | "tenK"
  | "fiveK"
  | "mile";

export interface PaceAdjustmentProposal {
  zone: PaceZone;
  current_pace_seconds_per_mile: number;
  proposed_pace_seconds_per_mile: number;
  delta_seconds: number; // signed: negative = faster, positive = slower
  evidence_reconciliation_ids: string[];
  reasoning: string;
}

interface Reconciliation {
  id: string;
  scheduled_workout_id: string;
  target_pace_seconds_per_mile: number | null;
  actual_pace_seconds_per_mile: number | null;
  adjusted_target_pace_seconds: number | null;
  adjusted_pace_delta_seconds: number | null;
  created_at: string;
}

// ── Tunables (single place to adjust the philosophy) ─────────────

/** Minimum days since plan start before any adjustment fires. */
const WARM_UP_DAYS = 14;

/** Minimum quality reconciliations required before any adjustment. */
const WARM_UP_SESSIONS = 4;

/** Number of recent reconciliations to consider in the rolling window. */
const ROLLING_WINDOW = 4;

/** Median delta within ±NO_CHANGE_TOLERANCE_SEC is treated as on-pace. */
const NO_CHANGE_TOLERANCE_SEC = 3;

/** Max one-step improvement (faster). Keeps "you've earned it" rare. */
const MAX_FASTER_STEP_SEC = 5;

/** Max one-step regression (slower). Even smaller — protect perceived fitness. */
const MAX_SLOWER_STEP_SEC = 3;

// ── Public API ───────────────────────────────────────────

/**
 * Propose a pace adjustment for the user, or return null if no change is
 * warranted. The caller wraps the proposal in a `plan_adjustments` row.
 */
export async function proposePaceAdjustment(
  supabase: SupabaseClient,
  userId: string,
): Promise<PaceAdjustmentProposal | null> {
  // ── Warm-up gate: must have BOTH a 14-day plan tenure AND 4 sessions ──
  const planStartedAt = await getActivePlanStartDate(supabase, userId);
  if (!planStartedAt) return null;
  const daysSinceStart =
    (Date.now() - planStartedAt.getTime()) / (1000 * 86400);
  if (daysSinceStart < WARM_UP_DAYS) return null;

  const recent = await fetchRecentReconciliations(supabase, userId);
  const usable = recent.filter(
    (r) =>
      r.adjusted_target_pace_seconds != null &&
      r.adjusted_pace_delta_seconds != null,
  );
  if (usable.length < WARM_UP_SESSIONS) return null;

  // Rolling median over the last N — outlier-robust. One bad tempo cannot
  // move the median significantly.
  const window = usable.slice(0, ROLLING_WINDOW);
  const medianDelta = median(
    window.map((r) => r.adjusted_pace_delta_seconds!),
  );

  // Within tolerance → no proposal.
  if (Math.abs(medianDelta) < NO_CHANGE_TOLERANCE_SEC) return null;

  // Cap the step. We never propose more than the max for either direction.
  const stepSize =
    medianDelta < 0
      ? Math.min(MAX_FASTER_STEP_SEC, Math.round(Math.abs(medianDelta)))
      : Math.min(MAX_SLOWER_STEP_SEC, Math.round(medianDelta));

  // Direction: median negative = athlete is faster than target → propose
  // faster paces. Median positive = athlete is slower → propose softer.
  const direction = medianDelta < 0 ? -1 : 1;

  // Find the dominant zone in the window. We adjust the zone that's
  // showing the trend most consistently rather than blanket-shifting all
  // paces. (For the V1 implementation, infer the zone from the median
  // target pace; future versions can split per-zone.)
  const zone = inferZoneFromPace(median(window.map((r) => r.adjusted_target_pace_seconds!)));
  const currentPace = Math.round(
    median(window.map((r) => r.adjusted_target_pace_seconds!)),
  );
  const proposedPace = currentPace + direction * stepSize;

  return {
    zone,
    current_pace_seconds_per_mile: currentPace,
    proposed_pace_seconds_per_mile: proposedPace,
    delta_seconds: direction * stepSize,
    evidence_reconciliation_ids: window.map((r) => r.id),
    reasoning: buildReasoning(zone, direction, stepSize, window.length),
  };
}

// ── Helpers ──────────────────────────────────────────────

async function getActivePlanStartDate(
  supabase: SupabaseClient,
  userId: string,
): Promise<Date | null> {
  const { data } = await supabase
    .from("training_plans")
    .select("created_at, start_date")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (!data) return null;
  const raw = (data as { start_date?: string; created_at?: string }).start_date
    ?? (data as { created_at?: string }).created_at;
  return raw ? new Date(raw) : null;
}

async function fetchRecentReconciliations(
  supabase: SupabaseClient,
  userId: string,
): Promise<Reconciliation[]> {
  // Fetch enough to cover the rolling window plus a buffer in case some
  // are missing the adjusted_* fields we filter on.
  const { data } = await supabase
    .from("workout_reconciliations")
    .select(
      "id, scheduled_workout_id, target_pace_seconds_per_mile, actual_pace_seconds_per_mile, adjusted_target_pace_seconds, adjusted_pace_delta_seconds, created_at",
    )
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(ROLLING_WINDOW * 3);

  return (data ?? []) as Reconciliation[];
}

/**
 * Median of a numeric array. For even length: average of the two middle
 * elements (standard definition). For odd: the middle element. Empty
 * input returns 0 — caller filters out empty windows above.
 */
export function median(xs: number[]): number {
  if (xs.length === 0) return 0;
  const sorted = [...xs].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 === 0
    ? (sorted[mid - 1] + sorted[mid]) / 2
    : sorted[mid];
}

/**
 * Rough zone inference from a pace value. Real implementation would
 * consult the athlete's pace table. For now we bucket by per-mile speed.
 */
function inferZoneFromPace(secPerMile: number): PaceZone {
  if (secPerMile >= 480) return "easy";       // slower than 8:00/mi
  if (secPerMile >= 380) return "marathon";   // 6:20-8:00/mi
  if (secPerMile >= 340) return "half";       // 5:40-6:20/mi
  if (secPerMile >= 310) return "tenK";       // 5:10-5:40/mi
  if (secPerMile >= 280) return "fiveK";      // 4:40-5:10/mi
  return "mile";
}

function buildReasoning(
  zone: PaceZone,
  direction: number,
  stepSize: number,
  sessions: number,
): string {
  const dir = direction < 0 ? "faster" : "softer";
  const cause = direction < 0
    ? `Your last ${sessions} ${zone} sessions ran consistently faster than target`
    : `Your last ${sessions} ${zone} sessions ran consistently above target`;
  return `${cause}. Proposing a ${stepSize}s/mi shift ${dir} for the ${zone} zone — small step, conservative.`;
}
