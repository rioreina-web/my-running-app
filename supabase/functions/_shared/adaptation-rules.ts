/**
 * Adaptation rules — pure functions that inspect recent athlete state and
 * emit zero or more AdaptationProposals. Each proposal becomes a
 * plan_adjustments row (auto-applied or pending-acknowledgement).
 *
 * Rules are intentionally boring: small windowed checks, clear thresholds,
 * no ML. The adapt-plan edge function wires them together.
 */

export type TriggerType =
  | "pace_over_target"
  | "pace_under_target"
  | "missed_sessions"
  | "race_result"
  | "volume_ramp_risk"
  | "heat_forecast"
  | "weekly_rebalance";

export type ActionType =
  | "reprice_future_paces"
  | "reduce_volume"
  | "cap_volume"
  | "propose_swap"
  | "update_fitness"
  | "pause_quality";

export interface AdaptationProposal {
  trigger_type: TriggerType;
  trigger_evidence: unknown[];
  action_type: ActionType;
  action_payload: Record<string, unknown>;
  auto_applied: boolean;
  proposed_until?: string | null; // ISO; null when auto-applied
}

export interface RuleContext {
  userId: string;
  planId: string | null;
  recentReconciliations: Reconciliation[];
  recentLogs: TrainingLog[];
  currentPlanWorkouts: ScheduledWorkout[];
  forecast14d: DailyForecast[];
  // deno-lint-ignore no-explicit-any
  profile: any | null;
}

export interface Reconciliation {
  id: string;
  training_log_id: string;
  created_at: string;
  target_pace_seconds_per_mile: number | null;
  actual_pace_seconds_per_mile: number | null;
  adjusted_pace_delta_seconds: number | null;
  hit_target: boolean | null;
  scheduled_workout_id: string | null;
}

export interface TrainingLog {
  id: string;
  workout_date: string;
  workout_type: string | null;
  workout_distance_miles: number | null;
  workout_duration_minutes: number | null;
}

export interface ScheduledWorkout {
  id: string;
  date: string;
  week_number: number;
  workout_type: string;
  status: string;
  // deno-lint-ignore no-explicit-any
  workout_data: any;
}

export interface DailyForecast {
  date: string;
  temp_f: number;
  dew_point_f: number;
}

const SEVEN_DAYS_MS = 7 * 24 * 60 * 60 * 1000;
const TWO_WEEKS = 14;

// ── Rule helpers ─────────────────────────────────────────────────

function withinLastDays(iso: string, days: number): boolean {
  const t = new Date(iso).getTime();
  return Date.now() - t <= days * 24 * 60 * 60 * 1000;
}

function sortDesc<T>(arr: T[], getDate: (t: T) => string): T[] {
  return [...arr].sort((a, b) => new Date(getDate(b)).getTime() - new Date(getDate(a)).getTime());
}

function hardReconciliations(ctx: RuleContext): Reconciliation[] {
  return ctx.recentReconciliations.filter(
    (r) => r.target_pace_seconds_per_mile != null && r.adjusted_pace_delta_seconds != null
  );
}

function inSevenDays(ts: string): boolean {
  return Date.now() - new Date(ts).getTime() <= SEVEN_DAYS_MS;
}

// ── Individual rules ─────────────────────────────────────────────

/** 3 consecutive hard sessions hit target within 3s → propose 3s/mi faster. */
export function rule_paceConsistentlyOver(ctx: RuleContext): AdaptationProposal[] {
  const hard = sortDesc(hardReconciliations(ctx), (r) => r.created_at).slice(0, 3);
  if (hard.length < 3) return [];
  const allHit = hard.every((r) => r.hit_target === true && Math.abs(r.adjusted_pace_delta_seconds ?? 99) <= 3);
  if (!allHit) return [];

  return [{
    trigger_type: "pace_over_target",
    trigger_evidence: hard.map((r) => r.id),
    action_type: "reprice_future_paces",
    action_payload: { delta_seconds_per_mile: -3, rationale: "3 hard sessions ≤ 3s delta" },
    auto_applied: false,
    proposed_until: new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString(),
  }];
}

/** 3 of last 4 hard sessions delta ≥ +10s → auto-slow 5-8s/mi scaled by magnitude. */
export function rule_paceConsistentlyUnder(ctx: RuleContext): AdaptationProposal[] {
  const hard = sortDesc(hardReconciliations(ctx), (r) => r.created_at).slice(0, 4);
  if (hard.length < 4) return [];
  const over = hard.filter((r) => (r.adjusted_pace_delta_seconds ?? 0) >= 10);
  if (over.length < 3) return [];

  const avgDelta = over.reduce((s, r) => s + (r.adjusted_pace_delta_seconds ?? 0), 0) / over.length;
  const scaled = Math.min(8, Math.max(5, Math.round(avgDelta * 0.4)));

  return [{
    trigger_type: "pace_under_target",
    trigger_evidence: hard.map((r) => r.id),
    action_type: "reprice_future_paces",
    action_payload: {
      delta_seconds_per_mile: scaled,
      rationale: `3/4 hard sessions ≥ +10s (avg +${Math.round(avgDelta)}s) — slowing targets by ${scaled}s/mi`,
    },
    auto_applied: true,
    proposed_until: null,
  }];
}

/** ≥2 quality sessions skipped in last 7 days → pause quality next 7 days. */
export function rule_missedSessions(ctx: RuleContext): AdaptationProposal[] {
  const QUALITY = new Set(["tempo", "intervals", "long_run", "race", "progression"]);
  const missed = ctx.currentPlanWorkouts.filter(
    (w) => QUALITY.has(w.workout_type) && w.status === "skipped" && inSevenDays(w.date)
  );
  if (missed.length < 2) return [];

  return [{
    trigger_type: "missed_sessions",
    trigger_evidence: missed.map((w) => w.id),
    action_type: "pause_quality",
    action_payload: {
      pause_days: 7,
      rationale: `${missed.length} quality sessions missed in the last 7 days — swapping to easy until recovery signal returns`,
    },
    auto_applied: true,
    proposed_until: null,
  }];
}

/** A race workout was logged → update_fitness from the race time. */
export function rule_raceResult(ctx: RuleContext): AdaptationProposal[] {
  const races = ctx.recentLogs.filter(
    (l) => l.workout_type === "race" && (l.workout_distance_miles ?? 0) > 0
  );
  if (races.length === 0) return [];
  const latest = sortDesc(races, (l) => l.workout_date)[0];

  return [{
    trigger_type: "race_result",
    trigger_evidence: [latest.id],
    action_type: "update_fitness",
    action_payload: {
      source_log_id: latest.id,
      distance_miles: latest.workout_distance_miles,
      duration_minutes: latest.workout_duration_minutes,
      rationale: "Race result detected — updating fitness predictions and repricing future paces",
    },
    auto_applied: true,
    proposed_until: null,
  }];
}

/** Weekly volume up >10% for 3 consecutive weeks → cap next week at current. */
export function rule_volumeRampRisk(ctx: RuleContext): AdaptationProposal[] {
  // Weekly volume = sum of distance on logs per ISO week. We look at the
  // 4 most recent complete weeks.
  const byWeek = new Map<number, number>();
  for (const log of ctx.recentLogs) {
    if (!log.workout_distance_miles) continue;
    const d = new Date(log.workout_date);
    const year = d.getUTCFullYear();
    const weekNum = getIsoWeek(d);
    const key = year * 100 + weekNum;
    byWeek.set(key, (byWeek.get(key) ?? 0) + log.workout_distance_miles);
  }
  const ordered = [...byWeek.entries()].sort(([a], [b]) => b - a).slice(0, 4).reverse();
  if (ordered.length < 4) return [];

  let rising = true;
  for (let i = 1; i < ordered.length; i++) {
    const prev = ordered[i - 1][1];
    const cur = ordered[i][1];
    if (prev <= 0 || cur <= prev * 1.10) { rising = false; break; }
  }
  if (!rising) return [];

  const latest = ordered[ordered.length - 1][1];
  return [{
    trigger_type: "volume_ramp_risk",
    trigger_evidence: ordered.map(([k, v]) => ({ week_key: k, miles: v })),
    action_type: "cap_volume",
    action_payload: {
      cap_miles: Math.round(latest * 10) / 10,
      rationale: "Weekly mileage up >10% three weeks running — capping next week to reduce injury risk",
    },
    auto_applied: true,
    proposed_until: null,
  }];
}

/** Forecast shows dew point > 68°F on 3+ scheduled quality sessions → propose swap. */
export function rule_heatForecast(ctx: RuleContext): AdaptationProposal[] {
  const QUALITY = new Set(["tempo", "intervals", "long_run", "race", "progression"]);
  const hotDays = new Set(ctx.forecast14d.filter((f) => f.dew_point_f > 68).map((f) => f.date));
  const affected = ctx.currentPlanWorkouts.filter(
    (w) => QUALITY.has(w.workout_type) && hotDays.has(w.date)
  );
  if (affected.length < 3) return [];

  return [{
    trigger_type: "heat_forecast",
    trigger_evidence: affected.map((w) => w.id),
    action_type: "propose_swap",
    action_payload: {
      affected_ids: affected.map((w) => w.id),
      reason: "dew_point_above_68",
      rationale: `${affected.length} upcoming quality sessions on high-dew-point days — consider moving to cooler days.`,
    },
    auto_applied: false,
    proposed_until: new Date(Date.now() + TWO_WEEKS * 24 * 60 * 60 * 1000).toISOString(),
  }];
}

// ── Runner ──────────────────────────────────────────────────────

export function runAllRules(ctx: RuleContext): AdaptationProposal[] {
  return [
    ...rule_paceConsistentlyOver(ctx),
    ...rule_paceConsistentlyUnder(ctx),
    ...rule_missedSessions(ctx),
    ...rule_raceResult(ctx),
    ...rule_volumeRampRisk(ctx),
    ...rule_heatForecast(ctx),
  ];
}

// ── Small helper ────────────────────────────────────────────────

function getIsoWeek(d: Date): number {
  const date = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - dayNum);
  const yearStart = new Date(Date.UTC(date.getUTCFullYear(), 0, 1));
  return Math.ceil(((date.getTime() - yearStart.getTime()) / 86_400_000 + 1) / 7);
}
