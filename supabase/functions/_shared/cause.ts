/**
 * Skip-cause attribution and the adjustment it implies.
 *
 * The coach's job, compressed: notice something, work out *why*, make one of
 * five moves. The five moves are already a closed vocabulary in
 * `plan_adjustments.action_type`. The "why" is what was missing — and it's
 * the whole ballgame, because the same event branches to opposite responses:
 *
 *     missed Tuesday + work blew up   → move the day, keep the load
 *     missed Tuesday + legs are dead  → drop it, and cut the week
 *
 * Division of labour, per the L0/L3 split in
 * `outputs/coach-shapeable-ai-architecture-2026-07-07.md`:
 *
 *   • The MODEL picks the cause. Reading "legs are trashed, work is nuts"
 *     and deciding which one actually cost the session is a language job.
 *     It selects from CAUSE_VOCAB — a closed list — so it can never invent
 *     a cause, the same way reschedule-plan can never invent a workout.
 *   • CODE picks the action. The table below is deterministic, unit-tested,
 *     and readable by a coach. No prompt decides what happens to a plan.
 *
 * Nothing here applies anything. Every proposal lands with
 * `auto_applied: false` and waits for a human — AI advises, never acts.
 */

import { INJURY_KEYWORDS, LOW_MOOD_LABELS } from "./rules/types.ts";

// ─── Cause vocabulary ────────────────────────────────────────────────────────

/**
 * Why a session was missed. Closed, and mirrored by the CHECK constraint in
 * 20260821140000_skip_cause_attribution.sql — keep both in step.
 *
 * `niggle`, never `injury`: a body-part mention is an observation, not a
 * finding. The system surfaces the pattern and routes the call to a human.
 * It does not diagnose (hard rule #2).
 */
export const CAUSE_VOCAB = [
  "fatigue",
  "schedule",
  "illness",
  "niggle",
  "weather",
  "unknown",
] as const;

export type SkipCause = typeof CAUSE_VOCAB[number];

export type CauseSource = "inferred" | "athlete_confirmed" | "coach_confirmed";
export type CauseConfidence = "low" | "medium" | "high";

/** A cause is only trustworthy alongside what it was read from. */
export interface CauseEvidence {
  kind: "memo" | "note" | "mood" | "check_in";
  ref: string | null;
  excerpt: string;
}

export interface AttributedCause {
  cause: SkipCause;
  source: CauseSource;
  confidence: CauseConfidence;
  evidence: CauseEvidence[];
}

// ─── The action vocabulary (mirrors plan_adjustments.action_type) ────────────

export type AdjustmentAction =
  | "shift_day"
  | "insert_rest"
  | "reduce_volume"
  | "cap_volume"
  | "reprice_future_paces"
  | "propose_swap"
  | "pause_quality"
  | "update_fitness";

export type TriggerType =
  | "missed_sessions"
  | "fatigue_signal"
  | "pace_over_target"
  | "pace_under_target"
  | "volume_ramp_risk"
  | "heat_forecast"
  | "weekly_rebalance"
  | "race_result";

// ─── The decision table ──────────────────────────────────────────────────────

export interface CauseResponse {
  /** The move. */
  action: AdjustmentAction;
  /** A second move that usually rides along — a fatigue skip is rarely just
   *  one session. Null when the primary move stands alone. */
  secondary: AdjustmentAction | null;
  trigger: TriggerType;
  /** How loud the proposal is. `high` surfaces first in the coach's queue. */
  severity: "low" | "med" | "high";
  /**
   * True when the system should stop at "here's what I see" and hand the
   * decision to a person rather than propose a plan change. Illness and
   * niggles both land here: past a certain point the right answer isn't a
   * training tweak, and the system is not allowed to make that judgment.
   */
  deferToHuman: boolean;
  /** Plain-English rationale, shown on the proposal card. Coach-legible by
   *  design — if this sentence reads wrong, the rule is wrong. */
  rationale: string;
}

/**
 * Cause → response. The heart of it.
 *
 * Read this top to bottom: it should say what you'd do. If it doesn't, this
 * table is the thing to edit — not a prompt.
 */
export const CAUSE_RESPONSES: Readonly<Record<SkipCause, CauseResponse>> = {
  // Life got in the way. The training was fine — protect the load, move it.
  schedule: {
    action: "shift_day",
    secondary: null,
    trigger: "missed_sessions",
    severity: "low",
    deferToHuman: false,
    rationale:
      "Life got in the way, not the training. Move the session and keep the week's load intact.",
  },

  // The athlete is cooked. Dropping the one session is the visible fix; the
  // week around it is usually the real one.
  fatigue: {
    action: "insert_rest",
    secondary: "reduce_volume",
    trigger: "fatigue_signal",
    severity: "med",
    deferToHuman: false,
    rationale:
      "The session was missed because the athlete was fatigued, not busy. Take the rest and ease the rest of the week rather than making the session up.",
  },

  // Never a medical claim, never "stop training" (hard rule #2). Note what
  // happened, hold quality, hand it to a person.
  illness: {
    action: "insert_rest",
    secondary: "pause_quality",
    trigger: "fatigue_signal",
    severity: "med",
    deferToHuman: true,
    rationale:
      "Illness showed up in the athlete's own words. Hold quality work for now — the call on the rest of the week is yours, not the system's.",
  },

  // A body mention is a pattern to surface, not a finding to act on.
  niggle: {
    action: "pause_quality",
    secondary: null,
    trigger: "missed_sessions",
    severity: "high",
    deferToHuman: true,
    rationale:
      "The athlete mentioned a body area around this session. Quality work is held pending your read — the system is flagging a mention, not making a judgment about it.",
  },

  // Conditions, not the athlete. Same load, different day or different shape.
  weather: {
    action: "shift_day",
    secondary: "propose_swap",
    trigger: "heat_forecast",
    severity: "low",
    deferToHuman: false,
    rationale:
      "Conditions cost the session, not fitness or fatigue. Move it, or swap the shape to something the weather doesn't ruin.",
  },

  // The honest branch. Guessing here is how a coach ends up coddling someone
  // who's fine, or burying someone who isn't — so ask instead.
  unknown: {
    action: "shift_day",
    secondary: null,
    trigger: "missed_sessions",
    severity: "low",
    deferToHuman: true,
    rationale:
      "No signal in the data for why this was missed. Worth one question before changing anything — busy week, or beat up?",
  },
};

// ─── Deterministic hinting ───────────────────────────────────────────────────

/**
 * Keyword pre-pass over the athlete's own words.
 *
 * This is not the attributor — the model does that, with far better reading
 * of context. This exists for two narrower jobs: seeding the model's context
 * with candidates, and standing in as a deterministic fallback when the model
 * is unavailable, over budget, or returns something outside CAUSE_VOCAB.
 *
 * Ordered by precedence, most consequential first: a memo that mentions both
 * a calf and a busy week should not resolve to "busy".
 */
const CAUSE_KEYWORDS: ReadonlyArray<{ cause: SkipCause; terms: readonly string[] }> = [
  { cause: "niggle", terms: INJURY_KEYWORDS },
  {
    cause: "illness",
    terms: ["sick", "illness", "ill", "flu", "fever", "cold", "covid", "chest", "virus"],
  },
  {
    cause: "fatigue",
    terms: [
      "tired", "exhausted", "wiped", "cooked", "trashed", "drained", "flat",
      "heavy legs", "dead legs", "no energy", "wrecked", "knackered",
      "run down", "burnt out", "burned out", "slept badly", "bad sleep",
      "no sleep", "shattered",
    ],
  },
  {
    cause: "schedule",
    terms: [
      "work", "meeting", "travel", "flight", "busy", "no time", "ran out of time",
      "kids", "childcare", "deadline", "commute", "shift", "family",
      "appointment", "overslept", "late",
    ],
  },
  {
    cause: "weather",
    terms: [
      "heat", "hot", "humid", "storm", "thunder", "lightning", "ice", "icy",
      "snow", "wind", "freezing", "downpour", "rain",
    ],
  },
];

/**
 * Scan text for cause candidates. Returns every match in precedence order —
 * the caller decides whether to take the first or hand all of them to the
 * model. Case-insensitive, substring-based, deliberately generous: a false
 * candidate costs one tap to correct, a missed one costs a wrong adjustment.
 */
export function inferCauseHints(
  text: string | null | undefined,
): Array<{ cause: SkipCause; matched: string }> {
  if (!text || !text.trim()) return [];
  const haystack = text.toLowerCase();
  const hits: Array<{ cause: SkipCause; matched: string }> = [];
  for (const { cause, terms } of CAUSE_KEYWORDS) {
    const matched = terms.find((t) => haystack.includes(t));
    if (matched) hits.push({ cause, matched });
  }
  return hits;
}

/** Mood labels the app already writes; `tired`/`struggling` corroborate fatigue. */
export function moodSuggestsFatigue(mood: string | null | undefined): boolean {
  return !!mood && LOW_MOOD_LABELS.has(mood.toLowerCase());
}

/** Guard for anything crossing the model boundary — never trust a free string. */
export function isSkipCause(v: unknown): v is SkipCause {
  return typeof v === "string" && (CAUSE_VOCAB as readonly string[]).includes(v);
}

// ─── Proposal ────────────────────────────────────────────────────────────────

export interface SkipContext {
  scheduledWorkoutId: string;
  /** ISO date of the missed session. */
  date: string;
  /** `scheduled_workouts.workout_type`. */
  workoutType: string;
  /** How many sessions this athlete has already missed in the current week —
   *  a second miss escalates a low-severity branch. */
  missedThisWeek: number;
}

export interface AdjustmentProposal {
  trigger_type: TriggerType;
  action_type: AdjustmentAction;
  secondary_action: AdjustmentAction | null;
  severity: "low" | "med" | "high";
  /** Stop-and-ask rather than propose-and-confirm. */
  defer_to_human: boolean;
  /** Whether the proposal should carry a cause-correction affordance. An
   *  inference is correctable in one tap; a human's own answer is not
   *  second-guessed. */
  ask_to_confirm_cause: boolean;
  rationale: string;
  cause: AttributedCause;
  context: SkipContext;
}

/**
 * The whole conditional, in one pure function.
 *
 * Deliberately boring: look the cause up, escalate on repetition, hand back a
 * proposal. Every interesting decision lives in CAUSE_RESPONSES where it can
 * be read and argued with.
 */
export function proposeForSkip(
  cause: AttributedCause,
  context: SkipContext,
): AdjustmentProposal {
  const response = CAUSE_RESPONSES[cause.cause];

  // Repetition changes the reading. One missed session is noise; the second
  // in a week is a pattern, and a pattern the athlete didn't explain is worth
  // a human's attention regardless of which branch it took.
  const repeated = context.missedThisWeek >= 2;
  const severity = repeated && response.severity === "low"
    ? "med"
    : response.severity;

  // Low-confidence inferences get corrected, not obeyed. A cause a person
  // actually confirmed is never re-litigated.
  const inferred = cause.source === "inferred";
  const askToConfirm = inferred &&
    (cause.confidence !== "high" || cause.cause === "unknown");

  return {
    trigger_type: response.trigger,
    action_type: response.action,
    secondary_action: response.secondary,
    severity,
    defer_to_human: response.deferToHuman || (repeated && inferred),
    ask_to_confirm_cause: askToConfirm,
    rationale: response.rationale,
    cause,
    context,
  };
}
